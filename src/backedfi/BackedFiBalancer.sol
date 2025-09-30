// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import "./BackedFiStorage.sol";
import {FunctionsOracle} from "../oracle/FunctionsOracle.sol";
import {Vault} from "../vault/Vault.sol";
import {StagingCustodyAccount} from "./StagingCustodyAccount.sol";
import {IRiskAssetFactory} from "./interfaces/IRiskAssetFactory.sol";
import {FeeCalculation} from "../libraries/FeeCalculation.sol";
import "../factory/IndexFactoryStorage.sol";

error WrongETHAmount();
error ZeroAddress();

contract BackedFiBalancer is Initializable, OwnableUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    struct RebalanceBatch {
        bool firstDone;
        bool secondDone;
        uint256 totalUsdcObtained;
        mapping(address => uint256) tokenDelta;
    }

    struct Ctx {
        Vault vault;
        IERC20 usdc;
    }

    struct Vars {
        uint256 usdcBalance;
        bool bondDeficit;
    }

    BackedFiStorage public factoryStorage;
    FunctionsOracle public functionsOracle;
    IndexFactoryStorage public globalStorage;

    uint256 public constant ONE_BPS_1e18 = 100e18;
    uint256 public rebalanceNonce;

    mapping(uint256 => RebalanceBatch) private _rebalanceBatches;

    event FirstRebalanceAction(
        uint256 indexed nonce, address[] tokensSold, uint256[] amountsSold, uint256 usdcExpected, uint256 time
    );
    event SecondRebalanceAction(uint256 batchId, uint256 time);
    event CompleteRebalanceActions(uint256 batchId, uint256 time);

    modifier onlyOwnerOrOperator() {
        require(
            msg.sender == owner() || factoryStorage.functionsOracle().isOperator(msg.sender)
                || msg.sender == factoryStorage.nexBot(),
            "balancer: only owner / operator / bot"
        );
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _storage, address _oracle, address _globalStorage) external initializer {
        require(_storage != address(0), "balancer: zero _storage");
        require(_oracle != address(0), "balancer: zero _oracle");
        require(_globalStorage != address(0), "balancer: zero _globalStorage");

        factoryStorage = BackedFiStorage(_storage);
        functionsOracle = FunctionsOracle(_oracle);
        globalStorage = IndexFactoryStorage(_globalStorage);

        __Ownable_init(msg.sender);
        __Pausable_init();
        __ReentrancyGuard_init();
    }

    function askValues(address _indexToken, address[] memory underlyings, uint256[] memory prices)
        external
        view
        returns (uint256 totalProviderValue, uint256[] memory assetValues)
    {
        require(_indexToken != address(0), "askValues: indexToken=0");
        require(underlyings.length == prices.length, "askValues: length mismatch");

        // (uint256 _totalShares, address[] memory _tokens, uint256[] memory _marketShares) = functionsOracle
        //     .getCurrentProviderIndexData(
        //     _indexToken, functionsOracle.currentFilledCount(_indexToken), factoryStorage.providerIndex()
        // );

        address vaultAddr = globalStorage.indexTokenToVault(_indexToken);
        require(vaultAddr != address(0), "askValues: vault not set");

        assetValues = new uint256[](underlyings.length);

        for (uint256 i = 0; i < underlyings.length; ++i) {
            address token = underlyings[i];
            uint256 price = prices[i];
            require(token != address(0), "askValues: ");

            uint256 balance = IERC20(token).balanceOf(vaultAddr);
            if (balance == 0 || price == 0) {
                assetValues[i] = 0;
            } else {
                assetValues[i] = Math.mulDiv(balance, price, 1e18);
                totalProviderValue += assetValues[i];
            }
        }
    }

    function firstRebalanceAction(
        address _indexToken,
        uint64 _providerIndex,
        uint256 currentFilledCount,
        uint256[] calldata prices
    ) external payable nonReentrant whenNotPaused onlyOwnerOrOperator returns (uint256 nonce) {
        address vaultAddr = globalStorage.indexTokenToVault(_indexToken);
        require(vaultAddr != address(0), "rebalance: vault not set");

        (, address[] memory tokens,) =
            functionsOracle.getCurrentProviderIndexData(_indexToken, currentFilledCount, _providerIndex);

        uint256 totalTokens = tokens.length;
        // require(totalTokens == targetShares1e18.length, "rebalance: bad oracle data");
        require(prices.length == totalTokens, "rebalance: price length mismatch");

        Ctx memory ctx = Ctx({vault: Vault(vaultAddr), usdc: factoryStorage.usdc()});

        nonce = ++rebalanceNonce;
        RebalanceBatch storage batch = _rebalanceBatches[nonce];
        require(!batch.firstDone, "rebalance: phase-1 done");

        address[] memory soldToken = new address[](totalTokens);
        uint256[] memory soldQty = new uint256[](totalTokens);
        uint256 soldLength;

        for (uint256 i = 0; i < totalTokens; ++i) {
            address token = tokens[i];

            uint256 currentShare = functionsOracle.tokenCurrentMarketShare(_indexToken, token);
            uint256 targetShare = functionsOracle.tokenOracleMarketShare(_indexToken, token);

            uint256 sellPct = _sellPercent(currentShare, targetShare);
            if (sellPct == 0) continue;

            uint256 qtySold = _sellBond(nonce, token, sellPct, prices[i], ctx);
            if (qtySold == 0) continue;

            soldToken[soldLength] = token;
            soldQty[soldLength] = qtySold;
            ++soldLength;
        }

        batch.firstDone = true;

        assembly {
            mstore(soldToken, soldLength)
            mstore(soldQty, soldLength)
        }

        emit FirstRebalanceAction(nonce, soldToken, soldQty, batch.totalUsdcObtained, block.timestamp);
    }

    function secondRebalanceAction(address _indexToken, uint256 batchId)
        external
        payable
        nonReentrant
        onlyOwnerOrOperator
    {
        RebalanceBatch storage batch = _rebalanceBatches[batchId];
        require(batch.firstDone && !batch.secondDone, "rebalance: bad phase");

        IERC20 usdc = factoryStorage.usdc();
        uint256 balance = usdc.balanceOf(address(this));
        require(balance > 0, "balancer: no USDC");

        bool bondDeficit = false;

        for (uint256 i; i < factoryStorage.functionsOracle().totalCurrentList(_indexToken); ++i) {
            address token = factoryStorage.functionsOracle().currentList(_indexToken, i);
            uint256 current = factoryStorage.functionsOracle().tokenCurrentMarketShare(_indexToken, token);
            uint256 oracle = factoryStorage.functionsOracle().tokenOracleMarketShare(_indexToken, token);

            bondDeficit = current < oracle;
        }

        if (bondDeficit) {
            usdc.safeTransfer(factoryStorage.nexBot(), balance);
            // batch.tokenDelta[bond] = 0;
            require(msg.value == 0, "balancer: no ETH needed");
        }

        batch.secondDone = true;
        emit SecondRebalanceAction(batchId, block.timestamp);
    }

    function _sellBond(uint256 nonce, address bondToken, uint256 sellPct, uint256 price, Ctx memory ctx)
        internal
        returns (uint256 soldQty)
    {
        uint256 vaultBalance = IERC20(bondToken).balanceOf(address(ctx.vault));
        if (vaultBalance == 0) return 0;

        soldQty = Math.mulDiv(vaultBalance, sellPct, ONE_BPS_1e18);
        if (soldQty == 0) return 0;

        ctx.vault.withdrawFunds(bondToken, address(this), soldQty);
        if (soldQty == 0) return 0;

        IERC20(bondToken).safeTransfer(factoryStorage.nexBot(), soldQty);

        RebalanceBatch storage batch = _rebalanceBatches[nonce];
        batch.tokenDelta[bondToken] = soldQty;
        if (price != 0) {
            batch.totalUsdcObtained += Math.mulDiv(soldQty, price, 1e18);
        }

        return soldQty;
    }

    // function _sellBond(uint256 nonce, address bondToken, uint256 shareDiff18, Ctx memory ctx)
    //     internal
    //     returns (uint256 soldQty18)
    // {
    //     uint256 vaultBal = IERC20(bondToken).balanceOf(address(ctx.vault));
    //     soldQty18 = (vaultBal * shareDiff18) / ONE_BPS_1e18;
    //     if (soldQty18 == 0) return 0;

    //     RebalanceBatch storage batch = _rebalanceBatches[nonce];
    //     batch.tokenDelta[bondToken] = soldQty18;

    //     // If you want to actually move tokens now:
    //     uint256 pulled = ctx.vault.withdrawFunds(bondToken, address(this), soldQty18);
    //     IERC20(bondToken).safeTransfer(factoryStorage.nexBot(), pulled);
    // }

    function _sellPercent(uint256 currentShare, uint256 targetShare) internal pure returns (uint256) {
        if (currentShare <= targetShare || currentShare == 0) return 0;
        return ((currentShare - targetShare) * 100e18) / currentShare;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {IndexFactory} from "../factory/IndexFactory.sol";
import {IndexToken} from "../token/IndexToken.sol";
import {IndexFactoryStorage} from "./IndexFactoryStorage.sol";
import {FunctionsOracle} from "../oracle/FunctionsOracle.sol";
import {FeeCalculation} from "../libraries/FeeCalculation.sol";
import {Vault} from "../vault/Vault.sol";
import {OrderManager} from "../orderManager/OrderManager.sol";

error ZeroAmount();
error ZeroAddress();
error InvalidRoundId();
error WrongETHAmount();
error RedemptionAmountIsZero();

contract StagingCustodyAccount is Initializable, ReentrancyGuardUpgradeable, OwnableUpgradeable {
    using SafeERC20 for IERC20;

    IndexFactoryStorage factoryStorage;
    FunctionsOracle functionsOracle;
    OrderManager orderManager;
    IndexFactory indexFactory;

    address public nexBot;

    event WithdrawnForPurchase(
        address indexed indexToken, uint256 indexed roundId, uint256 indexed amount, uint256 timestamp
    );
    event RedemptionSettled(
        address indexed indexToken, uint256 indexed roundId, uint256 indexed amount, uint256 timestamp
    );
    event IssuanceSettled(
        address indexed indexToken, uint256 indexed roundId, uint256 indexed usdcAmount, uint256 timestamp
    );
    event RedemptionRequested(
        address indexed indexToken, uint256 indexed totalIdx, uint256 indexed totalBond, uint256 timestamp
    );
    event IssuanceRequested(address indexed indexToken, uint256 indexed usdcForBond, uint256 timestamp);
    event IssuanceCompleted(
        address indexed indexToken, address indexed user, uint256 indexed amount, uint256 timestamp
    );
    event RedemptionCompleted(
        address indexed indexToken, address indexed user, uint256 indexed amount, uint256 timestamp
    );

    modifier onlyOwnerOrOperator() {
        require(
            msg.sender == owner() || functionsOracle.isOperator(msg.sender) || msg.sender == nexBot,
            "Caller is not the owner or operator"
        );
        _;
    }

    modifier onlyNexBot() {
        require(msg.sender == nexBot, "Caller is not the NEX bot");
        _;
    }

    function initialize(address _indexFactoryStorageAddress) external initializer {
        if (_indexFactoryStorageAddress == address(0)) revert ZeroAddress();

        factoryStorage = IndexFactoryStorage(_indexFactoryStorageAddress);
        nexBot = factoryStorage.nexBot();

        __ReentrancyGuard_init();
        __Ownable_init(msg.sender);
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function setNexBotAddress(address _newNexBotAddress) external onlyOwner {
        if (_newNexBotAddress == address(0)) revert ZeroAddress();
        nexBot = _newNexBotAddress;
    }

    function setIndexFactoryStorageAddress(address _newIndexFactoryStorageAddress) external onlyOwner {
        if (_newIndexFactoryStorageAddress == address(0)) revert ZeroAddress();
        factoryStorage = IndexFactoryStorage(_newIndexFactoryStorageAddress);
    }

    /// @notice Withdraw USDC for bond purchase; only active, unsettled rounds
    function withdrawForPurchase(address _indexToken, uint256 _roundId) public onlyOwnerOrOperator nonReentrant {
        uint256 roundIdBalance = factoryStorage.totalIssuanceByRound(_indexToken, _roundId);
        require(roundIdBalance > 0, "Insufficient USDC balance");
        IERC20(factoryStorage.usdc()).safeTransfer(nexBot, roundIdBalance);
        emit WithdrawnForPurchase(_indexToken, _roundId, roundIdBalance, block.timestamp);
    }

    function requestIssuance(address _indexToken, uint256 _roundId) public payable onlyOwnerOrOperator {
        if (_roundId < 1 || _roundId > factoryStorage.issuanceRoundId(_indexToken)) revert InvalidRoundId();
        uint256 prev = _roundId - 1;
        if (_roundId > 1) {
            require(!factoryStorage.issuanceRoundActive(_indexToken, prev), "Prev round still active");
            require(factoryStorage.issuanceIsCompleted(_indexToken, prev), "Prev round not completed");
        }
        require(factoryStorage.issuanceRoundActive(_indexToken, _roundId), "Round is not active");
        require(!factoryStorage.issuanceIsCompleted(_indexToken, _roundId), "Round already completed");

        uint256 roundIdBalance = factoryStorage.totalIssuanceByRound(_indexToken, _roundId);
        require(roundIdBalance > 0, "Total issuance in this round is Zero!");

        if (roundIdBalance > 0) {
            withdrawForPurchase(_indexToken, _roundId);
        }

        factoryStorage.setIssuanceRoundActive(_indexToken, _roundId, false);
        factoryStorage.increaseIssuanceRoundId(_indexToken);

        emit IssuanceRequested(_indexToken, roundIdBalance, block.timestamp);
    }

    function completeIssuance(
        address _indexToken,
        uint256 _roundId,
        address[] memory _underlyingAssets,
        uint256[] memory _prices
    ) external onlyNexBot {
        address vault = factoryStorage.indexTokenToVault(_indexToken);
        if (vault == address(0)) revert ZeroAddress();

        if (_roundId > factoryStorage.issuanceRoundId(_indexToken)) revert InvalidRoundId();
        if (_roundId < 1 || _roundId > factoryStorage.issuanceRoundId(_indexToken)) revert InvalidRoundId();
        uint256 prev = _roundId - 1;
        if (_roundId > 1) {
            require(!factoryStorage.issuanceRoundActive(_indexToken, prev), "Prev round still active");
            require(factoryStorage.issuanceIsCompleted(_indexToken, prev), "Prev round not completed");
        }
        require(!factoryStorage.issuanceRoundActive(_indexToken, _roundId), "Round is active");
        require(!factoryStorage.issuanceIsCompleted(_indexToken, _roundId), "Round already completed");

        uint256 assetsCount = _underlyingAssets.length;
        require(assetsCount > 0, "no assets");
        require(_prices.length == assetsCount, "length mismatch");

        for (uint256 i = 0; i < assetsCount;) {
            address tokenAddress = _underlyingAssets[i];
            uint256 price = _prices[i];

            uint256 oldValue = factoryStorage.getTokenValue(_indexToken, tokenAddress, price);
            uint256 balance = IERC20(tokenAddress).balanceOf(address(this));
            if (balance != 0) {
                IERC20(tokenAddress).safeTransfer(vault, balance);
            }
            uint256 newValue = factoryStorage.getTokenValue(_indexToken, tokenAddress, price);
            factoryStorage.indexFactory().handleCompleteIssuance(
                factoryStorage.indexFactory().issuanceNonce(), _indexToken, tokenAddress, oldValue, newValue
            );

            unchecked {
                ++i;
            }
        }

        uint256 total = factoryStorage.totalIssuanceByRound(_indexToken, _roundId);
        require(total > 0, "Nothing to distribute");

        factoryStorage.settleIssuance(_indexToken, _roundId);
        emit IssuanceSettled(_indexToken, _roundId, total, block.timestamp);
    }

    function requestRedemption(address _indexToken, uint256 _roundId)
        external
        payable
        nonReentrant
        onlyOwnerOrOperator
    {
        if (_roundId < 1 || _roundId > factoryStorage.redemptionRoundId(_indexToken)) revert InvalidRoundId();
        uint256 prev = _roundId - 1;
        if (_roundId > 1) {
            require(!factoryStorage.redemptionRoundActive(_indexToken, prev), "Prev redemption round active");
            require(factoryStorage.redemptionIsCompleted(_indexToken, prev), "Prev redemption not completed");
        }
        require(factoryStorage.redemptionRoundActive(_indexToken, _roundId), "Round not active");
        require(!factoryStorage.redemptionIsCompleted(_indexToken, _roundId), "Round already completed");

        address vault = factoryStorage.indexTokenToVault(_indexToken);

        // uint256 totalIdxThisRound = factoryStorage.totalRedemptionByIndexTokenRound(indexToken, roundId);
        uint256 totalIdxThisRound = factoryStorage.totalRedemptionByRound(_indexToken, _roundId);
        if (totalIdxThisRound == 0) revert RedemptionAmountIsZero();
        if (!factoryStorage.redemptionRoundActive(_indexToken, _roundId)) {
            revert("batch not started");
        }
        factoryStorage.setRedemptionRoundActive(_indexToken, _roundId, false);

        uint256 supplyBefore = IERC20(_indexToken).totalSupply();
        require(supplyBefore > totalIdxThisRound, "IDX supply is zero");
        // uint256 pct1e18 = (totalIdxThisRound * 1e18) / supplyBefore;

        uint256 burnPercent = factoryStorage.ordersBurnPercent(_indexToken, _roundId);

        uint256 currentList = functionsOracle.totalCurrentList(_indexToken);
        uint256 bondSliceTotal;
        for (uint256 i = 0; i < currentList; ++i) {
            address token = factoryStorage.functionsOracle().currentList(_indexToken, i);
            uint256 slice = IERC20(token).balanceOf(vault) * burnPercent / 1e18;

            if (slice == 0) continue;

            Vault(vault).withdrawFunds(token, address(this), slice);
            IERC20(token).safeTransfer(nexBot, slice);

            // bondSliceTotal += slice;
        }

        // if (bondSliceTotal > 0) {
        //     IERC20(bond).safeTransfer(nexBot, bondSliceTotal);
        // }

        factoryStorage.increaseRedemptionRoundId(_indexToken);
        factoryStorage.setRedemptionRoundActive(_indexToken, factoryStorage.redemptionRoundId(_indexToken), false);

        emit RedemptionRequested(_indexToken, totalIdxThisRound, bondSliceTotal, block.timestamp);
    }

    function completeRedemption(
        address _indexToken,
        uint256 _roundId,
        address[] memory _underlyingAssets,
        uint256[] memory _usdcOutputs
    ) external onlyNexBot {
        // if (_roundId < 1 || _roundId > factoryStorage.redemptionRoundId(_indexToken)) revert InvalidRoundId();
        if (_roundId > factoryStorage.redemptionRoundId(_indexToken)) revert InvalidRoundId();
        uint256 prev = _roundId - 1;
        if (_roundId > 1) {
            require(!factoryStorage.redemptionRoundActive(_indexToken, prev), "Prev redemption round active");
            require(factoryStorage.redemptionIsCompleted(_indexToken, prev), "Prev redemption not completed");
        }
        require(!factoryStorage.redemptionRoundActive(_indexToken, _roundId), "Round still active");
        require(!factoryStorage.redemptionIsCompleted(_indexToken, _roundId), "Round already completed");

        uint256 totalIDX = factoryStorage.totalRedemptionByRound(_indexToken, _roundId);
        require(totalIDX > 0, "No tokens to redeem");

        // if (usdcFromBond > 0) {
        //     factoryStorage.usdc().safeTransferFrom(msg.sender, address(this), usdcFromBond);
        // }

        uint256 assetsCount = _underlyingAssets.length;
        require(assetsCount > 0, "no assets");
        require(_usdcOutputs.length == assetsCount, "length mismatch");

        uint256 totalUSDC = 0;
        IERC20 usdc = IERC20(factoryStorage.usdc());

        for (uint256 i = 0; i < assetsCount;) {
            address asset = _underlyingAssets[i];
            uint256 usdcOut = _usdcOutputs[i];

            totalUSDC += usdcOut;

            if (usdcOut != 0) {
                usdc.safeTransfer(address(orderManager), usdcOut);

                factoryStorage.indexFactory().handleCompleteRedemption(
                    factoryStorage.indexFactory().redemptionNonce(), _indexToken, asset, usdcOut
                );
            }

            unchecked {
                ++i;
            }
        }

        factoryStorage.settleRedemption(_indexToken, _roundId);
        emit RedemptionSettled(_indexToken, _roundId, totalUSDC, block.timestamp);
    }

    function withRiskAsset(address token, address to, uint256 amount) public onlyOwner {
        uint256 balance = IERC20(token).balanceOf(address(this));
        require(amount <= balance, "Not enought balance");
        IERC20(token).safeTransfer(to, amount);
    }
}

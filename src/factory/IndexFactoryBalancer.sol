// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {FunctionsOracle} from "../oracle/FunctionsOracle.sol";
import {MainChainBalancer} from "../ccip/MainChainBalancer.sol";
import {MainChainBalancer2} from "../ccip/MainChainBalancer2.sol";
import {IndexFactoryStorage} from "./IndexFactoryStorage.sol";
import {Vault} from "../vault/Vault.sol";
import {FeeCalculation} from "../libraries/FeeCalculation.sol";
import {DinariBalancer} from "../dinari/DinariBalancer.sol";

contract IndexFactoryBalancer is Initializable, OwnableUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    FunctionsOracle public functionsOracle;
    IndexFactoryStorage public factoryStorage;
    MainChainBalancer public mainChainBalancer;
    MainChainBalancer2 public mainChainBalancer2;
    DinariBalancer public dinariBalancer;

    uint256 public updatePortfolioNonce;

    uint256 private constant SHARE_DENOMINATOR = 100e18;

    mapping(uint256 => uint256) public portfolioTotalValueByNonce; // mapping of updatePortfolioNonce to total value
    mapping(uint256 => mapping(uint64 => uint256)) public providerTotalValueByNonce; // mapping of updatePortfolioNonce to total value
    mapping(uint64 => mapping(uint256 => uint256)) public providerNonceToGlobalNonce; // mapping of providerNonce to globalNonce
    mapping(uint256 => uint256) public extraUsdcAmountByNonce; // mapping of updatePortfolioNonce to extra usdc amount
    mapping(uint256 => uint256) public reweightExtraPercentageByNonce; // mapping of updatePortfolioNonce to reweight extra percentage

    event UsdcProvided(
        address indexed indexToken,
        uint8 indexed providerIndex,
        uint256 indexed nonce,
        address to,
        uint256 requested,
        uint256 granted
    );

    function initialize(
        address _functionsOracle,
        address _factoryStorage,
        address _mainChainBalancer,
        address _mainChainBalancer2,
        address _dinariBalancer
    ) external initializer {
        require(_functionsOracle != address(0), "Invalid address for _functionsOracle");
        require(_factoryStorage != address(0), "Invalid address for _factoryStorage");
        require(_mainChainBalancer != address(0), "Invalid address for _mainChainBalancer");
        require(_mainChainBalancer2 != address(0), "Invalid address for _mainChainBalancer2");
        // require(_dinariBalancer != address(0), "Invalid address for _dinariBalancer");
        functionsOracle = FunctionsOracle(_functionsOracle);
        factoryStorage = IndexFactoryStorage(_factoryStorage);
        mainChainBalancer = MainChainBalancer(_mainChainBalancer);
        mainChainBalancer2 = MainChainBalancer2(_mainChainBalancer2);
        dinariBalancer = DinariBalancer(_dinariBalancer);

        __Ownable_init(msg.sender);
        __Pausable_init();
        __ReentrancyGuard_init();
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function increasePortfolioTotalValueByNonce(uint256 _updatePortfolioNonce, uint256 _totalValue) public {
        portfolioTotalValueByNonce[_updatePortfolioNonce] += _totalValue;
    }

    function increaseExtraUsdcAmountByNonce(uint256 _updatePortfolioNonce, uint256 _extraUsdcAmount) public {
        extraUsdcAmountByNonce[_updatePortfolioNonce] += _extraUsdcAmount;
    }

    function increaseReweightExtraPercentageByNonce(uint256 _updatePortfolioNonce, uint256 _extraPercentage) public {
        reweightExtraPercentageByNonce[_updatePortfolioNonce] += _extraPercentage;
    }

    function getGlobalPortfolioValueByProviderNonce(uint64 _providerIndex, uint256 _providerNonce)
        public
        view
        returns (uint256)
    {
        uint256 _updatePortfolioNonce = providerNonceToGlobalNonce[_providerIndex][_providerNonce];
        return portfolioTotalValueByNonce[_updatePortfolioNonce];
    }

    // =========================
    // === External Functions ==
    // =========================
    function askValues(address _indexToken) external whenNotPaused nonReentrant {
        // uint8 dinariProviderIndex = dinariBalancer.dinariStorage().providerIndex();
        uint8 dinariProviderIndex;

        uint256 currentFilledCount = functionsOracle.currentFilledCount(_indexToken);

        uint64[] memory currentProviderIndexes =
            functionsOracle.getCurrentProviderIndexes(_indexToken, currentFilledCount);
        updatePortfolioNonce++;
        for (uint256 i = 0; i < currentProviderIndexes.length; i++) {
            if (currentProviderIndexes[i] == 1) {
                askValueCCIP(_indexToken);
            } else if (currentProviderIndexes[i] == dinariProviderIndex) {
                askValuesDinari(_indexToken);
            }
        }
    }

    function firstReweightAction(address _indexToken, uint256 _updatePortfolioNonce)
        external
        whenNotPaused
        nonReentrant
    {
        uint256 currentFilledCount = functionsOracle.currentFilledCount(_indexToken);
        uint256 oracleFilledCount = functionsOracle.oracleFilledCount(_indexToken);
        uint64[] memory currentProviderIndexes =
            functionsOracle.getCurrentProviderIndexes(_indexToken, currentFilledCount);
        for (uint256 i = 0; i < currentProviderIndexes.length; i++) {
            uint256 realProviderMarketShare = (
                providerTotalValueByNonce[_updatePortfolioNonce][currentProviderIndexes[i]] * 100e18
            ) / portfolioTotalValueByNonce[_updatePortfolioNonce];
            uint256 targetProviderMarketShare = functionsOracle.getOracleProviderIndexTotalShares(
                _indexToken, oracleFilledCount, currentProviderIndexes[i]
            );

            if (realProviderMarketShare >= targetProviderMarketShare) {
                reweightExtraPercentageByNonce[_updatePortfolioNonce] +=
                    realProviderMarketShare - targetProviderMarketShare;
                if (currentProviderIndexes[i] == 1) {
                    uint256 targetPortfolioValue = (
                        providerTotalValueByNonce[_updatePortfolioNonce][1] * SHARE_DENOMINATOR
                    ) / targetProviderMarketShare;
                    reweightCCIP(_indexToken, targetPortfolioValue, 0);
                }
            }
        }
    }

    function completeFirstReweightAction(uint64 _providerIndex, uint256 _updateProviderNonce, uint256 _extraUsdcAmount)
        external
        whenNotPaused
    {
        if (_extraUsdcAmount > 0) {
            IERC20(factoryStorage.usdcAddress()).transferFrom(msg.sender, address(this), _extraUsdcAmount);
        }
        uint256 updatePortfolioNonce_ = providerNonceToGlobalNonce[_providerIndex][_updateProviderNonce];
        extraUsdcAmountByNonce[updatePortfolioNonce_] += _extraUsdcAmount;
    }

    function secondReweightAction(address _indexToken, uint256 _updatePortfolioNonce)
        external
        whenNotPaused
        nonReentrant
    {
        uint256 currentFilledCount = functionsOracle.currentFilledCount(_indexToken);
        uint256 oracleFilledCount = functionsOracle.oracleFilledCount(_indexToken);
        uint64[] memory currentProviderIndexes =
            functionsOracle.getCurrentProviderIndexes(_indexToken, currentFilledCount);
        for (uint256 i = 0; i < currentProviderIndexes.length; i++) {
            uint256 realProviderMarketShare = (
                providerTotalValueByNonce[_updatePortfolioNonce][currentProviderIndexes[i]] * 100e18
            ) / portfolioTotalValueByNonce[_updatePortfolioNonce];
            uint256 targetProviderMarketShare = functionsOracle.getOracleProviderIndexTotalShares(
                _indexToken, oracleFilledCount, currentProviderIndexes[i]
            );
            if (realProviderMarketShare <= targetProviderMarketShare) {
                uint256 negativePercentage = targetProviderMarketShare - realProviderMarketShare;
                uint256 extraUSDCAmount = (extraUsdcAmountByNonce[_updatePortfolioNonce] * negativePercentage)
                    / reweightExtraPercentageByNonce[_updatePortfolioNonce];
                if (currentProviderIndexes[i] == 1) {
                    uint256 targetPortfolioValue =
                        (portfolioTotalValueByNonce[_updatePortfolioNonce] * targetProviderMarketShare) / 100e18;
                    // reweightCalled = extraUSDCAmount;
                    reweightCCIP(_indexToken, targetPortfolioValue, extraUSDCAmount);
                }
            }
        }
    }

    function askValueCCIP(address _indexToken) internal whenNotPaused returns (uint256 orderNonce) {
        uint256 providerUpdateNonce = mainChainBalancer2.getUpdatePortfolioNonce();
        providerNonceToGlobalNonce[1][providerUpdateNonce + 1] = updatePortfolioNonce;
        mainChainBalancer2.askValues(_indexToken);
        return providerUpdateNonce + 1;
    }

    function completeAskValues(uint256 _updatePortfolioNonce, uint256 _value) external whenNotPaused {
        require(_value > 0, "Zero total value");
        require(_updatePortfolioNonce > 0, "Zero provider nonce");

        portfolioTotalValueByNonce[_updatePortfolioNonce] += _value;
    }

    function completeAskValueCCIP(uint256 _updateProviderNonce, uint256 _value) external whenNotPaused {
        require(_value > 0, "Zero total value");
        require(_updateProviderNonce > 0, "Zero provider nonce");

        uint256 _updatePortfolioNonce = providerNonceToGlobalNonce[1][_updateProviderNonce];
        if (_updatePortfolioNonce == 0) {
            revert("Invalid provider nonce");
        }
        portfolioTotalValueByNonce[_updatePortfolioNonce] += _value;
        providerTotalValueByNonce[_updatePortfolioNonce][1] += _value;
    }

    function askValuesDinari(address _indexToken) internal whenNotPaused nonReentrant returns (uint256) {
        uint8 providerIndex = dinariBalancer.dinariStorage().providerIndex();
        uint256 providerUpdateNonce = dinariBalancer.askValues(_indexToken);
        providerNonceToGlobalNonce[providerIndex][providerUpdateNonce] = updatePortfolioNonce;
        return providerUpdateNonce;
    }

    function completeDinariAskValues(uint256 _updateProviderNonce, uint256 _value)
        external
        whenNotPaused
        nonReentrant
    {
        require(_value > 0, "Zero total value");
        uint8 providerIndex = dinariBalancer.dinariStorage().providerIndex();

        uint256 _updatePortfolioNonce = providerNonceToGlobalNonce[providerIndex][_updateProviderNonce];
        if (_updatePortfolioNonce == 0) {
            revert("Invalid provider nonce");
        }
        portfolioTotalValueByNonce[_updatePortfolioNonce] += _value;
        providerTotalValueByNonce[_updatePortfolioNonce][providerIndex] += _value;
    }

    function askValuesBackedFi(address _indexToken) internal whenNotPaused nonReentrant returns (uint256 orderNonce) {
        uint8 providerIndex = dinariBalancer.dinariStorage().providerIndex();
        uint256 providerUpdateNonce = dinariBalancer.askValues(_indexToken);
        providerNonceToGlobalNonce[providerIndex][providerUpdateNonce] = updatePortfolioNonce;
        return providerUpdateNonce;
    }

    uint256 public reweightCalled;

    function reweightCCIP(address _indexToken, uint256 _targetPortfolioValue, uint256 _extraUsdcAmount)
        internal
        whenNotPaused
        returns (uint256 orderNonce)
    {
        if (_extraUsdcAmount > 0) {
            IERC20(factoryStorage.usdcAddress()).approve(address(mainChainBalancer), _extraUsdcAmount);
        }
        // reweightCalled++;
        mainChainBalancer.requestRebalance(
            _indexToken, _targetPortfolioValue, address(factoryStorage.usdcAddress()), _extraUsdcAmount
        );
    }

    function provideUsdc(address indexToken, uint8 providerIndex, uint256 nonce, address to, uint256 amount)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 granted)
    {
        require(to != address(0), "to=0");
        require(amount > 0, "amount=0");

        address usdcToken = dinariBalancer.dinariStorage().usdc();
        uint256 balance = IERC20(usdcToken).balanceOf(address(this));
        if (balance == 0) {
            emit UsdcProvided(indexToken, providerIndex, nonce, to, amount, 0);
            return 0;
        }

        granted = (balance < amount) ? balance : amount;
        IERC20(usdcToken).safeTransfer(to, granted);

        emit UsdcProvided(indexToken, providerIndex, nonce, to, amount, granted);
    }
}

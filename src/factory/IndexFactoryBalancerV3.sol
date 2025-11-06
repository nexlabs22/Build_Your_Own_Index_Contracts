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

/// @custom:oz-upgrades-from IndexFactoryBalancerV2
contract IndexFactoryBalancerV3 is Initializable, OwnableUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable {
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

    uint256 public reweightCalled;

    mapping(uint256 => RebalanceStatus) public rebalanceStatusByNonce; // mapping of updatePortfolioNonce to rebalance status
    mapping(uint64 => mapping(uint256 => ProviderRebalanceStatus)) public providerRebalanceStatus; // mapping of providerIndex to providerNonce to isRebalanceCompleted
    mapping(uint256 => uint256) public totalPendingAskValuesByNonce; // mapping of providerIndex to total pending ask values amount
    mapping(uint256 => uint256) public totalCompletedAskValuesByNonce; // mapping of
    mapping(uint256 => uint256) public totalPendingFirstRebalanceByNonce; // mapping of updatePortfolioNonce to total pending first rebalance amount
    mapping(uint256 => uint256) public totalPendingSecondRebalanceByNonce; // mapping of updatePortfolioNonce to total pending second rebalance amount
    mapping(uint256 => uint256) public totalCompletedFirstRebalanceByNonce; // mapping of updatePortfolioNonce to total completed first rebalance amount
    mapping(uint256 => uint256) public totalCompletedSecondRebalanceByNonce; // mapping of updatePortfolioNonce to total completed second rebalance amount

    mapping(address => bool) public isOperator;

    address public balancerSenderAddress;

    event UsdcProvided(
        address indexed indexToken,
        uint8 indexed providerIndex,
        uint256 indexed nonce,
        address to,
        uint256 requested,
        uint256 granted
    );

    enum ProviderRebalanceStatus {
        AskValues,
        FirstRebalance,
        SecondRebalance
    }

    enum RebalanceStatus {
        None,
        AskValuesRequested,
        AskValuesCompleted,
        FirstRebalanceRequested,
        FirstRebalanceCompleted,
        SecondRebalanceRequested,
        SecondRebalanceCompleted
    }

    event AskValuesRequested(address _indexToken, uint256 indexed portfolioNonce);
    event AskValuesFulfilled(
        address _indexToken, uint256 indexed portfolioNonce, uint256 indexed providerNonce, uint256 value
    );
    event AskValuesCompleted(address _indexToken, uint256 indexed portfolioNonce);
    event FirstRebalanceRequested(address _indexToken, uint256 indexed portfolioNonce);
    event FirstRebalanceFulfilled(address _indexToken, uint256 indexed portfolioNonce, uint256 indexed providerNonce);
    event FirstRebalanceCompleted(address _indexToken, uint256 indexed portfolioNonce);
    event SecondRebalanceRequested(address _indexToken, uint256 indexed portfolioNonce);
    event SecondRebalanceFulfilled(address _indexToken, uint256 indexed portfolioNonce, uint256 indexed providerNonce);
    event SecondRebalanceCompleted(address _indexToken, uint256 indexed portfolioNonce);

    modifier onlyOwnerOrOperator() {
        require(owner() == msg.sender || isOperator[msg.sender], "Not owner or operator");
        _;
    }

    modifier onlyProviderBalancers() {
        require(
            msg.sender == address(mainChainBalancer) || msg.sender == address(balancerSenderAddress)
                || msg.sender == address(mainChainBalancer2) || msg.sender == address(dinariBalancer),
            "Not provider balancer"
        );
        _;
    }

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
        require(_dinariBalancer != address(0), "Invalid address for _dinariBalancer");
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

    function setOperator(address _operator, bool _status) external onlyOwner {
        isOperator[_operator] = _status;
    }

    function setBalancerSenderAddress(address _balancerSenderAddress) external onlyOwner {
        balancerSenderAddress = _balancerSenderAddress;
    }

    function setMainChainBalancerAddress(address _mainChainBalancerAddress) external onlyOwner {
        mainChainBalancer = MainChainBalancer(_mainChainBalancerAddress);
    }

    function setMainChainBalancer2Address(address _mainChainBalancer2Address) external onlyOwner {
        mainChainBalancer2 = MainChainBalancer2(_mainChainBalancer2Address);
    }

    function setDinariBalancerAddress(address _dinariBalancerAddress) external onlyOwner {
        dinariBalancer = DinariBalancer(_dinariBalancerAddress);
    }

    function increasePortfolioTotalValueByNonce(uint256 _updatePortfolioNonce, uint256 _totalValue)
        public
        onlyOwnerOrOperator
    {
        portfolioTotalValueByNonce[_updatePortfolioNonce] += _totalValue;
    }

    function increaseExtraUsdcAmountByNonce(uint256 _updatePortfolioNonce, uint256 _extraUsdcAmount)
        public
        onlyOwnerOrOperator
    {
        extraUsdcAmountByNonce[_updatePortfolioNonce] += _extraUsdcAmount;
    }

    function increaseReweightExtraPercentageByNonce(uint256 _updatePortfolioNonce, uint256 _extraPercentage)
        public
        onlyOwnerOrOperator
    {
        reweightExtraPercentageByNonce[_updatePortfolioNonce] += _extraPercentage;
    }

    function setRebalanceStatus(uint256 _updatePortfolioNonce, RebalanceStatus _status) public onlyOwnerOrOperator {
        rebalanceStatusByNonce[_updatePortfolioNonce] = _status;
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
    function askValues(address _indexToken) external onlyOwnerOrOperator whenNotPaused nonReentrant {
        uint256 currentFilledCount = functionsOracle.currentFilledCount(_indexToken);

        uint64[] memory currentProviderIndexes =
            functionsOracle.getCurrentProviderIndexes(_indexToken, currentFilledCount);
        updatePortfolioNonce++;
        // update rebalance status
        rebalanceStatusByNonce[updatePortfolioNonce] = RebalanceStatus.AskValuesRequested;
        for (uint256 i = 0; i < currentProviderIndexes.length; i++) {
            if (currentProviderIndexes[i] == 1) {
                totalPendingAskValuesByNonce[updatePortfolioNonce]++;
                askValueCCIP(_indexToken);
            } else if (currentProviderIndexes[i] == 2) {
                totalPendingAskValuesByNonce[updatePortfolioNonce]++;
                askValuesDinari(_indexToken);
            }
        }
        emit AskValuesRequested(_indexToken, updatePortfolioNonce);
    }

    function firstReweightAction(address _indexToken, uint256 _updatePortfolioNonce)
        external
        onlyOwnerOrOperator
        whenNotPaused
        nonReentrant
    {
        uint256 currentFilledCount = functionsOracle.currentFilledCount(_indexToken);
        uint256 oracleFilledCount = functionsOracle.oracleFilledCount(_indexToken);
        uint64[] memory currentProviderIndexes =
            functionsOracle.getCurrentProviderIndexes(_indexToken, currentFilledCount);
        // update rebalance status
        require(
            rebalanceStatusByNonce[_updatePortfolioNonce] == RebalanceStatus.AskValuesCompleted,
            "Previous step not completed"
        );
        rebalanceStatusByNonce[_updatePortfolioNonce] = RebalanceStatus.FirstRebalanceRequested;
        for (uint256 i = 0; i < currentProviderIndexes.length; i++) {
            uint256 realProviderMarketShare =
                (providerTotalValueByNonce[_updatePortfolioNonce][currentProviderIndexes[i]] * 100e18)
                    / portfolioTotalValueByNonce[_updatePortfolioNonce];
            uint256 targetProviderMarketShare = functionsOracle.getOracleProviderIndexTotalShares(
                _indexToken, oracleFilledCount, currentProviderIndexes[i]
            );

            if (realProviderMarketShare >= targetProviderMarketShare) {
                reweightExtraPercentageByNonce[_updatePortfolioNonce] += realProviderMarketShare
                    - targetProviderMarketShare;
                if (currentProviderIndexes[i] == 1) {
                    uint256 targetPortfolioValue =
                        (providerTotalValueByNonce[_updatePortfolioNonce][1] * SHARE_DENOMINATOR)
                            / targetProviderMarketShare;
                    reweightCCIP(_indexToken, targetPortfolioValue, 0);
                    providerRebalanceStatus[1][_updatePortfolioNonce] = ProviderRebalanceStatus.FirstRebalance;
                    totalPendingFirstRebalanceByNonce[_updatePortfolioNonce]++;
                } else if (currentProviderIndexes[i] == 2) {
                    firstRebalanceDinari(_indexToken, 0);
                    providerRebalanceStatus[2][_updatePortfolioNonce] = ProviderRebalanceStatus.FirstRebalance;
                    totalPendingFirstRebalanceByNonce[_updatePortfolioNonce]++;
                }
            }
        }
        emit FirstRebalanceRequested(_indexToken, _updatePortfolioNonce);
    }

    function completeReweightAction(
        address _indexToken,
        uint64 _providerIndex,
        uint256 _updateProviderNonce,
        uint256 _extraUsdcAmount
    ) external onlyProviderBalancers whenNotPaused {
        uint256 updatePortfolioNonce_ = providerNonceToGlobalNonce[_providerIndex][_updateProviderNonce];
        if (providerRebalanceStatus[_providerIndex][updatePortfolioNonce_] == ProviderRebalanceStatus.FirstRebalance) {
            if (_extraUsdcAmount > 0) {
                IERC20(factoryStorage.usdcAddress()).transferFrom(msg.sender, address(this), _extraUsdcAmount);
            }
            extraUsdcAmountByNonce[updatePortfolioNonce_] += _extraUsdcAmount;
            emit FirstRebalanceFulfilled(
                _indexToken, providerNonceToGlobalNonce[_providerIndex][_updateProviderNonce], _updateProviderNonce
            );
            totalCompletedFirstRebalanceByNonce[updatePortfolioNonce_]++;
            if (
                totalCompletedFirstRebalanceByNonce[updatePortfolioNonce_]
                    == totalPendingFirstRebalanceByNonce[updatePortfolioNonce_]
            ) {
                rebalanceStatusByNonce[updatePortfolioNonce_] = RebalanceStatus.FirstRebalanceCompleted;
                emit FirstRebalanceCompleted(_indexToken, updatePortfolioNonce_);
            }
        } else if (
            providerRebalanceStatus[_providerIndex][updatePortfolioNonce_] == ProviderRebalanceStatus.SecondRebalance
        ) {
            emit SecondRebalanceFulfilled(_indexToken, updatePortfolioNonce_, _updateProviderNonce);
            totalCompletedSecondRebalanceByNonce[updatePortfolioNonce_]++;
            if (
                totalCompletedSecondRebalanceByNonce[updatePortfolioNonce_]
                    == totalPendingSecondRebalanceByNonce[updatePortfolioNonce_]
            ) {
                rebalanceStatusByNonce[updatePortfolioNonce_] = RebalanceStatus.SecondRebalanceCompleted;
                functionsOracle.updateCurrentList(_indexToken);
                emit SecondRebalanceCompleted(_indexToken, updatePortfolioNonce_);
            }
        }
    }

    function secondReweightAction(address _indexToken, uint256 _updatePortfolioNonce)
        external
        onlyOwnerOrOperator
        whenNotPaused
        nonReentrant
    {
        uint256 currentFilledCount = functionsOracle.currentFilledCount(_indexToken);
        uint256 oracleFilledCount = functionsOracle.oracleFilledCount(_indexToken);
        uint64[] memory currentProviderIndexes =
            functionsOracle.getCurrentProviderIndexes(_indexToken, currentFilledCount);
        // update rebalance status
        require(
            rebalanceStatusByNonce[_updatePortfolioNonce] == RebalanceStatus.FirstRebalanceCompleted,
            "Previous step not completed"
        );
        rebalanceStatusByNonce[_updatePortfolioNonce] = RebalanceStatus.SecondRebalanceRequested;
        bool isSecondEmpty = true;
        for (uint256 i = 0; i < currentProviderIndexes.length; i++) {
            uint256 realProviderMarketShare =
                (providerTotalValueByNonce[_updatePortfolioNonce][currentProviderIndexes[i]] * 100e18)
                    / portfolioTotalValueByNonce[_updatePortfolioNonce];
            uint256 targetProviderMarketShare = functionsOracle.getOracleProviderIndexTotalShares(
                _indexToken, oracleFilledCount, currentProviderIndexes[i]
            );
            if (realProviderMarketShare < targetProviderMarketShare) {
                isSecondEmpty = false;
                uint256 negativePercentage = targetProviderMarketShare - realProviderMarketShare;
                uint256 extraUSDCAmount = (extraUsdcAmountByNonce[_updatePortfolioNonce] * negativePercentage)
                    / reweightExtraPercentageByNonce[_updatePortfolioNonce];
                if (currentProviderIndexes[i] == 1) {
                    uint256 targetPortfolioValue =
                        (portfolioTotalValueByNonce[_updatePortfolioNonce] * targetProviderMarketShare) / 100e18;
                    // reweightCalled = extraUSDCAmount;
                    reweightCCIP(_indexToken, targetPortfolioValue, extraUSDCAmount);
                    providerRebalanceStatus[1][_updatePortfolioNonce] = ProviderRebalanceStatus.SecondRebalance;
                    totalPendingSecondRebalanceByNonce[_updatePortfolioNonce]++;
                } else if (currentProviderIndexes[i] == 2) {
                    firstRebalanceDinari(_indexToken, extraUSDCAmount);
                    providerRebalanceStatus[2][_updatePortfolioNonce] = ProviderRebalanceStatus.SecondRebalance;
                    totalPendingSecondRebalanceByNonce[_updatePortfolioNonce]++;
                }
            }
        }
        emit SecondRebalanceRequested(_indexToken, _updatePortfolioNonce);
        if (isSecondEmpty) {
            rebalanceStatusByNonce[_updatePortfolioNonce] = RebalanceStatus.SecondRebalanceCompleted;
            functionsOracle.updateCurrentList(_indexToken);
            emit SecondRebalanceCompleted(_indexToken, _updatePortfolioNonce);
        }
    }

    function askValueCCIP(address _indexToken) internal whenNotPaused returns (uint256 orderNonce) {
        uint256 providerUpdateNonce = mainChainBalancer2.getUpdatePortfolioNonce();
        providerNonceToGlobalNonce[1][providerUpdateNonce + 1] = updatePortfolioNonce;
        mainChainBalancer2.askValues(_indexToken);
        return providerUpdateNonce + 1;
    }

    function completeAskValues(uint256 _updatePortfolioNonce, uint256 _value) external onlyOwner whenNotPaused {
        require(_value > 0, "Zero total value");
        require(_updatePortfolioNonce > 0, "Zero provider nonce");

        portfolioTotalValueByNonce[_updatePortfolioNonce] += _value;
    }

    function _completeAskValues(
        address _indexToken,
        uint256 _updatePortfolioNonce,
        uint256 _providerNonce,
        uint256 _value
    ) internal whenNotPaused {
        totalCompletedAskValuesByNonce[_updatePortfolioNonce]++;
        emit AskValuesFulfilled(_indexToken, _updatePortfolioNonce, _providerNonce, _value);
        if (
            totalCompletedAskValuesByNonce[_updatePortfolioNonce] == totalPendingAskValuesByNonce[_updatePortfolioNonce]
        ) {
            rebalanceStatusByNonce[_updatePortfolioNonce] = RebalanceStatus.AskValuesCompleted;
            emit AskValuesCompleted(_indexToken, _updatePortfolioNonce);
        }
    }

    function completeAskValueCCIP(address _indexToken, uint256 _updateProviderNonce, uint256 _value)
        external
        onlyProviderBalancers
        whenNotPaused
    {
        require(_value > 0, "Zero total value");
        require(_updateProviderNonce > 0, "Zero provider nonce");

        uint256 _updatePortfolioNonce = providerNonceToGlobalNonce[1][_updateProviderNonce];
        if (_updatePortfolioNonce == 0) {
            revert("Invalid provider nonce");
        }
        portfolioTotalValueByNonce[_updatePortfolioNonce] += _value;
        providerTotalValueByNonce[_updatePortfolioNonce][1] += _value;
        _completeAskValues(_indexToken, _updatePortfolioNonce, _updateProviderNonce, _value);
    }

    function askValuesDinari(address _indexToken) internal whenNotPaused returns (uint256) {
        uint8 providerIndex = dinariBalancer.dinariStorage().providerIndex();
        uint256 providerUpdateNonce = dinariBalancer.rebalanceNonce(_indexToken);
        providerNonceToGlobalNonce[providerIndex][providerUpdateNonce + 1] = updatePortfolioNonce;
        dinariBalancer.askValues(_indexToken);
        return providerUpdateNonce + 1;
    }

    function completeDinariAskValues(address _indexToken, uint256 _updateProviderNonce, uint256 _value)
        external
        onlyProviderBalancers
        whenNotPaused
    {
        require(_value > 0, "Zero total value");
        // uint8 providerIndex = dinariBalancer.dinariStorage().providerIndex();

        uint256 _updatePortfolioNonce = providerNonceToGlobalNonce[2][_updateProviderNonce];
        if (_updatePortfolioNonce == 0) {
            revert("Invalid provider nonce");
        }
        portfolioTotalValueByNonce[_updatePortfolioNonce] += _value;
        providerTotalValueByNonce[_updatePortfolioNonce][2] += _value;
        _completeAskValues(_indexToken, _updatePortfolioNonce, _updateProviderNonce, _value);
    }

    function firstRebalanceDinari(address _indexToken, uint256 _dedicatedUSDCAmount) internal {
        DinariBalancer(dinariBalancer).firstRebalanceAction(_indexToken, _dedicatedUSDCAmount);
    }

    function askValuesBackedFi(address _indexToken) internal whenNotPaused returns (uint256 orderNonce) {
        // uint8 providerIndex = dinariBalancer.dinariStorage().providerIndex();
        uint256 providerUpdateNonce = dinariBalancer.askValues(_indexToken);
        providerNonceToGlobalNonce[3][providerUpdateNonce] = updatePortfolioNonce;
        return providerUpdateNonce;
    }

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

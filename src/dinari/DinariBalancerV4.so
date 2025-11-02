// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "../token/IndexToken.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import "./dinari/interfaces/IOrderProcessor.sol";
import {FeeLib} from "./dinari/common/FeeLib.sol";
import "./coa/ContractOwnedAccount.sol";
import "../vault/Vault.sol";
import "./dinari/WrappedDShare.sol";
import "./DinariStorage.sol";
import "./DinariFactory.sol";
import "./DinariOrderManager.sol";
import "../oracle/FunctionsOracle.sol";
import "../libraries/Commen.sol" as PrbMath2;
import "../factory/IndexFactoryStorage.sol";
import "../factory/IndexFactoryBalancer.sol";

error WrongRebalanceNonce();
error PrevActionNotCompleted();
// error UnauthorizedCaller();
// error ZeroFactoryStorageAddress();
// error ZeroFunctionsOracleAddress();
error ZeroGlobalStorageAddress();
error ZeroGlobalBalancerAddress();
error VaultNotSet();
error InvalidRequestId();

/// @title DinariBalancer
/// @author NEX Labs Protocol
/// @custom:oz-upgrades-from DinariBalancerV3
contract DinariBalancerV4 is Initializable, OwnableUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    struct ActionInfo {
        uint256 actionType;
        uint256 nonce;
    }

    // uint256 public rebalanceNonce;

    DinariStorage public dinariStorage;
    FunctionsOracle public functionsOracle;
    IndexFactoryStorage public globalStorage;
    IndexFactoryBalancer public globalBalancer;

    mapping(address => uint256) public rebalanceNonce;
    mapping(address => mapping(uint256 => mapping(address => uint256))) public rebalanceRequestId;

    mapping(address => mapping(uint256 => uint256)) public rebalanceBuyPayedAmountById;
    mapping(address => mapping(uint256 => uint256)) public rebalanceSellAssetAmountById;

    mapping(address => mapping(uint256 => uint256)) public portfolioValueByNonce;
    mapping(address => mapping(uint256 => mapping(address => uint256))) public tokenValueByNonce;
    mapping(address => mapping(uint256 => mapping(address => uint256))) public tokenShortagePercentByNonce;
    mapping(address => mapping(uint256 => uint256)) public totalShortagePercentByNonce;

    mapping(address => mapping(uint256 => ActionInfo)) public actionInfoById;
    mapping(address => mapping(uint256 => uint256)) public providerSurplusUsdByNonce; // expected USD realized from sells here
    mapping(address => mapping(uint256 => uint256)) public providerShortageUsdByNonce; // USD needed to reach targets here

    mapping(address => mapping(uint256 => uint256)) public usdcRealizedByNonce;
    mapping(address => mapping(uint256 => uint256)) public usdcSpentByNonce;
    mapping(address => mapping(uint256 => uint256)) public usdcForwardedByNonce;
    mapping(uint256 => uint256) public assetClaimedByRequestId;

    event AskValuesRequested(uint256 indexed providerIndex, address indexed indexToken, uint256 indexed timestamp);
    event FirstRebalanceAction(uint256 indexed providerIndex, address indexed indexToken, uint256 nonce, uint256 time);
    event SecondRebalanceAction(uint256 indexed providerIndex, address indexed indexToken, uint256 nonce, uint256 time);
    event CompleteRebalanceActions(
        uint256 indexed providerIndex, address indexed indexToken, uint256 nonce, uint256 time
    );
    event GlobalUsdcRequested(address indexed indexToken, uint256 indexed nonce, uint256 requested, uint256 granted);

    uint256 public minimumOrderAmount;
    mapping(address => mapping(uint256 => mapping(address => uint256))) public tokenExtraPercentByNonce;
    mapping(address => mapping(uint256 => uint256)) public totalExtraPercentByNonce;
    mapping(address => mapping(uint256 => uint256)) public dedicatedUSDCAmountByNonce;

    modifier onlyOwnerOrOperator() {
        if (msg.sender != owner() && !functionsOracle.isOperator(msg.sender)) revert UnauthorizedCaller();
        _;
    }

    function initialize(
        address _factoryStorage,
        address _functionsOracle,
        address _globalStorage,
        address _globalBalancer
    ) external initializer {
        if (_factoryStorage == address(0)) revert ZeroFactoryStorageAddress();
        if (_functionsOracle == address(0)) revert ZeroFunctionsOracleAddress();
        if (_globalStorage == address(0)) revert ZeroGlobalStorageAddress();
        if (_globalBalancer == address(0)) revert ZeroGlobalBalancerAddress();

        dinariStorage = DinariStorage(_factoryStorage);
        functionsOracle = FunctionsOracle(_functionsOracle);
        globalStorage = IndexFactoryStorage(_globalStorage);
        globalBalancer = IndexFactoryBalancer(_globalBalancer);

        __Ownable_init(msg.sender);
        __Pausable_init();
        __ReentrancyGuard_init();
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function setMinimumOrderAmount(uint256 _minimumOrderAmount) public onlyOwnerOrOperator returns (bool) {
        minimumOrderAmount = _minimumOrderAmount;
        return true;
    }

    function setIndexFactoryStorage(address _indexFactoryStorage) public onlyOwner returns (bool) {
        dinariStorage = DinariStorage(_indexFactoryStorage);
        return true;
    }

    function setFunctionsOracle(address _functionsOracle) public onlyOwner returns (bool) {
        functionsOracle = FunctionsOracle(_functionsOracle);
        return true;
    }

    function getAmountAfterFee(uint24 percentageFeeRate, uint256 orderValue) internal pure returns (uint256) {
        return
            percentageFeeRate != 0
                ? PrbMath2.mulDiv(orderValue, 1_000_000, (1_000_000 + percentageFeeRate))
                : orderValue;
    }

    function askValues(address _indexToken) public whenNotPaused onlyOwnerOrOperator returns (uint256) {
        rebalanceNonce[_indexToken] += 1;
        uint256 nonce = rebalanceNonce[_indexToken];

        uint256 portfolioValue;
        (, address[] memory underlyingAssets,) = functionsOracle.getCurrentProviderIndexData(
            _indexToken, functionsOracle.currentFilledCount(_indexToken), dinariStorage.providerIndex()
        );

        for (uint256 i = 0; i < underlyingAssets.length; i++) {
            address token = underlyingAssets[i];
            uint256 tokenValue = dinariStorage.getVaultDshareValue(_indexToken, token);
            tokenValueByNonce[_indexToken][nonce][token] = tokenValue;
            portfolioValue += tokenValue;
        }

        portfolioValueByNonce[_indexToken][nonce] = portfolioValue;

        globalBalancer.completeDinariAskValues(nonce, portfolioValue);

        emit AskValuesRequested(dinariStorage.providerIndex(), _indexToken, block.timestamp);

        return dinariStorage.updatePortfolioNonce();
    }

    function requestBuyOrder(address _indexToken, address _token, uint256 _orderAmount, address _receiver)
        internal
        returns (uint256)
    {
        IOrderProcessor.Order memory order = dinariStorage.getPrimaryOrder(_indexToken, false);
        order.recipient = _receiver;
        order.assetToken = address(_token);
        order.paymentTokenQuantity = _orderAmount;

        DinariOrderManager dinariOrderManager = dinariStorage.dinariOrderManager();
        uint256 id = dinariOrderManager.requestBuyOrderFromCurrentBalance(_token, _orderAmount, _receiver);
        dinariStorage.setOrderInstanceById(_indexToken, id, order);
        return id;
    }

    function requestSellOrder(address _indexToken, address _token, uint256 _amount, address _receiver)
        internal
        returns (uint256, uint256)
    {
        address wrapped = dinariStorage.wrappedDshareAddress(_token);
        address vault = globalStorage.indexTokenToVault(_indexToken);

        uint256 orderAmount;
        {
            Vault(vault).withdrawFunds(wrapped, address(this), _amount);
            uint256 redeemed = WrappedDShare(wrapped).redeem(_amount, address(this), address(this));

            IOrderProcessor issuer = dinariStorage.issuer();
            uint8 decRed = issuer.orderDecimalReduction(_token);

            if (decRed > 0) {
                orderAmount = redeemed - (redeemed % 10 ** (decRed - 1));
            } else {
                orderAmount = redeemed;
            }

            uint256 extra = redeemed - orderAmount;
            if (extra > 0) {
                IERC20(_token).approve(wrapped, extra);
                WrappedDShare(wrapped).deposit(extra, vault); // if/when needed
            }
        }

        return _submitSellOrder(_indexToken, _token, orderAmount, _receiver);
    }

    function _submitSellOrder(address indexToken, address token, uint256 orderAmount, address receiver)
        internal
        returns (uint256 id, uint256 finalAmount)
    {
        IOrderProcessor.Order memory order = dinariStorage.getPrimaryOrder(indexToken, true);
        order.assetToken = token;
        order.assetTokenQuantity = orderAmount;
        order.recipient = receiver;

        address orderManager = address(dinariStorage.dinariOrderManager());

        IERC20(token).safeTransfer(orderManager, orderAmount);

        id = DinariOrderManager(orderManager).requestSellOrderFromCurrentBalance(token, orderAmount, receiver);

        dinariStorage.setOrderInstanceById(indexToken, id, order);

        return (id, orderAmount);
    }

    function _recordSell(address indexToken, uint256 nonce, address token, uint256 requestId, uint256 assetAmount)
        internal
    {
        actionInfoById[indexToken][requestId] = ActionInfo({actionType: 5, nonce: nonce});
        rebalanceRequestId[indexToken][nonce][token] = requestId;
        rebalanceSellAssetAmountById[indexToken][requestId] = assetAmount;
    }

    function _processTokenForFirstRebalanceAction(
        address indexToken,
        uint256 nonce,
        address token,
        address vault,
        uint256 portfolioValue
    ) internal {
        uint256 tokenValue = tokenValueByNonce[indexToken][nonce][token];

        uint256 globalTotal = globalBalancer.getGlobalPortfolioValueByProviderNonce(
            dinariStorage.providerIndex(), rebalanceNonce[indexToken]
        );
        uint256 currentPct = globalTotal == 0 ? 0 : (tokenValue * 100e18) / globalTotal;

        uint256 targetPct = functionsOracle.tokenOracleMarketShare(indexToken, token);

        if (currentPct > targetPct) {
            tokenExtraPercentByNonce[indexToken][nonce][token] = currentPct - targetPct;
            totalExtraPercentByNonce[indexToken][nonce] += (currentPct - targetPct);
            address wrapped = dinariStorage.wrappedDshareAddress(token);
            uint256 wrappedBalance = IERC20(wrapped).balanceOf(vault);
            if (wrappedBalance == 0) return;

            uint256 sellAmount = wrappedBalance - (wrappedBalance * targetPct) / currentPct;
            if (sellAmount == 0) return;

            uint256 estValueToSell = (tokenValue * sellAmount) / wrappedBalance;
            if (estValueToSell <= minimumOrderAmount) return;

            (uint256 requestId, uint256 assetAmount) =
                requestSellOrder(indexToken, token, sellAmount, address(dinariStorage.dinariOrderManager()));

            _recordSell(indexToken, nonce, token, requestId, assetAmount);

            _addProviderSurplus(indexToken, nonce, estValueToSell);
        } else if (currentPct < targetPct) {
            uint256 shortagePct = targetPct - currentPct;
            if ((globalTotal * shortagePct) / 100e18 > minimumOrderAmount) {
                tokenShortagePercentByNonce[indexToken][nonce][token] = shortagePct;
                totalShortagePercentByNonce[indexToken][nonce] += shortagePct;
            }

            uint256 targetUsd = (globalTotal * targetPct) / 100e18;
            if (targetUsd > tokenValue) {
                providerShortageUsdByNonce[indexToken][nonce] += (targetUsd - tokenValue);
            }
        }
    }

    function _addProviderSurplus(address indexToken, uint256 nonce, uint256 value) internal {
        providerSurplusUsdByNonce[indexToken][nonce] += value;
    }

    function _withdrawDedicatedUSDC(address _indexToken, uint256 _nonce, uint256 _dedicatedUSDCAmount) internal {
        if (_dedicatedUSDCAmount > 0) {
            IERC20 usdc = IERC20(dinariStorage.usdc());
            usdc.safeTransferFrom(address(msg.sender), address(this), _dedicatedUSDCAmount);
            dedicatedUSDCAmountByNonce[_indexToken][_nonce] = _dedicatedUSDCAmount;
        }
    }

    function firstRebalanceAction(address _indexToken, uint256 _dedicatedUSDCAmount)
        public
        nonReentrant
        onlyOwnerOrOperator
        returns (uint256)
    {
        uint256 nonce = rebalanceNonce[_indexToken];
        uint8 providerIndex = dinariStorage.providerIndex();

        providerSurplusUsdByNonce[_indexToken][nonce] = 0;
        providerShortageUsdByNonce[_indexToken][nonce] = 0;
        _withdrawDedicatedUSDC(_indexToken, nonce, _dedicatedUSDCAmount);

        uint256 portfolioValue;
        (, address[] memory underlyingAssets,) = functionsOracle.getCurrentProviderIndexData(
            _indexToken, functionsOracle.currentFilledCount(_indexToken), dinariStorage.providerIndex()
        );

        for (uint256 i = 0; i < underlyingAssets.length; i++) {
            address token = underlyingAssets[i];
            uint256 tokenValue = dinariStorage.getVaultDshareValue(_indexToken, token);
            tokenValueByNonce[_indexToken][nonce][token] = tokenValue;
            portfolioValue += tokenValue;
        }

        portfolioValueByNonce[_indexToken][nonce] = portfolioValue;

        if (portfolioValue == 0) {
            emit FirstRebalanceAction(providerIndex, _indexToken, nonce, block.timestamp);
            return nonce;
        }

        address vault = globalStorage.indexTokenToVault(_indexToken);

        for (uint256 i = 0; i < underlyingAssets.length; i++) {
            address token = underlyingAssets[i];
            _processTokenForFirstRebalanceAction(_indexToken, nonce, token, vault, portfolioValue);
        }

        // uint256 surplusUsd = providerSurplusUsdByNonce[_indexToken][nonce];
        // uint256 shortageUsd = providerShortageUsdByNonce[_indexToken][nonce];
        // globalBalancer.registerProviderNetFlow(
        //     _indexToken, dinariStorage.providerIndex(), nonce, surplusUsd, shortageUsd
        // );

        emit FirstRebalanceAction(providerIndex, _indexToken, nonce, block.timestamp);
        return nonce;
    }

    function _withdrawUsdcFromIssuer(uint256 amount) internal returns (uint256 pulled) {
        if (amount == 0) return 0;
        address usdc = dinariStorage.usdc();

        uint256 beforeBal = IERC20(usdc).balanceOf(address(this));
        DinariOrderManager(dinariStorage.dinariOrderManager()).withdrawFunds(address(usdc), address(this), amount);
        uint256 afterBal = IERC20(usdc).balanceOf(address(this));

        // Return only what actually arrived this call
        unchecked {
            return afterBal - beforeBal;
        }
    }

    function _forwardToGlobalBalancer(address _indexToken, uint256 _rebalanceNonce, uint256 amount) internal {
        if (amount == 0) return;
        IERC20 usdc = IERC20(dinariStorage.usdc());
        usdc.approve(address(globalBalancer), amount);
        globalBalancer.completeFirstReweightAction(dinariStorage.providerIndex(), _rebalanceNonce, amount);
        // IERC20(address(dinariStorage.usdc())).safeTransfer(address(globalBalancer), amount);
        // usdcForwardedByNonce[_indexToken][_rebalanceNonce] += amount;
        // globalBalancer.registerProviderSurplus(_indexToken, dinariStorage.providerIndex(), _rebalanceNonce, amount);
    }

    function _placeBuyUnderweighted(
        address indexToken,
        uint256 nonce,
        address token,
        uint256 paymentAmount,
        uint256 flatFee,
        uint24 percentageFeeRate
    ) internal returns (uint256 spentUsdc) {
        uint256 grossAfterPct = getAmountAfterFee(percentageFeeRate, paymentAmount);
        if (grossAfterPct <= flatFee) return 0;

        uint256 amountAfterFee = grossAfterPct - flatFee;

        IERC20(dinariStorage.usdc()).approve(address(dinariStorage.dinariOrderManager()), amountAfterFee);

        uint256 requestId =
            requestBuyOrder(indexToken, token, amountAfterFee, address(dinariStorage.dinariOrderManager()));

        actionInfoById[indexToken][requestId] = ActionInfo({actionType: 6, nonce: nonce});
        rebalanceBuyPayedAmountById[indexToken][requestId] = amountAfterFee;

        return amountAfterFee;
    }

    function _buyUnderweightedAssets(
        address _indexToken,
        uint256 _rebalanceNonce,
        uint256 _totalShortagePercent,
        uint256 _usdcBalance
    ) internal returns (uint256 totalSpent) {
        IOrderProcessor issuer = dinariStorage.issuer();
        (uint256 flatFee, uint24 percentageFeeRate) = issuer.getStandardFees(false, dinariStorage.usdc());

        (, address[] memory underlyingAssets,) = functionsOracle.getCurrentProviderIndexData(
            _indexToken, functionsOracle.currentFilledCount(_indexToken), dinariStorage.providerIndex()
        );

        for (uint256 i = 0; i < underlyingAssets.length; i++) {
            address token = underlyingAssets[i];
            uint256 shortagePct = tokenShortagePercentByNonce[_indexToken][_rebalanceNonce][token];
            if (shortagePct == 0) continue;

            uint256 paymentAmount = (_usdcBalance * shortagePct) / _totalShortagePercent;
            if (paymentAmount == 0) continue;

            uint256 spent =
                _placeBuyUnderweighted(_indexToken, _rebalanceNonce, token, paymentAmount, flatFee, percentageFeeRate);
            totalSpent += spent;
        }
    }

    function secondRebalanceAction(address _indexToken, uint256 _rebalanceNonce)
        public
        nonReentrant
        onlyOwnerOrOperator
    {
        if (!checkFirstRebalanceOrdersStatus(_indexToken, _rebalanceNonce)) {
            revert PrevActionNotCompleted();
        }
        // require(checkFirstRebalanceOrdersStatus(_indexToken, _rebalanceNonce), "Rebalance orders are not completed");

        uint8 providerIndex = dinariStorage.providerIndex();

        IOrderProcessor issuer = dinariStorage.issuer();
        (, address[] memory underlyingAssets,) = functionsOracle.getCurrentProviderIndexData(
            _indexToken, functionsOracle.currentFilledCount(_indexToken), dinariStorage.providerIndex()
        );

        uint256 usdcOwed;
        for (uint256 i = 0; i < underlyingAssets.length; i++) {
            address token = underlyingAssets[i];
            uint256 reqId = rebalanceRequestId[_indexToken][_rebalanceNonce][token];
            if (reqId == 0) continue;
            IOrderProcessor.Order memory order = dinariStorage.getOrderInstanceById(_indexToken, reqId);
            if (order.sell) {
                uint256 received = issuer.getReceivedAmount(reqId);
                uint256 feeTaken = issuer.getFeesTaken(reqId);
                unchecked {
                    usdcOwed += (received - feeTaken);
                }
            }
        }

        uint256 pulled = _withdrawUsdcFromIssuer(usdcOwed);
        usdcRealizedByNonce[_indexToken][_rebalanceNonce] += pulled;

        // uint256 granted = 0;
        // if (_maxUsdcFromGlobal > 0) {
        //     uint256 shortageUsd = providerShortageUsdByNonce[_indexToken][_rebalanceNonce];
        //     uint256 ask = shortageUsd < _maxUsdcFromGlobal ? shortageUsd : _maxUsdcFromGlobal;
        //     if (ask > 0) {
        //         granted = _requestUsdcFromGlobal(_indexToken, _rebalanceNonce, ask);
        //     }
        // }
        uint256 granted = dedicatedUSDCAmountByNonce[_indexToken][_rebalanceNonce];
        uint256 totalShortagePercent = totalShortagePercentByNonce[_indexToken][_rebalanceNonce];
        uint256 totalExtraPercent = totalExtraPercentByNonce[_indexToken][_rebalanceNonce];
        if (totalShortagePercent >= totalExtraPercent) {
            uint256 budget = pulled + granted;
            if (budget > 0) {
                uint256 spent = _buyUnderweightedAssets(_indexToken, _rebalanceNonce, totalShortagePercent, budget);
                usdcSpentByNonce[_indexToken][_rebalanceNonce] += spent;
            }
        } else {
            uint256 budget = pulled * totalShortagePercent / totalExtraPercent;
            if (budget > 0) {
                uint256 spent = _buyUnderweightedAssets(_indexToken, _rebalanceNonce, totalShortagePercent, budget);
                usdcSpentByNonce[_indexToken][_rebalanceNonce] += spent;
            }
            if (pulled > budget) {
                uint256 remaining = pulled - budget;
                _forwardToGlobalBalancer(_indexToken, _rebalanceNonce, remaining);
            }
        }

        // uint256 totalShortagePercent = totalShortagePercentByNonce[_indexToken][_rebalanceNonce];
        // uint256 spent = 0;
        // if (pulled > 0 && totalShortagePercent > 0) {
        //     spent = _buyUnderweightedAssets(_indexToken, _rebalanceNonce, totalShortagePercent, pulled);
        //     usdcSpentByNonce[_indexToken][_rebalanceNonce] += spent;
        // }

        // uint256 realized = usdcRealizedByNonce[_indexToken][_rebalanceNonce];
        // uint256 already = usdcForwardedByNonce[_indexToken][_rebalanceNonce];
        // uint256 sendable = realized > (usdcSpentByNonce[_indexToken][_rebalanceNonce] + already)
        //     ? realized - usdcSpentByNonce[_indexToken][_rebalanceNonce] - already
        //     : 0;

        // uint256 currentBalance = IERC20(address(dinariStorage.usdc())).balanceOf(address(this));
        // if (sendable > currentBalance) sendable = currentBalance;

        // if (sendable > 0) {
        //     _forwardToGlobalBalancer(_indexToken, _rebalanceNonce, sendable);
        // }

        emit SecondRebalanceAction(providerIndex, _indexToken, _rebalanceNonce, block.timestamp);
    }

    function estimateAmountAfterFee(uint256 _amount) public view returns (uint256) {
        IOrderProcessor issuer = dinariStorage.issuer();
        (uint256 flatFee, uint24 percentageFeeRate) = issuer.getStandardFees(false, address(dinariStorage.usdc()));
        uint256 amountAfterFee = getAmountAfterFee(percentageFeeRate, _amount) - flatFee;
        return amountAfterFee;
    }

    function updatePendingTokenSellAmounts(address _indexToken, uint256 _rebalanceNonce) internal {
        (, address[] memory underlyingAssets,) = functionsOracle.getCurrentProviderIndexData(
            _indexToken, functionsOracle.currentFilledCount(_indexToken), dinariStorage.providerIndex()
        );
        for (uint256 i; i < underlyingAssets.length; i++) {
            // address tokenAddress = functionsOracle.currentList(i);
            address tokenAddress = underlyingAssets[i];
            uint256 requestId = rebalanceRequestId[_indexToken][_rebalanceNonce][tokenAddress];
            if (requestId > 0) {
                IOrderProcessor.Order memory order = dinariStorage.getOrderInstanceById(_indexToken, requestId);
                if (order.sell) {
                    uint256 assetAmount = order.assetTokenQuantity;
                    dinariStorage.decreaseTokenPendingRebalanceAmount(
                        _indexToken, tokenAddress, _rebalanceNonce, assetAmount
                    );
                }
            }
        }
    }

    function completeRebalanceActions(address _indexToken, uint256 _rebalanceNonce)
        public
        nonReentrant
        onlyOwnerOrOperator
    {
        if (!checkSecondRebalanceOrdersStatus(_indexToken, _rebalanceNonce)) {
            revert PrevActionNotCompleted();
        }
        // require(checkSecondRebalanceOrdersStatus(_indexToken, _rebalanceNonce), "Rebalance orders are not completed");

        IOrderProcessor issuer = dinariStorage.issuer();
        uint8 providerIndex = dinariStorage.providerIndex();

        (, address[] memory underlyingAssets,) = functionsOracle.getCurrentProviderIndexData(
            _indexToken, functionsOracle.currentFilledCount(_indexToken), dinariStorage.providerIndex()
        ); // oracle filled count

        address vault = globalStorage.indexTokenToVault(_indexToken);
        if (vault == address(0)) revert VaultNotSet();

        address orderManager = address(dinariStorage.dinariOrderManager());

        for (uint256 i = 0; i < underlyingAssets.length; i++) {
            address token = underlyingAssets[i];
            uint256 requestId = rebalanceRequestId[_indexToken][_rebalanceNonce][token];

            if (requestId > 0) {
                IOrderProcessor.Order memory order = dinariStorage.getOrderInstanceById(_indexToken, requestId);

                if (!order.sell) {
                    uint256 received = issuer.getReceivedAmount(requestId);
                    if (received > 0) {
                        DinariOrderManager(orderManager).withdrawFunds(token, address(this), received);
                        address wrapped = dinariStorage.wrappedDshareAddress(token);
                        IERC20(token).approve(wrapped, received);
                        WrappedDShare(wrapped).deposit(received, vault);
                    }
                }
            }

            // updatePendingTokenSellAmounts(_indexToken, _rebalanceNonce);
            // functionsOracle.updateCurrentList(_indexToken);
            // unpauseIndexFactory();

            emit CompleteRebalanceActions(providerIndex, _indexToken, _rebalanceNonce, block.timestamp);
        }
    }

    function _requestUsdcFromGlobal(address indexToken, uint256 nonce, uint256 amount)
        internal
        returns (uint256 granted)
    {
        if (amount == 0) return 0;
        uint8 providerIndex = dinariStorage.providerIndex();

        granted = globalBalancer.provideUsdc(indexToken, providerIndex, nonce, address(this), amount);

        if (granted > 0) {
            usdcRealizedByNonce[indexToken][nonce] += granted;
        }

        emit GlobalUsdcRequested(indexToken, nonce, amount, granted);
    }

    function checkFirstRebalanceOrdersStatus(address _indexToken, uint256 _rebalanceNonce) public view returns (bool) {
        if (_rebalanceNonce > rebalanceNonce[_indexToken]) revert WrongRebalanceNonce();
        // require(_rebalanceNonce <= rebalanceNonce[_indexToken], "Wrong rebalance nonce!");
        // uint256 completedOrdersCount;
        (, address[] memory underlyingAssets,) = functionsOracle.getCurrentProviderIndexData(
            _indexToken, functionsOracle.currentFilledCount(_indexToken), dinariStorage.providerIndex()
        );
        IOrderProcessor issuer = dinariStorage.issuer();
        for (uint256 i; i < underlyingAssets.length; i++) {
            // address tokenAddress = functionsOracle.currentList(i);
            address tokenAddress = underlyingAssets[i];
            uint256 requestId = rebalanceRequestId[_indexToken][_rebalanceNonce][tokenAddress];
            uint256 assetAmount = rebalanceSellAssetAmountById[_indexToken][requestId];
            if (
                requestId > 0 && assetAmount > 0
                    && uint8(issuer.getOrderStatus(requestId)) != uint8(IOrderProcessor.OrderStatus.FULFILLED)
            ) {
                return false;
            }
        }
        return true;
    }

    function checkSecondRebalanceOrdersStatus(address _indexToken, uint256 _rebalanceNonce) public view returns (bool) {
        if (_rebalanceNonce > rebalanceNonce[_indexToken]) revert WrongRebalanceNonce();

        // require(_rebalanceNonce <= rebalanceNonce[_indexToken], "Wrong rebalance nonce!");
        // uint256 completedOrdersCount;
        IOrderProcessor issuer = dinariStorage.issuer();
        (, address[] memory underlyingAssets,) = functionsOracle.getCurrentProviderIndexData(
            _indexToken, functionsOracle.currentFilledCount(_indexToken), dinariStorage.providerIndex()
        );
        for (uint256 i; i < underlyingAssets.length; i++) {
            // address tokenAddress = functionsOracle.currentList(i);
            address tokenAddress = underlyingAssets[i];
            uint256 requestId = rebalanceRequestId[_indexToken][_rebalanceNonce][tokenAddress];
            uint256 payedAmount = rebalanceBuyPayedAmountById[_indexToken][requestId];
            if (
                requestId > 0 && payedAmount > 0
                    && uint8(issuer.getOrderStatus(requestId)) != uint8(IOrderProcessor.OrderStatus.FULFILLED)
            ) {
                return false;
            }
        }
        return true;
    }

    function checkMultical(address _indexToken, uint256 _reqeustId) public view returns (bool) {
        ActionInfo memory actionInfo = actionInfoById[_indexToken][_reqeustId];
        if (actionInfo.actionType == 5) {
            return checkFirstRebalanceOrdersStatus(_indexToken, actionInfo.nonce);
        } else if (actionInfo.actionType == 6) {
            return checkSecondRebalanceOrdersStatus(_indexToken, actionInfo.nonce);
        }
        return false;
    }

    function multical(address _indexToken, uint256 _requestId) public {
        // require(_requestId > 0, "Invalid request id");
        if (_requestId == 0) revert InvalidRequestId();
        ActionInfo memory actionInfo = actionInfoById[_indexToken][_requestId];
        if (actionInfo.actionType == 5) {
            secondRebalanceAction(_indexToken, actionInfo.nonce);
        } else if (actionInfo.actionType == 6) {
            completeRebalanceActions(_indexToken, actionInfo.nonce);
        }
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // pause index factory when rebalance happens
    function pauseIndexFactory() internal {
        address indexFactoryAddress = dinariStorage.factoryAddress();
        DinariFactory indexFactory = DinariFactory(payable(indexFactoryAddress));
        if (!indexFactory.paused()) {
            indexFactory.pause();
        }
    }

    // unpause index factory when rebalance is done
    function unpauseIndexFactory() internal {
        address indexFactoryAddress = dinariStorage.factoryAddress();
        DinariFactory indexFactory = DinariFactory(payable(indexFactoryAddress));
        if (indexFactory.paused()) {
            indexFactory.unpause();
        }
    }
}

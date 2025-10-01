// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "../token/IndexToken.sol";
// import "../token/RequestNFT.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

// import "../chainlink/ChainlinkClient.sol";
import "./dinari/interfaces/IOrderProcessor.sol";
import {FeeLib} from "./dinari/common/FeeLib.sol";
import "./coa/ContractOwnedAccount.sol";
import "../vault/Vault.sol";
import "./dinari/WrappedDShare.sol";
// import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
// import "../libraries/Commen.sol" as PrbMath;
import "./DinariStorage.sol";
import "./DinariFactory.sol";
import "./DinariOrderManager.sol";
import "../oracle/FunctionsOracle.sol";
import "../libraries/Commen.sol" as PrbMath2;
import "../factory/IndexFactoryStorage.sol";

/// @title Index Token Factory
/// @author NEX Labs Protocol
/// @notice Allows User to initiate burn/mint requests and allows issuers to approve or deny them
contract IndexFactoryBalancer is Initializable, OwnableUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    struct ActionInfo {
        uint256 actionType;
        uint256 nonce;
    }

    // uint256 public rebalanceNonce;

    DinariStorage public dinariStorage;
    FunctionsOracle public functionsOracle;
    IndexFactoryStorage public globalStorage;

    mapping(address => uint256) public rebalanceNonce;
    mapping(address => mapping(uint256 => mapping(address => uint256))) public rebalanceRequestId;

    mapping(address => mapping(uint256 => uint256)) public rebalanceBuyPayedAmountById;
    mapping(address => mapping(uint256 => uint256)) public rebalanceSellAssetAmountById;

    mapping(address => mapping(uint256 => uint256)) public portfolioValueByNonce;
    mapping(address => mapping(uint256 => mapping(address => uint256))) public tokenValueByNonce;
    mapping(address => mapping(uint256 => mapping(address => uint256))) public tokenShortagePercentByNonce;
    mapping(address => mapping(uint256 => uint256)) public totalShortagePercentByNonce;

    mapping(address => mapping(uint256 => ActionInfo)) public actionInfoById;

    event FirstRebalanceAction(address indexed indexToken, uint256 nonce, uint256 time);
    event SecondRebalanceAction(address indexed indexToken, uint256 nonce, uint256 time);
    event CompleteRebalanceActions(address indexed indexToken, uint256 nonce, uint256 time);

    uint256 public minimumOrderAmount;

    modifier onlyOwnerOrOperator() {
        require(
            msg.sender == owner() || functionsOracle.isOperator(msg.sender),
            "Only owner or operator can call this function"
        );
        _;
    }

    function initialize(address _factoryStorage, address _functionsOracle, address _globalStorage)
        external
        initializer
    {
        require(_factoryStorage != address(0), "invalid _factoryStorage address");
        require(_functionsOracle != address(0), "invalid _functionsOracle address");
        require(_globalStorage != address(0), "invalid _globalStorage address");
        dinariStorage = DinariStorage(_factoryStorage);
        functionsOracle = FunctionsOracle(_functionsOracle);
        globalStorage = IndexFactoryStorage(_globalStorage);
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
        return percentageFeeRate != 0
            ? PrbMath2.mulDiv(orderValue, 1_000_000, (1_000_000 + percentageFeeRate))
            : orderValue;
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
        uint256 id = dinariOrderManager.requestBuyOrderFromCurrentBalance(_indexToken, _token, _orderAmount, _receiver);
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
                // WrappedDShare(wrapped).deposit(extra, address(dinariStorage.vault())); // if/when needed
            }
        }

        // 2) Transfer underlying to order manager and place the sell in a tiny helper
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

    function _sellOverweightedAssets(address _indexToken, uint256 _rebalanceNonce, uint256 _portfolioValue) internal {
        (, address[] memory underlyingAssets,) = functionsOracle.getCurrentProviderIndexData(
            _indexToken, functionsOracle.currentFilledCount(_indexToken), dinariStorage.providerIndex()
        );

        address vault = globalStorage.indexTokenToVault(_indexToken);

        for (uint256 i; i < underlyingAssets.length; i++) {
            // address tokenAddress = functionsOracle.currentList(i);
            address tokenAddress = underlyingAssets[i];
            uint256 tokenValue = tokenValueByNonce[_indexToken][_rebalanceNonce][tokenAddress];
            address wrappedDshare = dinariStorage.wrappedDshareAddress(tokenAddress);

            uint256 tokenBalance = IERC20(wrappedDshare).balanceOf(vault);
            uint256 tokenValuePercent = (tokenValue * 100e18) / _portfolioValue;
            if (tokenValuePercent > functionsOracle.tokenOracleMarketShare(_indexToken, tokenAddress)) {
                uint256 amount = tokenBalance
                    - (
                        (tokenBalance * functionsOracle.tokenOracleMarketShare(_indexToken, tokenAddress))
                            / tokenValuePercent
                    );
                if (tokenValue * amount / tokenBalance > minimumOrderAmount) {
                    (uint256 requestId, uint256 assetAmount) =
                        requestSellOrder(_indexToken, tokenAddress, amount, address(dinariStorage.dinariOrderManager()));
                    actionInfoById[_indexToken][requestId] = ActionInfo(5, _rebalanceNonce);
                    rebalanceRequestId[_indexToken][_rebalanceNonce][tokenAddress] = requestId;
                    rebalanceSellAssetAmountById[_indexToken][requestId] = amount;
                }
            } else {
                uint256 shortagePercent =
                    functionsOracle.tokenOracleMarketShare(_indexToken, tokenAddress) - tokenValuePercent;
                if ((_portfolioValue * shortagePercent) / 100e18 > minimumOrderAmount) {
                    tokenShortagePercentByNonce[_indexToken][_rebalanceNonce][tokenAddress] = shortagePercent;
                    totalShortagePercentByNonce[_indexToken][_rebalanceNonce] += shortagePercent;
                }
            }
        }
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

        // percentages are 1e18-scaled
        uint256 currentPct = (tokenValue == 0) ? 0 : (tokenValue * 100e18) / portfolioValue;
        uint256 targetPct = functionsOracle.tokenOracleMarketShare(indexToken, token);

        if (currentPct > targetPct) {
            // Overweight → compute sell amount in *wrapped dShare* units
            address wrapped = dinariStorage.wrappedDshareAddress(token);
            uint256 wrappedBalance = IERC20(wrapped).balanceOf(vault);
            if (wrappedBalance == 0) return;

            uint256 sellAmount = wrappedBalance - (wrappedBalance * targetPct) / currentPct; // rounds down
            if (sellAmount == 0) return;

            // Skip dust: approximate USD value being sold = tokenValue * (sellAmount / wrappedBalance)
            uint256 estValueToSell = (tokenValue * sellAmount) / wrappedBalance;
            if (estValueToSell <= minimumOrderAmount) return;

            (uint256 requestId, uint256 assetAmount) =
                requestSellOrder(indexToken, token, sellAmount, address(dinariStorage.dinariOrderManager()));

            _recordSell(indexToken, nonce, token, requestId, assetAmount);

            // // Bookkeeping for follow-ups
            // actionInfoById[indexToken][requestId] = ActionInfo({actionType: 5, nonce: nonce});
            // rebalanceRequestId[indexToken][nonce][token] = requestId;
            // rebalanceSellAssetAmountById[indexToken][requestId] = assetAmount;
        } else if (currentPct < targetPct) {
            // Underweight → record shortage percent; actual purchases are done in second rebalance
            uint256 shortagePct = targetPct - currentPct;
            // Optional dust filter on expected USD
            if ((portfolioValue * shortagePct) / 100e18 > minimumOrderAmount) {
                tokenShortagePercentByNonce[indexToken][nonce][token] = shortagePct;
                totalShortagePercentByNonce[indexToken][nonce] += shortagePct;
            }
        }
    }

    function firstRebalanceAction(address _indexToken) public nonReentrant onlyOwnerOrOperator returns (uint256) {
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

        if (portfolioValue == 0) {
            emit FirstRebalanceAction(_indexToken, nonce, block.timestamp);
            return nonce;
        }

        address vault = globalStorage.indexTokenToVault(_indexToken);

        for (uint256 i = 0; i < underlyingAssets.length; i++) {
            address token = underlyingAssets[i];
            // push all per-iteration work into a helper to keep this frame tiny
            _processTokenForFirstRebalanceAction(_indexToken, nonce, token, vault, portfolioValue);
        }

        emit FirstRebalanceAction(_indexToken, nonce, block.timestamp);
        return nonce;
    }

    function _buyUnderweightedAssets(
        address _indexToken,
        uint256 _rebalanceNonce,
        uint256 _totalShortagePercent,
        uint256 _usdcBalance
    ) internal {
        // Cache invariants once to reduce live locals in the loop
        address usdc = address(dinariStorage.usdc());
        address orderMgr = address(dinariStorage.dinariOrderManager());
        IOrderProcessor issuer = dinariStorage.issuer();

        (uint256 flatFee, uint24 percentageFeeRate) = issuer.getStandardFees(false, usdc);

        (, address[] memory underlyingAssets,) = functionsOracle.getCurrentProviderIndexData(
            _indexToken, functionsOracle.currentFilledCount(_indexToken), dinariStorage.providerIndex()
        );

        for (uint256 i = 0; i < underlyingAssets.length; i++) {
            address token = underlyingAssets[i];
            uint256 shortagePct = tokenShortagePercentByNonce[_indexToken][_rebalanceNonce][token];
            if (shortagePct == 0) continue;

            // Allocate USDC proportionally to shortage %
            uint256 paymentAmount = (_usdcBalance * shortagePct) / _totalShortagePercent;
            if (paymentAmount == 0) continue;

            _placeBuyUnderweighted(
                _indexToken, _rebalanceNonce, token, paymentAmount, usdc, orderMgr, flatFee, percentageFeeRate
            );
        }
    }

    function _placeBuyUnderweighted(
        address indexToken,
        uint256 nonce,
        address token,
        uint256 paymentAmount,
        address usdc,
        address orderMgr,
        uint256 flatFee,
        uint24 percentageFeeRate
    ) internal {
        // Compute net spendable after fees
        uint256 grossAfterPct = getAmountAfterFee(percentageFeeRate, paymentAmount);
        if (grossAfterPct <= flatFee) return; // nothing left after flat fee
        uint256 amountAfterFee = grossAfterPct - flatFee;

        // Approve once per order (you may prefer max-allowance pattern elsewhere)
        IERC20(usdc).approve(orderMgr, paymentAmount);

        uint256 requestId = requestBuyOrder(indexToken, token, amountAfterFee, orderMgr);

        // Keep loop-frame tiny by doing bookkeeping here
        actionInfoById[indexToken][requestId] = ActionInfo({actionType: 6, nonce: nonce});
        rebalanceBuyPayedAmountById[indexToken][requestId] = amountAfterFee;
    }

    function secondRebalanceAction(address _indexToken, uint256 _rebalanceNonce)
        public
        nonReentrant
        onlyOwnerOrOperator
    {
        require(
            checkFirstRebalanceOrdersStatus(_indexToken, rebalanceNonce[_indexToken]),
            "Rebalance orders are not completed"
        );
        uint256 portfolioValue = portfolioValueByNonce[_indexToken][_rebalanceNonce];
        uint256 totalShortagePercent = totalShortagePercentByNonce[_indexToken][_rebalanceNonce];
        IOrderProcessor issuer = dinariStorage.issuer();
        uint256 usdcBalance;
        (, address[] memory underlyingAssets,) = functionsOracle.getCurrentProviderIndexData(
            _indexToken, functionsOracle.currentFilledCount(_indexToken), dinariStorage.providerIndex()
        );
        for (uint256 i; i < underlyingAssets.length; i++) {
            // address tokenAddress = functionsOracle.currentList(i);
            address tokenAddress = underlyingAssets[i];
            uint256 requestId = rebalanceRequestId[_indexToken][_rebalanceNonce][tokenAddress];
            if (requestId > 0) {
                IOrderProcessor.Order memory order = dinariStorage.getOrderInstanceById(_indexToken, requestId);
                uint256 assetAmount = order.assetTokenQuantity;
                if (order.sell) {
                    uint256 balance = issuer.getReceivedAmount(requestId);
                    uint256 feeTaken = issuer.getFeesTaken(requestId);
                    usdcBalance += balance - feeTaken;
                }
            }
        }
        _buyUnderweightedAssets(_indexToken, _rebalanceNonce, totalShortagePercent, usdcBalance);
        emit SecondRebalanceAction(_indexToken, _rebalanceNonce, block.timestamp);
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
        require(checkSecondRebalanceOrdersStatus(_indexToken, _rebalanceNonce), "Rebalance orders are not completed");
        IOrderProcessor issuer = dinariStorage.issuer();
        (, address[] memory underlyingAssets,) = functionsOracle.getCurrentProviderIndexData(
            _indexToken, functionsOracle.currentFilledCount(_indexToken), dinariStorage.providerIndex()
        );
        address vault = globalStorage.indexTokenToVault(_indexToken);
        for (uint256 i; i < underlyingAssets.length; i++) {
            // address tokenAddress = functionsOracle.currentList(i);
            address tokenAddress = underlyingAssets[i];
            uint256 requestId = rebalanceRequestId[_indexToken][_rebalanceNonce][tokenAddress];
            if (requestId > 0) {
                IOrderProcessor.Order memory order = dinariStorage.getOrderInstanceById(_indexToken, requestId);
                if (!order.sell) {
                    uint256 tokenBalance = issuer.getReceivedAmount(requestId);
                    if (tokenBalance > 0) {
                        DinariOrderManager(dinariStorage.dinariOrderManager()).withdrawFunds(
                            tokenAddress, address(this), tokenBalance
                        );
                        IERC20(tokenAddress).approve(dinariStorage.wrappedDshareAddress(tokenAddress), tokenBalance);
                        WrappedDShare(dinariStorage.wrappedDshareAddress(tokenAddress)).deposit(tokenBalance, vault);
                    }
                }
            }
        }
        updatePendingTokenSellAmounts(_indexToken, _rebalanceNonce);
        functionsOracle.updateCurrentList(_indexToken);
        unpauseIndexFactory();
        emit CompleteRebalanceActions(_indexToken, _rebalanceNonce, block.timestamp);
    }

    function checkFirstRebalanceOrdersStatus(address _indexToken, uint256 _rebalanceNonce) public view returns (bool) {
        require(_rebalanceNonce <= rebalanceNonce[_indexToken], "Wrong rebalance nonce!");
        uint256 completedOrdersCount;
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

    function checkSecondRebalanceOrdersStatus(address _indexToken, uint256 _rebalanceNonce)
        public
        view
        returns (bool)
    {
        require(_rebalanceNonce <= rebalanceNonce[_indexToken], "Wrong rebalance nonce!");
        uint256 completedOrdersCount;
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
        require(_requestId > 0, "Invalid request id");
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

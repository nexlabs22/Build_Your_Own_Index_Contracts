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
import "./StockStorage.sol";
import "./StockFactory.sol";
import "./StockOrderManager.sol";
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

    uint256 public rebalanceNonce;

    StockStorage public stockFactoryStorage;
    FunctionsOracle public functionsOracle;
    IndexFactoryStorage public globalStorage;

    mapping(uint256 => mapping(address => uint256)) public rebalanceRequestId;

    mapping(uint256 => uint256) public rebalanceBuyPayedAmountById;
    mapping(uint256 => uint256) public rebalanceSellAssetAmountById;

    mapping(uint256 => uint256) public portfolioValueByNonce;
    mapping(uint256 => mapping(address => uint256)) public tokenValueByNonce;
    mapping(uint256 => mapping(address => uint256)) public tokenShortagePercentByNonce;
    mapping(uint256 => uint256) public totalShortagePercentByNonce;

    mapping(uint256 => ActionInfo) public actionInfoById;

    event FirstRebalanceAction(uint256 nonce, uint256 time);
    event SecondRebalanceAction(uint256 nonce, uint256 time);
    event CompleteRebalanceActions(uint256 nonce, uint256 time);

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
        stockFactoryStorage = StockStorage(_factoryStorage);
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
        stockFactoryStorage = StockStorage(_indexFactoryStorage);
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
        IOrderProcessor.Order memory order = stockFactoryStorage.getPrimaryOrder(_indexToken, false);
        order.recipient = _receiver;
        order.assetToken = address(_token);
        order.paymentTokenQuantity = _orderAmount;

        StockOrderManager stockOrderManager = stockFactoryStorage.stockOrderManager();
        uint256 id = stockOrderManager.requestBuyOrderFromCurrentBalance(_indexToken, _token, _orderAmount, _receiver);
        stockFactoryStorage.setOrderInstanceById(_indexToken, id, order);
        return id;
    }

    function requestSellOrder(address _indexToken, address _token, uint256 _amount, address _receiver)
        internal
        returns (uint256, uint256)
    {
        address wrappedDshare = stockFactoryStorage.wrappedDshareAddress(_token);
        // Vault(stockFactoryStorage.vault()).withdrawFunds(wrappedDshare, address(this), _amount);
        uint256 orderAmount0 = WrappedDShare(wrappedDshare).redeem(_amount, address(this), address(this));

        //rounding order
        IOrderProcessor issuer = stockFactoryStorage.issuer();
        uint8 decimalReduction = issuer.orderDecimalReduction(_token);

        uint256 orderAmount;
        if (decimalReduction > 0) {
            orderAmount = orderAmount0 - (orderAmount0 % 10 ** (decimalReduction - 1));
        } else {
            orderAmount = orderAmount0;
        }
        uint256 extraAmount = orderAmount0 - orderAmount;

        if (extraAmount > 0) {
            IERC20(_token).approve(wrappedDshare, extraAmount);
            // WrappedDShare(wrappedDshare).deposit(extraAmount, address(stockFactoryStorage.vault()));
        }

        IOrderProcessor.Order memory order = stockFactoryStorage.getPrimaryOrder(_indexToken, true);
        order.assetToken = _token;
        order.assetTokenQuantity = orderAmount;
        order.recipient = _receiver;

        IERC20(_token).safeTransfer(address(stockFactoryStorage.stockOrderManager()), orderAmount);
        StockOrderManager stockOrderManager = stockFactoryStorage.stockOrderManager();
        uint256 id = stockOrderManager.requestSellOrderFromCurrentBalance(_token, orderAmount, _receiver);
        // stockFactoryStorage.setOrderInstanceById(_indexToken, id, order);
        // stockFactoryStorage.increaseTokenPendingRebalanceAmount(_indexToken, _token, rebalanceNonce, orderAmount);
        return (id, orderAmount);
    }

    function _sellOverweightedAssets(address _indexToken, uint256 _rebalanceNonce, uint256 _portfolioValue) internal {
        (, address[] memory underlyingAssets,) = functionsOracle.getCurrentProviderIndexData(
            _indexToken, functionsOracle.currentFilledCount(_indexToken), stockFactoryStorage.providerIndex()
        );

        address vault = globalStorage.indexTokenToVault(_indexToken);

        for (uint256 i; i < underlyingAssets.length; i++) {
            // address tokenAddress = functionsOracle.currentList(i);
            address tokenAddress = underlyingAssets[i];
            uint256 tokenValue = tokenValueByNonce[_rebalanceNonce][tokenAddress];
            address wrappedDshare = stockFactoryStorage.wrappedDshareAddress(tokenAddress);

            uint256 tokenBalance = IERC20(wrappedDshare).balanceOf(vault);
            uint256 tokenValuePercent = (tokenValue * 100e18) / _portfolioValue;
            if (tokenValuePercent > functionsOracle.tokenOracleMarketShare(_indexToken, tokenAddress)) {
                uint256 amount = tokenBalance
                    - (
                        (tokenBalance * functionsOracle.tokenOracleMarketShare(_indexToken, tokenAddress))
                            / tokenValuePercent
                    );
                if (tokenValue * amount / tokenBalance > minimumOrderAmount) {
                    (uint256 requestId, uint256 assetAmount) = requestSellOrder(
                        _indexToken, tokenAddress, amount, address(stockFactoryStorage.stockOrderManager())
                    );
                    actionInfoById[requestId] = ActionInfo(5, _rebalanceNonce);
                    rebalanceRequestId[_rebalanceNonce][tokenAddress] = requestId;
                    rebalanceSellAssetAmountById[requestId] = amount;
                }
            } else {
                uint256 shortagePercent =
                    functionsOracle.tokenOracleMarketShare(_indexToken, tokenAddress) - tokenValuePercent;
                if ((_portfolioValue * shortagePercent) / 100e18 > minimumOrderAmount) {
                    tokenShortagePercentByNonce[_rebalanceNonce][tokenAddress] = shortagePercent;
                    totalShortagePercentByNonce[_rebalanceNonce] += shortagePercent;
                }
            }
        }
    }

    function firstRebalanceAction(address _indexToken) public nonReentrant onlyOwnerOrOperator returns (uint256) {
        pauseIndexFactory();
        rebalanceNonce += 1;
        uint256 portfolioValue;
        (, address[] memory underlyingAssets,) = functionsOracle.getCurrentProviderIndexData(
            _indexToken, functionsOracle.currentFilledCount(_indexToken), stockFactoryStorage.providerIndex()
        );
        for (uint256 i; i < underlyingAssets.length; i++) {
            // address tokenAddress = functionsOracle.currentList(i);
            address tokenAddress = underlyingAssets[i];
            uint256 tokenValue = stockFactoryStorage.getVaultDshareValue(_indexToken, tokenAddress);
            tokenValueByNonce[rebalanceNonce][tokenAddress] = tokenValue;
            portfolioValue += tokenValue;
        }
        portfolioValueByNonce[rebalanceNonce] = portfolioValue;
        _sellOverweightedAssets(_indexToken, rebalanceNonce, portfolioValue);
        emit FirstRebalanceAction(rebalanceNonce, block.timestamp);
        return rebalanceNonce;
    }

    function _buyUnderweightedAssets(
        address _indexToken,
        uint256 _rebalanceNonce,
        uint256 _totalShortagePercent,
        uint256 _usdcBalance
    ) internal {
        IOrderProcessor issuer = stockFactoryStorage.issuer();
        (, address[] memory underlyingAssets,) = functionsOracle.getCurrentProviderIndexData(
            _indexToken, functionsOracle.currentFilledCount(_indexToken), stockFactoryStorage.providerIndex()
        );
        for (uint256 i; i < underlyingAssets.length; i++) {
            // address tokenAddress = functionsOracle.currentList(i);
            address tokenAddress = underlyingAssets[i];
            uint256 tokenShortagePercent = tokenShortagePercentByNonce[_rebalanceNonce][tokenAddress];
            if (tokenShortagePercent > 0) {
                uint256 paymentAmount = (tokenShortagePercent * _usdcBalance) / _totalShortagePercent;
                (uint256 flatFee, uint24 percentageFeeRate) =
                    issuer.getStandardFees(false, address(stockFactoryStorage.usdc()));

                uint256 amountAfterFee = getAmountAfterFee(percentageFeeRate, paymentAmount) > flatFee
                    ? getAmountAfterFee(percentageFeeRate, paymentAmount) - flatFee
                    : 0;

                if (amountAfterFee > 0) {
                    uint256 esFee = flatFee + FeeLib.applyPercentageFee(percentageFeeRate, amountAfterFee);
                    IERC20(stockFactoryStorage.usdc()).approve(
                        address(stockFactoryStorage.stockOrderManager()), paymentAmount
                    );
                    uint256 requestId = requestBuyOrder(
                        _indexToken, tokenAddress, amountAfterFee, address(stockFactoryStorage.stockOrderManager())
                    );
                    actionInfoById[requestId] = ActionInfo(6, _rebalanceNonce);
                    // rebalanceRequestId[_rebalanceNonce][tokenAddress] = requestId;
                    rebalanceBuyPayedAmountById[requestId] = amountAfterFee;
                }
            }
        }
    }

    function secondRebalanceAction(address _indexToken, uint256 _rebalanceNonce)
        public
        nonReentrant
        onlyOwnerOrOperator
    {
        require(checkFirstRebalanceOrdersStatus(_indexToken, rebalanceNonce), "Rebalance orders are not completed");
        uint256 portfolioValue = portfolioValueByNonce[_rebalanceNonce];
        uint256 totalShortagePercent = totalShortagePercentByNonce[_rebalanceNonce];
        IOrderProcessor issuer = stockFactoryStorage.issuer();
        uint256 usdcBalance;
        (, address[] memory underlyingAssets,) = functionsOracle.getCurrentProviderIndexData(
            _indexToken, functionsOracle.currentFilledCount(_indexToken), stockFactoryStorage.providerIndex()
        );
        for (uint256 i; i < underlyingAssets.length; i++) {
            // address tokenAddress = functionsOracle.currentList(i);
            address tokenAddress = underlyingAssets[i];
            uint256 requestId = rebalanceRequestId[_rebalanceNonce][tokenAddress];
            if (requestId > 0) {
                IOrderProcessor.Order memory order = stockFactoryStorage.getOrderInstanceById(_indexToken, requestId);
                uint256 assetAmount = order.assetTokenQuantity;
                if (order.sell) {
                    uint256 balance = issuer.getReceivedAmount(requestId);
                    uint256 feeTaken = issuer.getFeesTaken(requestId);
                    usdcBalance += balance - feeTaken;
                }
            }
        }
        _buyUnderweightedAssets(_indexToken, _rebalanceNonce, totalShortagePercent, usdcBalance);
        emit SecondRebalanceAction(_rebalanceNonce, block.timestamp);
    }

    function estimateAmountAfterFee(uint256 _amount) public view returns (uint256) {
        IOrderProcessor issuer = stockFactoryStorage.issuer();
        (uint256 flatFee, uint24 percentageFeeRate) = issuer.getStandardFees(false, address(stockFactoryStorage.usdc()));
        uint256 amountAfterFee = getAmountAfterFee(percentageFeeRate, _amount) - flatFee;
        return amountAfterFee;
    }

    function updatePendingTokenSellAmounts(address _indexToken, uint256 _rebalanceNonce) internal {
        (, address[] memory underlyingAssets,) = functionsOracle.getCurrentProviderIndexData(
            _indexToken, functionsOracle.currentFilledCount(_indexToken), stockFactoryStorage.providerIndex()
        );
        for (uint256 i; i < underlyingAssets.length; i++) {
            // address tokenAddress = functionsOracle.currentList(i);
            address tokenAddress = underlyingAssets[i];
            uint256 requestId = rebalanceRequestId[_rebalanceNonce][tokenAddress];
            if (requestId > 0) {
                IOrderProcessor.Order memory order = stockFactoryStorage.getOrderInstanceById(_indexToken, requestId);
                if (order.sell) {
                    uint256 assetAmount = order.assetTokenQuantity;
                    stockFactoryStorage.decreaseTokenPendingRebalanceAmount(
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
        IOrderProcessor issuer = stockFactoryStorage.issuer();
        (, address[] memory underlyingAssets,) = functionsOracle.getCurrentProviderIndexData(
            _indexToken, functionsOracle.currentFilledCount(_indexToken), stockFactoryStorage.providerIndex()
        );
        address vault = globalStorage.indexTokenToVault(_indexToken);
        for (uint256 i; i < underlyingAssets.length; i++) {
            // address tokenAddress = functionsOracle.currentList(i);
            address tokenAddress = underlyingAssets[i];
            uint256 requestId = rebalanceRequestId[_rebalanceNonce][tokenAddress];
            if (requestId > 0) {
                IOrderProcessor.Order memory order = stockFactoryStorage.getOrderInstanceById(_indexToken, requestId);
                if (!order.sell) {
                    uint256 tokenBalance = issuer.getReceivedAmount(requestId);
                    if (tokenBalance > 0) {
                        StockOrderManager(stockFactoryStorage.stockOrderManager()).withdrawFunds(
                            tokenAddress, address(this), tokenBalance
                        );
                        IERC20(tokenAddress).approve(
                            stockFactoryStorage.wrappedDshareAddress(tokenAddress), tokenBalance
                        );
                        WrappedDShare(stockFactoryStorage.wrappedDshareAddress(tokenAddress)).deposit(
                            tokenBalance, vault
                        );
                    }
                }
            }
        }
        updatePendingTokenSellAmounts(_indexToken, _rebalanceNonce);
        functionsOracle.updateCurrentList(_indexToken);
        unpauseIndexFactory();
        emit CompleteRebalanceActions(_rebalanceNonce, block.timestamp);
    }

    function checkFirstRebalanceOrdersStatus(address _indexToken, uint256 _rebalanceNonce) public view returns (bool) {
        require(_rebalanceNonce <= rebalanceNonce, "Wrong rebalance nonce!");
        uint256 completedOrdersCount;
        (, address[] memory underlyingAssets,) = functionsOracle.getCurrentProviderIndexData(
            _indexToken, functionsOracle.currentFilledCount(_indexToken), stockFactoryStorage.providerIndex()
        );
        IOrderProcessor issuer = stockFactoryStorage.issuer();
        for (uint256 i; i < underlyingAssets.length; i++) {
            // address tokenAddress = functionsOracle.currentList(i);
            address tokenAddress = underlyingAssets[i];
            uint256 requestId = rebalanceRequestId[_rebalanceNonce][tokenAddress];
            uint256 assetAmount = rebalanceSellAssetAmountById[requestId];
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
        require(_rebalanceNonce <= rebalanceNonce, "Wrong rebalance nonce!");
        uint256 completedOrdersCount;
        IOrderProcessor issuer = stockFactoryStorage.issuer();
        (, address[] memory underlyingAssets,) = functionsOracle.getCurrentProviderIndexData(
            _indexToken, functionsOracle.currentFilledCount(_indexToken), stockFactoryStorage.providerIndex()
        );
        for (uint256 i; i < underlyingAssets.length; i++) {
            // address tokenAddress = functionsOracle.currentList(i);
            address tokenAddress = underlyingAssets[i];
            uint256 requestId = rebalanceRequestId[_rebalanceNonce][tokenAddress];
            uint256 payedAmount = rebalanceBuyPayedAmountById[requestId];
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
        ActionInfo memory actionInfo = actionInfoById[_reqeustId];
        if (actionInfo.actionType == 5) {
            return checkFirstRebalanceOrdersStatus(_indexToken, actionInfo.nonce);
        } else if (actionInfo.actionType == 6) {
            return checkSecondRebalanceOrdersStatus(_indexToken, actionInfo.nonce);
        }
        return false;
    }

    function multical(address _indexToken, uint256 _requestId) public {
        require(_requestId > 0, "Invalid request id");
        ActionInfo memory actionInfo = actionInfoById[_requestId];
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
        address indexFactoryAddress = stockFactoryStorage.factoryAddress();
        StockFactory indexFactory = StockFactory(payable(indexFactoryAddress));
        if (!indexFactory.paused()) {
            indexFactory.pause();
        }
    }

    // unpause index factory when rebalance is done
    function unpauseIndexFactory() internal {
        address indexFactoryAddress = stockFactoryStorage.factoryAddress();
        StockFactory indexFactory = StockFactory(payable(indexFactoryAddress));
        if (indexFactory.paused()) {
            indexFactory.unpause();
        }
    }
}

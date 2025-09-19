// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "../token/IndexToken.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "./dinari/interfaces/IOrderProcessor.sol";
// import {FeeLib} from "../dinary/common/FeeLib.sol";
import "./NexVault.sol";
import "./dinari/WrappedDShare.sol";
import "./IndexFactoryStorage.sol";
import "./IndexFactoryProcessor.sol";
import "./OrderManager.sol";
import "./FunctionsOracle.sol";

/// @title Index Token Factory
/// @author NEX Labs Protocol
/// @notice Allows User to initiate burn/mint requests and allows issuers to approve or deny them
/// @custom:oz-upgrades-from IndexFactory
// IndexFactoryV2
contract IndexFactory is Initializable, OwnableUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    struct ActionInfo {
        uint256 actionType;
        uint256 nonce;
    }

    IndexFactoryStorage public factoryStorage;
    FunctionsOracle public functionsOracle;

    event RequestIssuance(
        uint256 indexed nonce,
        address indexed user,
        address inputToken,
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 time
    );

    event RequestCancelIssuance(
        uint256 indexed nonce,
        address indexed user,
        address inputToken,
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 time
    );

    event RequestRedemption(
        uint256 indexed nonce,
        address indexed user,
        address outputToken,
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 time
    );

    event RequestCancelRedemption(
        uint256 indexed nonce,
        address indexed user,
        address outputToken,
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 time
    );

    modifier onlyOwnerOrOperatorOrBalancer() {
        require(
            msg.sender == owner() || functionsOracle.isOperator(msg.sender)
                || msg.sender == factoryStorage.factoryBalancerAddress(),
            "Caller is not the owner or operator or balancer."
        );
        _;
    }
    /**
     * @dev Initializes the contract with the given factory storage address.
     * @param _factoryStorage The address of the factory storage contract.
     */

    function initialize(address _factoryStorage, address _functionsOracle) external initializer {
        require(_factoryStorage != address(0), "invalid factory storage address");
        factoryStorage = IndexFactoryStorage(_factoryStorage);
        functionsOracle = FunctionsOracle(_functionsOracle);
        __Ownable_init(msg.sender);
        __Pausable_init();
        __ReentrancyGuard_init();
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Sets the functions oracle address.
     * @param _functionsOracle The address of the new functions oracle contract.
     */
    function setFunctionsOracle(address _functionsOracle) external onlyOwner {
        require(_functionsOracle != address(0), "invalid functions oracle address");
        functionsOracle = FunctionsOracle(_functionsOracle);
    }

    /**
     * @dev Sets the factory storage address.
     * @param _factoryStorage The address of the new factory storage contract.
     * @return bool indicating success.
     */
    function setIndexFactoryStorage(address _factoryStorage) external onlyOwner returns (bool) {
        require(_factoryStorage != address(0), "invalid factory storage address");
        factoryStorage = IndexFactoryStorage(_factoryStorage);
        return true;
    }

    /**
     * @dev Requests a buy order.
     * @param _token The address of the token to buy.
     * @param _orderAmount The amount of the token to buy.
     * @param _receiver The address to receive the bought tokens.
     * @return uint The ID of the buy order.
     */
    function requestBuyOrder(address _token, uint256 _orderAmount, address _receiver) internal returns (uint256) {
        IOrderProcessor.Order memory order = factoryStorage.getPrimaryOrder(false);
        order.recipient = _receiver;
        order.assetToken = address(_token);
        order.paymentTokenQuantity = _orderAmount;

        OrderManager orderManager = factoryStorage.orderManager();
        uint256 id = orderManager.requestBuyOrderFromCurrentBalance(_token, _orderAmount, _receiver);
        factoryStorage.setOrderInstanceById(id, order);
        return id;
    }

    /**
     * @dev Requests a sell order.
     * @param _token The address of the token to sell.
     * @param _amount The amount of the token to sell.
     * @param _receiver The address to receive the sold tokens.
     * @return (uint, uint) The ID of the sell order and the order amount.
     */
    function requestSellOrder(address _token, uint256 _amount, address _receiver) internal returns (uint256, uint256) {
        address wrappedDshare = factoryStorage.wrappedDshareAddress(_token);
        NexVault(factoryStorage.vault()).withdrawFunds(wrappedDshare, address(this), _amount);
        uint256 orderAmount0 = WrappedDShare(wrappedDshare).redeem(_amount, address(this), address(this));

        //rounding order
        IOrderProcessor issuer = factoryStorage.issuer();
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
            WrappedDShare(wrappedDshare).deposit(extraAmount, address(factoryStorage.vault()));
        }

        IOrderProcessor.Order memory order = factoryStorage.getPrimaryOrder(true);
        order.assetToken = _token;
        order.assetTokenQuantity = orderAmount;
        order.recipient = _receiver;

        IERC20(_token).safeTransfer(address(factoryStorage.orderManager()), orderAmount);
        OrderManager orderManager = factoryStorage.orderManager();
        uint256 id = orderManager.requestSellOrderFromCurrentBalance(_token, orderAmount, _receiver);
        factoryStorage.setOrderInstanceById(id, order);
        return (id, orderAmount);
    }

    /**
     * @dev Requests a sell order from the order manager's balance.
     * @param _token The address of the token to sell.
     * @param _amount The amount of the token to sell.
     * @param _receiver The address to receive the sold tokens.
     * @return (uint, uint) The ID of the sell order and the order amount.
     */
    function requestSellOrderFromOrderManagerBalance(address _token, uint256 _amount, address _receiver)
        internal
        returns (uint256, uint256)
    {
        //rounding order
        IOrderProcessor issuer = factoryStorage.issuer();
        uint8 decimalReduction = issuer.orderDecimalReduction(_token);
        uint256 orderAmount;
        if (decimalReduction > 0) {
            orderAmount = _amount - (_amount % 10 ** (decimalReduction - 1));
        } else {
            orderAmount = _amount;
        }
        uint256 extraAmount = _amount - orderAmount;

        IOrderProcessor.Order memory order = factoryStorage.getPrimaryOrder(true);
        order.assetToken = _token;
        order.assetTokenQuantity = orderAmount;
        order.recipient = _receiver;

        OrderManager orderManager = factoryStorage.orderManager();
        uint256 id = orderManager.requestSellOrderFromCurrentBalance(_token, orderAmount, _receiver);
        factoryStorage.setOrderInstanceById(id, order);
        return (id, orderAmount);
    }

    /**
     * @dev Issues index tokens.
     * @param _inputAmount The amount of input tokens.
     * @return uint256 The issuance nonce.
     */
    function issuanceIndexTokens(uint256 _inputAmount) public nonReentrant whenNotPaused returns (uint256) {
        require(_inputAmount > 0, "Invalid input amount");
        uint256 feeAmount = (_inputAmount * factoryStorage.feeRate()) / 10000;
        uint256 orderProcessorFee = factoryStorage.calculateIssuanceFee(_inputAmount);
        uint256 quantityIn = orderProcessorFee + _inputAmount;
        IERC20(factoryStorage.usdc()).safeTransferFrom(msg.sender, address(factoryStorage.orderManager()), quantityIn);
        IERC20(factoryStorage.usdc()).safeTransferFrom(msg.sender, factoryStorage.feeReceiver(), feeAmount);

        factoryStorage.increaseIssuanceNonce();
        uint256 issuanceNonce = factoryStorage.issuanceNonce();
        factoryStorage.setIssuanceInputAmount(issuanceNonce, _inputAmount);
        for (uint256 i; i < functionsOracle.totalCurrentList(); i++) {
            address tokenAddress = functionsOracle.currentList(i);
            uint256 amount = _inputAmount * functionsOracle.tokenCurrentMarketShare(tokenAddress) / 100e18;
            uint256 requestId = requestBuyOrder(tokenAddress, amount, address(factoryStorage.orderManager()));
            factoryStorage.setActionInfoById(requestId, IndexFactoryStorage.ActionInfo(1, issuanceNonce));
            factoryStorage.setBuyRequestPayedAmountById(requestId, amount);
            factoryStorage.setIssuanceRequestId(issuanceNonce, tokenAddress, requestId);
            factoryStorage.setIssuanceRequesterByNonce(issuanceNonce, msg.sender);
            uint256 wrappedDsharesBalance =
                IERC20(factoryStorage.wrappedDshareAddress(tokenAddress)).balanceOf(address(factoryStorage.vault()));
            uint256 dShareBalance =
                WrappedDShare(factoryStorage.wrappedDshareAddress(tokenAddress)).previewRedeem(wrappedDsharesBalance);
            factoryStorage.setIssuanceTokenPrimaryBalance(issuanceNonce, tokenAddress, dShareBalance);
            factoryStorage.setIssuanceIndexTokenPrimaryTotalSupply(
                issuanceNonce, IERC20(factoryStorage.token()).totalSupply()
            );
        }
        emit RequestIssuance(issuanceNonce, msg.sender, factoryStorage.usdc(), _inputAmount, 0, block.timestamp);
        return issuanceNonce;
    }

    /**
     * @dev Cancels an issuance.
     * @param _issuanceNonce The nonce of the issuance to cancel.
     */
    function cancelIssuance(uint256 _issuanceNonce) public whenNotPaused nonReentrant {
        require(!factoryStorage.issuanceIsCompleted(_issuanceNonce), "Issuance is completed");
        address requester = factoryStorage.issuanceRequesterByNonce(_issuanceNonce);
        require(msg.sender == requester, "Only requester can cancel the issuance");
        IOrderProcessor issuer = factoryStorage.issuer();
        uint256 latestCancelIssuanceReqeustId;
        for (uint256 i; i < functionsOracle.totalCurrentList(); i++) {
            address tokenAddress = functionsOracle.currentList(i);
            uint256 requestId = factoryStorage.issuanceRequestId(_issuanceNonce, tokenAddress);
            IOrderProcessor.Order memory order = factoryStorage.getOrderInstanceById(requestId);
            if (
                uint8(issuer.getOrderStatus(requestId)) == uint8(IOrderProcessor.OrderStatus.ACTIVE)
                    && issuer.getReceivedAmount(requestId) == 0
            ) {
                OrderManager orderManager = factoryStorage.orderManager();
                factoryStorage.setCancelIssuanceUnfilledAmount(
                    _issuanceNonce, tokenAddress, issuer.getUnfilledAmount(requestId)
                );
                orderManager.cancelOrder(requestId);
            } else if (
                uint8(issuer.getOrderStatus(requestId)) == uint8(IOrderProcessor.OrderStatus.FULFILLED)
                    || issuer.getReceivedAmount(requestId) > 0
            ) {
                uint256 balance = issuer.getReceivedAmount(requestId);
                (uint256 cancelRequestId, uint256 assetAmount) = requestSellOrderFromOrderManagerBalance(
                    tokenAddress, balance, address(factoryStorage.orderManager())
                );
                factoryStorage.setActionInfoById(cancelRequestId, IndexFactoryStorage.ActionInfo(3, _issuanceNonce));
                factoryStorage.setCancelIssuanceRequestId(_issuanceNonce, tokenAddress, cancelRequestId);
                factoryStorage.setSellRequestAssetAmountById(cancelRequestId, assetAmount);
                latestCancelIssuanceReqeustId = cancelRequestId;
                if (uint8(issuer.getOrderStatus(requestId)) == uint8(IOrderProcessor.OrderStatus.ACTIVE)) {
                    factoryStorage.setCancelIssuanceUnfilledAmount(
                        _issuanceNonce, tokenAddress, issuer.getUnfilledAmount(requestId)
                    );
                    OrderManager orderManager = factoryStorage.orderManager();
                    orderManager.cancelOrder(requestId);
                }
            }
        }
        emit RequestCancelIssuance(
            _issuanceNonce,
            requester,
            factoryStorage.usdc(),
            factoryStorage.issuanceInputAmount(_issuanceNonce),
            0,
            block.timestamp
        );
    }

    /**
     * @dev Redeems index tokens.
     * @param _inputAmount The amount of input tokens.
     * @return uint The redemption nonce.
     */
    function redemption(uint256 _inputAmount) public nonReentrant whenNotPaused returns (uint256) {
        require(_inputAmount > 0, "Invalid input amount");
        factoryStorage.increaseRedemptionNonce();
        uint256 redemptionNonce = factoryStorage.redemptionNonce();
        factoryStorage.setRedemptionInputAmount(redemptionNonce, _inputAmount);
        IndexToken token = factoryStorage.token();
        uint256 tokenBurnPercent = _inputAmount * 1e18 / token.totalSupply();
        token.burn(msg.sender, _inputAmount);
        factoryStorage.setBurnedTokenAmountByNonce(redemptionNonce, _inputAmount);
        for (uint256 i; i < functionsOracle.totalCurrentList(); i++) {
            address tokenAddress = functionsOracle.currentList(i);
            uint256 amount = tokenBurnPercent
                * IERC20(factoryStorage.wrappedDshareAddress(tokenAddress)).balanceOf(address(factoryStorage.vault()))
                / 1e18;
            (uint256 requestId, uint256 assetAmount) =
                requestSellOrder(tokenAddress, amount, address(factoryStorage.orderManager()));
            factoryStorage.setActionInfoById(requestId, IndexFactoryStorage.ActionInfo(2, redemptionNonce));
            factoryStorage.setSellRequestAssetAmountById(requestId, assetAmount);
            factoryStorage.setRedemptionRequestId(redemptionNonce, tokenAddress, requestId);
            factoryStorage.setRedemptionRequesterByNonce(redemptionNonce, msg.sender);
        }
        emit RequestRedemption(redemptionNonce, msg.sender, factoryStorage.usdc(), _inputAmount, 0, block.timestamp);
        return redemptionNonce;
    }

    /**
     * @dev Cancels an executed redemption.
     * @param _tokenAddress The address of the token.
     * @param _redemptionNonce The nonce of the redemption.
     * @param _requestId The ID of the request.
     * @param _filledAmount The filled amount.
     * @param _unFilledAmount The unfilled amount.
     */
    function _cancelExecutedRedemption(
        address _tokenAddress,
        uint256 _redemptionNonce,
        uint256 _requestId,
        uint256 _filledAmount,
        uint256 _unFilledAmount
    ) internal {
        IOrderProcessor issuer = factoryStorage.issuer();
        (uint256 flatFee, uint24 percentageFeeRate) = issuer.getStandardFees(false, address(factoryStorage.usdc()));
        uint256 amountAfterFee = factoryStorage.getAmountAfterFee(percentageFeeRate, _filledAmount) - flatFee;
        uint256 cancelRequestId = requestBuyOrder(_tokenAddress, amountAfterFee, address(factoryStorage.orderManager()));
        factoryStorage.setActionInfoById(cancelRequestId, IndexFactoryStorage.ActionInfo(4, _redemptionNonce));
        factoryStorage.setCancelRedemptionRequestId(_redemptionNonce, _tokenAddress, cancelRequestId);
        if (uint8(issuer.getOrderStatus(_requestId)) == uint8(IOrderProcessor.OrderStatus.ACTIVE)) {
            factoryStorage.setCancelRedemptionUnfilledAmount(_redemptionNonce, _tokenAddress, _unFilledAmount);
            OrderManager orderManager = factoryStorage.orderManager();
            orderManager.cancelOrder(_requestId);
        }
    }

    /**
     * @dev Cancels a redemption.
     * @param _redemptionNonce The nonce of the redemption to cancel.
     */
    function cancelRedemption(uint256 _redemptionNonce) public nonReentrant whenNotPaused {
        require(!factoryStorage.redemptionIsCompleted(_redemptionNonce), "Redemption is completed");
        address requester = factoryStorage.redemptionRequesterByNonce(_redemptionNonce);
        require(msg.sender == requester, "Only requester can cancel the redemption");
        IOrderProcessor issuer = factoryStorage.issuer();
        for (uint256 i; i < functionsOracle.totalCurrentList(); i++) {
            address tokenAddress = functionsOracle.currentList(i);
            uint256 requestId = factoryStorage.redemptionRequestId(_redemptionNonce, tokenAddress);
            IOrderProcessor.Order memory order = factoryStorage.getOrderInstanceById(requestId);
            uint256 filledAmount = issuer.getReceivedAmount(requestId) - issuer.getFeesTaken(requestId);
            uint256 unFilledAmount = issuer.getUnfilledAmount(requestId);
            if (
                uint8(issuer.getOrderStatus(requestId)) == uint8(IOrderProcessor.OrderStatus.ACTIVE)
                    && filledAmount == 0
            ) {
                OrderManager orderManager = factoryStorage.orderManager();
                orderManager.cancelOrder(requestId);
                factoryStorage.setActionInfoById(requestId, IndexFactoryStorage.ActionInfo(4, _redemptionNonce));
                factoryStorage.setCancelRedemptionUnfilledAmount(_redemptionNonce, tokenAddress, unFilledAmount);
            } else if (
                uint8(issuer.getOrderStatus(requestId)) == uint8(IOrderProcessor.OrderStatus.FULFILLED)
                    || filledAmount > 0
            ) {
                _cancelExecutedRedemption(tokenAddress, _redemptionNonce, requestId, filledAmount, unFilledAmount);
            }
        }
        emit RequestCancelRedemption(
            _redemptionNonce,
            requester,
            factoryStorage.usdc(),
            factoryStorage.redemptionInputAmount(_redemptionNonce),
            0,
            block.timestamp
        );
    }

    /**
     * @dev Pauses the contract.
     */
    function pause() external onlyOwnerOrOperatorOrBalancer {
        _pause();
    }

    /**
     * @dev Unpauses the contract.
     */
    function unpause() external onlyOwnerOrOperatorOrBalancer {
        _unpause();
    }
}

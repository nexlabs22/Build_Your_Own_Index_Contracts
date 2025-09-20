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
// import "./FunctionsOracle.sol";
import {FunctionsOracle} from "../oracle/FunctionsOracle.sol";

/// @title Index Token Factory
/// @author NEX Labs Protocol
/// @notice Allows User to initiate burn/mint requests and allows issuers to approve or deny them
contract IndexFactory is Initializable, OwnableUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    struct ActionInfo {
        uint256 actionType;
        uint256 nonce;
    }

    IndexFactoryStorage public factoryStorage;
    FunctionsOracle public functionsOracle;

    event RequestIssuance(
        address indexed indexToken,
        uint256 indexed nonce,
        address indexed user,
        address inputToken,
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 time
    );

    event RequestRedemption(
        address indexed indexToken,
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
    function requestBuyOrder(address _indexToken, address _token, uint256 _orderAmount, address _receiver)
        internal
        returns (uint256)
    {
        IOrderProcessor.Order memory order = factoryStorage.getPrimaryOrder(false);
        order.recipient = _receiver;
        order.assetToken = address(_token);
        order.paymentTokenQuantity = _orderAmount;

        OrderManager orderManager = factoryStorage.orderManager();
        uint256 id = orderManager.requestBuyOrderFromCurrentBalance(_token, _orderAmount, _receiver);
        factoryStorage.setOrderInstanceById(_indexToken, id, order);
        return id;
    }

    /**
     * @dev Requests a sell order.
     * @param _token The address of the token to sell.
     * @param _amount The amount of the token to sell.
     * @param _receiver The address to receive the sold tokens.
     * @return (uint, uint) The ID of the sell order and the order amount.
     */
    function requestSellOrder(address _indexToken, address _token, uint256 _amount, address _receiver)
        internal
        returns (uint256, uint256)
    {
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
        // factoryStorage.setOrderInstanceById(_indexToken, id, order); //
        return (id, orderAmount);
    }

    /**
     * @dev Requests a sell order from the order manager's balance.
     * @param _token The address of the token to sell.
     * @param _amount The amount of the token to sell.
     * @param _receiver The address to receive the sold tokens.
     * @return (uint, uint) The ID of the sell order and the order amount.
     */
    function requestSellOrderFromOrderManagerBalance(
        address _indexToken,
        address _token,
        uint256 _amount,
        address _receiver
    ) internal returns (uint256, uint256) {
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
        factoryStorage.setOrderInstanceById(_indexToken, id, order);
        return (id, orderAmount);
    }

    /**
     * @dev Issues index tokens.
     * @param _inputAmount The amount of input tokens.
     * @return uint256 The issuance nonce.
     */
    function issuanceIndexTokens(address _indexToken, uint256 _inputAmount)
        public
        nonReentrant
        whenNotPaused
        returns (uint256)
    {
        require(_inputAmount > 0, "Invalid input amount");
        uint256 orderProcessorFee = factoryStorage.calculateIssuanceFee(_indexToken, _inputAmount);
        uint256 quantityIn = orderProcessorFee + _inputAmount;
        IERC20(factoryStorage.usdc()).safeTransferFrom(msg.sender, address(factoryStorage.orderManager()), quantityIn);

        factoryStorage.increaseIssuanceNonce();
        uint256 issuanceNonce = factoryStorage.issuanceNonce();
        factoryStorage.setIssuanceInputAmount(_indexToken, issuanceNonce, _inputAmount);
        for (uint256 i; i < functionsOracle.totalCurrentList(_indexToken); i++) {
            address tokenAddress = functionsOracle.currentList(_indexToken, i);
            uint256 amount = _inputAmount * functionsOracle.tokenCurrentMarketShare(_indexToken, tokenAddress) / 100e18;
            uint256 requestId =
                requestBuyOrder(_indexToken, tokenAddress, amount, address(factoryStorage.orderManager()));
            factoryStorage.setActionInfoById(_indexToken, requestId, IndexFactoryStorage.ActionInfo(1, issuanceNonce));
            factoryStorage.setBuyRequestPayedAmountById(_indexToken, requestId, amount);
            factoryStorage.setIssuanceRequestId(_indexToken, issuanceNonce, tokenAddress, requestId);
            factoryStorage.setIssuanceRequesterByNonce(_indexToken, issuanceNonce, msg.sender);
            uint256 wrappedDsharesBalance =
                IERC20(factoryStorage.wrappedDshareAddress(tokenAddress)).balanceOf(address(factoryStorage.vault()));
            uint256 dShareBalance =
                WrappedDShare(factoryStorage.wrappedDshareAddress(tokenAddress)).previewRedeem(wrappedDsharesBalance);
            factoryStorage.setIssuanceTokenPrimaryBalance(_indexToken, issuanceNonce, tokenAddress, dShareBalance);
            factoryStorage.setIssuanceIndexTokenPrimaryTotalSupply(
                _indexToken, issuanceNonce, IERC20(factoryStorage.token()).totalSupply()
            );
        }
        emit RequestIssuance(
            _indexToken, issuanceNonce, msg.sender, factoryStorage.usdc(), _inputAmount, 0, block.timestamp
        );
        return issuanceNonce;
    }

    /**
     * @dev Redeems index tokens.
     * @param _inputAmount The amount of input tokens.
     * @return uint The redemption nonce.
     */
    function redemption(address _indexToken, uint256 _inputAmount)
        public
        nonReentrant
        whenNotPaused
        returns (uint256)
    {
        require(_inputAmount > 0, "Invalid input amount");
        factoryStorage.increaseRedemptionNonce();
        uint256 redemptionNonce = factoryStorage.redemptionNonce();
        factoryStorage.setRedemptionInputAmount(_indexToken, redemptionNonce, _inputAmount);
        IndexToken token = factoryStorage.token();
        uint256 tokenBurnPercent = _inputAmount * 1e18 / token.totalSupply();
        token.burn(msg.sender, _inputAmount);
        factoryStorage.setBurnedTokenAmountByNonce(_indexToken, redemptionNonce, _inputAmount);
        for (uint256 i; i < functionsOracle.totalCurrentList(_indexToken); i++) {
            address tokenAddress = functionsOracle.currentList(_indexToken, i);
            uint256 amount = tokenBurnPercent
                * IERC20(factoryStorage.wrappedDshareAddress(tokenAddress)).balanceOf(address(factoryStorage.vault()))
                / 1e18;
            (uint256 requestId, uint256 assetAmount) =
                requestSellOrder(_indexToken, tokenAddress, amount, address(factoryStorage.orderManager()));
            factoryStorage.setActionInfoById(_indexToken, requestId, IndexFactoryStorage.ActionInfo(2, redemptionNonce));
            factoryStorage.setSellRequestAssetAmountById(_indexToken, requestId, assetAmount);
            factoryStorage.setRedemptionRequestId(_indexToken, redemptionNonce, tokenAddress, requestId);
            factoryStorage.setRedemptionRequesterByNonce(_indexToken, redemptionNonce, msg.sender);
        }
        emit RequestRedemption(
            _indexToken, redemptionNonce, msg.sender, factoryStorage.usdc(), _inputAmount, 0, block.timestamp
        );
        return redemptionNonce;
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

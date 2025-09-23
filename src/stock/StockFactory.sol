// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "./dinari/interfaces/IOrderProcessor.sol";

import {IndexToken} from "../token/IndexToken.sol";
import {Vault} from "../vault/Vault.sol";
import {WrappedDShare} from "./dinari/WrappedDShare.sol";
import {StockStorage} from "./StockStorage.sol";
import {IndexFactoryProcessor} from "./IndexFactoryProcessor.sol";
import {StockOrderManager} from "./StockOrderManager.sol";
import {FunctionsOracle} from "../oracle/FunctionsOracle.sol";
import {IndexFactoryStorage} from "../factory/IndexFactoryStorage.sol";

/// @title Stock Factory
/// @author NEX Labs Protocol
/// @notice Allows User to initiate burn/mint requests and allows issuers to approve or deny them
contract StockFactory is Initializable, OwnableUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    struct ActionInfo {
        uint256 actionType;
        uint256 nonce;
    }

    StockStorage public stockStorage;
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
                || msg.sender == stockStorage.factoryBalancerAddress(),
            "Caller is not the owner or operator or balancer."
        );
        _;
    }

    function initialize(address _indexFactoryStorage, address _stockStorage, address _functionsOracle)
        external
        initializer
    {
        require(_indexFactoryStorage != address(0), "invalid _indexFactoryStorage address");
        require(_stockStorage != address(0), "invalid _stockStorage address");
        require(_functionsOracle != address(0), "invalid _functionsOracle address");
        stockStorage = StockStorage(_stockStorage);
        functionsOracle = FunctionsOracle(_functionsOracle);
        factoryStorage = IndexFactoryStorage(_indexFactoryStorage);
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
        stockStorage = StockStorage(_factoryStorage);
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
        IOrderProcessor.Order memory order = stockStorage.getPrimaryOrder(_indexToken, false);
        order.recipient = _receiver;
        order.assetToken = address(_token);
        order.paymentTokenQuantity = _orderAmount;

        StockOrderManager orderManager = stockStorage.stockOrderManager();
        uint256 id = orderManager.requestBuyOrderFromCurrentBalance(_indexToken, _token, _orderAmount, _receiver);
        stockStorage.setOrderInstanceById(_indexToken, id, order);
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
        address wrappedDshare = stockStorage.wrappedDshareAddress(_token);
        Vault(factoryStorage.indexTokenToVault(_indexToken)).withdrawFunds(wrappedDshare, address(this), _amount);
        uint256 orderAmount0 = WrappedDShare(wrappedDshare).redeem(_amount, address(this), address(this));

        //rounding order
        IOrderProcessor issuer = stockStorage.issuer();
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
            // WrappedDShare(wrappedDshare).deposit(extraAmount, factoryStorage.indexTokenToVault(_indexToken));
        }

        IOrderProcessor.Order memory order = stockStorage.getPrimaryOrder(_indexToken, true);
        order.assetToken = _token;
        order.assetTokenQuantity = orderAmount;
        order.recipient = _receiver;

        IERC20(_token).safeTransfer(address(stockStorage.stockOrderManager()), orderAmount);
        StockOrderManager orderManager = stockStorage.stockOrderManager();
        uint256 id = orderManager.requestSellOrderFromCurrentBalance(_token, orderAmount, _receiver);
        _setRequestSellOrderData(_indexToken, id, order);
        // stockStorage.setOrderInstanceById(_indexToken, id, order); //
        return (id, orderAmount);
    }

    function _setRequestSellOrderData(address _indexToken, uint256 _id, IOrderProcessor.Order memory _order) internal {
        stockStorage.setOrderInstanceById(_indexToken, _id, _order); //
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
        IOrderProcessor issuer = stockStorage.issuer();
        uint8 decimalReduction = issuer.orderDecimalReduction(_token);
        uint256 orderAmount;
        if (decimalReduction > 0) {
            orderAmount = _amount - (_amount % 10 ** (decimalReduction - 1));
        } else {
            orderAmount = _amount;
        }
        // uint256 extraAmount = _amount - orderAmount;

        IOrderProcessor.Order memory order = stockStorage.getPrimaryOrder(_indexToken, true);
        order.assetToken = _token;
        order.assetTokenQuantity = orderAmount;
        order.recipient = _receiver;

        StockOrderManager orderManager = stockStorage.stockOrderManager();
        uint256 id = orderManager.requestSellOrderFromCurrentBalance(_token, orderAmount, _receiver);
        stockStorage.setOrderInstanceById(_indexToken, id, order);
        return (id, orderAmount);
    }

    function _setIssuanceRequestData(
        address _indexToken,
        uint256 _requestId,
        uint256 _issuanceNonce,
        uint256 _amount,
        address _tokenAddress
    ) internal {
        stockStorage.setActionInfoById(_indexToken, _requestId, StockStorage.ActionInfo(1, _issuanceNonce));
        stockStorage.setBuyRequestPayedAmountById(_indexToken, _requestId, _amount);
        stockStorage.setIssuanceRequestId(_indexToken, _issuanceNonce, _tokenAddress, _requestId);
        stockStorage.setIssuanceRequesterByNonce(_indexToken, _issuanceNonce, msg.sender);
        uint256 wrappedDsharesBalance = IERC20(stockStorage.wrappedDshareAddress(_tokenAddress)).balanceOf(
            factoryStorage.indexTokenToVault(_indexToken)
        );
        uint256 dShareBalance =
            WrappedDShare(stockStorage.wrappedDshareAddress(_tokenAddress)).previewRedeem(wrappedDsharesBalance);
        stockStorage.setIssuanceTokenPrimaryBalance(_indexToken, _issuanceNonce, _tokenAddress, dShareBalance);
        stockStorage.setIssuanceIndexTokenPrimaryTotalSupply(
            _indexToken, _issuanceNonce, IERC20(_indexToken).totalSupply()
        );
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
        uint256 orderProcessorFee = stockStorage.calculateIssuanceFee(_indexToken, _inputAmount);
        uint256 quantityIn = orderProcessorFee + _inputAmount;
        IERC20(stockStorage.usdc()).safeTransferFrom(msg.sender, address(stockStorage.stockOrderManager()), quantityIn);

        stockStorage.increaseIssuanceNonce(_indexToken);
        uint256 issuanceNonce = stockStorage.issuanceNonce(_indexToken);
        stockStorage.setIssuanceInputAmount(_indexToken, issuanceNonce, _inputAmount);

        (uint256 totalMarketShare, address[] memory underlyingAssets, uint256[] memory underlyingMarketShares) =
        functionsOracle.getCurrentProviderIndexData(
            _indexToken, functionsOracle.currentFilledCount(_indexToken), stockStorage.providerIndex()
        );

        for (uint256 i; i < underlyingAssets.length; i++) {
            address tokenAddress = underlyingAssets[i];
            uint256 amount = _inputAmount * underlyingMarketShares[i] / totalMarketShare;

            uint256 requestId =
                requestBuyOrder(_indexToken, tokenAddress, amount, address(stockStorage.stockOrderManager()));
            _setIssuanceRequestData(_indexToken, requestId, issuanceNonce, amount, tokenAddress);
        }
        emit RequestIssuance(
            _indexToken, issuanceNonce, msg.sender, stockStorage.usdc(), _inputAmount, 0, block.timestamp
        );
        return issuanceNonce;
    }

    /**
     * @dev Redeems index tokens.
     * @param _inputAmount The amount of input tokens.
     * @return uint The redemption nonce.
     */
    function redemption(address _indexToken, uint256 _inputAmount, uint256 _burnPercent)
        public
        nonReentrant
        whenNotPaused
        returns (uint256)
    {
        require(_inputAmount > 0, "Invalid input amount");
        stockStorage.increaseRedemptionNonce(_indexToken);
        uint256 redemptionNonce = stockStorage.redemptionNonce(_indexToken);
        stockStorage.setRedemptionInputAmount(_indexToken, redemptionNonce, _inputAmount);
        IndexToken token = IndexToken(_indexToken);
        token.burn(msg.sender, _inputAmount);
        stockStorage.setBurnedTokenAmountByNonce(_indexToken, redemptionNonce, _inputAmount);

        (, address[] memory underlyingAssets,) = functionsOracle.getCurrentProviderIndexData(
            _indexToken, functionsOracle.currentFilledCount(_indexToken), stockStorage.providerIndex()
        );

        for (uint256 i; i < underlyingAssets.length; i++) {
            address tokenAddress = underlyingAssets[i];
            uint256 amount = _burnPercent
                * IERC20(stockStorage.wrappedDshareAddress(tokenAddress)).balanceOf(
                    factoryStorage.indexTokenToVault(_indexToken)
                ) / 1e18;

            (uint256 requestId, uint256 assetAmount) =
                requestSellOrder(_indexToken, tokenAddress, amount, address(stockStorage.stockOrderManager()));
            stockStorage.setActionInfoById(_indexToken, requestId, StockStorage.ActionInfo(2, redemptionNonce));
            stockStorage.setSellRequestAssetAmountById(_indexToken, requestId, assetAmount);
            stockStorage.setRedemptionRequestId(_indexToken, redemptionNonce, tokenAddress, requestId);
            stockStorage.setRedemptionRequesterByNonce(_indexToken, redemptionNonce, msg.sender);
        }
        emit RequestRedemption(
            _indexToken, redemptionNonce, msg.sender, stockStorage.usdc(), _inputAmount, 0, block.timestamp
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

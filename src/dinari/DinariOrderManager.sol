// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import "./dinari/interfaces/IOrderProcessor.sol";
import {FeeLib} from "./dinari/common/FeeLib.sol";

/// @title Order Manager
/// @author NEX Labs Protocol
/// @notice Allows User to initiate burn/mint requests and allows issuers to approve or deny them
contract DinariOrderManager is Initializable, OwnableUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable {
    enum RequestStatus {
        NULL,
        PENDING,
        CANCELED,
        APPROVED,
        REJECTED
    }

    event FundsWithdrawn(address token, address to, uint256 amount);

    struct Request {
        address indexToken;
        address requester; // sender of the request.
        uint256 amount; // amount of token to mint/burn.
        address[] depositAddresses; // issuer's asset address in mint, merchant's asset address in burn.
        uint256 nonce; // serial number allocated for each request.
        uint256 timestamp; // time of the request creation.
        RequestStatus status; // status of the request.
    }

    IOrderProcessor public issuer;

    address public usdc;
    uint8 public usdcDecimals;

    mapping(address => bool) public isOperator;

    event BuyRequest(address indexed indexToken, uint256 indexed id, uint256 time, uint256 inutAmount);
    event SellRequest(address indexed indexToken, uint256 indexed id, uint256 time, uint256 inutAmount);

    error ZeroUsdcAddress();
    error ZeroIssuerAddress();
    error InvalidUsdcDecimals();
    error UnauthorizedSender();
    error ZeroTokenAddress();
    error ZeroReceiverAddress();
    error AmountMustBeGreaterThanZero();
    error TransferFailed();
    error InvalidRequestId();

    function initialize(address _usdc, uint8 _usdcDecimals, address _issuer) external initializer {
        // require(_usdc != address(0), "invalid token address");
        if (_usdc == address(0)) revert ZeroUsdcAddress();
        // require(_issuer != address(0), "invalid issuer address");
        if (_issuer == address(0)) revert ZeroIssuerAddress();
        // require(_usdcDecimals > 0, "invalid decimals");
        if (_usdcDecimals == 0) revert InvalidUsdcDecimals();
        usdc = _usdc;
        usdcDecimals = _usdcDecimals;
        issuer = IOrderProcessor(_issuer);
        __Ownable_init(msg.sender);
        __Pausable_init();
        __ReentrancyGuard_init();
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function setIssuer(address _issuer) external onlyOwner {
        // require(_issuer != address(0), "invalid issuer address");
        if (_issuer == address(0)) revert ZeroIssuerAddress();
        issuer = IOrderProcessor(_issuer);
    }

    function setUsdcAddress(address _usdc, uint8 _usdcDecimals) public onlyOwner returns (bool) {
        // require(_usdc != address(0), "invalid token address");
        if (_usdc == address(0)) revert ZeroUsdcAddress();
        usdc = _usdc;
        usdcDecimals = _usdcDecimals;
        return true;
    }

    function setOperator(address _operator, bool _status) public onlyOwner {
        isOperator[_operator] = _status;
    }

    function getPrimaryOrder(bool sell) internal view returns (IOrderProcessor.Order memory) {
        return IOrderProcessor.Order({
            requestTimestamp: uint64(block.timestamp),
            recipient: address(this),
            assetToken: address(0),
            paymentToken: address(usdc),
            sell: sell,
            orderType: IOrderProcessor.OrderType.MARKET,
            assetTokenQuantity: sell ? 100 ether : 0,
            paymentTokenQuantity: sell ? 0 : 100 ether,
            price: 0,
            tif: IOrderProcessor.TIF.GTC
        });
    }

    function calculateFees(uint256 orderAmount) public view returns (uint256) {
        (uint256 flatFee, uint24 percentageFeeRate) = issuer.getStandardFees(false, address(usdc));
        uint256 fees = flatFee + FeeLib.applyPercentageFee(percentageFeeRate, orderAmount);
        return fees;
    }

    function requestBuyOrder(address _indexToken, address _token, uint256 _orderAmount, address _receiver)
        external
        nonReentrant
        whenNotPaused
        returns (uint256)
    {
        // require(_token != address(0), "invalid token address");
        if (_token == address(0)) revert ZeroTokenAddress();
        // require(_receiver != address(0), "invalid address");
        if (_receiver == address(0)) revert ZeroReceiverAddress();
        // require(_orderAmount > 0, "amount must be greater than 0");
        if (_orderAmount == 0) revert AmountMustBeGreaterThanZero();
        // require(isOperator[msg.sender] || msg.sender == owner(), "Not authorized Sender For Buy And Sell");
        if (!isOperator[msg.sender] && msg.sender != owner()) revert UnauthorizedSender();
        uint256 fees = calculateFees(_orderAmount);

        IOrderProcessor.Order memory order = getPrimaryOrder(false);
        order.recipient = _receiver;
        order.assetToken = address(_token);
        order.paymentTokenQuantity = _orderAmount;
        uint256 quantityIn = order.paymentTokenQuantity + fees;

        // require(IERC20(usdc).transferFrom(msg.sender, address(this), quantityIn), "Transfer failed");
        if (!IERC20(usdc).transferFrom(msg.sender, address(this), quantityIn)) revert TransferFailed();
        IERC20(usdc).approve(address(issuer), quantityIn);

        uint256 id = issuer.createOrderStandardFees(order);
        // orderInstanceById[id] = order;
        emit BuyRequest(_indexToken, id, block.timestamp, _orderAmount);
        return id;
        // return 1;
    }

    function requestBuyOrderFromCurrentBalance(
        address _indexToken,
        address _token,
        uint256 _orderAmount,
        address _receiver
    ) external nonReentrant whenNotPaused returns (uint256) {
        // require(_token != address(0), "invalid token address");
        if (_token == address(0)) revert ZeroTokenAddress();
        // require(_receiver != address(0), "invalid address");
        if (_receiver == address(0)) revert ZeroReceiverAddress();
        // require(_orderAmount > 0, "amount must be greater than 0");
        if (_orderAmount == 0) revert AmountMustBeGreaterThanZero();
        // require(isOperator[msg.sender] || msg.sender == owner(), "Not authorized Sender For Buy And Sell");
        if (!isOperator[msg.sender] && msg.sender != owner()) revert UnauthorizedSender();
        uint256 fees = calculateFees(_orderAmount);

        IOrderProcessor.Order memory order = getPrimaryOrder(false);
        order.recipient = _receiver;
        order.assetToken = address(_token);
        order.paymentTokenQuantity = _orderAmount;
        uint256 quantityIn = order.paymentTokenQuantity + fees;

        IERC20(usdc).approve(address(issuer), quantityIn);

        uint256 id = issuer.createOrderStandardFees(order);
        // orderInstanceById[id] = order;
        emit BuyRequest(_indexToken, id, block.timestamp, _orderAmount);
        return id;
        // return 1;
    }

    function requestSellOrder(address _token, uint256 _amount, address _receiver)
        external
        nonReentrant
        whenNotPaused
        returns (uint256)
    {
        // require(_token != address(0), "invalid token address");
        if (_token == address(0)) revert ZeroTokenAddress();
        // require(_receiver != address(0), "invalid address");
        if (_receiver == address(0)) revert ZeroReceiverAddress();
        // require(_amount > 0, "amount must be greater than 0");
        if (_amount == 0) revert AmountMustBeGreaterThanZero();
        // require(isOperator[msg.sender] || msg.sender == owner(), "Not authorized Sender For Buy And Sell");
        if (!isOperator[msg.sender] && msg.sender != owner()) revert UnauthorizedSender();

        IOrderProcessor.Order memory order = getPrimaryOrder(true);
        order.assetToken = _token;
        order.assetTokenQuantity = _amount;
        order.recipient = _receiver;

        // require(IERC20(_token).transferFrom(msg.sender, address(this), _amount), "Transfer failed");
        if (!IERC20(_token).transferFrom(msg.sender, address(this), _amount)) revert TransferFailed();

        IERC20(_token).approve(address(issuer), _amount);
        uint256 id = issuer.createOrderStandardFees(order);

        return id;
    }

    function requestSellOrderFromCurrentBalance(address _token, uint256 _amount, address _receiver)
        external
        nonReentrant
        whenNotPaused
        returns (uint256)
    {
        // require(_token != address(0), "invalid token address");
        if (_token == address(0)) revert ZeroTokenAddress();
        // require(_receiver != address(0), "invalid address");
        if (_receiver == address(0)) revert ZeroReceiverAddress();
        // require(_amount > 0, "amount must be greater than 0");
        if (_amount == 0) revert AmountMustBeGreaterThanZero();
        // require(isOperator[msg.sender] || msg.sender == owner(), "Not authorized Sender For Buy And Sell");
        if (!isOperator[msg.sender] && msg.sender != owner()) revert UnauthorizedSender();

        IOrderProcessor.Order memory order = getPrimaryOrder(true);
        order.assetToken = _token;
        order.assetTokenQuantity = _amount;
        order.recipient = _receiver;

        IERC20(_token).approve(address(issuer), _amount);

        uint256 id = issuer.createOrderStandardFees(order);

        return id;
    }

    function withdrawFunds(address _token, address _to, uint256 _amount) external {
        // require(_token != address(0), "invalid token address");
        if (_token == address(0)) revert ZeroTokenAddress();
        // require(_to != address(0), "invalid address");
        if (_to == address(0)) revert ZeroReceiverAddress();
        // require(_amount > 0, "amount must be greater than 0");
        if (_amount == 0) revert AmountMustBeGreaterThanZero();
        // require(isOperator[msg.sender] || msg.sender == owner(), "Not authorized Sender For Buy And Sell");
        if (!isOperator[msg.sender] && msg.sender != owner()) revert UnauthorizedSender();
        emit FundsWithdrawn(_token, _to, _amount);
        // require(IERC20(_token).transfer(_to, _amount), "Transfer failed");
        if (!IERC20(_token).transfer(_to, _amount)) revert TransferFailed();
    }

    function cancelOrder(uint256 _requestId) external whenNotPaused {
        // require(_requestId > 0, "Invalid Request Id");
        if (_requestId == 0) revert InvalidRequestId();
        // require(isOperator[msg.sender] || msg.sender == owner(), "Not authorized Sender For Buy And Sell");
        if (!isOperator[msg.sender] && msg.sender != owner()) revert UnauthorizedSender();
        issuer.requestCancel(_requestId);
    }
}

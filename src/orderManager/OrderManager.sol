// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "../factory/IndexFactory.sol";

contract OrderManager is Initializable, OwnableUpgradeable {
    using SafeERC20 for IERC20;

    struct OrderNonceInfo {
        uint256 buyOrderNonce;
        uint256 sellOrderNonce;
        uint256 orderNonce;
    }

    // create order function info in struct
    struct CreateOrderConfig {
        uint256 requestNonce;
        address indexTokenAddress;
        address inputTokenAddress;
        address outputTokenAddress;
        uint64 providerIndex; // 1 for ERC20, 2 for ERC721,
        uint256 inputTokenAmount;
        uint256 outputTokenAmount; // for buy order, this will be 0 initially
        bool isBuyOrder;
        uint256 burnPercent;
    }

    struct OrderInfo {
        address indexTokenAddress;
        address targetTokenAddress;
        uint64 providerIndex; // 1 for ERC20, 2 for ERC721, 3 for ERC1155
        uint256 usdcAmount;
        uint256 targetTokenAmount; // for buy order, this will be 0 initially
        bool isBuyOrder;
        bool isExecuted;
        uint256 timestamp;
    }

    OrderNonceInfo public orderNonceInfo;
    address public usdcAddress;
    IndexFactory public factory;

    mapping(address => bool) public isOperator;
    mapping(uint256 => OrderInfo) public orderInfo; // mapping of orderNonce to OrderInfo

    event FundsWithdrawn(address token, address to, uint256 amount);
    event OrderCreated(
        address indexed indexToken,
        uint256 indexed orderNonce,
        address indexed user,
        bool isBuyOrder,
        address inputToken,
        uint256 inputAmount,
        address outputToken,
        uint256 outputAmount
    );

    modifier onlyOperator() {
        require(isOperator[msg.sender], "NexVault: caller is not an operator");
        _;
    }

    function initialize(address _usdcAddress, address _indexFactory) external initializer {
        __Ownable_init(msg.sender);
        usdcAddress = _usdcAddress;
        factory = IndexFactory(_indexFactory);
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function setOperator(address _operator, bool _status) external onlyOwner {
        isOperator[_operator] = _status;
    }

    function setUsdcAddress(address _usdcAddress) external onlyOwner {
        usdcAddress = _usdcAddress;
    }

    function setFactoryAddress(address _factoryAddress) external onlyOwner {
        factory = IndexFactory(_factoryAddress);
    }

    function _increaseOrderNonce(bool isBuyOrder) internal {
        if (isBuyOrder) {
            orderNonceInfo.buyOrderNonce += 1;
        } else {
            orderNonceInfo.sellOrderNonce += 1;
        }
        orderNonceInfo.orderNonce += 1;
    }

    function _transferInputTokenFromCaller(address _inputToken, uint256 _amount) internal {
        require(_inputToken != address(0), "OrderManger: invalid token address");
        require(_amount > 0, "OrderManger: amount must be greater than 0");

        IERC20(_inputToken).safeTransferFrom(msg.sender, address(this), _amount);
    }

    function _initializeOrder(CreateOrderConfig memory _config) internal {
        // logic to initialize buy order
        if (_config.isBuyOrder) {
            orderInfo[orderNonceInfo.orderNonce] = OrderInfo({
                indexTokenAddress: _config.indexTokenAddress,
                targetTokenAddress: _config.outputTokenAddress,
                providerIndex: _config.providerIndex,
                usdcAmount: _config.inputTokenAmount,
                targetTokenAmount: 0,
                isBuyOrder: true,
                isExecuted: false,
                timestamp: block.timestamp
            });
        } else {
            // logic to initialize sell order
            orderInfo[orderNonceInfo.orderNonce] = OrderInfo({
                indexTokenAddress: _config.indexTokenAddress,
                targetTokenAddress: _config.inputTokenAddress,
                providerIndex: _config.providerIndex,
                usdcAmount: 0,
                targetTokenAmount: _config.inputTokenAmount,
                isBuyOrder: false,
                isExecuted: false,
                timestamp: block.timestamp
            });
        }
    }

    function createOrder(CreateOrderConfig memory _config) external onlyOperator returns (uint256 orderNonce) {
        // increasing order nonce
        _increaseOrderNonce(_config.isBuyOrder);
        // transfer USDC from caller to order manager contract
        _transferInputTokenFromCaller(_config.inputTokenAddress, _config.inputTokenAmount);
        // initialize the order based on buy or sell
        _initializeOrder(_config);
        //call the provider function

        // emit the event
        emit OrderCreated(
            _config.indexTokenAddress,
            orderNonceInfo.orderNonce,
            msg.sender,
            _config.isBuyOrder,
            _config.inputTokenAddress,
            _config.inputTokenAmount,
            _config.outputTokenAddress,
            _config.outputTokenAmount
        );
        return orderNonceInfo.orderNonce;
    }

    function completeOrder(uint256 _orderNonce) external onlyOperator {
        require(_orderNonce > 0 && _orderNonce <= orderNonceInfo.orderNonce, "OrderManager: invalid order nonce");
        OrderInfo storage order = orderInfo[_orderNonce];
        require(!order.isExecuted, "OrderManager: order already executed");
        order.isExecuted = true;
        // logic to handle post order execution can be added here
    }

    function completeIssuance(
        uint256 _issuanceNonce,
        address _indexToken,
        address _underlyingTokenAddress,
        uint256 _oldTokenValue,
        uint256 _newTokenValue
    ) external onlyOperator {
        factory.handleCompleteIssuance(
            _issuanceNonce, _indexToken, _underlyingTokenAddress, _oldTokenValue, _newTokenValue
        );
    }

    function redemption(
        uint256 _redemptionNonce,
        address _indexToken,
        address _underlyingTokenAddress,
        uint256 _outputValue
    ) external onlyOperator {
        factory.handleCompleteRedemption(_redemptionNonce, _indexToken, _underlyingTokenAddress, _outputValue);
    }
}

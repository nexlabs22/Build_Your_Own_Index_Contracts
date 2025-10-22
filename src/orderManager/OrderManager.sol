// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "../factory/IndexFactory.sol";
import {BackedFiFactory} from "../backedfi/BackedFiFactory.sol";
import {MainChainFactory} from "../ccip/MainChainFactory.sol";
import {IndexFactoryStorage} from "../factory/IndexFactoryStorage.sol";

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
        uint256 crossChainFee;
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
    BackedFiFactory public backedFiFactory;
    MainChainFactory public mainChainFactory;
    IndexFactoryStorage public factoryStorage;
    uint public issuanceCalled;


    

    mapping(address => bool) public isOperator;
    mapping(uint256 => OrderInfo) public orderInfo; // mapping of orderNonce to OrderInfo
    mapping(address => mapping(uint64 => mapping(uint256 => bool))) public providerToNonceCount; // is cross chain 
    mapping(address => mapping(uint64 => mapping(uint256 => uint256))) public providerNonceToBuyOrderNonce; // mapping of providerNonce to orderNonce
    mapping(address => mapping(uint64 => mapping(uint256 => uint256))) public providerNonceToSellOrderNonce; // mapping of providerNonce to orderNonce
    mapping(uint256 => uint256) public orderNonceToIssuanceNonce; // mapping of orderNonce to issuanceNonce
    mapping(uint256 => uint256) public orderNonceToRedemptionNonce; // mapping of orderNonce to redemptionNonce

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

    function initialize(address _usdcAddress, address _indexFactory, address _factoryStorage) external initializer {
        __Ownable_init(msg.sender);
        usdcAddress = _usdcAddress;
        factory = IndexFactory(_indexFactory);
        factoryStorage = IndexFactoryStorage(_factoryStorage);
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function getOrderNonce() external view returns (uint256) {
        return orderNonceInfo.orderNonce;
    }
    function getCCIPFeeInUsdc(address indexToken, address usdc, uint256 amount)
        external
        view
        returns (uint256)
    {
        uint256 feeInWETH = mainChainFactory.getIssuanceFee(
            indexToken,
            usdc,
            amount
        );
        uint256 feeInUSDC = factoryStorage.convertEthToUsd(feeInWETH);
        return feeInUSDC;
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

    function setFactoryStorage(address _factoryStorage) external onlyOwner {
        factoryStorage = IndexFactoryStorage(_factoryStorage);
    }

    function setBackedFiIndexFactory(address _backedfiFactoryAddress) external onlyOwner {
        backedFiFactory = BackedFiFactory(_backedfiFactoryAddress);
    }

    function setMainChainFactory(address payable _mainChainFactoryAddress) external onlyOwner {
        mainChainFactory = MainChainFactory(_mainChainFactoryAddress);
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
        if(_config.isBuyOrder){
        _transferInputTokenFromCaller(_config.inputTokenAddress, _config.inputTokenAmount + _config.crossChainFee);
        } else if(!_config.isBuyOrder && _config.crossChainFee > 0){
            _transferInputTokenFromCaller(usdcAddress, _config.crossChainFee);
        }
        // initialize the order based on buy or sell
        _initializeOrder(_config);
        //call the provider function
        if(_config.isBuyOrder) {
            if(_config.providerIndex == 1) {
                uint256 ccipNonce = issuanceWithCCIPFactory(
                    _config.indexTokenAddress, 
                    _config.inputTokenAddress,
                    _config.inputTokenAmount,
                    _config.crossChainFee
                );
                providerNonceToBuyOrderNonce[_config.indexTokenAddress][_config.providerIndex][ccipNonce] = orderNonceInfo.orderNonce;
                orderNonceToIssuanceNonce[orderNonceInfo.orderNonce] = _config.requestNonce;
            }
        } else{
            if((_config.providerIndex == 1)) {
                    uint256 ccipNonce = redemptionWithCCIPFactory(_config.indexTokenAddress, _config.burnPercent, _config.outputTokenAddress, _config.crossChainFee);
                    providerNonceToSellOrderNonce[_config.indexTokenAddress][_config.providerIndex][ccipNonce] = orderNonceInfo.orderNonce;
                    orderNonceToRedemptionNonce[orderNonceInfo.orderNonce] = _config.requestNonce;
            }
        }
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
        uint64 _providerIndex,
        uint256 _providerIssuanceNonce,
        address _indexToken,
        address _underlyingTokenAddress,
        uint256 _oldTokenValue,
        uint256 _newTokenValue
    ) external onlyOperator {
        uint256 orderNonce = providerNonceToBuyOrderNonce[_indexToken][_providerIndex][_providerIssuanceNonce];
        factory.handleCompleteIssuance(
            orderNonceToIssuanceNonce[orderNonce], _indexToken, _underlyingTokenAddress, _oldTokenValue, _newTokenValue
        );
    }

    function completeRedemption(
        uint64 providerIndex,
        uint256 _redemptionNonce,
        address _indexToken,
        address _underlyingTokenAddress,
        uint256 _outputValue
    ) external onlyOperator {
        // transfer output usdc
        IERC20(usdcAddress).safeTransferFrom(msg.sender, address(this), _outputValue);
        uint256 orderNonce = providerNonceToSellOrderNonce[_indexToken][providerIndex][_redemptionNonce];
        IERC20(usdcAddress).approve(address(factory), _outputValue);
        factory.handleCompleteRedemption(orderNonceToRedemptionNonce[orderNonce], _indexToken, _underlyingTokenAddress, _outputValue);
    }

    function issuanceWithCCIPFactory(address _indexToken, address _tokenIn, uint256 _inputAmount, uint256 _crossChainFee) internal returns (uint256) {
        require(_inputAmount > 0, "Invalid amount!");
        require(_indexToken != address(0), "Invalid address!");
        IERC20(_tokenIn).approve(address(mainChainFactory), _inputAmount + _crossChainFee);
        return mainChainFactory.issuanceIndexTokens(
            _indexToken,
            _tokenIn,
            _inputAmount,
            _crossChainFee
        );
    }

    function issuanceWithBackedFiFactory(address _indexToken, uint256 _inputAmount) public {
        require(_inputAmount > 0, "Invalid amount!");
        require(_indexToken != address(0), "Invalid address!");
        backedFiFactory.issuanceIndexTokens(_indexToken, _inputAmount);
    }

    function redemptionWithBackedFiFactory(address _indexToken, uint256 _inputAmount, uint256 _burnPercent) public {
        require(_inputAmount > 0, "Invalid amount!");
        require(_indexToken != address(0), "Invalid address!");
        backedFiFactory.redemption(_indexToken, _inputAmount, _burnPercent);
    }

    function redemptionWithCCIPFactory(address _indexToken,uint256 _burnPercent, address _tokenOut, uint256 _crossChainFee) internal returns (uint256) {
        require(_indexToken != address(0), "Invalid address!");
        require(_burnPercent > 0, "Invalid burn percent!");
        require(_tokenOut != address(0), "Invalid address!");
        IERC20(_tokenOut).approve(address(mainChainFactory), _crossChainFee);
        return mainChainFactory.redemption(_indexToken, _burnPercent, _tokenOut, _crossChainFee);
    }
}
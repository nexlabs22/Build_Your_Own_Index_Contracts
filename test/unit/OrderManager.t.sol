// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol"; // Corrected import style
import {console} from "forge-std/console.sol"; // Corrected import style
import {OrderManager} from "../../src/orderManager/OrderManager.sol"; // Corrected import style
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol"; // Corrected import style
import {TestHelpers} from "../utils/TestHelpers.sol"; // Corrected import style
import {MockUSDC} from "../utils/MockContracts.sol"; // Corrected import style

contract OrderManagerTest is Test, TestHelpers {
    OrderManager public orderManager;
    ERC1967Proxy public proxy;
    MockUSDC public mockUsdc; // Corrected variable name
    address public owner;
    address public operator;
    address public user1;

    event OrderCreated(uint indexed orderNonce, address indexed user, bool isBuyOrder, address inputToken, uint256 inputAmount, address outputToken, uint256 outputAmount);

    function setUp() public {
        owner = address(this);
        operator = makeAddr("operator");
        user1 = makeAddr("user1");

        // Deploy mock USDC
        mockUsdc = new MockUSDC(); // Corrected variable name

        // Deploy implementation
        OrderManager implementation = new OrderManager();
        
        // Deploy proxy
        bytes memory initData = abi.encodeWithSelector(
            OrderManager.initialize.selector,
            address(mockUsdc) // Corrected variable name
        );
        
        proxy = new ERC1967Proxy(address(implementation), initData);
        orderManager = OrderManager(address(proxy));
        
        // Set up operator
        vm.prank(owner);
        orderManager.setOperator(operator, true);
        
        // Give user some USDC
        assertTrue(mockUsdc.transfer(user1, 10000 * 1e6)); // Corrected variable name, added assertTrue
    }

    function testInitialization() public view { // Added view
        assertEq(orderManager.owner(), owner);
        assertEq(orderManager.usdcAddress(), address(mockUsdc)); // Corrected variable name
        
        // Destructure the tuple returned by orderNonceInfo()
        (uint buyOrderNonce, uint sellOrderNonce, uint orderNonce) = orderManager.orderNonceInfo();
        assertEq(orderNonce, 0);
        assertEq(buyOrderNonce, 0);
        assertEq(sellOrderNonce, 0);
    }

    function testSetOperator() public {
        vm.prank(owner);
        orderManager.setOperator(user1, true);
        
        assertTrue(orderManager.isOperator(user1));
        
        vm.prank(owner);
        orderManager.setOperator(user1, false);
        
        assertFalse(orderManager.isOperator(user1));
    }

    function testOnlyOwnerCanSetOperator() public {
        vm.prank(user1);
        vm.expectRevert("Ownable: caller is not the owner");
        orderManager.setOperator(user1, true);
    }

    function testSetUsdcAddress() public {
        address newUsdc = makeAddr("newUsdc"); // Corrected variable name
        
        vm.prank(owner);
        orderManager.setUsdcAddress(newUsdc); // Corrected variable name
        
        assertEq(orderManager.usdcAddress(), newUsdc); // Corrected variable name
    }

    function testCreateBuyOrder() public {
        OrderManager.CreateOrderConfig memory config = OrderManager.CreateOrderConfig({
            inputTokenAddress: address(mockUsdc), // Corrected variable name
            outputTokenAddress: makeAddr("indexToken"),
            assetType: 1,
            inputTokenAmount: 1000 * 1e6,
            outputTokenAmount: 0,
            isBuyOrder: true
        });

        vm.prank(user1);
        mockUsdc.approve(address(orderManager), 1000 * 1e6); // Corrected variable name

        vm.expectEmit(true, true, true, true);
        emit OrderCreated(1, operator, true, address(mockUsdc), 1000 * 1e6, makeAddr("indexToken"), 0); // Corrected variable name

        vm.prank(operator);
        uint256 orderId = orderManager.createOrder(config);

        assertEq(orderId, 1);
        
        // Destructure the tuple returned by orderNonceInfo()
        (uint buyOrderNonce, uint sellOrderNonce, uint orderNonce) = orderManager.orderNonceInfo();
        assertEq(orderNonce, 1);
        assertEq(buyOrderNonce, 1);
        assertEq(sellOrderNonce, 0);
        
        // Destructure the tuple returned by orderInfo()
        (address _targetTokenAddress, uint64 _assetType, uint256 _usdcAmount, uint256 _targetTokenAmount, bool _isBuyOrder, bool _isExecuted, uint256 _timestamp) = orderManager.orderInfo(1); // Used _ for unused variables
        assertEq(_targetTokenAddress, makeAddr("indexToken"));
        assertEq(_assetType, 1);
        assertEq(_usdcAmount, 1000 * 1e6);
        assertEq(_targetTokenAmount, 0);
        assertTrue(_isBuyOrder);
        assertFalse(_isExecuted);
        assertEq(_timestamp, block.timestamp);
    }

    function testCreateSellOrder() public {
        OrderManager.CreateOrderConfig memory config = OrderManager.CreateOrderConfig({
            inputTokenAddress: makeAddr("indexToken"),
            outputTokenAddress: address(mockUsdc), // Corrected variable name
            assetType: 1,
            inputTokenAmount: 1000 * 1e18,
            outputTokenAmount: 0,
            isBuyOrder: false
        });

        vm.prank(user1);
        mockUsdc.approve(address(orderManager), 1000 * 1e6); // Corrected variable name

        vm.expectEmit(true, true, true, true);
        emit OrderCreated(1, operator, false, makeAddr("indexToken"), 1000 * 1e18, address(mockUsdc), 0); // Corrected variable name

        vm.prank(operator);
        uint256 orderId = orderManager.createOrder(config);

        assertEq(orderId, 1);
        
        // Destructure the tuple returned by orderNonceInfo()
        (uint buyOrderNonce, uint sellOrderNonce, uint orderNonce) = orderManager.orderNonceInfo();
        assertEq(orderNonce, 1);
        assertEq(buyOrderNonce, 0);
        assertEq(sellOrderNonce, 1);
        
        // Destructure the tuple returned by orderInfo()
        (address _targetTokenAddress, uint64 _assetType, uint256 _usdcAmount, uint256 _targetTokenAmount, bool _isBuyOrder, bool _isExecuted, uint256 _timestamp) = orderManager.orderInfo(1); // Used _ for unused variables
        assertEq(_targetTokenAddress, makeAddr("indexToken"));
        assertEq(_assetType, 1);
        assertEq(_usdcAmount, 0);
        assertEq(_targetTokenAmount, 1000 * 1e18);
        assertFalse(_isBuyOrder);
        assertFalse(_isExecuted);
        assertEq(_timestamp, block.timestamp);
    }

    function testCreateOrderOnlyOperator() public {
        OrderManager.CreateOrderConfig memory config = OrderManager.CreateOrderConfig({
            inputTokenAddress: address(mockUsdc), // Corrected variable name
            outputTokenAddress: makeAddr("indexToken"),
            assetType: 1,
            inputTokenAmount: 1000 * 1e6,
            outputTokenAmount: 0,
            isBuyOrder: true
        });

        vm.prank(user1);
        mockUsdc.approve(address(orderManager), 1000 * 1e6); // Corrected variable name

        vm.prank(user1);
        vm.expectRevert("OrderManager: caller is not an operator");
        orderManager.createOrder(config);
    }

    function testCreateOrderInvalidToken() public {
        OrderManager.CreateOrderConfig memory config = OrderManager.CreateOrderConfig({
            inputTokenAddress: address(0),
            outputTokenAddress: makeAddr("indexToken"),
            assetType: 1,
            inputTokenAmount: 1000 * 1e6,
            outputTokenAmount: 0,
            isBuyOrder: true
        });

        vm.prank(operator);
        vm.expectRevert("OrderManager: invalid token address");
        orderManager.createOrder(config);
    }

    function testCreateOrderZeroAmount() public {
        OrderManager.CreateOrderConfig memory config = OrderManager.CreateOrderConfig({
            inputTokenAddress: address(mockUsdc), // Corrected variable name
            outputTokenAddress: makeAddr("indexToken"),
            assetType: 1,
            inputTokenAmount: 0,
            outputTokenAmount: 0,
            isBuyOrder: true
        });

        vm.prank(operator);
        vm.expectRevert("OrderManager: amount must be greater than 0");
        orderManager.createOrder(config);
    }

    function testCompleteOrder() public {
        // First create an order
        OrderManager.CreateOrderConfig memory config = OrderManager.CreateOrderConfig({
            inputTokenAddress: address(mockUsdc), // Corrected variable name
            outputTokenAddress: makeAddr("indexToken"),
            assetType: 1,
            inputTokenAmount: 1000 * 1e6,
            outputTokenAmount: 0,
            isBuyOrder: true
        });

        vm.prank(user1);
        mockUsdc.approve(address(orderManager), 1000 * 1e6); // Corrected variable name

        vm.prank(operator);
        uint256 orderId = orderManager.createOrder(config);

        // Complete the order
        vm.prank(operator);
        orderManager.completeOrder(orderId);

        // Destructure the tuple returned by orderInfo()
        (address _targetTokenAddress, uint64 _assetType, uint256 _usdcAmount, uint256 _targetTokenAmount, bool _isBuyOrder, bool isExecuted, uint256 _timestamp) = orderManager.orderInfo(orderId); // Used _ for unused variables
        assertTrue(isExecuted);
    }

    function testCompleteOrderOnlyOperator() public {
        vm.prank(user1);
        vm.expectRevert("OrderManager: caller is not an operator");
        orderManager.completeOrder(1);
    }

    function testCompleteOrderInvalidNonce() public {
        vm.prank(operator);
        vm.expectRevert("OrderManager: invalid order nonce");
        orderManager.completeOrder(0);
    }

    function testCompleteOrderAlreadyExecuted() public {
        // Create and complete an order
        OrderManager.CreateOrderConfig memory config = OrderManager.CreateOrderConfig({
            inputTokenAddress: address(mockUsdc), // Corrected variable name
            outputTokenAddress: makeAddr("indexToken"),
            assetType: 1,
            inputTokenAmount: 1000 * 1e6,
            outputTokenAmount: 0,
            isBuyOrder: true
        });

        vm.prank(user1);
        mockUsdc.approve(address(orderManager), 1000 * 1e6); // Corrected variable name

        vm.prank(operator);
        uint256 orderId = orderManager.createOrder(config);

        vm.prank(operator);
        orderManager.completeOrder(orderId);

        // Try to complete again
        vm.prank(operator);
        vm.expectRevert("OrderManager: order already executed");
        orderManager.completeOrder(orderId);
    }
}

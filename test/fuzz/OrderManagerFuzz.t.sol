// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol"; // Corrected import style
import {console} from "forge-std/console.sol"; // Corrected import style
import {OrderManager} from "../../src/orderManager/OrderManager.sol"; // Corrected import style
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol"; // Corrected import style
import {TestHelpers} from "../utils/TestHelpers.sol"; // Corrected import style
import {MockUSDC} from "../utils/MockContracts.sol"; // Corrected import style

contract OrderManagerFuzzTest is Test, TestHelpers {
    OrderManager public orderManager;
    ERC1967Proxy public proxy;
    MockUSDC public mockUsdc; // Corrected variable name
    address public owner;
    address public operator;
    address public user1;

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
        assertTrue(mockUsdc.transfer(user1, 1000000 * 1e6)); // Corrected variable name, added assertTrue
    }

    function testFuzzCreateBuyOrder(uint256 amount) public {
        vm.assume(amount > 0 && amount <= 1000000 * 1e6);
        
        OrderManager.CreateOrderConfig memory config = OrderManager.CreateOrderConfig({
            inputTokenAddress: address(mockUsdc), // Corrected variable name
            outputTokenAddress: makeAddr("indexToken"),
            assetType: 1,
            inputTokenAmount: amount,
            outputTokenAmount: 0,
            isBuyOrder: true
        });

        vm.prank(user1);
        mockUsdc.approve(address(orderManager), amount); // Corrected variable name

        vm.prank(operator);
        uint256 orderId = orderManager.createOrder(config);

        assertEq(orderId, 1);
        
        // Destructure the tuple returned by orderNonceInfo()
        (uint buyOrderNonce, , ) = orderManager.orderNonceInfo();
        assertEq(buyOrderNonce, 1);
        
        // Destructure the tuple returned by orderInfo()
        (address _targetTokenAddress, uint64 _assetType, uint256 _usdcAmount, uint256 _targetTokenAmount, bool _isBuyOrder, bool _isExecuted, uint256 _timestamp) = orderManager.orderInfo(1); // Used _ for unused variables
        assertEq(_targetTokenAddress, makeAddr("indexToken"));
        assertEq(_assetType, 1);
        assertEq(_usdcAmount, amount);
        assertEq(_targetTokenAmount, 0);
        assertTrue(_isBuyOrder);
        assertFalse(_isExecuted);
    }

    function testFuzzCreateSellOrder(uint256 amount) public {
        vm.assume(amount > 0 && amount <= 1000000 * 1e18);
        
        OrderManager.CreateOrderConfig memory config = OrderManager.CreateOrderConfig({
            inputTokenAddress: makeAddr("indexToken"),
            outputTokenAddress: address(mockUsdc), // Corrected variable name
            assetType: 1,
            inputTokenAmount: amount,
            outputTokenAmount: 0,
            isBuyOrder: false
        });

        vm.prank(operator);
        uint256 orderId = orderManager.createOrder(config);

        assertEq(orderId, 1);
        
        // Destructure the tuple returned by orderNonceInfo()
        (, uint sellOrderNonce, ) = orderManager.orderNonceInfo();
        assertEq(sellOrderNonce, 1);
        
        // Destructure the tuple returned by orderInfo()
        (address _targetTokenAddress, uint64 _assetType, uint256 _usdcAmount, uint256 _targetTokenAmount, bool _isBuyOrder, bool _isExecuted, uint256 _timestamp) = orderManager.orderInfo(1); // Used _ for unused variables
        assertEq(_targetTokenAddress, makeAddr("indexToken"));
        assertEq(_assetType, 1);
        assertEq(_usdcAmount, 0);
        assertEq(_targetTokenAmount, amount);
        assertFalse(_isBuyOrder);
        assertFalse(_isExecuted);
    }

    function testFuzzMultipleOrders(uint256 numOrders) public {
        vm.assume(numOrders > 0 && numOrders <= 10);
        
        for (uint256 i = 0; i < numOrders; i++) {
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

            assertEq(orderId, i + 1);
            
            // Destructure the tuple returned by orderInfo()
            (address _targetTokenAddress, uint64 _assetType, uint256 _usdcAmount, uint256 _targetTokenAmount, bool _isBuyOrder, bool _isExecuted, uint256 _timestamp) = orderManager.orderInfo(orderId); // Used _ for unused variables
            assertEq(_targetTokenAddress, makeAddr("indexToken"));
            assertEq(_assetType, 1);
            assertEq(_usdcAmount, 1000 * 1e6);
            assertEq(_targetTokenAmount, 0);
            assertTrue(_isBuyOrder);
            assertFalse(_isExecuted);
        }
        
        // Destructure the tuple returned by orderNonceInfo()
        (, , uint orderNonce) = orderManager.orderNonceInfo();
        assertEq(orderNonce, numOrders);
    }
}
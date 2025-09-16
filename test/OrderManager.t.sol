// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {OrderManager} from "../../src/orderManager/OrderManager.sol";
import "./utils/TestERC20.sol";

contract OrderManager_MainTest is Test {
    address owner_ = address(0xA11CE);
    address operator_ = makeAddr("operator");
    address user = address(0xBEEF);

    address idxToken = makeAddr("IDX");
    address outToken = makeAddr("OUT"); // dummy output token address

    TestERC20 usdc;
    TestERC20 underlying;

    OrderManager orderManagerImpl;
    OrderManager orderManager;

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

    function setUp() public {
        vm.startPrank(owner_);

        usdc = new TestERC20("USD Coin", "USDC");
        underlying = new TestERC20("Underlying", "UND");

        orderManagerImpl = new OrderManager();

        orderManager = OrderManager(
            address(
                new ERC1967Proxy(
                    address(orderManagerImpl),
                    abi.encodeCall(OrderManager.initialize, (address(usdc), address(0xDEAD))) // factory addr placeholder
                )
            )
        );

        orderManager.setOperator(operator_, true);

        usdc.mint(operator_, 1_000_000e18);
        underlying.mint(operator_, 500_000e18);
        vm.stopPrank();

        vm.startPrank(operator_);
        usdc.approve(address(orderManager), type(uint256).max);
        underlying.approve(address(orderManager), type(uint256).max);
        vm.stopPrank();
    }

    function testOwnerOnly_AdminSetters() public {
        vm.prank(owner_);
        orderManager.setUsdcAddress(address(underlying));
        assertEq(orderManager.usdcAddress(), address(underlying));

        vm.prank(owner_);
        orderManager.setFactoryAddress(address(0xFACADE));

        vm.expectRevert();
        orderManager.setUsdcAddress(address(usdc));
    }

    // ===== onlyOperator gating =====

    function testOnlyOperator_CreateOrder_RevertsForNonOperator() public {
        OrderManager.CreateOrderConfig memory cfg = OrderManager.CreateOrderConfig({
            requestNonce: 1,
            indexTokenAddress: idxToken,
            inputTokenAddress: address(usdc),
            outputTokenAddress: outToken,
            providerIndex: 1,
            inputTokenAmount: 100e18,
            outputTokenAmount: 0,
            isBuyOrder: true,
            burnPercent: 0
        });

        vm.expectRevert(bytes("NexVault: caller is not an operator"));
        vm.prank(user);
        orderManager.createOrder(cfg);
    }

    function testOnlyOperator_CompleteOrder_RevertsForNonOperator() public {
        // Prepare an order first from operator
        OrderManager.CreateOrderConfig memory cfg = OrderManager.CreateOrderConfig({
            requestNonce: 42,
            indexTokenAddress: idxToken,
            inputTokenAddress: address(usdc),
            outputTokenAddress: outToken,
            providerIndex: 1,
            inputTokenAmount: 10e18,
            outputTokenAmount: 0,
            isBuyOrder: true,
            burnPercent: 0
        });

        vm.prank(operator_);
        uint256 nonce = orderManager.createOrder(cfg);

        vm.expectRevert(bytes("NexVault: caller is not an operator"));
        vm.prank(user);
        orderManager.completeOrder(nonce);
    }

    function testCreateOrder_Buy_SetsState_PullsFunds_Emits() public {
        uint256 amt = 123e18;

        OrderManager.CreateOrderConfig memory cfg = OrderManager.CreateOrderConfig({
            requestNonce: 7,
            indexTokenAddress: idxToken,
            inputTokenAddress: address(usdc), // buy -> paying in USDC
            outputTokenAddress: outToken, // want OUT token
            providerIndex: 1,
            inputTokenAmount: amt,
            outputTokenAmount: 0,
            isBuyOrder: true,
            burnPercent: 0
        });

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit OrderCreated(
            idxToken,
            1, // first ever order nonce
            operator_,
            true,
            address(usdc),
            amt,
            outToken,
            0
        );

        uint256 balBefore = usdc.balanceOf(operator_);

        vm.prank(operator_);
        uint256 orderNonce = orderManager.createOrder(cfg);

        assertEq(orderNonce, 1, "order nonce mismatch");
        assertEq(usdc.balanceOf(operator_), balBefore - amt, "operator usdc debited");
        assertEq(usdc.balanceOf(address(orderManager)), amt, "OM credited usdc");

        address indexTokenAddress;
        address targetTokenAddress;
        uint64 providerIndex;
        uint256 usdcAmount;
        uint256 targetTokenAmount;
        bool isBuy;
        bool isExecuted;
        uint256 burnPercent;

        // Proper 8-value destructure with types
        (
            indexTokenAddress,
            targetTokenAddress,
            providerIndex,
            usdcAmount,
            targetTokenAmount,
            isBuy,
            isExecuted,
            burnPercent
        ) = orderManager.orderInfo(orderNonce);

        assertEq(usdcAmount, amt, "stored usdcAmount");
        assertEq(targetTokenAmount, 0, "stored targetTokenAmount");
        assertEq(isBuy, true, "stored isBuy");
        assertEq(isExecuted, false, "stored isExecuted");

        // Read struct-as-tuple
        (uint256 buyN, uint256 sellN, uint256 ordN) = orderManager.orderNonceInfo();
        assertEq(buyN, 1, "buy nonce");
        assertEq(sellN, 0, "sell nonce");
        assertEq(ordN, 1, "total nonce");
    }

    function testCreateOrder_Sell_SetsState_PullsFunds_Emits() public {
        uint256 amt = 77e18;

        OrderManager.CreateOrderConfig memory cfg = OrderManager.CreateOrderConfig({
            requestNonce: 8,
            indexTokenAddress: idxToken,
            inputTokenAddress: address(underlying), // sell -> sending underlying in
            outputTokenAddress: address(usdc), // want USDC back (hint)
            providerIndex: 1,
            inputTokenAmount: amt,
            outputTokenAmount: 0,
            isBuyOrder: false,
            burnPercent: 0
        });

        uint256 balBefore = underlying.balanceOf(operator_);

        vm.expectEmit(true, true, true, true);
        emit OrderCreated(idxToken, 1, operator_, false, address(underlying), amt, address(usdc), 0);

        vm.prank(operator_);
        uint256 orderNonce = orderManager.createOrder(cfg);

        assertEq(orderNonce, 1, "order nonce mismatch");
        assertEq(underlying.balanceOf(operator_), balBefore - amt, "operator underlying debited");
        assertEq(underlying.balanceOf(address(orderManager)), amt, "OM credited underlying");

        address indexTokenAddress;
        address targetTokenAddress;
        uint64 providerIndex;
        uint256 usdcAmount;
        uint256 targetTokenAmount;
        bool isBuy;
        bool isExecuted;
        uint256 burnPercent;

        (
            indexTokenAddress,
            targetTokenAddress,
            providerIndex,
            usdcAmount,
            targetTokenAmount,
            isBuy,
            isExecuted,
            burnPercent
        ) = orderManager.orderInfo(orderNonce);

        assertEq(usdcAmount, 0, "sell sets usdcAmount to 0 (uses targetTokenAmount)");
        assertEq(targetTokenAmount, amt, "stored targetTokenAmount");
        assertEq(isBuy, false, "stored isBuy");
        assertEq(isExecuted, false, "stored isExecuted");

        // (uint256 buyN, uint256 sellN, uint256 ordN) =
        //     (orderManager.orderNonceInfo().buyOrderNonce, orderManager.orderNonceInfo().sellOrderNonce, orderManager.orderNonceInfo().orderNonce);
        // assertEq(buyN, 0, "buy nonce");
        // assertEq(sellN, 1, "sell nonce");
        // assertEq(ordN, 1, "total nonce");
    }

    function testCreateOrder_Revert_ZeroInputToken() public {
        OrderManager.CreateOrderConfig memory cfg = OrderManager.CreateOrderConfig({
            requestNonce: 1,
            indexTokenAddress: idxToken,
            inputTokenAddress: address(0),
            outputTokenAddress: outToken,
            providerIndex: 1,
            inputTokenAmount: 1e18,
            outputTokenAmount: 0,
            isBuyOrder: true,
            burnPercent: 0
        });

        vm.expectRevert(bytes("OrderManger: invalid token address"));
        vm.prank(operator_);
        orderManager.createOrder(cfg);
    }

    function testCreateOrder_Revert_ZeroAmount() public {
        OrderManager.CreateOrderConfig memory cfg = OrderManager.CreateOrderConfig({
            requestNonce: 1,
            indexTokenAddress: idxToken,
            inputTokenAddress: address(usdc),
            outputTokenAddress: outToken,
            providerIndex: 1,
            inputTokenAmount: 0,
            outputTokenAmount: 0,
            isBuyOrder: true,
            burnPercent: 0
        });

        vm.expectRevert(bytes("OrderManger: amount must be greater than 0"));
        vm.prank(operator_);
        orderManager.createOrder(cfg);
    }

    function testCompleteOrder_SetsExecuted_AndRevertsOnSecondCall() public {
        OrderManager.CreateOrderConfig memory cfg = OrderManager.CreateOrderConfig({
            requestNonce: 99,
            indexTokenAddress: idxToken,
            inputTokenAddress: address(usdc),
            outputTokenAddress: outToken,
            providerIndex: 1,
            inputTokenAmount: 5e18,
            outputTokenAmount: 0,
            isBuyOrder: true,
            burnPercent: 0
        });

        vm.prank(operator_);
        uint256 orderNonce = orderManager.createOrder(cfg);

        vm.prank(operator_);
        orderManager.completeOrder(orderNonce);

        address indexTokenAddress;
        address targetTokenAddress;
        uint64 providerIndex;
        uint256 usdcAmount;
        uint256 targetTokenAmount;
        bool isBuy;
        bool isExecuted;
        uint256 burnPercent;

        (
            indexTokenAddress,
            targetTokenAddress,
            providerIndex,
            usdcAmount,
            targetTokenAmount,
            isBuy,
            isExecuted,
            burnPercent
        ) = orderManager.orderInfo(orderNonce);
        assertTrue(isExecuted, "order should be executed");

        vm.expectRevert(bytes("OrderManager: order already executed"));
        vm.prank(operator_);
        orderManager.completeOrder(orderNonce);
    }

    function testCompleteOrder_Revert_InvalidNonce() public {
        vm.expectRevert(bytes("OrderManager: invalid order nonce"));
        vm.prank(operator_);
        orderManager.completeOrder(1);
    }
}

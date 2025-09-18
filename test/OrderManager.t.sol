// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {OrderManager} from "../../src/orderManager/OrderManager.sol";
// import {IndexFactory} from "../src/factory/IndexFactory.sol";
import {BackedFiFactory} from "../src/backedfi/BackedFiFactory.sol";
import {IndexFactoryStorage} from "../src/backedfi/IndexFactoryStorage.sol";
import "./OlympixUnitTest.sol";
import "./utils/TestERC20.sol";

contract OrderManagerTest is OlympixUnitTest("OrderManager") {
    address owner_ = address(0xA11CE);
    address operator_ = makeAddr("operator");
    address user = address(0xBEEF);

    address idxToken = makeAddr("IDX");
    address outToken = makeAddr("OUT"); // dummy output token address

    TestERC20 usdc;
    TestERC20 underlying;

    OrderManager orderManagerImpl;
    OrderManager orderManager;
    BackedFiFactory indexFactoryImpl;
    BackedFiFactory indexFactory;
    IndexFactoryStorage indexFactoryStorageImpl;
    IndexFactoryStorage indexFactoryStorage;

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

        // ---- implementations ----
        orderManagerImpl = new OrderManager();
        indexFactoryImpl = new BackedFiFactory();
        indexFactoryStorageImpl = new IndexFactoryStorage();

        // ---- proxy: IndexFactoryStorage ----
        indexFactoryStorage = IndexFactoryStorage(
            address(
                new ERC1967Proxy(
                    address(indexFactoryStorageImpl),
                    abi.encodeCall(
                        IndexFactoryStorage.initialize,
                        (
                            address(0xDEAD), // _indexFactory (placeholder, non-zero)
                            address(0xBEEF), // _functionsOracle (placeholder, non-zero)
                            address(0xCAFE), // _stagingCustodyAccount (placeholder, non-zero)
                            address(0xB), // _nexBot (placeholder, non-zero)
                            address(usdc) // _usdc (real)
                        )
                    )
                )
            )
        );

        // ---- proxy: BackedFiFactory ----
        // needs: (_indexFactoryStorage, _feeVault)
        indexFactory = BackedFiFactory(
            address(
                new ERC1967Proxy(
                    address(indexFactoryImpl),
                    abi.encodeCall(
                        BackedFiFactory.initialize,
                        (address(indexFactoryStorage)) // pass the *proxy* of storage + non-zero fee vault
                    )
                )
            )
        );

        // After factory proxy exists, set it into storage (owner-only)
        indexFactoryStorage.setIndexFactory(address(indexFactory));

        // ---- proxy: OrderManager ----
        // needs: (usdcAddress, indexFactoryAddress)
        orderManager = OrderManager(
            address(
                new ERC1967Proxy(
                    address(orderManagerImpl),
                    abi.encodeCall(
                        OrderManager.initialize,
                        (address(usdc), address(indexFactory)) // pass the *proxy* of BackedFiFactory (or IndexFactory if you have it)
                    )
                )
            )
        );

        // operator setup + funds
        orderManager.setOperator(operator_, true);
        orderManager.setBackedFiIndexFactory(address(indexFactory));
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

    function test_issuanceWithBackedFiFactory_Revert_InvalidAmount() public {
        // Arrange: Deploy minimal mock for backedFiFactory
        address mockBackedFi = address(0x420420);
        vm.prank(owner_);
        orderManager.setFactoryAddress(address(0xDEAD));

        // Note:
        // We'll set backedFiFactory via storage slot. For now, assume it's initialized to 0.
        bytes32 slot = bytes32(uint256(6)); // backedFiFactory is the 6th storage slot (after 5 simple types), per inheritance order
        vm.store(address(orderManager), slot, bytes32(uint256(uint160(mockBackedFi))));

        // _inputAmount == 0 should revert with "Invalid amount!"
        vm.expectRevert(bytes("Invalid amount!"));
        orderManager.issuanceWithBackedFiFactory(idxToken, 0);
    }

    function test_issuanceWithBackedFiFactory_Revert_InvalidAddress() public {
        // Arrange: Deploy minimal mock for backedFiFactory
        address mockBackedFi = address(0x420420);
        vm.prank(owner_);
        orderManager.setFactoryAddress(address(0xDEAD));

        // Patch backedFiFactory address via low-level store
        bytes32 slot = bytes32(uint256(6));
        vm.store(address(orderManager), slot, bytes32(uint256(uint160(mockBackedFi))));

        // Should revert if indexToken is address(0)
        vm.expectRevert(bytes("Invalid address!"));
        orderManager.issuanceWithBackedFiFactory(address(0), 100);
    }

    // Positive branch for opix-target-branch-212-True
    function test_issuanceWithBackedFiFactory_HappyPath() public {
        usdc.mint(address(orderManager), 1_000_000e18);

        vm.startPrank(address(orderManager));
        usdc.approve(address(indexFactory), 1_000_000e18);
        vm.stopPrank();

        // Arrange: Deploy a minimal backedFiFactory mock that records call
        address mockBackedFi;
        {
            // Deploy a contract which emits log on call to issuanceIndexTokens
            bytes memory code =
                hex"608060405234801561001057600080fd5b50610149806100206000396000f3fe6080604052600436106100235760003560e01c80636a9027e514610028575b600080fd5b610038600480360381019061003391906100da565b61003a565b005b8373ffffffffffffffffffffffffffffffffffffffff166323b872dd6040518163ffffffff1660e01b815260040160206040518083038186803b15801561007657600080fd5b505af415801561008a573d6000803e3d6000fd5b5050505056fea2646970667358221220aeed5be69bd77cbb5dc8a798e4fdd9636c3f7e6e51397bf7a10d1671b4d8b65b64736f6c63430008190033"; // minimal stub: just returns, no storage
            assembly {
                mockBackedFi := create(0, add(code, 0x20), mload(code))
            }
        }
        vm.prank(owner_);
        orderManager.setFactoryAddress(address(0xDEAD));
        // Patch backedFiFactory via storage slot
        bytes32 slot = bytes32(uint256(6));
        vm.store(address(orderManager), slot, bytes32(uint256(uint160(mockBackedFi))));

        // Call happy path: nonzero input, valid address
        orderManager.issuanceWithBackedFiFactory(idxToken, 100);
    }

    function test_redemptionWithBackedFiFactory_zeroAmount_reverts() public {
        // Arrange: Set up a minimal mock BackedFiFactory
        // Setup the storage slot for backedFiFactory. It is slot 6 in OrderManager (after 5 vars used),
        // but for ownable proxy, the layout is preserved. We'll use slot 6, as in other similar tests above.
        address mockBackedFi;
        {
            // Deploy a contract which has a fallback for .redemption(), just returns (for the revert test, not called)
            bytes memory code =
                hex"6080604052348015600f57600080fd5b5060c08061001d6000396000f3fe60806040526004361060295760003560e01c8063b3fecbc514602e575b600080fd5b603c60383660046045565b603e565b005b7fffffffff00000000000000000000000000000000000000000000000000000000000000006020526000908152604090205460ff168156fea264697066735822122044b492ec3765e5486de6d7c33433851ae4b8c5e8ddbed5df10dc9b6ec4eaae6064736f6c63430008190033";
            assembly {
                mockBackedFi := create(0, add(code, 0x20), mload(code))
            }
        }
        // Patch the backedFiFactory storage slot
        vm.prank(owner_);
        orderManager.setFactoryAddress(address(0xDEAD));
        bytes32 slot = bytes32(uint256(6));
        vm.store(address(orderManager), slot, bytes32(uint256(uint160(mockBackedFi))));
        // test: amount == 0 triggers revert (opix-target-branch-218-True)
        vm.expectRevert(bytes("Invalid amount!"));
        orderManager.redemptionWithBackedFiFactory(idxToken, 0, 123);
    }

    function test_redemptionWithBackedFiFactory_zeroIndexTokenAddress_reverts() public {
        // Arrange: Set up a minimal mock BackedFiFactory that just returns
        address mockBackedFi;
        {
            // Deploy a contract that has a fallback for .redemption(), does nothing
            bytes memory code =
                hex"6080604052348015600f57600080fd5b5060c08061001d6000396000f3fe60806040526004361060295760003560e01c8063b3fecbc514602e575b600080fd5b603c60383660046045565b603e565b005b7fffffffff00000000000000000000000000000000000000000000000000000000000000006020526000908152604090205460ff168156fea264697066735822122044b492ec3765e5486de6d7c33433851ae4b8c5e8ddbed5df10dc9b6ec4eaae6064736f6c63430008190033";
            assembly {
                mockBackedFi := create(0, add(code, 0x20), mload(code))
            }
        }
        // Patch the backedFiFactory storage slot in the proxy instance
        vm.prank(owner_);
        orderManager.setFactoryAddress(address(0xDEAD));
        bytes32 slot = bytes32(uint256(6));
        vm.store(address(orderManager), slot, bytes32(uint256(uint160(mockBackedFi))));
        // test: indexToken == address(0) triggers revert (opix-target-branch-219-True)
        vm.expectRevert(bytes("Invalid address!"));
        orderManager.redemptionWithBackedFiFactory(address(0), 123, 456);
    }
}

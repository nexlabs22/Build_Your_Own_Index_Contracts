// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {DinariFactory} from "../../src/dinari/DinariFactory.sol";
import {DinariStorage} from "../../src/dinari/DinariStorage.sol";
import {FunctionsOracle} from "../../src/oracle/FunctionsOracle.sol";
import {IndexFactoryStorage} from "../../src/factory/IndexFactoryStorage.sol";
import {DinariOrderManager} from "../../src/dinari/DinariOrderManager.sol";
import {TestERC20} from "../utils/TestERC20.sol";
import "../OlympixUnitTest.sol";

interface IOrderProcessor {
    enum OrderType {
        LIMIT,
        MARKET
    }
    enum TIF {
        GTC,
        IOC,
        FOK
    }
    enum OrderStatus {
        NONE,
        ACTIVE,
        FULFILLED,
        CANCELLED
    }

    struct Order {
        uint64 requestTimestamp;
        address recipient;
        address assetToken;
        address paymentToken;
        bool sell;
        OrderType orderType;
        uint256 assetTokenQuantity;
        uint256 paymentTokenQuantity;
        uint256 price;
        TIF tif;
    }

    struct PricePoint {
        uint256 price;
        uint256 timestamp;
    }

    function getStandardFees(bool sell, address paymentToken) external view returns (uint256 flatFee, uint24 pctFee);
    function latestFillPrice(address asset, address quote) external view returns (PricePoint memory);
    function orderDecimalReduction(address token) external view returns (uint8);
    function getOrderStatus(uint256 id) external view returns (OrderStatus);
}

/* ---------- Minimal external issuer stub ---------- */
contract TestIssuer is IOrderProcessor {
    function getStandardFees(bool, address) external pure returns (uint256, uint24) {
        return (0, 0); // keep issuance fee = 0 for a simple USDC transfer test
    }

    function latestFillPrice(address, address) external view returns (PricePoint memory) {
        return PricePoint({price: 1e18, timestamp: block.timestamp});
    }

    function orderDecimalReduction(address) external pure returns (uint8) {
        return 0;
    }

    function getOrderStatus(uint256) external pure returns (OrderStatus) {
        return OrderStatus.ACTIVE;
    }
}

contract DinariFactory_MainTest is OlympixUnitTest("DinariFactory") {
    address owner = address(0xA11CE);
    address user = address(0xBEEF);
    address balancer = makeAddr("Balancer");

    address idxToken = makeAddr("IDX"); // just an address for event topic

    TestERC20 usdc;

    // core instances
    DinariFactory factoryImpl;
    DinariFactory factory;

    DinariStorage storageImpl;
    DinariStorage dinariStorage;

    IndexFactoryStorage gFactoryImpl;
    IndexFactoryStorage gFactory;

    DinariOrderManager omImpl;
    DinariOrderManager om;

    FunctionsOracle oracleImpl;
    FunctionsOracle oracle;

    TestIssuer issuer;

    event RequestIssuance(
        address indexed indexToken,
        uint256 indexed nonce,
        address indexed user,
        address inputToken,
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 time
    );

    function setUp() public {
        vm.startPrank(owner);

        usdc = new TestERC20("USD Coin", "USDC");
        issuer = new TestIssuer();

        // Global storage (IndexFactoryStorage)
        gFactoryImpl = new IndexFactoryStorage();
        gFactory = IndexFactoryStorage(address(new ERC1967Proxy(address(gFactoryImpl), "")));
        gFactory.initialize(
            // address(0xDEAD), // indexFactory
            // address(0xF00D), // functionsOracle (unused path here)
            // address(0xCAFE), // SCA
            // address(0xB07), // nexBot
            // address(usdc) // usdc
        );

        // FunctionsOracle (real)
        oracleImpl = new FunctionsOracle();
        oracle = FunctionsOracle(address(new ERC1967Proxy(address(oracleImpl), "")));
        oracle.initialize(address(0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF), bytes32("DON"));

        // DinariStorage
        storageImpl = new DinariStorage();
        dinariStorage = DinariStorage(address(new ERC1967Proxy(address(storageImpl), "")));
        dinariStorage.initialize(
            address(issuer),
            address(gFactory),
            address(0x11111),
            address(usdc),
            6, // USDC decimals
            address(oracle),
            false, // isMainnet
            1 // providerIndex
        );

        // DinariOrderManager (your contract; initializer defaults assumed)
        omImpl = new DinariOrderManager();
        om = DinariOrderManager(address(new ERC1967Proxy(address(omImpl), "")));
        // allow factory to deposit into order manager by just setting it in storage
        dinariStorage.setOrderManager(address(om));

        // DinariFactory
        factoryImpl = new DinariFactory();
        factory = DinariFactory(address(new ERC1967Proxy(address(factoryImpl), "")));
        factory.initialize(address(gFactory), address(dinariStorage), address(oracle));

        // give balancer power in storage so pause/unpause alt-path works
        vm.stopPrank();
        vm.prank(owner);
        dinariStorage.setFactoryBalancer(balancer);

        // fund user & approve factory (fee=0 with TestIssuer)
        usdc.mint(user, 1_000e6);
        vm.prank(user);
        usdc.approve(address(dinariStorage.dinariOrderManager()), type(uint256).max); // Factory transfers to OM
        // NOTE: DinariFactory.transferFrom uses spender = factory, **but token is dinariStorage.usdc()** and recipient is OM.
        // So we must approve the **factory** as spender:
        vm.prank(user);
        usdc.approve(address(factory), type(uint256).max);
    }

    /* ---------- initialize reverts ---------- */

    function testInitialize_RevertsOnZeroArgs() public {
        DinariFactory impl = new DinariFactory();
        DinariFactory fresh = DinariFactory(address(new ERC1967Proxy(address(impl), "")));

        vm.expectRevert(bytes("invalid _indexFactoryStorage address"));
        fresh.initialize(address(0), address(dinariStorage), address(oracle));

        vm.expectRevert(bytes("invalid _dinariStorage address"));
        fresh.initialize(address(gFactory), address(0), address(oracle));

        vm.expectRevert(bytes("invalid _functionsOracle address"));
        fresh.initialize(address(gFactory), address(dinariStorage), address(0));
    }

    /* ---------- pause/unpause ---------- */

    function testPause_Unpause_Roles() public {
        // non authorized
        vm.expectRevert(bytes("Caller is not the owner or operator or balancer."));
        factory.pause();

        // owner
        vm.prank(owner);
        factory.pause();

        // balancer (set in storage)
        vm.prank(balancer);
        factory.unpause();
    }

    /* ---------- setFunctionsOracle onlyOwner ---------- */

    function testSetFunctionsOracle_OnlyOwner() public {
        vm.expectRevert();
        factory.setFunctionsOracle(address(oracle));

        vm.prank(owner);
        factory.setFunctionsOracle(address(oracle));
        // no revert == success
    }

    /* ---------- very light issuance smoke (USDC moves; nonce increments) ---------- */

    function testIssuance_Smoke_MoveUSDC_ToOrderManager_AndNonce() public {
        uint256 amt = 250e6; // USDC 6 decimals
        uint256 balUserBefore = usdc.balanceOf(user);
        uint256 balOmBefore = usdc.balanceOf(address(dinariStorage.dinariOrderManager()));

        vm.startPrank(address(dinariStorage.owner()));
        dinariStorage.setFactory(address(factory));
        vm.stopPrank();

        // // expect event (outputAmount is 0 here)
        // vm.expectEmit(true, false, true, true);
        // emit RequestIssuance(idxToken, 1, user, address(usdc), amt, 0, block.timestamp);

        vm.prank(user);
        uint256 nonce = factory.issuanceIndexTokens(idxToken, amt);
        assertEq(nonce, 1, "issuance nonce");

        // funds should land in DinariOrderManager (as per implementation)
        assertEq(usdc.balanceOf(user), balUserBefore - amt, "user debited");
        assertEq(
            usdc.balanceOf(address(dinariStorage.dinariOrderManager())), balOmBefore + amt, "OM credited from factory"
        );

        // storage nonce incremented
        assertEq(dinariStorage.issuanceNonce(idxToken), 1, "storage issuance nonce");
        assertEq(dinariStorage.issuanceInputAmount(idxToken, 1), amt, "stored input");
    }

    function testSetFunctionsOracle_RevertOnZeroAddress() public {
        // Arrange: Only owner can call
        vm.prank(owner);
        // Act/Assert: should revert with 'invalid functions oracle address' if argument is zero
        vm.expectRevert(bytes("invalid functions oracle address"));
        factory.setFunctionsOracle(address(0));
    }

    function testIssuanceIndexTokens_RevertOnZeroAmount() public {
        // Arrange: set index factory in storage to let factory call through
        vm.startPrank(address(dinariStorage.owner()));
        dinariStorage.setFactory(address(factory));
        vm.stopPrank();

        // When: user invokes issuanceIndexTokens with _inputAmount = 0, should revert with message
        vm.prank(user);
        vm.expectRevert("Invalid input amount");
        factory.issuanceIndexTokens(idxToken, 0);
    }

    function testRedemption_RevertOnZeroAmount() public {
        // Setup: indexToken by owner
        vm.startPrank(address(dinariStorage.owner()));
        dinariStorage.setFactory(address(factory));
        vm.stopPrank();

        // Try with _inputAmount = 0, expect revert
        vm.prank(user);
        vm.expectRevert(bytes("Invalid input amount"));
        factory.redemption(idxToken, 0, 1e18);
    }

    function test_unpause_roles_opix_345_true_branch() public {
        // This test targets the opix-target-branch-345-True branch:
        //
        //         require(
        //             msg.sender == owner() || functionsOracle.isOperator(msg.sender)
        //                 || msg.sender == dinariStorage.factoryBalancerAddress(),
        //             "Caller is not the owner or operator or balancer."
        //         );
        //
        // We test that unpause() succeeds for each role: owner, operator, balancer.
        // - Owner: address(0xA11CE)
        // - Operator: we register a new address as operator in FunctionsOracle
        // - Balancer: as set in storage/balancer (via setUp)

        // 1. As owner
        vm.startPrank(owner);
        factory.pause(); // set contract to paused
        factory.unpause(); // should succeed
        vm.stopPrank();

        // 2. As operator (not owner, not balancer)
        address operator = address(0x0909);
        vm.prank(owner); // only owner can setOperator in FunctionsOracle
        oracle.setOperator(operator, true);
        vm.startPrank(operator);
        factory.pause();
        factory.unpause(); // should succeed
        vm.stopPrank();

        // 3. As balancer
        // ensure Factory is paused again
        vm.prank(operator);
        factory.pause();
        vm.prank(balancer); // this is the balancer as set in setUp
        factory.unpause(); // should succeed

        // 4. As unauthorized: expect revert
        address bad = address(0xDEAD);
        vm.expectRevert(bytes("Caller is not the owner or operator or balancer."));
        vm.prank(bad);
        factory.unpause();
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {DinariStorage} from "../../src/dinari/DinariStorage.sol";
import {FunctionsOracle} from "../../src/oracle/FunctionsOracle.sol";
import {IndexFactoryStorage} from "../../src/factory/IndexFactoryStorage.sol";
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

/* ---------- Minimal issuer stub (external dependency) ---------- */
contract TestIssuer is IOrderProcessor {
    function getStandardFees(bool, address) external pure returns (uint256, uint24) {
        return (1e6, 1000); // flat=1e6, pct=0.1%
    }

    function latestFillPrice(address, address) external view returns (PricePoint memory) {
        return PricePoint({price: 1e18, timestamp: block.timestamp}); // 1.0 in 1e18
    }

    function orderDecimalReduction(address) external pure returns (uint8) {
        return 0;
    }

    function getOrderStatus(uint256) external pure returns (OrderStatus) {
        return OrderStatus.ACTIVE;
    }
}

contract DinariStorage_MainTest is OlympixUnitTest("DinariStorage") {
    address owner = address(0xA11CE);
    address factory = address(0xFACADE);

    TestERC20 usdc;

    DinariStorage storageImpl;
    DinariStorage dinariStorage; // proxy

    IndexFactoryStorage gFactoryImpl;
    IndexFactoryStorage gFactory;

    FunctionsOracle oracleImpl;
    FunctionsOracle oracle;

    TestIssuer issuer;

    address idxToken = makeAddr("IndexToken");

    function setUp() public {
        vm.startPrank(owner);

        usdc = new TestERC20("USD Coin", "USDC");
        issuer = new TestIssuer();

        // global IndexFactoryStorage (just needs non-zero addresses)
        gFactoryImpl = new IndexFactoryStorage();
        gFactory = IndexFactoryStorage(address(new ERC1967Proxy(address(gFactoryImpl), "")));
        gFactory.initialize(
            // address(0xDEAD), // _indexFactory
            // address(0xBEEF), // _functionsOracle (unused here)
            // address(0xCAFE), // _stagingCustodyAccount
            // address(0xB07), // _nexBot
            // address(usdc) // _usdc
        );

        // real FunctionsOracle (init with dummy router + donId)
        oracleImpl = new FunctionsOracle();
        oracle = FunctionsOracle(address(new ERC1967Proxy(address(oracleImpl), "")));
        oracle.initialize(address(0x01), bytes32("DON"));

        // DinariStorage
        storageImpl = new DinariStorage();
        dinariStorage = DinariStorage(address(new ERC1967Proxy(address(storageImpl), "")));
        dinariStorage.initialize(
            address(issuer),
            address(gFactory),
            address(0x11111),
            address(usdc),
            6, // usdcDecimals
            address(oracle),
            false, // isMainnet
            1 // providerIndex
        );

        vm.stopPrank();
    }

    /* ---------- initialize reverts ---------- */

    function testInitialize_RevertsOnInvalidArgs() public {
        DinariStorage impl = new DinariStorage();
        DinariStorage fresh = DinariStorage(address(new ERC1967Proxy(address(impl), "")));

        vm.expectRevert(bytes("invalid _issuer address"));
        fresh.initialize(address(0), address(gFactory), address(0x11111), address(usdc), 6, address(oracle), false, 1);

        vm.expectRevert(bytes("invalid _indexFactoryStorage address"));
        fresh.initialize(address(issuer), address(0), address(0x11111), address(usdc), 6, address(oracle), false, 1);

        vm.expectRevert(bytes("invalid _usdc address"));
        fresh.initialize(address(issuer), address(gFactory), address(0x11111), address(0), 6, address(oracle), false, 1);

        vm.expectRevert(bytes("invalid _usdcDecimals"));
        fresh.initialize(
            address(issuer), address(gFactory), address(0x11111), address(usdc), 0, address(oracle), false, 1
        );

        vm.expectRevert(bytes("invalid _functionsOracle address"));
        fresh.initialize(address(issuer), address(gFactory), address(0x11111), address(usdc), 6, address(0), false, 1);

        vm.expectRevert(bytes("invalid _providerIndex"));
        fresh.initialize(
            address(issuer), address(gFactory), address(0x11111), address(usdc), 6, address(oracle), false, 0
        );
    }

    /* ---------- owner-only setters ---------- */

    function testOwnerOnly_Setters() public {
        // setUsdcAddress
        vm.prank(owner);
        assertTrue(dinariStorage.setUsdcAddress(address(usdc), 6));
        assertEq(dinariStorage.usdc(), address(usdc));
        assertEq(dinariStorage.usdcDecimals(), 6);

        // setFeeReceiver
        vm.prank(owner);
        dinariStorage.setFeeReceiver(address(0xFEED));
        assertEq(dinariStorage.feeReceiver(), address(0xFEED));

        // setIsMainnet
        vm.prank(owner);
        dinariStorage.setIsMainnet(true);
        assertTrue(dinariStorage.isMainnet());

        // setFunctionsOracle
        vm.prank(owner);
        dinariStorage.setFunctionsOracle(address(oracle));
        assertEq(address(dinariStorage.functionsOracle()), address(oracle));

        // non-owner reverts
        vm.expectRevert();
        dinariStorage.setUsdcAddress(address(usdc), 6);
    }

    /* ---------- onlyFactory gates (happy smoke) ---------- */

    function testOnlyFactory_IncreaseNonces() public {
        // point factoryAddress to a sender we control
        vm.prank(owner);
        dinariStorage.setFactory(factory);

        // try as non-factory -> revert
        vm.expectRevert(bytes("Caller is not a factory contract"));
        dinariStorage.increaseIssuanceNonce(idxToken);

        // call as factory -> ok
        vm.prank(factory);
        dinariStorage.increaseIssuanceNonce(idxToken);
        assertEq(dinariStorage.issuanceNonce(idxToken), 1);

        vm.prank(factory);
        dinariStorage.increaseRedemptionNonce(idxToken);
        assertEq(dinariStorage.redemptionNonce(idxToken), 1);
    }

    /* ---------- fee calc (uses stub issuer) ---------- */

    function testCalculateIssuanceFee_ZeroUnderlying_ReturnsZero() public view {
        // With empty oracle lists, fee loops over 0 assets → 0
        uint256 fee = dinariStorage.calculateIssuanceFee(idxToken, 100e6);
        assertEq(fee, 0);
    }

    function testSetFeeReceiver_RevertWhenZeroAddress() public {
        // This tests src/dinari/DinariStorage.sol line 157 (require nonzero address)
        vm.prank(owner);
        vm.expectRevert("invalid fee receiver address");
        dinariStorage.setFeeReceiver(address(0));
    }

    function test_setUsdcAddress_revertsIfZeroAddress() public {
        // Arrange: run as owner, attempt to set USDC address to 0
        vm.prank(owner);
        vm.expectRevert("invalid token address");
        dinariStorage.setUsdcAddress(address(0), 6);
    }

    // Test that setUsdcAddress reverts if usdcDecimals is zero (covering DinariStorage.sol branch opix-target-branch-175-True for revert)
    function test_setUsdcAddress_revertsIfDecimalsZero_branch_175() public {
        // Run as owner
        vm.prank(owner);
        // Set a valid USDC address but decimals = 0 should revert.
        vm.expectRevert("invalid decimals");
        dinariStorage.setUsdcAddress(address(usdc), 0);
    }

    function test_setOrderManager_revertsOnZero() public {
        // set up as owner
        vm.startPrank(owner);
        // Should revert when address is zero
        vm.expectRevert(bytes("invalid order manager address"));
        dinariStorage.setOrderManager(address(0));
        vm.stopPrank();
    }

    function test_setOrderManager_branchTrue() public {
        // set up as owner
        vm.startPrank(owner);
        // Should succeed and return true for nonzero address
        address someTarget = address(0x99);
        bool out = dinariStorage.setOrderManager(someTarget);
        // Value is set
        assertEq(address(dinariStorage.dinariOrderManager()), someTarget);
        assertTrue(out);
        vm.stopPrank();
    }

    // Test for DinariStorage.setIssuer: branch opix-target-branch-201-False
    // The test should succeed (not revert) when called by owner with a nonzero _issuer address (covering the require branch with condition == false).
    function test_setIssuer_allowsNonzeroAddress_opixTargetBranch201False() public {
        // Arrange: Owner is sender
        vm.startPrank(owner);
        // Provide a non-zero address for _issuer (should not revert, and should set the issuer)
        address newIssuer = address(0xCAFECAFE);
        bool result = dinariStorage.setIssuer(newIssuer);
        // Assert: value is set
        assertEq(address(dinariStorage.issuer()), newIssuer);
        // And the return value should be true as per contract
        assertTrue(result);
        vm.stopPrank();
    }

    function test_setWrappedDshareArrayLengthMismatch_reverts() public {
        // Arrange: make unequal length arrays
        address[] memory dShares = new address[](2);
        address[] memory wrapped = new address[](1);
        address[] memory feeds = new address[](2);
        dShares[0] = address(0x1001);
        dShares[1] = address(0x1002);
        wrapped[0] = address(0x2001);
        feeds[0] = address(0x3001);
        feeds[1] = address(0x3002);

        // Act/Assert: Should revert because dShares/wrapped arrays are length mismatch
        vm.prank(owner);
        vm.expectRevert(bytes("Array length mismatch"));
        dinariStorage.setWrappedDshareAndPriceFeedAddresses(dShares, wrapped, feeds);
    }

    // Test covers DinariStorage.setWrappedDshareAndPriceFeedAddresses branch: opix-target-branch-212-False
    function test_setWrappedDshareAndPriceFeedAddresses_arrayLengthMismatch_branchFalse() public {
        // Arrange: make all arrays the same length (should *not* revert on opix-target-branch-212-False)
        address[] memory dShares = new address[](2);
        address[] memory wrapped = new address[](2);
        address[] memory feeds = new address[](2);
        dShares[0] = address(0x1001);
        dShares[1] = address(0x1002);
        wrapped[0] = address(0x2001);
        wrapped[1] = address(0x2002);
        feeds[0] = address(0x3001);
        feeds[1] = address(0x3002);

        // Only owner can call
        vm.prank(owner);
        // Should *not* revert (hit branch-212-False)
        dinariStorage.setWrappedDshareAndPriceFeedAddresses(dShares, wrapped, feeds);

        // After setting, mapping should be updated
        for (uint256 i = 0; i < dShares.length; i++) {
            assertEq(dinariStorage.wrappedDshareAddress(dShares[i]), wrapped[i], "wrappedDshareAddress mismatch");
            assertEq(dinariStorage.priceFeedByTokenAddress(dShares[i]), feeds[i], "priceFeedByTokenAddress mismatch");
        }
    }

    // Test for DinariStorage.setWrappedDshareAndPriceFeedAddresses covering opix-target-branch-213-True (revert when price feeds array length is not equal to dShares array length)
    function test_setWrappedDshareAndPriceFeedAddresses_revertsOnPriceFeedsArrayLengthMismatch_branch213True() public {
        // Arrange - all lengths match except feeds is wrong
        address[] memory dShares = new address[](2);
        address[] memory wrapped = new address[](2);
        address[] memory feeds = new address[](1); // Mismatched length!
        dShares[0] = address(0x1005);
        dShares[1] = address(0x1006);
        wrapped[0] = address(0x2005);
        wrapped[1] = address(0x2006);
        feeds[0] = address(0x3005); // Only 1 feed

        // Only owner can call
        vm.prank(owner);
        vm.expectRevert("Array length mismatch"); // As in contract line guarded by opix-target-branch-213-True
        dinariStorage.setWrappedDshareAndPriceFeedAddresses(dShares, wrapped, feeds);
    }

    // Test setFactory rejects zero address (DinariStorage, branch: opix-target-branch-221-True, require)
    function test_setFactoryZeroAddress_reverts() public {
        // Arrange: act as the owner
        address zeroFactory = address(0);
        vm.prank(owner);
        // Expect revert on zero address for factory
        vm.expectRevert(bytes("invalid factory address"));
        dinariStorage.setFactory(zeroFactory);
    }

    function test_setFactoryBalancer_revertsOnZeroAddress() public {
        vm.prank(owner);
        // Attempt to call setFactoryBalancer with address(0), should revert
        vm.expectRevert(bytes("invalid factory balancer address"));
        dinariStorage.setFactoryBalancer(address(0));
    }

    function test_setFactoryBalancer_setsValueWhenValid() public {
        vm.prank(owner);
        address newBalancer = address(0xBEEF01);
        dinariStorage.setFactoryBalancer(newBalancer);
        assertEq(dinariStorage.factoryBalancerAddress(), newBalancer);
    }

    // Test opix-target-branch-231-True: setFactoryProcessor requires nonzero address and sets the value
    function test_setFactoryProcessor_revertsOnZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(bytes("invalid factory processor address"));
        dinariStorage.setFactoryProcessor(address(0));
    }

    // Test for DinariStorage.increaseTokenPendingRebalanceAmount: branch opix-target-branch-239-True
    // This test ensures that only the three factory roles are allowed, and the branch (require) passes when one of them is the caller (so the body is entered/executed)
    function test_increaseTokenPendingRebalanceAmount_onlyFactoryRolesAllowed_branch239True() public {
        // Setup: assign all three factory role addresses that we control
        address fakeFactory = address(0xF001);
        address fakeProcessor = address(0xF002);
        address fakeBalancer = address(0xF003);
        address indexToken = idxToken;
        address testToken = address(0xDEAD1);
        uint256 testNonce = 17;
        uint256 testAmount = 2222;

        // Assign factory addresses as owner
        vm.prank(owner);
        dinariStorage.setFactory(fakeFactory);
        vm.prank(owner);
        dinariStorage.setFactoryProcessor(fakeProcessor);
        vm.prank(owner);
        dinariStorage.setFactoryBalancer(fakeBalancer);
        // Each should be allowed:
        address[3] memory allowed = [fakeFactory, fakeProcessor, fakeBalancer];
        for (uint256 i = 0; i < allowed.length; i++) {
            // Reset the slot for this triple
            vm.prank(allowed[i]);
            dinariStorage.increaseTokenPendingRebalanceAmount(indexToken, testToken, testNonce, testAmount);
            // State should be set as expected
            assertEq(
                dinariStorage.tokenPendingRebalanceAmount(indexToken, testToken),
                testAmount * (i + 1),
                string.concat("tokenPendingRebalanceAmount mismatch after #", vm.toString(i))
            );
            assertEq(
                dinariStorage.tokenPendingRebalanceAmountByNonce(indexToken, testToken, testNonce),
                testAmount * (i + 1),
                string.concat("tokenPendingRebalanceAmountByNonce mismatch after #", vm.toString(i))
            );
        }
        // Negative: not allowed sender should revert
        address notAllowed = address(0x9999);
        vm.prank(notAllowed);
        vm.expectRevert("Caller is not a factory contract");
        dinariStorage.increaseTokenPendingRebalanceAmount(indexToken, testToken, testNonce, testAmount);
    }

    // Test for DinariStorage.increaseTokenPendingRebalanceAmount: branch opix-target-branch-246-True
    // The test must call as an allowed sender and for _token == address(0) (should revert with 'invalid token address')
    function test_increaseTokenPendingRebalanceAmount_zeroToken_reverts_branch_246_True() public {
        // Arrange: set up the three factory roles
        address fakeFactory = address(0xAFF1);
        address fakeProcessor = address(0xAFF2);
        address fakeBalancer = address(0xAFF3);
        address indexToken = idxToken;
        uint256 nonce = 88;
        uint256 amount = 1;
        vm.prank(owner);
        dinariStorage.setFactory(fakeFactory);
        vm.prank(owner);
        dinariStorage.setFactoryProcessor(fakeProcessor);
        vm.prank(owner);
        dinariStorage.setFactoryBalancer(fakeBalancer);
        // All three roles should revert if _token == address(0)
        address zeroToken = address(0);
        address[3] memory allowed = [fakeFactory, fakeProcessor, fakeBalancer];
        for (uint256 i = 0; i < allowed.length; i++) {
            vm.prank(allowed[i]);
            vm.expectRevert("invalid token address");
            dinariStorage.increaseTokenPendingRebalanceAmount(indexToken, zeroToken, nonce, amount);
        }
    }

    // opix-target-branch-247-True: require(_amount > 0, "Invalid amount");
    // Test that increaseTokenPendingRebalanceAmount reverts when _amount == 0 (branch is taken)
    function test_increaseTokenPendingRebalanceAmount_zeroAmount_reverts_branch_247_True() public {
        // Set up all three allowed factory roles
        address fakeFactory = address(0xFEED1);
        address fakeProcessor = address(0xFEED2);
        address fakeBalancer = address(0xFEED3);
        address indexToken = idxToken;
        address testToken = address(0x101010);
        uint256 testNonce = 42;
        uint256 zeroAmount = 0;
        // Grant all roles
        vm.prank(owner);
        dinariStorage.setFactory(fakeFactory);
        vm.prank(owner);
        dinariStorage.setFactoryProcessor(fakeProcessor);
        vm.prank(owner);
        dinariStorage.setFactoryBalancer(fakeBalancer);
        address[3] memory allowed = [fakeFactory, fakeProcessor, fakeBalancer];
        // Each allowed sender should revert when amount==0
        for (uint256 i = 0; i < allowed.length; i++) {
            vm.prank(allowed[i]);
            vm.expectRevert("Invalid amount");
            dinariStorage.increaseTokenPendingRebalanceAmount(indexToken, testToken, testNonce, zeroAmount);
        }
    }

    // This test hits DinariStorage.decreaseTokenPendingRebalanceAmount branch opix-target-branch-256-False
    // by calling as an ALLOWED sender (factory, processor, or balancer) to ensure the branch is exercised where the require passes (else branch of require is NOT taken, so the body executes!)
    function test_decreaseTokenPendingRebalanceAmount_opixTargetBranch256False_executesForFactoryProcessorBalancer()
        public
    {
        address fakeFactory = address(0xDFAC1);
        address fakeProcessor = address(0xDFAC2);
        address fakeBalancer = address(0xDFAC3);
        address indexToken = idxToken;
        address testToken = address(0xD9012);
        uint256 testNonce = 11;
        uint256 amount = 21;

        // Set up DinariStorage so the testToken has an initial pending rebalance amount (use one of the allowed sender addresses)
        vm.prank(owner);
        dinariStorage.setFactory(fakeFactory);
        vm.prank(owner);
        dinariStorage.setFactoryProcessor(fakeProcessor);
        vm.prank(owner);
        dinariStorage.setFactoryBalancer(fakeBalancer);
        // Pre-populate the mapping so that decrease will not revert (amount > 0 and >= _amount):
        vm.prank(fakeFactory);
        dinariStorage.increaseTokenPendingRebalanceAmount(indexToken, testToken, testNonce, amount);
        assertEq(dinariStorage.tokenPendingRebalanceAmount(indexToken, testToken), amount, "Initial increase failed");

        // Now call decreaseTokenPendingRebalanceAmount as each allowed sender (factory, processor, balancer)
        address[3] memory senders = [fakeFactory, fakeProcessor, fakeBalancer];
        for (uint256 i = 0; i < 3; i++) {
            // Reset to a known value for each iteration
            vm.prank(senders[i]);
            dinariStorage.increaseTokenPendingRebalanceAmount(indexToken, testToken, testNonce, amount);
            uint256 before = dinariStorage.tokenPendingRebalanceAmount(indexToken, testToken);
            // Decrease by a smaller amount (should not revert):
            vm.prank(senders[i]);
            dinariStorage.decreaseTokenPendingRebalanceAmount(indexToken, testToken, testNonce, 5);
            // Check state: should have reduced by 5
            assertEq(
                dinariStorage.tokenPendingRebalanceAmount(indexToken, testToken),
                before - 5,
                string.concat("failed for ", vm.toString(senders[i]))
            );
        }
    }

    // Branch coverage for DinariStorage.decreaseTokenPendingRebalanceAmount
    // opix-target-branch-263-True (require(_token != address(0)))
    function test_decreaseTokenPendingRebalanceAmount_revertOnZeroToken_branch_263_True() public {
        // Setup: Use allowed factory roles
        address factoryAddr = address(0xF0DEC0);
        address processorAddr = address(0xF0DEC1);
        address balancerAddr = address(0xF0DEC2);
        vm.prank(owner);
        dinariStorage.setFactory(factoryAddr);
        vm.prank(owner);
        dinariStorage.setFactoryProcessor(processorAddr);
        vm.prank(owner);
        dinariStorage.setFactoryBalancer(balancerAddr);
        address indexToken = idxToken;
        uint256 nonce = 101;
        uint256 amount = 55;
        address zeroToken = address(0);

        // It should revert for all three roles if _token == address(0)
        address[3] memory allowed = [factoryAddr, processorAddr, balancerAddr];
        for (uint256 i = 0; i < 3; i++) {
            vm.prank(allowed[i]);
            vm.expectRevert("invalid token address");
            dinariStorage.decreaseTokenPendingRebalanceAmount(indexToken, zeroToken, nonce, amount);
        }
    }

    // This Foundry test covers branch opix-target-branch-264-True in DinariStorage.decreaseTokenPendingRebalanceAmount,
    // which is the 'require(_amount > 0, "Invalid amount")' at line 264 true branch.
    // The test will call decreaseTokenPendingRebalanceAmount as one of the factory roles
    // with _amount == 0, and expects a revert with the correct message.
    function test_decreaseTokenPendingRebalanceAmount_zeroAmount_reverts_branch_264_True() public {
        // Arrange: set up all allowed factory roles, set each as contract knowledge in DinariStorage
        address factoryAddr = address(0xB00F1);
        address processorAddr = address(0xB00F2);
        address balancerAddr = address(0xB00F3);
        address indexToken = idxToken;
        address testToken = address(0xDECA1);
        uint256 testNonce = 731;
        uint256 amount = 0; // the zero amount triggers the targeted branch
        // Register factory/processor/balancer addresses
        vm.prank(owner);
        dinariStorage.setFactory(factoryAddr);
        vm.prank(owner);
        dinariStorage.setFactoryProcessor(processorAddr);
        vm.prank(owner);
        dinariStorage.setFactoryBalancer(balancerAddr);
        // All three factory roles should revert on zero _amount
        address[3] memory allowed = [factoryAddr, processorAddr, balancerAddr];
        for (uint256 i = 0; i < allowed.length; i++) {
            vm.prank(allowed[i]);
            vm.expectRevert("Invalid amount");
            dinariStorage.decreaseTokenPendingRebalanceAmount(indexToken, testToken, testNonce, amount);
        }
    }

    // Foundry unit test to cover DinariStorage.decreaseTokenPendingRebalanceAmount branch opix-target-branch-265-True.
    // This test must call as a valid factory address, and have tokenPendingRebalanceAmount[_indexToken][_token] < _amount, so the require fails and branch is hit.
    function test_decreaseTokenPendingRebalanceAmount_revertsOnInsufficientRebalance_opixBranch265True() public {
        // Allowed roles: set factory, processor, balancer to different addresses
        address fac = address(0xABC01);
        address proc = address(0xABC02);
        address bal = address(0xABC03);
        // Register roles
        vm.prank(owner);
        dinariStorage.setFactory(fac);
        vm.prank(owner);
        dinariStorage.setFactoryProcessor(proc);
        vm.prank(owner);
        dinariStorage.setFactoryBalancer(bal);
        // Choose any indexToken, token, nonce
        address indexToken = idxToken;
        address testToken = address(0x19191);
        uint256 nonce = 1001;
        // Pre-populate a small value
        uint256 small = 3;
        vm.prank(fac);
        dinariStorage.increaseTokenPendingRebalanceAmount(indexToken, testToken, nonce, small);
        assertEq(dinariStorage.tokenPendingRebalanceAmount(indexToken, testToken), small);
        uint256 excessiveAmt = small + 5;
        // All roles should revert on decrease with excessive amount
        address[3] memory allowed = [fac, proc, bal];
        for (uint256 i = 0; i < allowed.length; i++) {
            // Reset: zero out, then populate to `small`
            // Only owner or operator can reset, do as owner
            vm.prank(owner);
            dinariStorage.resetTokenPendingRebalanceAmount(indexToken, testToken, nonce);
            // Restore to `small` with current caller
            vm.prank(allowed[i]);
            dinariStorage.increaseTokenPendingRebalanceAmount(indexToken, testToken, nonce, small);
            // Now, call decrease by too much (should revert on branch opix-target-branch-265-True)
            vm.prank(allowed[i]);
            vm.expectRevert(bytes("Insufficient pending rebalance amount"));
            dinariStorage.decreaseTokenPendingRebalanceAmount(indexToken, testToken, nonce, excessiveAmt);
        }
    }

    // Test for DinariStorage.resetTokenPendingRebalanceAmount branch opix-target-branch-272-False
    // The test should ensure that only the owner or an operator (as reported by the functionsOracle) may call;
    // and for a disallowed address, revert with the expected message. This test will also demonstrate success for owner/operator.
    function test_resetTokenPendingRebalanceAmount_onlyOwnerOrOperator_branch_272_False() public {
        address someToken = address(0xBEEF);
        address indexToken = idxToken;
        uint256 nonce = 99;

        // Case 1: Not owner, not operator - should revert
        address notAllowed = address(0x111222);
        vm.prank(notAllowed);
        vm.expectRevert("Caller is not the owner or operator");
        dinariStorage.resetTokenPendingRebalanceAmount(indexToken, someToken, nonce);

        // Case 2: Owner succeeds
        vm.prank(owner);
        dinariStorage.resetTokenPendingRebalanceAmount(indexToken, someToken, nonce);
        // After call, mapping should be zero
        assertEq(dinariStorage.tokenPendingRebalanceAmount(indexToken, someToken), 0);
        assertEq(dinariStorage.tokenPendingRebalanceAmountByNonce(indexToken, someToken, nonce), 0);

        // Case 3: Operator (set on oracle) should be allowed
        address op = address(0xCAFECAFE);
        vm.prank(owner);
        oracle.setOperator(op, true);
        vm.prank(op);
        // Should not revert for operator
        dinariStorage.resetTokenPendingRebalanceAmount(indexToken, someToken, nonce);
        // Again, mapping should stay at zero
        assertEq(dinariStorage.tokenPendingRebalanceAmount(indexToken, someToken), 0);
        assertEq(dinariStorage.tokenPendingRebalanceAmountByNonce(indexToken, someToken, nonce), 0);
    }

    // Branch test for DinariStorage.resetTokenPendingRebalanceAmount: opix-target-branch-277-True
    // This require(_token != address(0)), so should revert if _token == address(0)
    function test_resetTokenPendingRebalanceAmount_zeroToken_branch_277_True() public {
        address indexToken = idxToken;
        uint256 nonce = 123;
        address zeroToken = address(0);

        // Owner is always valid, but token zero triggers require
        vm.prank(owner);
        vm.expectRevert(bytes("invalid token address"));
        dinariStorage.resetTokenPendingRebalanceAmount(indexToken, zeroToken, nonce);
    }

    // Test for DinariStorage.resetAllTokenPendingRebalanceAmount: branch coverage opix-target-branch-284-False
    // This test should enter the else branch of the require checking owner or functionsOracle.isOperator(msg.sender), with True sender (the owner), so the require passes.
    function test_resetAllTokenPendingRebalanceAmount_branch_284_False() public {
        // Arrange: take control as owner, create dummy underlying assets array via oracle stub
        vm.startPrank(owner);
        // Configure one underlying asset in oracle for _indexToken
        address indexToken = idxToken;

        // Setup provider index data in FunctionsOracle stub on indexToken
        // provider index = 1 (set in setUp), so we populate chain for providerIndex=1
        address singleToken = address(0xBEEF1234);
        uint256 totalShare = 1e18;
        address[] memory assets = new address[](1);
        assets[0] = singleToken;
        uint256[] memory shares = new uint256[](1);
        shares[0] = totalShare;
        // Manually call _initPathData on oracle to set up chain selectors/provider index so that providerIndex on this token returns 1 (as set in dinariStorage)
        uint64 providerIdx = 1;
        uint64 chainSelector = 1;
        bytes memory pathBytes = abi.encode(assets, new uint24[](0));
        uint64[] memory providerInds = new uint64[](1);
        uint64[] memory chainSel = new uint64[](1);
        bytes[] memory pbs = new bytes[](1);
        providerInds[0] = providerIdx;
        chainSel[0] = chainSelector;
        pbs[0] = pathBytes;
        oracle.updatePathData(providerInds, chainSel, pbs);

        // Trick: need currentProviderIndexData to return (totalMarketShare, assets, shares)
        // We forcibly call _initData via internal function simulated by requestAssetsData (skipped here, but updatePathData suffices for this oracle implementation)

        // Now populate DinariStorage.tokenPendingRebalanceAmount for this indexToken/token
        dinariStorage.tokenPendingRebalanceAmount(indexToken, singleToken); // optional: just to ensure field is present
        // Set a nonzero value using hevm.store (cheat for test)
        // bytes32 slot = keccak256(
        //     abi.encodePacked(
        //         keccak256(abi.encodePacked(singleToken, uint256(keccak256(abi.encodePacked(indexToken, uint256(711)))))) // mapping layout approximation
        //     )
        // );
        // Not required unless you want to check value before/after

        // Action: owner calls resetAllTokenPendingRebalanceAmount to hit opix-target-branch-284-False (require passes, else block)
        dinariStorage.resetAllTokenPendingRebalanceAmount(indexToken, 711);
        // Should not revert, function completes.

        // For sanity: tokenPendingRebalanceAmount should be zero (if underlying asset found)
        assertEq(dinariStorage.tokenPendingRebalanceAmount(indexToken, singleToken), 0);
        assertEq(dinariStorage.tokenPendingRebalanceAmountByNonce(indexToken, singleToken, 711), 0);
        vm.stopPrank();
    }

    // Test for branch opix-target-branch-313-True in DinariStorage.increaseRedemptionNonce.
    // Goal: ensure branch is covered by calling as any allowed (factory, processor, balancer).
    function test_increaseRedemptionNonce_opixTargetBranch313True_allFactoryAddrs() public {
        address fakeFactory = address(0xFACFAC);
        address fakeProcessor = address(0xFACBEE);
        address fakeBalancer = address(0xFACC11);
        address indexToken = idxToken;

        // Set all factory roles to nonzero, different, controlled by test.
        vm.prank(owner);
        dinariStorage.setFactory(fakeFactory);
        vm.prank(owner);
        dinariStorage.setFactoryProcessor(fakeProcessor);
        vm.prank(owner);
        dinariStorage.setFactoryBalancer(fakeBalancer);

        // Branch: Only any of these callers should pass, all others must revert.
        // address notAllowed = address(0x12345);
        vm.expectRevert("Caller is not a factory contract");
        dinariStorage.increaseRedemptionNonce(indexToken);

        // As pure factory: increments once
        assertEq(dinariStorage.redemptionNonce(indexToken), 0);
        vm.prank(fakeFactory);
        dinariStorage.increaseRedemptionNonce(indexToken);
        assertEq(dinariStorage.redemptionNonce(indexToken), 1);

        // As processor: increments again
        vm.prank(fakeProcessor);
        dinariStorage.increaseRedemptionNonce(indexToken);
        assertEq(dinariStorage.redemptionNonce(indexToken), 2);

        // As balancer: increments a third time
        vm.prank(fakeBalancer);
        dinariStorage.increaseRedemptionNonce(indexToken);
        assertEq(dinariStorage.redemptionNonce(indexToken), 3);
    }

    function test_setIssuanceIsCompleted_onlyFactory_branch_true() public {
        // Set up DinariStorage and configure factory address
        vm.prank(owner);
        dinariStorage.setFactory(factory);

        address _indexToken = idxToken;
        uint256 _issuanceNonce = 1;
        bool _isCompleted = true;

        // As non-factory: should revert
        vm.expectRevert("Caller is not a factory contract");
        dinariStorage.setIssuanceIsCompleted(_indexToken, _issuanceNonce, _isCompleted);

        // Call as factory (should pass branch on require) -- opix-target-branch-325-True
        vm.prank(factory);
        dinariStorage.setIssuanceIsCompleted(_indexToken, _issuanceNonce, _isCompleted);

        // Assert state was updated
        assertEq(dinariStorage.issuanceIsCompleted(_indexToken, _issuanceNonce), true);
    }

    function test_setRedemptionIsCompleted_onlyFactory_branch_true() public {
        // Arrange: set up a factory address, as owner
        vm.prank(owner);
        dinariStorage.setFactory(factory);

        address indexToken = idxToken;
        uint256 redemptionNonce = 2;
        bool isCompleted = true;

        // As a non-factory address: revert
        vm.expectRevert("Caller is not a factory contract");
        dinariStorage.setRedemptionIsCompleted(indexToken, redemptionNonce, isCompleted);

        // Act as the factory (should hit the require branch opix-target-branch-337-True)
        vm.prank(factory);
        dinariStorage.setRedemptionIsCompleted(indexToken, redemptionNonce, isCompleted);

        // Assert: the mapping is updated
        assertTrue(dinariStorage.redemptionIsCompleted(indexToken, redemptionNonce), "redemptionIsCompleted not set");
    }

    function test_setBurnedTokenAmountByNonce_onlyFactory_AllowsFactoryLikeAddresses() public {
        // DinariStorage's setBurnedTokenAmountByNonce only gives access to factoryAddress, factoryProcessorAddress, or factoryBalancerAddress
        address fakeFactory = address(0xFAAAAC);
        address fakeProcessor = address(0xFAAAAD);
        address fakeBalancer = address(0xFAAAAE);
        vm.prank(owner);
        dinariStorage.setFactory(fakeFactory);
        vm.prank(owner);
        dinariStorage.setFactoryProcessor(fakeProcessor);
        vm.prank(owner);
        dinariStorage.setFactoryBalancer(fakeBalancer);

        address indexToken = idxToken;
        uint256 redemptionNonce = 42;
        uint256 burnedAmount = 1234;

        // Should revert if not a factory address
        vm.expectRevert(bytes("Caller is not a factory contract"));
        dinariStorage.setBurnedTokenAmountByNonce(indexToken, redemptionNonce, burnedAmount);

        // As factoryAddress (should succeed)
        vm.prank(fakeFactory);
        dinariStorage.setBurnedTokenAmountByNonce(indexToken, redemptionNonce, burnedAmount);
        assertEq(
            dinariStorage.burnedTokenAmountByNonce(indexToken, redemptionNonce),
            burnedAmount,
            "Burned amount wrong (factoryAddress)"
        );
        // As factoryProcessorAddress (should succeed)
        uint256 newAmount = 1111;
        vm.prank(fakeProcessor);
        dinariStorage.setBurnedTokenAmountByNonce(indexToken, redemptionNonce, newAmount);
        assertEq(
            dinariStorage.burnedTokenAmountByNonce(indexToken, redemptionNonce),
            newAmount,
            "Burned amount wrong (factoryProcessorAddress)"
        );
        // As factoryBalancerAddress (should succeed)
        uint256 finalAmount = 999;
        vm.prank(fakeBalancer);
        dinariStorage.setBurnedTokenAmountByNonce(indexToken, redemptionNonce, finalAmount);
        assertEq(
            dinariStorage.burnedTokenAmountByNonce(indexToken, redemptionNonce),
            finalAmount,
            "Burned amount wrong (factoryBalancerAddress)"
        );
    }

    function test_setBurnedTokenAmountByNonce_invalidAmount_reverts() public {
        // Setup with valid factory address
        vm.prank(owner);
        dinariStorage.setFactory(factory);
        vm.prank(factory);
        // zero amount should revert
        vm.expectRevert(bytes("Invalid burn amount"));
        dinariStorage.setBurnedTokenAmountByNonce(idxToken, 77, 0);
    }

    // Test that DinariStorage.setBurnedTokenAmountByNonce reverts with burn amount zero, hitting require(_burnedAmount > 0, ...) branch [opix-target-branch-358-True]
    function test_setBurnedTokenAmountByNonce_zeroAmount_reverts() public {
        // Set up as factory caller
        vm.prank(owner);
        dinariStorage.setFactory(factory);

        address indexToken = idxToken;
        uint256 redemptionNonce = 42;
        uint256 burnedAmount = 0;
        // Call as factory, should revert on zero burn amount
        vm.prank(factory);
        vm.expectRevert(bytes("Invalid burn amount"));
        dinariStorage.setBurnedTokenAmountByNonce(indexToken, redemptionNonce, burnedAmount);
    }

    function test_setIssuanceRequestId_onlyFactory_branch_true() public {
        // Set up factory addresses
        vm.prank(owner);
        dinariStorage.setFactory(factory);

        // sample inputs
        address indexToken = idxToken;
        uint256 issuanceNonce = 1;
        address testToken = address(0xBEEF1);
        uint256 requestId = 42;

        // As non-factory: should revert
        vm.expectRevert("Caller is not a factory contract");
        dinariStorage.setIssuanceRequestId(indexToken, issuanceNonce, testToken, requestId);

        // As factory: happy path (should hit opix-target-branch-366-True)
        vm.prank(factory);
        dinariStorage.setIssuanceRequestId(indexToken, issuanceNonce, testToken, requestId);

        // Should update storage
        assertEq(dinariStorage.issuanceRequestId(indexToken, issuanceNonce, testToken), requestId);
    }

    function test_setIssuanceRequestId_requestIdZero_reverts() public {
        // Arrange: assign factory so we can prank as that address
        vm.prank(owner);
        dinariStorage.setFactory(factory);

        address indexToken = idxToken;
        uint256 issuanceNonce = 2;
        address testToken = address(0xD100A);
        uint256 requestId = 0; // Intentionally 0 for revert branch

        // Act/Assert: Should revert with "Invalid issuance Request Id" when requestId == 0
        vm.prank(factory);
        vm.expectRevert(bytes("Invalid issuance Request Id"));
        dinariStorage.setIssuanceRequestId(indexToken, issuanceNonce, testToken, requestId);
    }

    // Test for DinariStorage.setIssuanceRequestId revert branch: opix-target-branch-374-True
    // This test should ensure that if _token == address(0), the transaction reverts with correct message.
    function test_setIssuanceRequestId_tokenIsZero_branch374True() public {
        // Arrange: allow factory address
        vm.prank(owner);
        dinariStorage.setFactory(factory);
        address indexToken = idxToken;
        uint256 issuanceNonce = 1337;
        address zeroToken = address(0); // _token is zero, should revert
        uint256 reqId = 42;

        // Act: as factory, call with _token == address(0); should revert (hit require(_token != address(0)))
        vm.prank(factory);
        vm.expectRevert(bytes("Invalid token address"));
        dinariStorage.setIssuanceRequestId(indexToken, issuanceNonce, zeroToken, reqId);
    }

    // Foundry test to cover DinariStorage.setRedemptionRequestId opix-target-branch-382-True
    // This test ensures that the require allowing only the three factory contracts passes and function executes
    function test_setRedemptionRequestId_onlyFactory_branch_true() public {
        // Set up valid factory, processor, balancer roles
        address factoryAddr = address(0xFAF1);
        address processorAddr = address(0xFAF2);
        address balancerAddr = address(0xFAF3);
        address indexToken = idxToken;
        uint256 redemptionNonce = 123;
        address token = address(0xCAFECAFE);
        uint256 requestIdBase = 0x12345;

        // Assign contract roles
        vm.prank(owner);
        dinariStorage.setFactory(factoryAddr);
        vm.prank(owner);
        dinariStorage.setFactoryProcessor(processorAddr);
        vm.prank(owner);
        dinariStorage.setFactoryBalancer(balancerAddr);

        // All allowed senders should be able to call without revert and hit opix-target-branch-382-True
        address[3] memory callers = [factoryAddr, processorAddr, balancerAddr];
        for (uint256 i = 0; i < callers.length; i++) {
            vm.prank(callers[i]);
            dinariStorage.setRedemptionRequestId(indexToken, redemptionNonce + i, token, requestIdBase + i);
            // Confirm state updated
            assertEq(
                dinariStorage.redemptionRequestId(indexToken, redemptionNonce + i, token),
                requestIdBase + i,
                "redemptionRequestId not set for allowed factory role"
            );
        }

        // Negative: someone not a factory role must revert
        address notAllowed = address(0xBAD5);
        vm.prank(notAllowed);
        vm.expectRevert("Caller is not a factory contract");
        dinariStorage.setRedemptionRequestId(indexToken, redemptionNonce + 42, token, requestIdBase + 42);
    }

    // Test for DinariStorage.setRedemptionRequestId: branch opix-target-branch-382-False
    // This hit should call as any legitimate factory, processor, or balancer address and SUCCEED (i.e., require passes). It should also test that zero requestId or zero token revert as covered elsewhere, so here we focus on a happy path hitting branch 382-False (branch condition is false; the require passes and body is executed).
    function test_setRedemptionRequestId_onlyFactory_branch_false_executes() public {
        // address factory1 = address(0xFA123);
        address processor = address(0xFA456);
        address balancer = address(0xFA789);
        address indexToken = idxToken;
        uint256 redemptionNonce = 999;
        address testToken = address(0xDEAD);
        uint256 requestId = 8888;

        // Assign all roles to ensure any of these can be valid
        vm.prank(owner);
        dinariStorage.setFactory(factory);
        vm.prank(owner);
        dinariStorage.setFactoryProcessor(processor);
        vm.prank(owner);
        dinariStorage.setFactoryBalancer(balancer);

        // #1: As factoryAddress
        vm.prank(factory);
        dinariStorage.setRedemptionRequestId(indexToken, redemptionNonce, testToken, requestId);
        assertEq(
            dinariStorage.redemptionRequestId(indexToken, redemptionNonce, testToken),
            requestId,
            "redemptionRequestId not set (factory)"
        );
        // #2: As processor
        uint256 nextNonce = redemptionNonce + 1;
        uint256 nextRequestId = requestId + 1;
        vm.prank(processor);
        dinariStorage.setRedemptionRequestId(indexToken, nextNonce, testToken, nextRequestId);
        assertEq(
            dinariStorage.redemptionRequestId(indexToken, nextNonce, testToken),
            nextRequestId,
            "redemptionRequestId not set (processor)"
        );
        // #3: As balancer
        uint256 thirdNonce = redemptionNonce + 2;
        uint256 thirdRequestId = requestId + 2;
        vm.prank(balancer);
        dinariStorage.setRedemptionRequestId(indexToken, thirdNonce, testToken, thirdRequestId);
        assertEq(
            dinariStorage.redemptionRequestId(indexToken, thirdNonce, testToken),
            thirdRequestId,
            "redemptionRequestId not set (balancer)"
        );
    }

    // Foundry unit test to cover DinariStorage.setRedemptionRequestId branch opix-target-branch-389-True
    // This branch is the require(_requestId > 0, "Invalid redemption request id")
    function test_setRedemptionRequestId_revertOnZeroRequestId_branch389True() public {
        // Arrange: assign all three factory addresses so any is authorized
        address fac = address(0xB3FACA);
        address proc = address(0xB3FACE);
        address bal = address(0xB3BA1);
        vm.prank(owner);
        dinariStorage.setFactory(fac);
        vm.prank(owner);
        dinariStorage.setFactoryProcessor(proc);
        vm.prank(owner);
        dinariStorage.setFactoryBalancer(bal);
        address indexToken = idxToken;
        uint256 redemptionNonce = 111;
        address testToken = address(0xCAFC0FFEE);
        uint256 zeroRequestId = 0; // will hit the require and revert
        // As factory
        vm.prank(fac);
        vm.expectRevert("Invalid redemption request id");
        dinariStorage.setRedemptionRequestId(indexToken, redemptionNonce, testToken, zeroRequestId);
        // As processor
        vm.prank(proc);
        vm.expectRevert("Invalid redemption request id");
        dinariStorage.setRedemptionRequestId(indexToken, redemptionNonce + 1, testToken, zeroRequestId);
        // As balancer
        vm.prank(bal);
        vm.expectRevert("Invalid redemption request id");
        dinariStorage.setRedemptionRequestId(indexToken, redemptionNonce + 2, testToken, zeroRequestId);
    }

    // Test for DinariStorage.setRedemptionRequestId require(_token != address(0)) branch (opix-target-branch-390-True)
    function test_setRedemptionRequestId_zeroToken_reverts_branch390True() public {
        // Arrange: assign all three allowed factory-like addresses
        address fac = address(0xF123);
        address proc = address(0xF456);
        address bal = address(0xF789);
        vm.prank(owner);
        dinariStorage.setFactory(fac);
        vm.prank(owner);
        dinariStorage.setFactoryProcessor(proc);
        vm.prank(owner);
        dinariStorage.setFactoryBalancer(bal);
        address indexToken = idxToken;
        uint256 redemptionNonce = 1024;
        address zeroToken = address(0); // will trigger require on _token
        uint256 reqId = 1;
        // As factory
        vm.prank(fac);
        vm.expectRevert("Invalid token address");
        dinariStorage.setRedemptionRequestId(indexToken, redemptionNonce, zeroToken, reqId);
        // As processor
        vm.prank(proc);
        vm.expectRevert("Invalid token address");
        dinariStorage.setRedemptionRequestId(indexToken, redemptionNonce + 1, zeroToken, reqId);
        // As balancer
        vm.prank(bal);
        vm.expectRevert("Invalid token address");
        dinariStorage.setRedemptionRequestId(indexToken, redemptionNonce + 2, zeroToken, reqId);
    }

    function test_setIssuanceRequesterByNonce_onlyFactory_branch_true() public {
        // Set factoryAddress to a sender we control
        vm.prank(owner);
        dinariStorage.setFactory(factory);

        // Only factory, factoryProcessor, or factoryBalancer can call
        address indexToken = idxToken;
        uint256 issuanceNonce = 7;
        address requester = address(0xBEEFCAFE);

        // Should revert for wrong caller
        vm.expectRevert("Caller is not a factory contract");
        dinariStorage.setIssuanceRequesterByNonce(indexToken, issuanceNonce, requester);

        // Should revert if _requester == 0
        vm.prank(factory);
        vm.expectRevert("Invalid issuance requester address");
        dinariStorage.setIssuanceRequesterByNonce(indexToken, issuanceNonce, address(0));

        // Should succeed for allowed sender and nonzero requester
        vm.prank(factory);
        dinariStorage.setIssuanceRequesterByNonce(indexToken, issuanceNonce, requester);
        assertEq(dinariStorage.issuanceRequesterByNonce(indexToken, issuanceNonce), requester);
    }

    function test_setRedemptionRequesterByNonce_onlyFactory_branch_true() public {
        // Set up owner, factory, processor, balancer addresses
        vm.prank(owner);
        dinariStorage.setFactory(factory);
        address processor = address(0xBEEF01);
        address balancer = address(0xBEEF02);
        vm.prank(owner);
        dinariStorage.setFactoryProcessor(processor);
        vm.prank(owner);
        dinariStorage.setFactoryBalancer(balancer);

        address redemptionRequester = address(0xD00D);
        uint256 redemptionNonce = 1;
        address indexToken = idxToken;

        // not in allowed set
        address notAFactory = address(0x1234);
        vm.prank(notAFactory);
        vm.expectRevert("Caller is not a factory contract");
        dinariStorage.setRedemptionRequesterByNonce(indexToken, redemptionNonce, redemptionRequester);

        // Called as factoryAddress (should succeed)
        vm.prank(factory);
        dinariStorage.setRedemptionRequesterByNonce(indexToken, redemptionNonce, redemptionRequester);
        assertEq(dinariStorage.redemptionRequesterByNonce(indexToken, redemptionNonce), redemptionRequester);

        // Called as factoryProcessorAddress (should succeed)
        vm.prank(processor);
        dinariStorage.setRedemptionRequesterByNonce(indexToken, redemptionNonce + 1, redemptionRequester);
        assertEq(dinariStorage.redemptionRequesterByNonce(indexToken, redemptionNonce + 1), redemptionRequester);

        // Called as factoryBalancerAddress (should succeed)
        vm.prank(balancer);
        dinariStorage.setRedemptionRequesterByNonce(indexToken, redemptionNonce + 2, redemptionRequester);
        assertEq(dinariStorage.redemptionRequesterByNonce(indexToken, redemptionNonce + 2), redemptionRequester);
    }

    // Test for setRedemptionRequesterByNonce: branch coverage for opix-target-branch-418-True
    function test_setRedemptionRequesterByNonce_revert_on_zero_address() public {
        // Arrange: assign all three factory-like addresses so any are allowed
        address fakeFactory = address(0xFAAAC1);
        address fakeProcessor = address(0xFAAAC2);
        address fakeBalancer = address(0xFAAAC3);
        vm.prank(owner);
        dinariStorage.setFactory(fakeFactory);
        vm.prank(owner);
        dinariStorage.setFactoryProcessor(fakeProcessor);
        vm.prank(owner);
        dinariStorage.setFactoryBalancer(fakeBalancer);

        address indexToken = idxToken;
        uint256 redemptionNonce = 1234;
        address zeroAddress = address(0);

        // Test as allowed factory -- should revert if _requester == 0 (hit branch require(_requester != address(0)); on line 418)
        vm.prank(fakeFactory);
        vm.expectRevert("Invalid redemption requester address");
        dinariStorage.setRedemptionRequesterByNonce(indexToken, redemptionNonce, zeroAddress);
        // Try as processor
        vm.prank(fakeProcessor);
        vm.expectRevert("Invalid redemption requester address");
        dinariStorage.setRedemptionRequesterByNonce(indexToken, redemptionNonce, zeroAddress);
        // Try as balancer
        vm.prank(fakeBalancer);
        vm.expectRevert("Invalid redemption requester address");
        dinariStorage.setRedemptionRequesterByNonce(indexToken, redemptionNonce, zeroAddress);
    }

    function test_setBuyRequestPayedAmountById_onlyFactory_branch_424_True() public {
        // Arrange: Set all three factory addresses to the same nonzero, controlled factory addr
        vm.prank(owner);
        dinariStorage.setFactory(factory);
        vm.prank(owner);
        dinariStorage.setFactoryBalancer(factory);
        vm.prank(owner);
        dinariStorage.setFactoryProcessor(factory);

        // Inputs
        address _indexToken = idxToken;
        uint256 _requestId = 314;
        uint256 _amount = 1000;

        // Try with wrong sender first - must revert (to verify onlyFactory behavior)
        // address notFactory = address(0x1234);
        vm.expectRevert("Caller is not a factory contract");
        dinariStorage.setBuyRequestPayedAmountById(_indexToken, _requestId, _amount);

        // Now, call as any factory address, all should succeed (will cover || logic)
        // #1: as factoryAddress
        vm.prank(factory);
        dinariStorage.setBuyRequestPayedAmountById(_indexToken, _requestId, _amount);
        assertEq(dinariStorage.buyRequestPayedAmountById(_indexToken, _requestId), _amount);

        // #2: as factoryBalancerAddress
        vm.prank(owner);
        dinariStorage.setFactory(address(0xFA990));
        vm.prank(factory); // still set as factoryBalancer
        dinariStorage.setBuyRequestPayedAmountById(_indexToken, _requestId + 1, _amount + 1);
        assertEq(dinariStorage.buyRequestPayedAmountById(_indexToken, _requestId + 1), _amount + 1);

        // #3: as factoryProcessorAddress
        vm.prank(owner);
        dinariStorage.setFactoryBalancer(address(0xB000));
        vm.prank(factory); // still set as factoryProcessor
        dinariStorage.setBuyRequestPayedAmountById(_indexToken, _requestId + 2, _amount + 2);
        assertEq(dinariStorage.buyRequestPayedAmountById(_indexToken, _requestId + 2), _amount + 2);
    }

    // opix-target-branch-431-True: require(_amount > 0, "Invalid buy request amount");
    function test_setBuyRequestPayedAmountById_revertsOnZeroAmount() public {
        // Arrange: set up factory addresses as caller
        vm.prank(owner);
        dinariStorage.setFactory(factory);
        // Try setting zero amount, should revert with the correct message
        vm.prank(factory);
        vm.expectRevert(bytes("Invalid buy request amount"));
        dinariStorage.setBuyRequestPayedAmountById(idxToken, 1234, 0);
    }

    // Test for DinariStorage.setBuyRequestPayedAmountById, opix-target-branch-432-True
    // Should revert if _requestId == 0
    function test_setBuyRequestPayedAmountById_requestIdZero_reverts() public {
        // Arrange: allow factory address
        vm.prank(owner);
        dinariStorage.setFactory(factory);

        address indexToken = idxToken;
        uint256 requestId = 0; // Intentionally 0 to hit revert branch
        uint256 amount = 1000;

        // Act: call as factory, expect revert
        vm.prank(factory);
        vm.expectRevert(bytes("Invalid Request Id"));
        dinariStorage.setBuyRequestPayedAmountById(indexToken, requestId, amount);
    }

    function test_setSellRequestAssetAmountById_onlyFactory_access() public {
        // Setup: assign factory, processor, balancer
        address proc = address(0xBEEF01);
        address balancer = address(0xBEEF02);
        vm.prank(owner);
        dinariStorage.setFactory(factory);
        vm.prank(owner);
        dinariStorage.setFactoryProcessor(proc);
        vm.prank(owner);
        dinariStorage.setFactoryBalancer(balancer);

        address testIndexToken = idxToken;
        uint256 reqId = 42;
        uint256 amt = 123_456;

        // Not factory - revert
        vm.expectRevert(bytes("Caller is not a factory contract"));
        dinariStorage.setSellRequestAssetAmountById(testIndexToken, reqId, amt);

        // As factory - succeeds
        vm.prank(factory);
        dinariStorage.setSellRequestAssetAmountById(testIndexToken, reqId, amt);
        assertEq(dinariStorage.sellRequestAssetAmountById(testIndexToken, reqId), amt);

        // As processor - succeeds
        vm.prank(proc);
        dinariStorage.setSellRequestAssetAmountById(testIndexToken, reqId + 1, amt + 1);
        assertEq(dinariStorage.sellRequestAssetAmountById(testIndexToken, reqId + 1), amt + 1);

        // As balancer - succeeds
        vm.prank(balancer);
        dinariStorage.setSellRequestAssetAmountById(testIndexToken, reqId + 2, amt + 2);
        assertEq(dinariStorage.sellRequestAssetAmountById(testIndexToken, reqId + 2), amt + 2);
    }

    function test_setSellRequestAssetAmountById_amount_zero_reverts() public {
        // Setup: assign factory
        vm.prank(owner);
        dinariStorage.setFactory(factory);
        address testIndexToken = idxToken;
        uint256 reqId = 55;
        uint256 zeroAmt = 0;
        vm.prank(factory);
        vm.expectRevert(bytes("Invalid sell request amount"));
        dinariStorage.setSellRequestAssetAmountById(testIndexToken, reqId, zeroAmt);
    }

    // Test opix-target-branch-456-True: setIssuanceTokenPrimaryBalance requires msg.sender is factory/factoryProcessor/factoryBalancer
    function test_setIssuanceTokenPrimaryBalance_onlyFactory_branch_true() public {
        // Arrange: assign all three factory addresses
        address proc = address(0xCAFE01);
        address bal = address(0xCAFE02);
        vm.prank(owner);
        dinariStorage.setFactory(factory);
        vm.prank(owner);
        dinariStorage.setFactoryProcessor(proc);
        vm.prank(owner);
        dinariStorage.setFactoryBalancer(bal);

        address indexToken = idxToken;
        uint256 issuanceNonce_ = 44;
        address token = address(0xD5A9); // use any nonzero address
        uint256 amount = 123456;

        // Should revert for not being a factory-like caller
        vm.expectRevert("Caller is not a factory contract");
        dinariStorage.setIssuanceTokenPrimaryBalance(indexToken, issuanceNonce_, token, amount);

        // Should succeed for factory
        vm.prank(factory);
        dinariStorage.setIssuanceTokenPrimaryBalance(indexToken, issuanceNonce_, token, amount);
        assertEq(
            dinariStorage.issuanceTokenPrimaryBalance(indexToken, issuanceNonce_, token),
            amount,
            "balance not set by factory"
        );

        // Should succeed for processor
        vm.prank(proc);
        dinariStorage.setIssuanceTokenPrimaryBalance(indexToken, issuanceNonce_ + 1, token, amount + 1);
        assertEq(
            dinariStorage.issuanceTokenPrimaryBalance(indexToken, issuanceNonce_ + 1, token),
            amount + 1,
            "balance not set by processor"
        );

        // Should succeed for balancer
        vm.prank(bal);
        dinariStorage.setIssuanceTokenPrimaryBalance(indexToken, issuanceNonce_ + 2, token, amount + 2);
        assertEq(
            dinariStorage.issuanceTokenPrimaryBalance(indexToken, issuanceNonce_ + 2, token),
            amount + 2,
            "balance not set by balancer"
        );
    }

    // Branch coverage for DinariStorage.setIssuanceTokenPrimaryBalance
    // opix-target-branch-463-True (require(_token != address(0)))
    function test_setIssuanceTokenPrimaryBalance_revertOnZeroToken_branch_463_True() public {
        // Arrange: set up allowed factory addresses for sender
        address proc = address(0xCD01);
        address bal = address(0xCD02);
        vm.prank(owner);
        dinariStorage.setFactory(factory);
        vm.prank(owner);
        dinariStorage.setFactoryProcessor(proc);
        vm.prank(owner);
        dinariStorage.setFactoryBalancer(bal);

        address idx = idxToken;
        uint256 issuanceNonce_ = 99;
        address zeroToken = address(0);
        uint256 amount = 555;

        // Act/Assert: as factory sender, but with _token == 0
        vm.prank(factory);
        vm.expectRevert("Invalid issuance primary token address");
        dinariStorage.setIssuanceTokenPrimaryBalance(idx, issuanceNonce_, zeroToken, amount);

        // as processor
        vm.prank(proc);
        vm.expectRevert("Invalid issuance primary token address");
        dinariStorage.setIssuanceTokenPrimaryBalance(idx, issuanceNonce_, zeroToken, amount);

        // as balancer
        vm.prank(bal);
        vm.expectRevert("Invalid issuance primary token address");
        dinariStorage.setIssuanceTokenPrimaryBalance(idx, issuanceNonce_, zeroToken, amount);
    }

    // Test to cover DinariStorage.setIssuanceIndexTokenPrimaryTotalSupply: branch opix-target-branch-471-False
    // Test that only a factory/factoryProcessor/factoryBalancer can set the total supply, and that other callers revert
    function test_setIssuanceIndexTokenPrimaryTotalSupply_access_control_branch_471_False() public {
        // Arrange -- make the three factory addresses
        address fakeFactory = address(0x101);
        address fakeProcessor = address(0x102);
        address fakeBalancer = address(0x103);
        address testIndexToken = idxToken;
        uint256 testNonce = 77;
        uint256 testAmount = 10000;

        // Register factories
        vm.prank(owner);
        dinariStorage.setFactory(fakeFactory);
        vm.prank(owner);
        dinariStorage.setFactoryProcessor(fakeProcessor);
        vm.prank(owner);
        dinariStorage.setFactoryBalancer(fakeBalancer);

        // Non-factory should revert
        // address notFactory = address(0x999);
        vm.expectRevert(bytes("Caller is not a factory contract"));
        dinariStorage.setIssuanceIndexTokenPrimaryTotalSupply(testIndexToken, testNonce, testAmount);

        // All 3 factory addresses should succeed (branch 471-False is NOT reverting on the require)
        address[3] memory allowed = [fakeFactory, fakeProcessor, fakeBalancer];
        for (uint256 i = 0; i < 3; i++) {
            vm.prank(allowed[i]);
            dinariStorage.setIssuanceIndexTokenPrimaryTotalSupply(testIndexToken, testNonce + i, testAmount + i);
            assertEq(
                dinariStorage.issuanceIndexTokenPrimaryTotalSupply(testIndexToken, testNonce + i),
                testAmount + i,
                "Incorrect set value"
            );
        }
    }

    function test_setIssuanceInputAmount_onlyFactory_branch_true() public {
        // Arrange: Set up the factory, processor, and balancer addresses
        address proc = address(0x1111);
        address bal = address(0x2222);
        vm.prank(owner);
        dinariStorage.setFactory(factory);
        vm.prank(owner);
        dinariStorage.setFactoryProcessor(proc);
        vm.prank(owner);
        dinariStorage.setFactoryBalancer(bal);

        address idx = idxToken;
        uint256 nonce = 9;
        uint256 amount = 321e6;

        // Non-factory address should revert
        vm.expectRevert(bytes("Caller is not a factory contract"));
        dinariStorage.setIssuanceInputAmount(idx, nonce, amount);

        // Factory, processor, and balancer are allowed to call
        address[3] memory allowed = [factory, proc, bal];
        for (uint256 i = 0; i < allowed.length; i++) {
            // Set a different amount for each
            uint256 amt = amount + i;
            vm.prank(allowed[i]);
            dinariStorage.setIssuanceInputAmount(idx, nonce, amt);
            assertEq(
                dinariStorage.issuanceInputAmount(idx, nonce),
                amt,
                string.concat("failed for ", vm.toString(allowed[i]))
            );
        }
    }

    function test_setIssuanceInputAmount_invalid_zero_amount_reverts() public {
        // Factory is set
        vm.prank(owner);
        dinariStorage.setFactory(factory);
        // As factory, set amount to 0 → should revert on require(_amount > 0)
        vm.prank(factory);
        vm.expectRevert(bytes("Invalid issuance input amount"));
        dinariStorage.setIssuanceInputAmount(idxToken, 1, 0);
    }

    // Branch coverage: DinariStorage.setIssuanceInputAmount require(_amount > 0) branch (opix-target-branch-490-True)
    function test_setIssuanceInputAmount_revertsOnZeroAmount() public {
        // Arrange: Set up allowed sender (factory)
        address factoryAddr = address(0xF00001);
        vm.prank(owner);
        dinariStorage.setFactory(factoryAddr);

        // Act as factory, but pass _amount = 0. Should hit branch require(_amount > 0) and revert.
        vm.prank(factoryAddr);
        vm.expectRevert(bytes("Invalid issuance input amount"));
        dinariStorage.setIssuanceInputAmount(idxToken, 1234, 0);
    }

    // Branch coverage: DinariStorage.setRedemptionInputAmount
    // opix-target-branch-496-True (require msg.sender is factory/factoryProcessor/factoryBalancer)
    function test_setRedemptionInputAmount_onlyFactory_branch_true() public {
        // Set up the required factory-like addresses
        address fakeFactory = address(0xFAAAAF);
        address fakeProcessor = address(0xFAAABB);
        address fakeBalancer = address(0xFAAACC);
        address indexToken = idxToken;
        uint256 redemptionNonce = 0x42;
        uint256 amount = 1234;

        // Give DinariStorage knowledge of these factories
        vm.prank(owner);
        dinariStorage.setFactory(fakeFactory);
        vm.prank(owner);
        dinariStorage.setFactoryProcessor(fakeProcessor);
        vm.prank(owner);
        dinariStorage.setFactoryBalancer(fakeBalancer);

        // Should revert if not one of the factories
        vm.expectRevert(bytes("Caller is not a factory contract"));
        dinariStorage.setRedemptionInputAmount(indexToken, redemptionNonce, amount);

        // Succeeds as factory
        vm.prank(fakeFactory);
        dinariStorage.setRedemptionInputAmount(indexToken, redemptionNonce, amount);
        assertEq(dinariStorage.redemptionInputAmount(indexToken, redemptionNonce), amount);

        // Succeeds as processor
        vm.prank(fakeProcessor);
        dinariStorage.setRedemptionInputAmount(indexToken, redemptionNonce + 1, amount + 1);
        assertEq(dinariStorage.redemptionInputAmount(indexToken, redemptionNonce + 1), amount + 1);

        // Succeeds as balancer
        vm.prank(fakeBalancer);
        dinariStorage.setRedemptionInputAmount(indexToken, redemptionNonce + 2, amount + 2);
        assertEq(dinariStorage.redemptionInputAmount(indexToken, redemptionNonce + 2), amount + 2);
    }

    // Test for DinariStorage.setRedemptionInputAmount: require(_amount > 0, ...) branch (opix-target-branch-503-True)
    function test_setRedemptionInputAmount_zeroAmount_reverts_branch_503_True() public {
        // Arrange: set all 3 factory-relevant addresses
        address fac = address(0xFAAA1);
        address proc = address(0xFAAA2);
        address bal = address(0xFAAA3);
        vm.prank(owner);
        dinariStorage.setFactory(fac);
        vm.prank(owner);
        dinariStorage.setFactoryProcessor(proc);
        vm.prank(owner);
        dinariStorage.setFactoryBalancer(bal);

        address indexToken = idxToken;
        uint256 redemptionNonce = 32;
        uint256 zeroAmount = 0;

        // Prank as a factory address: should revert on require(_amount > 0)
        vm.prank(fac);
        vm.expectRevert(bytes("Invalid redemption input amount"));
        dinariStorage.setRedemptionInputAmount(indexToken, redemptionNonce, zeroAmount);

        // Prank as processor: should revert
        vm.prank(proc);
        vm.expectRevert(bytes("Invalid redemption input amount"));
        dinariStorage.setRedemptionInputAmount(indexToken, redemptionNonce + 1, zeroAmount);

        // Prank as balancer: should revert
        vm.prank(bal);
        vm.expectRevert(bytes("Invalid redemption input amount"));
        dinariStorage.setRedemptionInputAmount(indexToken, redemptionNonce + 2, zeroAmount);
    }

    /// Branch coverage for DinariStorage.setActionInfoById opix-target-branch-509-True (require msg.sender is factory/factoryProcessor/factoryBalancer)
    function test_setActionInfoById_onlyFactory_branchTrue() public {
        // Set up the three allowed addresses: factory, processor, balancer
        address proc = address(0xBEEF102);
        address bal = address(0xBEEF103);
        vm.prank(owner);
        dinariStorage.setFactory(factory);
        vm.prank(owner);
        dinariStorage.setFactoryProcessor(proc);
        vm.prank(owner);
        dinariStorage.setFactoryBalancer(bal);

        // Compose an ActionInfo struct
        DinariStorage.ActionInfo memory action = DinariStorage.ActionInfo({actionType: 10, nonce: 5432});
        address indexToken = idxToken;
        uint256 reqId = 7;

        // Should ONLY succeed for the three allowed senders
        // 1. factory
        vm.prank(factory);
        dinariStorage.setActionInfoById(indexToken, reqId, action);
        // Validate
        DinariStorage.ActionInfo memory ret1 = dinariStorage.getActionInfoById(indexToken, reqId);
        assertEq(ret1.actionType, 10);
        assertEq(ret1.nonce, 5432);
        // 2. processor
        DinariStorage.ActionInfo memory act2 = DinariStorage.ActionInfo({actionType: 99, nonce: 8888});
        reqId = 8;
        vm.prank(proc);
        dinariStorage.setActionInfoById(indexToken, reqId, act2);
        DinariStorage.ActionInfo memory ret2 = dinariStorage.getActionInfoById(indexToken, reqId);
        assertEq(ret2.actionType, 99);
        assertEq(ret2.nonce, 8888);
        // 3. balancer
        DinariStorage.ActionInfo memory act3 = DinariStorage.ActionInfo({actionType: 77, nonce: 7777});
        reqId = 9;
        vm.prank(bal);
        dinariStorage.setActionInfoById(indexToken, reqId, act3);
        DinariStorage.ActionInfo memory ret3 = dinariStorage.getActionInfoById(indexToken, reqId);
        assertEq(ret3.actionType, 77);
        assertEq(ret3.nonce, 7777);

        // Try an unauthorized sender, should revert hitting same require (false branch)
        address notAllowed = address(0xBAD);
        vm.prank(notAllowed);
        vm.expectRevert(bytes("Caller is not a factory contract"));
        dinariStorage.setActionInfoById(indexToken, 10, action);
    }

    // Covering branch opix-target-branch-516-True in setActionInfoById
    // require(_requestId > 0, "Invalid Request Id");
    function test_setActionInfoById_revertOnZeroRequestId_branch_516_true() public {
        // Arrange: setup factory, processor, balancer as allowed callers
        address fac = address(0xFA1);
        address proc = address(0xFA2);
        address bal = address(0xFA3);
        vm.prank(owner);
        dinariStorage.setFactory(fac);
        vm.prank(owner);
        dinariStorage.setFactoryProcessor(proc);
        vm.prank(owner);
        dinariStorage.setFactoryBalancer(bal);

        DinariStorage.ActionInfo memory act;
        act.actionType = 1;
        act.nonce = 55;
        address indexToken = idxToken;
        uint256 requestId = 0; // <--- zero, triggers revert

        // Any of the allowed senders should revert on _requestId==0
        address[3] memory allowed = [fac, proc, bal];
        for (uint256 i = 0; i < allowed.length; i++) {
            vm.prank(allowed[i]);
            vm.expectRevert(bytes("Invalid Request Id"));
            dinariStorage.setActionInfoById(indexToken, requestId, act);
        }
    }

    // Test that getActionInfoById reverts as expected when _id == 0 (i.e. branch: opix-target-branch-545-True)
    function test_getActionInfoById_reverts_on_id_zero() public {
        // Must be called by a valid caller, but _id == 0 (should revert)
        vm.expectRevert(bytes("Invalid Request Id"));
        dinariStorage.getActionInfoById(idxToken, 0);
    }

    // Test for getActionInfoById: branch coverage opix-target-branch-545-False (call with id != 0, should NOT revert)
    function test_getActionInfoById_branchFalse_returnsStruct() public {
        // Arrange: set up an ActionInfo at a given id (id!=0)
        address indexToken = idxToken;
        uint256 actionId = 1; // any nonzero value
        DinariStorage.ActionInfo memory info;
        info.actionType = 42;
        info.nonce = 999;
        // Only "factory" may set
        vm.prank(owner);
        dinariStorage.setFactory(factory);
        vm.prank(factory);
        dinariStorage.setActionInfoById(indexToken, actionId, info);
        // Act: should NOT revert and return struct
        DinariStorage.ActionInfo memory read = dinariStorage.getActionInfoById(indexToken, actionId);
        // Assert: matches
        assertEq(read.actionType, 42);
        assertEq(read.nonce, 999);
    }

    function test_getVaultDshareBalance_RevertsOnZeroAddress() public {
        // Arrange: Set up so wrappedDshareAddress[_token] exists but _token is zero
        address zeroToken = address(0);
        // Test: Should revert with 'invalid token address' (require statement on line 550)
        vm.expectRevert(bytes("invalid token address"));
        dinariStorage.getVaultDshareBalance(idxToken, zeroToken);
    }

    // Test that getAmountAfterFee returns zero when percentageFeeRate==0 (DinariStorage.sol branch opix-target-branch-559-True)
    function test_getAmountAfterFee_returnsZeroWhenPctFeeRateIsZero_opixTargetBranch559True() public view {
        // Act: call with percentageFeeRate == 0
        uint256 orderValue = 1000;
        uint24 pctFee = 0;
        uint256 result = dinariStorage.getAmountAfterFee(pctFee, orderValue);
        // Assert
        assertEq(result, 0, "Should return zero when pctFee is zero, as per opix-target-branch-559-True");
    }

    function test_priceInWei_reverts_on_ZeroTokenAddress() public {
        // This test covers DinariStorage.priceInWei branch require(_tokenAddress != address(0)), opix-target-branch-594-True
        vm.expectRevert(bytes("invalid token address"));
        dinariStorage.priceInWei(address(0));
    }

    // This Foundry test covers DinariStorage.priceInWei branch opix-target-branch-606-False,
    // which requires NOT entering the if (isMainnet) branch, thus isMainnet==false, so the 'else' is executed.
    // The path should call priceInWei on a nonzero token and return the testIssuer.latestFillPrice().
    function test_priceInWei_branch_opixTargetBranch606False_entersElseBranch() public {
        // Arrange: ensure DinariStorage.isMainnet() is false
        assertEq(dinariStorage.isMainnet(), false, "isMainnet must be false to enter else branch");
        // Patch latestPriceDecimals to nonzero (since it's used in .priceInWei)
        vm.prank(owner);
        dinariStorage.setLatestPriceDecimals(18);
        // Call priceInWei on nonzero _token (testERC20 address)
        address testToken = address(usdc); // any valid token address
        // Should not revert and should use issuer.latestFillPrice
        uint256 price = dinariStorage.priceInWei(testToken);
        // In our testing stub, latestFillPrice returns price 1e18, timestamp now
        assertEq(price, 1e18, "priceInWei (else branch) should return expected value from issuer.latestFillPrice");
    }

    /// Test that calculateBuyRequestFee reverts if amount is zero (require branch)
    function testCalculateBuyRequestFee_RevertsOnZeroAmount() public {
        vm.prank(owner);
        vm.expectRevert(bytes("Invalid amount"));
        dinariStorage.calculateBuyRequestFee(0);
    }

    // The following test hits DinariStorage.calculateIssuanceFee branch: require(_inputAmount > 0) (opix-target-branch-638-True)
    function testCalculateIssuanceFee_RevertsOnZeroAmount() public {
        // Arrange: needs valid caller, zero _inputAmount
        vm.expectRevert("Invalid amount");
        dinariStorage.calculateIssuanceFee(idxToken, 0);
    }
}

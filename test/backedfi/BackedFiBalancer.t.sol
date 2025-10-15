// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {BackedFiBalancer} from "../../src/backedfi/BackedFiBalancer.sol";
import {BackedFiStorage} from "../../src/backedfi/BackedFiStorage.sol";
import {StagingCustodyAccount} from "../../src/backedfi/StagingCustodyAccount.sol";
import {FunctionsOracle} from "../../src/oracle/FunctionsOracle.sol";
import {IndexFactoryStorage} from "../../src/factory/IndexFactoryStorage.sol";
import {Vault} from "../../src/vault/Vault.sol";
import {TestERC20} from "../utils/TestERC20.sol";
import "../OlympixUnitTest.sol";

contract BackedFiBalancerTest is OlympixUnitTest("BackedFiBalancer") {
    address internal owner = makeAddr("owner");
    address internal operator = makeAddr("operator");
    address internal nexBot = makeAddr("nexBot");
    address internal stranger = makeAddr("stranger");
    address internal indexToken = makeAddr("indexToken");

    BackedFiBalancer internal balancer;
    BackedFiStorage internal backedStorage;
    FunctionsOracle internal oracle;
    IndexFactoryStorage internal globalStorage;
    TestERC20 internal usdc;
    Vault internal vault;

    function setUp() public {
        vm.startPrank(owner);

        // Deploy and initialize FunctionsOracle
        FunctionsOracle oracleImpl = new FunctionsOracle();
        oracle = FunctionsOracle(
            address(
                new ERC1967Proxy(
                    address(oracleImpl),
                    abi.encodeWithSelector(FunctionsOracle.initialize.selector, address(0x01), bytes32("DON"))
                )
            )
        );
        oracle.setOperator(operator, true);

        // Deploy and initialize IndexFactoryStorage
        IndexFactoryStorage storageImpl = new IndexFactoryStorage();
        globalStorage = IndexFactoryStorage(
            address(
                new ERC1967Proxy(address(storageImpl), abi.encodeWithSelector(IndexFactoryStorage.initialize.selector))
            )
        );

        // Deploy BackedFiStorage (initialize after ancillary contracts exist)
        BackedFiStorage backingStorageImpl = new BackedFiStorage();
        backedStorage = BackedFiStorage(address(new ERC1967Proxy(address(backingStorageImpl), "")));

        // Deploy StagingCustodyAccount (needs storage address for initialization)
        StagingCustodyAccount scaImpl = new StagingCustodyAccount();
        StagingCustodyAccount sca = StagingCustodyAccount(address(new ERC1967Proxy(address(scaImpl), "")));

        usdc = new TestERC20("USD Coin", "USDC");

        backedStorage.initialize(address(0xFACADE), address(oracle), address(sca), nexBot, address(usdc), 2);

        sca.initialize(address(backedStorage));

        BackedFiBalancer balancerImpl = new BackedFiBalancer();
        balancer = BackedFiBalancer(address(new ERC1967Proxy(address(balancerImpl), "")));
        balancer.initialize(address(backedStorage), address(oracle), address(globalStorage));

        vm.stopPrank();

        // Map the index token to a vault in IndexFactoryStorage for rebalance flows
        vault = new Vault();
        bytes32 operatorSlot = keccak256(abi.encode(address(balancer), uint256(0)));
        vm.store(address(vault), operatorSlot, bytes32(uint256(1)));
        bytes32 slot = keccak256(abi.encode(indexToken, uint256(55)));
        vm.store(address(globalStorage), slot, bytes32(uint256(uint160(address(vault)))));
    }

    function testInitializeSetsDependencies() public {
        assertEq(address(balancer.backedfiStorage()), address(backedStorage));
        assertEq(address(balancer.functionsOracle()), address(oracle));
        assertEq(address(balancer.globalStorage()), address(globalStorage));
        assertEq(balancer.owner(), owner);
    }

    function testInitializeRevertsOnZeroAddress() public {
        BackedFiBalancer impl = new BackedFiBalancer();
        BackedFiBalancer fresh = BackedFiBalancer(address(new ERC1967Proxy(address(impl), "")));

        vm.expectRevert("balancer: zero _backedfiStorage");
        fresh.initialize(address(0), address(oracle), address(globalStorage));
    }

    function testFirstRebalanceActionOnlyOwnerOrOperator() public {
        vm.prank(stranger);
        vm.expectRevert("balancer: only owner / operator / bot");
        balancer.firstRebalanceAction(indexToken, 2, new uint256[](0));
    }

    function testOwnerCanRunFirstRebalanceAction() public {
        vm.prank(owner);
        uint256 nonce = balancer.firstRebalanceAction(indexToken, 2, new uint256[](0));

        assertEq(nonce, 1);
        (bool firstDone, bool secondDone,) = balancer.rebalanceBatches(nonce);
        assertTrue(firstDone);
        assertFalse(secondDone);
        assertEq(balancer.rebalanceNonce(), 1);
    }

    function testOperatorCanRunFirstRebalanceAction() public {
        vm.prank(operator);
        uint256 nonce = balancer.firstRebalanceAction(indexToken, 2, new uint256[](0));
        assertEq(nonce, 1);
    }

    function testNexBotCanRunFirstRebalanceAction() public {
        vm.prank(nexBot);
        uint256 nonce = balancer.firstRebalanceAction(indexToken, 2, new uint256[](0));
        assertEq(nonce, 1);
    }

    function testSecondRebalanceActionRequiresFirstDone() public {
        vm.prank(owner);
        vm.expectRevert("rebalance: bad phase");
        balancer.secondRebalanceAction(indexToken, 1, new uint256[](0));
    }

    function testSecondRebalanceActionSetsSecondDone() public {
        vm.prank(owner);
        balancer.firstRebalanceAction(indexToken, 2, new uint256[](0));

        // fund balancer with USDC (required by secondRebalanceAction)
        usdc.mint(address(balancer), 1_000e6);

        vm.prank(owner);
        balancer.secondRebalanceAction(indexToken, 1, new uint256[](0));

        (bool firstDone, bool secondDone,) = balancer.rebalanceBatches(1);
        assertTrue(firstDone);
        assertTrue(secondDone);
    }

    function testSecondRebalanceActionOnlyOwnerOrOperator() public {
        vm.prank(owner);
        balancer.firstRebalanceAction(indexToken, 2, new uint256[](0));
        usdc.mint(address(balancer), 1_000e6);

        vm.prank(stranger);
        vm.expectRevert("balancer: only owner / operator / bot");
        balancer.secondRebalanceAction(indexToken, 1, new uint256[](0));
    }

    function testCompleteRebalanceActionsRequiresSecondDone() public {
        vm.prank(owner);
        balancer.firstRebalanceAction(indexToken, 2, new uint256[](0));

        vm.prank(owner);
        vm.expectRevert(bytes("rebalance: wrong phase"));
        balancer.completeRebalanceActions(indexToken, 1);
    }

    function testCompleteRebalanceActionsAfterSecondPhase() public {
        vm.prank(owner);
        balancer.firstRebalanceAction(indexToken, 2, new uint256[](0));
        usdc.mint(address(balancer), 1_000e6);
        vm.prank(owner);
        balancer.secondRebalanceAction(indexToken, 1, new uint256[](0));

        vm.prank(owner);
        balancer.completeRebalanceActions(indexToken, 1);
    }

    function testFirstRebalanceActionSellsOverweightTokens() public {
        TestERC20 bond = new TestERC20("Bond", "BND");
        bond.mint(address(vault), 600e18);
        uint256[] memory prices = new uint256[](1);
        prices[0] = 2e18;
        address[] memory tokens = new address[](1);
        tokens[0] = address(bond);
        uint256[] memory shares = new uint256[](1);
        shares[0] = 1;
        vm.mockCall(
            address(oracle),
            abi.encodeWithSelector(FunctionsOracle.getCurrentProviderIndexData.selector, indexToken, 0, uint64(2)),
            abi.encode(uint256(0), tokens, shares)
        );
        vm.mockCall(
            address(oracle),
            abi.encodeWithSignature("tokenCurrentMarketShare(address,address)", indexToken, address(bond)),
            abi.encode(uint256(60e18))
        );
        vm.mockCall(
            address(oracle),
            abi.encodeWithSignature("tokenOracleMarketShare(address,address)", indexToken, address(bond)),
            abi.encode(uint256(20e18))
        );

        vm.prank(owner);
        uint256 nonce = balancer.firstRebalanceAction(indexToken, 2, prices);

        bytes32 base = keccak256(abi.encode(nonce, uint256(4)));
        bytes32 tokenSlot = keccak256(abi.encode(address(bond), uint256(base) + 2));
        bytes32 usdcSlot = bytes32(uint256(base) + 1);
        uint256 currentShare = 60e18;
        uint256 targetShare = 20e18;
        uint256 sellPct = ((currentShare - targetShare) * 100e18) / currentShare;
        uint256 expectedSold = (600e18 * sellPct) / 100e18;
        uint256 expectedUsdc = (expectedSold * prices[0]) / 1e18;
        assertEq(uint256(vm.load(address(balancer), tokenSlot)), expectedSold);
        assertEq(uint256(vm.load(address(balancer), usdcSlot)), expectedUsdc);
        assertEq(bond.balanceOf(nexBot), expectedSold);

        vm.clearMockedCalls();
    }

    function testSecondRebalanceActionAllocatesUsdcToShortages() public {
        TestERC20 bond = new TestERC20("Bond", "BND");
        bond.mint(address(vault), 600e18);
        uint256[] memory prices = new uint256[](1);
        prices[0] = 2e18;
        address[] memory tokens = new address[](1);
        tokens[0] = address(bond);
        uint256[] memory shares = new uint256[](1);
        shares[0] = 1;
        vm.mockCall(
            address(oracle),
            abi.encodeWithSelector(FunctionsOracle.getCurrentProviderIndexData.selector, indexToken, 0, uint64(2)),
            abi.encode(uint256(0), tokens, shares)
        );
        vm.mockCall(
            address(oracle),
            abi.encodeWithSignature("tokenCurrentMarketShare(address,address)", indexToken, address(bond)),
            abi.encode(uint256(60e18))
        );
        vm.mockCall(
            address(oracle),
            abi.encodeWithSignature("tokenOracleMarketShare(address,address)", indexToken, address(bond)),
            abi.encode(uint256(20e18))
        );
        vm.prank(owner);
        uint256 nonce = balancer.firstRebalanceAction(indexToken, 2, prices);
        vm.clearMockedCalls();
        vm.mockCall(
            address(oracle),
            abi.encodeWithSelector(FunctionsOracle.getCurrentProviderIndexData.selector, indexToken, 0, uint64(2)),
            abi.encode(uint256(0), tokens, shares)
        );
        vm.mockCall(
            address(oracle),
            abi.encodeWithSignature("tokenCurrentMarketShare(address,address)", indexToken, address(bond)),
            abi.encode(uint256(10e18))
        );
        vm.mockCall(
            address(oracle),
            abi.encodeWithSignature("tokenOracleMarketShare(address,address)", indexToken, address(bond)),
            abi.encode(uint256(50e18))
        );
        usdc.mint(address(balancer), 1_000e18);

        vm.prank(owner);
        balancer.secondRebalanceAction(indexToken, nonce, prices);

        bytes32 base = keccak256(abi.encode(nonce, uint256(4)));
        bytes32 expectedSlot = keccak256(abi.encode(address(bond), uint256(base) + 3));
        uint256 expectedTokens = (1_000e18 * 1e18) / prices[0];
        assertEq(uint256(vm.load(address(balancer), expectedSlot)), expectedTokens);
        (bool firstDone, bool secondDone,) = balancer.rebalanceBatches(nonce);
        assertTrue(firstDone);
        assertTrue(secondDone);
        assertEq(usdc.balanceOf(nexBot), 1_000e18);

        vm.clearMockedCalls();
    }

    function testCompleteRebalanceActionsTransfersInboundToVault() public {
        TestERC20 bond = new TestERC20("Bond", "BND");
        bond.mint(address(vault), 600e18);
        uint256[] memory prices = new uint256[](1);
        prices[0] = 2e18;
        address[] memory tokens = new address[](1);
        tokens[0] = address(bond);
        uint256[] memory shares = new uint256[](1);
        shares[0] = 1;
        vm.mockCall(
            address(oracle),
            abi.encodeWithSelector(FunctionsOracle.getCurrentProviderIndexData.selector, indexToken, 0, uint64(2)),
            abi.encode(uint256(0), tokens, shares)
        );
        vm.mockCall(
            address(oracle),
            abi.encodeWithSignature("tokenCurrentMarketShare(address,address)", indexToken, address(bond)),
            abi.encode(uint256(60e18))
        );
        vm.mockCall(
            address(oracle),
            abi.encodeWithSignature("tokenOracleMarketShare(address,address)", indexToken, address(bond)),
            abi.encode(uint256(20e18))
        );
        vm.prank(owner);
        uint256 nonce = balancer.firstRebalanceAction(indexToken, 2, prices);
        vm.clearMockedCalls();
        vm.mockCall(
            address(oracle),
            abi.encodeWithSelector(FunctionsOracle.getCurrentProviderIndexData.selector, indexToken, 0, uint64(2)),
            abi.encode(uint256(0), tokens, shares)
        );
        vm.mockCall(
            address(oracle),
            abi.encodeWithSignature("tokenCurrentMarketShare(address,address)", indexToken, address(bond)),
            abi.encode(uint256(10e18))
        );
        vm.mockCall(
            address(oracle),
            abi.encodeWithSignature("tokenOracleMarketShare(address,address)", indexToken, address(bond)),
            abi.encode(uint256(50e18))
        );
        usdc.mint(address(balancer), 1_000e18);
        vm.prank(owner);
        balancer.secondRebalanceAction(indexToken, nonce, prices);
        uint256 preVaultBalance = bond.balanceOf(address(vault));
        uint256 depositAmount = 200e18;
        bond.mint(address(balancer), depositAmount);

        vm.prank(owner);
        balancer.completeRebalanceActions(indexToken, nonce);

        bytes32 base = keccak256(abi.encode(nonce, uint256(4)));
        bytes32 claimedSlot = keccak256(abi.encode(address(bond), uint256(base) + 4));
        assertEq(bond.balanceOf(address(vault)), preVaultBalance + depositAmount);
        assertEq(bond.balanceOf(address(balancer)), 0);
        assertEq(uint256(vm.load(address(balancer), claimedSlot)), depositAmount);

        vm.clearMockedCalls();
    }

    function testInitializeRevertsOnZeroOracleAddress() public {
        BackedFiBalancer impl = new BackedFiBalancer();
        BackedFiBalancer fresh = BackedFiBalancer(address(new ERC1967Proxy(address(impl), "")));

        // This should revert on the oracle address being zero (which targets the opix-target-branch-83-True branch in the subject code)
        vm.expectRevert("balancer: zero _oracle");
        fresh.initialize(address(backedStorage), address(0), address(globalStorage));
    }

    function testInitializeRevertsOnZeroGlobalStorageAddress() public {
        BackedFiBalancer impl = new BackedFiBalancer();
        BackedFiBalancer fresh = BackedFiBalancer(address(new ERC1967Proxy(address(impl), "")));
        // Should revert with "balancer: zero _globalStorage" at opix-target-branch-84-True
        vm.expectRevert("balancer: zero _globalStorage");
        fresh.initialize(address(backedStorage), address(oracle), address(0));
    }

    function test_askValues_revertsWhenIndexTokenIsZero() public {
        address zeroAddress = address(0);
        address[] memory underlyings = new address[](1);
        underlyings[0] = address(0x1234);
        uint256[] memory prices = new uint256[](1);
        prices[0] = 1e18;
        // Cover branch: require(_indexToken != address(0)), opix-target-branch-100-True
        vm.expectRevert(bytes("askValues: indexToken=0"));
        balancer.askValues(zeroAddress, underlyings, prices);
    }

    function test_askValues_indexTokenNotZero_branch100_False() public {
        // This test targets opix-target-branch-100-False by ensuring _indexToken != address(0).

        // Arrange: Use indexToken as setup in setUp(), which is mapped to a vault.
        // Prepare a new ERC20 as the underlying asset and credit the vault with a balance.
        TestERC20 token = new TestERC20("Asset", "AST");
        address tokenAddr = address(token);
        uint256 tokenBalance = 12e18;
        token.mint(address(vault), tokenBalance);

        address[] memory underlyings = new address[](1);
        underlyings[0] = tokenAddr;
        uint256 price = 7e18;
        uint256[] memory prices = new uint256[](1);
        prices[0] = price;

        // Act: call askValues (should NOT revert)
        (uint256 totalProviderValue, uint256[] memory assetValues) = balancer.askValues(indexToken, underlyings, prices);

        // Assert:
        uint256 expectedVal = tokenBalance * price / 1e18;
        assertEq(assetValues.length, 1);
        assertEq(assetValues[0], expectedVal);
        assertEq(totalProviderValue, expectedVal);
        // Also, assetValues[0] == vault's token balance * price / 1e18
    }

    function test_askValues_lengthMismatchReverts() public {
        address[] memory underlyings = new address[](2);
        underlyings[0] = address(0x1234);
        underlyings[1] = address(0x4567);
        uint256[] memory prices = new uint256[](1);
        prices[0] = 1e18;
        // This triggers require(underlyings.length == prices.length, ...) in askValues
        // which is the opix-target-branch-101-True branch
        vm.expectRevert(bytes("askValues: length mismatch"));
        balancer.askValues(indexToken, underlyings, prices);
    }

    function test_askValues_revertWhenVaultNotSet_branch109_True() public {
        // This test targets opix-target-branch-109-True, i.e., require(vaultAddr != address(0), "askValues: vault not set");
        // Arrange: Use an indexToken with no vault set in globalStorage mapping.
        address fakeIndexToken = address(0xC0FFEE);
        // No mapping into globalStorage for this fakeIndexToken, so vaultAddr will be zero
        address[] memory underlyings = new address[](1);
        underlyings[0] = address(0xABCD);
        uint256[] memory prices = new uint256[](1);
        prices[0] = 1e18;
        // Act: Expect revert
        vm.expectRevert(bytes("askValues: vault not set"));
        balancer.askValues(fakeIndexToken, underlyings, prices);
    }

    function test_askValues_revertOnUnderlying0_branch116_True() public {
        // This test targets opix-target-branch-116-True, i.e. require(token != address(0), "askValues: ");
        // Arrange: Use a token address of zero in underlyings.
        address[] memory underlyings = new address[](1);
        underlyings[0] = address(0);
        uint256[] memory prices = new uint256[](1);
        prices[0] = 5e18;
        // Act/Assert: We expect revert on token==address(0) at require(token!=address(0)), covering branch 116-True
        vm.expectRevert();
        balancer.askValues(indexToken, underlyings, prices);
    }

    function test_askValues_whenBalanceOrPriceIsZero_branch119_True() public {
        // This targets opix-target-branch-119-True: if (balance == 0 || price == 0) {assetValues[i] = 0;}
        // Arrange: Setup vault with zero asset balance and nonzero price
        TestERC20 token = new TestERC20("Asset", "AST");
        address tokenAddr = address(token);
        uint256 tokenBalance = 0;
        // No mint, so vault balance is zero.
        address[] memory underlyings = new address[](1);
        underlyings[0] = tokenAddr;
        uint256[] memory prices = new uint256[](1);
        prices[0] = 9e18;
        // Act: askValues -- should yield 0, not revert
        (uint256 totalProviderValue1, uint256[] memory assetValues1) =
            balancer.askValues(indexToken, underlyings, prices);
        // Assert zero result from branch (balance == 0)
        assertEq(assetValues1.length, 1);
        assertEq(assetValues1[0], 0);
        assertEq(totalProviderValue1, 0);

        // Now, test with nonzero balance, but price == 0
        token.mint(address(vault), 10e18);
        prices[0] = 0;
        (uint256 totalProviderValue2, uint256[] memory assetValues2) =
            balancer.askValues(indexToken, underlyings, prices);
        assertEq(assetValues2.length, 1);
        assertEq(assetValues2[0], 0);
        assertEq(totalProviderValue2, 0);
    }

    function testFirstRebalanceActionVaultNotSetReverts() public {
        // Setup: Use an indexToken not mapped to any vault in globalStorage
        address missingVaultIndexToken = address(0xDCBA);
        uint256[] memory prices = new uint256[](0); // prices don't matter since require should hit first

        vm.prank(owner);
        vm.expectRevert("rebalance: vault not set");
        balancer.firstRebalanceAction(missingVaultIndexToken, 2, prices);
    }

    function testFirstRebalanceActionPriceLengthMismatchReverts() public {
        // Setup: indexToken is mapped to the vault in globalStorage in setUp, so it is valid.
        TestERC20 bond = new TestERC20("Bond", "BND");
        bond.mint(address(vault), 1000e18);
        address[] memory tokens = new address[](2);
        tokens[0] = address(bond);
        tokens[1] = address(0x1234);
        uint256[] memory shares = new uint256[](2);
        shares[0] = 50e18;
        shares[1] = 50e18;
        // prices array too short (only 1 instead of 2), triggers price length mismatch branch
        uint256[] memory prices = new uint256[](1);
        prices[0] = 2e18;
        // Mock the oracle to report 2 tokens for this provider index
        vm.mockCall(
            address(oracle),
            abi.encodeWithSelector(FunctionsOracle.getCurrentProviderIndexData.selector, indexToken, 0, uint64(2)),
            abi.encode(uint256(0), tokens, shares)
        );

        vm.prank(owner);
        vm.expectRevert("rebalance: price length mismatch");
        balancer.firstRebalanceAction(indexToken, 2, prices);

        vm.clearMockedCalls();
    }

    function testSecondRebalanceActionRevertsWhenNoUSDC() public {
        // Arrange - set up the balancer so that phase1 is done, but contract has no USDC
        address bond = address(new TestERC20("Bond", "BND"));
        uint256[] memory prices = new uint256[](1);
        prices[0] = 1e18;
        address[] memory tokens = new address[](1);
        tokens[0] = bond;
        uint256[] memory shares = new uint256[](1);
        shares[0] = 1;
        vm.mockCall(
            address(oracle),
            abi.encodeWithSelector(FunctionsOracle.getCurrentProviderIndexData.selector, indexToken, 0, uint64(2)),
            abi.encode(uint256(0), tokens, shares)
        );
        vm.mockCall(
            address(oracle),
            abi.encodeWithSignature("tokenCurrentMarketShare(address,address)", indexToken, bond),
            abi.encode(uint256(10e18))
        );
        vm.mockCall(
            address(oracle),
            abi.encodeWithSignature("tokenOracleMarketShare(address,address)", indexToken, bond),
            abi.encode(uint256(0))
        );

        vm.prank(owner);
        uint256 nonce = balancer.firstRebalanceAction(indexToken, 2, prices);
        vm.clearMockedCalls();
        vm.mockCall(
            address(oracle),
            abi.encodeWithSelector(FunctionsOracle.getCurrentProviderIndexData.selector, indexToken, 0, uint64(2)),
            abi.encode(uint256(0), tokens, shares)
        );
        vm.mockCall(
            address(oracle),
            abi.encodeWithSignature("tokenCurrentMarketShare(address,address)", indexToken, bond),
            abi.encode(uint256(0))
        );
        vm.mockCall(
            address(oracle),
            abi.encodeWithSignature("tokenOracleMarketShare(address,address)", indexToken, bond),
            abi.encode(uint256(10e18))
        );
        // Purposefully do NOT mint USDC to balancer, so USDC balance is 0
        // Act & Assert
        vm.prank(owner);
        vm.expectRevert("balancer: no USDC");
        balancer.secondRebalanceAction(indexToken, nonce, prices);
        vm.clearMockedCalls();
    }

    function test_secondRebalanceAction_revertsOnPriceLengthMismatch() public {
        TestERC20 bond = new TestERC20("Bond", "BND");
        bond.mint(address(vault), 500e18);
        uint256[] memory correctPrices = new uint256[](1);
        uint256[] memory wrongPrices = new uint256[](2);
        correctPrices[0] = 2e18;
        wrongPrices[0] = 2e18;
        wrongPrices[1] = 3e18;
        address[] memory tokens = new address[](1);
        tokens[0] = address(bond);
        uint256[] memory shares = new uint256[](1);
        shares[0] = 1;
        vm.mockCall(
            address(oracle),
            abi.encodeWithSelector(FunctionsOracle.getCurrentProviderIndexData.selector, indexToken, 0, uint64(2)),
            abi.encode(uint256(0), tokens, shares)
        );
        vm.mockCall(
            address(oracle),
            abi.encodeWithSignature("tokenCurrentMarketShare(address,address)", indexToken, address(bond)),
            abi.encode(uint256(10e18))
        );
        vm.mockCall(
            address(oracle),
            abi.encodeWithSignature("tokenOracleMarketShare(address,address)", indexToken, address(bond)),
            abi.encode(uint256(5e18))
        );
        vm.prank(owner);
        uint256 nonce = balancer.firstRebalanceAction(indexToken, 2, correctPrices);
        // Mint USDC to balancer so that secondRebalanceAction runs far enough to hit require
        usdc.mint(address(balancer), 1_000e18);
        // SecondRebalanceAction with wrong prices length -> want opix-target-branch-221-True
        vm.prank(owner);
        vm.expectRevert("rebalance: price length mismatch");
        balancer.secondRebalanceAction(indexToken, nonce, wrongPrices);
        vm.clearMockedCalls();
    }

    function test_secondRebalanceAction_priceIsZero_branch251_False() public {
        // This targets opix-target-branch-251-False by ensuring `if (price > 0)` is false (i.e., price == 0).
        // Arrange: Setup balancer mid-rebalance, ensure there is a shortage, and price for target token is 0.
        TestERC20 bond = new TestERC20("Bond", "BND");
        bond.mint(address(vault), 1000e18);
        uint256[] memory prices = new uint256[](1);
        prices[0] = 2e18; // For phase1, does not matter
        address[] memory tokens = new address[](1);
        tokens[0] = address(bond);
        uint256[] memory shares = new uint256[](1);
        shares[0] = 1;
        vm.mockCall(
            address(oracle),
            abi.encodeWithSelector(FunctionsOracle.getCurrentProviderIndexData.selector, indexToken, 0, uint64(2)),
            abi.encode(uint256(0), tokens, shares)
        );
        // Setup so token is overweight for first phase
        vm.mockCall(
            address(oracle),
            abi.encodeWithSignature("tokenCurrentMarketShare(address,address)", indexToken, address(bond)),
            abi.encode(uint256(80e18))
        );
        vm.mockCall(
            address(oracle),
            abi.encodeWithSignature("tokenOracleMarketShare(address,address)", indexToken, address(bond)),
            abi.encode(uint256(30e18))
        );
        vm.prank(owner);
        uint256 nonce = balancer.firstRebalanceAction(indexToken, 2, prices);

        vm.clearMockedCalls();
        // Now, for second phase: set the shortage (oracle value > current value) and price == 0 to hit branch 251-False
        vm.mockCall(
            address(oracle),
            abi.encodeWithSelector(FunctionsOracle.getCurrentProviderIndexData.selector, indexToken, 0, uint64(2)),
            abi.encode(uint256(0), tokens, shares)
        );
        vm.mockCall(
            address(oracle),
            abi.encodeWithSignature("tokenCurrentMarketShare(address,address)", indexToken, address(bond)),
            abi.encode(uint256(10e18))
        );
        vm.mockCall(
            address(oracle),
            abi.encodeWithSignature("tokenOracleMarketShare(address,address)", indexToken, address(bond)),
            abi.encode(uint256(50e18))
        );
        usdc.mint(address(balancer), 1_000e18);
        uint256[] memory pricesBranch = new uint256[](1);
        pricesBranch[0] = 0; // price == 0 ensures branch 251-False hit

        vm.prank(owner);
        // Should not revert, we assert that expectedInbound is not updated due to price == 0
        balancer.secondRebalanceAction(indexToken, nonce, pricesBranch);
        bytes32 base = keccak256(abi.encode(nonce, uint256(4)));
        bytes32 expectedSlot = keccak256(abi.encode(address(bond), uint256(base) + 3));
        assertEq(
            uint256(vm.load(address(balancer), expectedSlot)), 0, "expectedInbound should remain 0 when price == 0"
        );
        (bool firstDone, bool secondDone,) = balancer.rebalanceBatches(nonce);
        assertTrue(firstDone);
        assertTrue(secondDone);
        vm.clearMockedCalls();
    }

    function test_handleShortageForSecondRebalance_else_branch_274_YOUR_TEST_SHOULD_ENTER_THIS_ELSE_BRANCH() public {
        // This test covers the opix-target-branch-274-YOUR-TEST-SHOULD-ENTER-THIS-ELSE-BRANCH:
        // It should ensure that _handleShortageForSecondRebalance's 'else' branch fires: current >= target
        // Setup a scenario where current >= target

        address bond = address(new TestERC20("Bond", "BND"));
        uint256 current = 15e18;
        uint256 target = 10e18;

        // Prepare balance for rebalance prerequisites
        uint256[] memory prices = new uint256[](1);
        prices[0] = 5e18;
        address[] memory tokens = new address[](1);
        tokens[0] = bond;
        uint256[] memory shares = new uint256[](1);
        shares[0] = 1;

        // Mock oracle for phase 1 (overweight, so some is sold, but not critical for this branch)
        vm.mockCall(
            address(oracle),
            abi.encodeWithSelector(FunctionsOracle.getCurrentProviderIndexData.selector, indexToken, 0, uint64(2)),
            abi.encode(uint256(0), tokens, shares)
        );
        vm.mockCall(
            address(oracle),
            abi.encodeWithSignature("tokenCurrentMarketShare(address,address)", indexToken, bond),
            abi.encode(current)
        );
        // Use target < current so phase1 will sell
        vm.mockCall(
            address(oracle),
            abi.encodeWithSignature("tokenOracleMarketShare(address,address)", indexToken, bond),
            abi.encode(target)
        );
        // Start phase 1
        vm.prank(owner);
        uint256 nonce = balancer.firstRebalanceAction(indexToken, 2, prices);
        // Mint USDC so phase 2 can run
        usdc.mint(address(balancer), 1_000e18);
        // Phase 2: focus on branch 274-YOUR-TEST-SHOULD-ENTER-THIS-ELSE-BRANCH
        vm.clearMockedCalls();

        // Mock for phase 2: current >= target (should take 'else' path)
        vm.mockCall(
            address(oracle),
            abi.encodeWithSelector(FunctionsOracle.getCurrentProviderIndexData.selector, indexToken, 0, uint64(2)),
            abi.encode(uint256(0), tokens, shares)
        );
        vm.mockCall(
            address(oracle),
            abi.encodeWithSignature("tokenCurrentMarketShare(address,address)", indexToken, bond),
            abi.encode(current) // (current >= target)
        );
        vm.mockCall(
            address(oracle),
            abi.encodeWithSignature("tokenOracleMarketShare(address,address)", indexToken, bond),
            abi.encode(target)
        );

        // Run phase 2 (should hit the 'else' branch)
        vm.prank(owner);
        balancer.secondRebalanceAction(indexToken, nonce, prices);
        // Now, check that shortages is set to zero for this asset (set by else branch)
        bytes32 base = keccak256(abi.encode(nonce, uint256(4)));
        bytes32 shortagesSlot = keccak256(abi.encode(address(bond), uint256(base) + 3));
        assertEq(uint256(vm.load(address(balancer), shortagesSlot)), 0, "Shortages should be zero due to else branch");

        (bool firstDone, bool secondDone,) = balancer.rebalanceBatches(nonce);
        assertTrue(firstDone);
        assertTrue(secondDone);

        vm.clearMockedCalls();
    }

    function test__sellBond_priceZero_opix_target_branch_343_YOUR_TEST_SHOULD_ENTER_THIS_ELSE_BRANCH() public {
        // This test targets opix-target-branch-343-YOUR-TEST-SHOULD-ENTER-THIS-ELSE-BRANCH:
        // The if (price != 0) in _sellBond() should be false (price == 0).
        // Arrange:
        TestERC20 bond = new TestERC20("Bond", "BND");
        bond.mint(address(vault), 500e18);
        address[] memory tokens = new address[](1);
        tokens[0] = address(bond);
        uint256[] memory shares = new uint256[](1);
        shares[0] = 1;
        uint256[] memory prices = new uint256[](1);
        prices[0] = 0; // Price is zero (this is the target for the branch)
        // Set up mocking:
        vm.mockCall(
            address(oracle),
            abi.encodeWithSelector(FunctionsOracle.getCurrentProviderIndexData.selector, indexToken, 0, uint64(2)),
            abi.encode(uint256(0), tokens, shares)
        );
        // To cause a sell, make current > target
        vm.mockCall(
            address(oracle),
            abi.encodeWithSignature("tokenCurrentMarketShare(address,address)", indexToken, address(bond)),
            abi.encode(uint256(20e18))
        );
        vm.mockCall(
            address(oracle),
            abi.encodeWithSignature("tokenOracleMarketShare(address,address)", indexToken, address(bond)),
            abi.encode(uint256(10e18))
        );
        // Act: run firstRebalanceAction, which in turn will call _sellBond with price == 0
        vm.prank(owner);
        uint256 nonce = balancer.firstRebalanceAction(indexToken, 2, prices);
        // Assert: check that batch.totalUsdcObtained for this batch is zero (since price == 0)
        bytes32 base = keccak256(abi.encode(nonce, uint256(4)));
        bytes32 usdcSlot = bytes32(uint256(base) + 1);
        assertEq(
            uint256(vm.load(address(balancer), usdcSlot)), 0, "totalUsdcObtained should remain zero for price == 0"
        );
        // Also, verify bond was sold and credited to nexBot
        uint256 currentShare = 20e18;
        uint256 targetShare = 10e18;
        uint256 sellPct = ((currentShare - targetShare) * 100e18) / currentShare;
        uint256 expectedSold = (500e18 * sellPct) / 100e18;
        assertEq(bond.balanceOf(nexBot), expectedSold, "All sold bonds should be transferred to nexBot");
        // There should be no revert, and assert(true) is executed for price == 0 inside the branch
        vm.clearMockedCalls();
    }

    function test_pause_branch_356_True() public {
        // This test targets the opix-target-branch-356-True in pause():
        // If true { _pause(); }
        // Arrange: Only owner can call pause(), balancer is initially unpaused by setUp
        assertFalse(balancer.paused(), "Should start unpaused");
        vm.prank(owner);
        balancer.pause();
        assertTrue(balancer.paused(), "Balancer should be paused");
    }

    function test_unpause_opix_target_branch_362_True() public {
        // This test targets the opix-target-branch-362-True branch: the if (true) { _unpause(); } branch of unpause()
        // Arrange: The contract must first be paused so that unpause() will run _unpause() without revert
        vm.prank(owner);
        balancer.pause();
        // Act: Now, call unpause as owner
        vm.prank(owner);
        balancer.unpause();
        // Assert: The contract should not be paused
        assertFalse(balancer.paused(), "Balancer should be unpaused after calling unpause");
    }

    // function test_Gas_firstRebalanceAction_Success() public {
    //     // set up state so it succeeds…
    //     uint256 g0 = gasleft();
    //     balancer.firstRebalanceAction(indexToken, 4, [1e18]);
    //     uint256 used = g0 - gasleft();
    //     emit log_named_uint("gas used (success path)", used);
    // }
}

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

contract BackedFiBalancerTest is Test {
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
            address(new ERC1967Proxy(address(oracleImpl), abi.encodeWithSelector(FunctionsOracle.initialize.selector, address(0x01), bytes32("DON"))))
        );
        oracle.setOperator(operator, true);

        // Deploy and initialize IndexFactoryStorage
        IndexFactoryStorage storageImpl = new IndexFactoryStorage();
        globalStorage = IndexFactoryStorage(
            address(new ERC1967Proxy(address(storageImpl), abi.encodeWithSelector(IndexFactoryStorage.initialize.selector)))
        );

        // Deploy BackedFiStorage (initialize after ancillary contracts exist)
        BackedFiStorage backingStorageImpl = new BackedFiStorage();
        backedStorage = BackedFiStorage(address(new ERC1967Proxy(address(backingStorageImpl), "")));

        // Deploy StagingCustodyAccount (needs storage address for initialization)
        StagingCustodyAccount scaImpl = new StagingCustodyAccount();
        StagingCustodyAccount sca =
            StagingCustodyAccount(address(new ERC1967Proxy(address(scaImpl), "")));

        usdc = new TestERC20("USD Coin", "USDC");

        backedStorage.initialize(
            address(0xFACADE),
            address(oracle),
            address(sca),
            nexBot,
            address(usdc),
            2
        );

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
}

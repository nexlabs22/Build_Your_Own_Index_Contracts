// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {DinariBalancer} from "../../src/dinari/DinariBalancer.sol";
import {DinariStorage} from "../../src/dinari/DinariStorage.sol";
import {FunctionsOracle} from "../../src/oracle/FunctionsOracle.sol";
import {IndexFactoryStorage} from "../../src/factory/IndexFactoryStorage.sol";
import {IndexFactoryBalancer} from "../../src/factory/IndexFactoryBalancer.sol";
import {TestERC20} from "../utils/TestERC20.sol";
import {OrderProcessor} from "../../src/dinari/dinari/orders/OrderProcessor.sol";
import {IOrderProcessor} from "../../src/dinari/dinari/interfaces/IOrderProcessor.sol";

contract DinariBalancerTest is Test {
    address internal owner = makeAddr("owner");
    address internal operator = makeAddr("operator");
    address internal stranger = makeAddr("stranger");

    DinariBalancer internal balancer;
    DinariStorage internal dinariStorage;
    FunctionsOracle internal oracle;
    IndexFactoryStorage internal globalStorage;
    IndexFactoryBalancer internal globalBalancer;

    function setUp() public {
        vm.startPrank(owner);

        // Deploy upgradeable DinariStorage (initializer called after balancer deployment)
        DinariStorage storageImpl = new DinariStorage();
        dinariStorage = DinariStorage(address(new ERC1967Proxy(address(storageImpl), "")));

        // Deploy and initialize FunctionsOracle
        FunctionsOracle oracleImpl = new FunctionsOracle();
        oracle = FunctionsOracle(
            address(new ERC1967Proxy(address(oracleImpl), abi.encodeWithSelector(FunctionsOracle.initialize.selector, address(0x01), bytes32("DON"))))
        );
        oracle.setOperator(operator, true);

        // Deploy and initialize IndexFactoryStorage
        IndexFactoryStorage storageGlobalImpl = new IndexFactoryStorage();
        globalStorage = IndexFactoryStorage(
            address(new ERC1967Proxy(address(storageGlobalImpl), abi.encodeWithSelector(IndexFactoryStorage.initialize.selector)))
        );

        // Deploy real IndexFactoryBalancer (left uninitialized – sufficient for dependency wiring)
        globalBalancer = new IndexFactoryBalancer();

        // Deploy DinariBalancer through proxy and initialize
        DinariBalancer balancerImpl = new DinariBalancer();
        balancer = DinariBalancer(address(new ERC1967Proxy(address(balancerImpl), "")));
        balancer.initialize(address(dinariStorage), address(oracle), address(globalStorage), address(globalBalancer));

        // Complete DinariStorage initialization now that balancer exists
        OrderProcessor orderProcessor = new OrderProcessor();
        TestERC20 usdc = new TestERC20("USD Coin", "USDC");
        dinariStorage.initialize(
            address(orderProcessor),
            address(globalStorage),
            address(balancer),
            address(usdc),
            6,
            address(oracle),
            false,
            2
        );

        vm.stopPrank();
    }

    function testInitializeSetsDependencies() public {
        assertEq(address(balancer.dinariStorage()), address(dinariStorage));
        assertEq(address(balancer.functionsOracle()), address(oracle));
        assertEq(address(balancer.globalStorage()), address(globalStorage));
        assertEq(address(balancer.globalBalancer()), address(globalBalancer));
        assertEq(balancer.owner(), owner);
    }

    function testInitializeRevertsOnZeroFactoryStorage() public {
        DinariBalancer impl = new DinariBalancer();
        DinariBalancer fresh = DinariBalancer(address(new ERC1967Proxy(address(impl), "")));

        vm.expectRevert("invalid _factoryStorage address");
        fresh.initialize(address(0), address(oracle), address(globalStorage), address(globalBalancer));
    }

    function testInitializeRevertsOnZeroOracle() public {
        DinariBalancer impl = new DinariBalancer();
        DinariBalancer fresh = DinariBalancer(address(new ERC1967Proxy(address(impl), "")));

        vm.expectRevert("invalid _functionsOracle address");
        fresh.initialize(address(dinariStorage), address(0), address(globalStorage), address(globalBalancer));
    }

    function testCannotReinitialize() public {
        vm.expectRevert(abi.encodeWithSignature("InvalidInitialization()"));
        balancer.initialize(address(dinariStorage), address(oracle), address(globalStorage), address(globalBalancer));
    }

    function testSetMinimumOrderAmountOwner() public {
        uint256 amount = 1_000_000;

        vm.prank(owner);
        bool updated = balancer.setMinimumOrderAmount(amount);
        assertTrue(updated);
        assertEq(balancer.minimumOrderAmount(), amount);
    }

    function testSetMinimumOrderAmountRequiresOwnerOrOperator() public {
        vm.prank(stranger);
        vm.expectRevert("Only owner or operator can call this function");
        balancer.setMinimumOrderAmount(5);
    }

    function testOperatorCanSetMinimumOrderAmount() public {
        uint256 amount = 77;
        vm.prank(operator);
        bool updated = balancer.setMinimumOrderAmount(amount);
        assertTrue(updated);
        assertEq(balancer.minimumOrderAmount(), amount);
    }

    function testSetIndexFactoryStorageOnlyOwner() public {
        address newStorage = makeAddr("newStorage");

        vm.prank(owner);
        bool ok = balancer.setIndexFactoryStorage(newStorage);
        assertTrue(ok);
        assertEq(address(balancer.dinariStorage()), newStorage);

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, stranger));
        balancer.setIndexFactoryStorage(makeAddr("fail"));
    }

    function testSetFunctionsOracleOnlyOwner() public {
        FunctionsOracle oracleImpl = new FunctionsOracle();
        FunctionsOracle another = FunctionsOracle(
            address(new ERC1967Proxy(address(oracleImpl), abi.encodeWithSelector(FunctionsOracle.initialize.selector, address(0x02), bytes32("NEW"))))
        );

        vm.prank(owner);
        bool ok = balancer.setFunctionsOracle(address(another));
        assertTrue(ok);
        assertEq(address(balancer.functionsOracle()), address(another));

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, stranger));
        balancer.setFunctionsOracle(address(oracle));
    }

    function testPauseAndUnpauseOnlyOwner() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, stranger));
        balancer.pause();

        vm.prank(owner);
        balancer.pause();
        assertTrue(balancer.paused());

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, stranger));
        balancer.unpause();

        vm.prank(owner);
        balancer.unpause();
        assertFalse(balancer.paused());
    }

    function testAskValuesRecordsPortfolioData() public {
        address indexToken = makeAddr("index");
        address tokenA = makeAddr("tokenA");
        address tokenB = makeAddr("tokenB");
        address[] memory tokens = new address[](2);
        tokens[0] = tokenA;
        tokens[1] = tokenB;
        uint256[] memory shares = new uint256[](2);
        shares[0] = 1;
        shares[1] = 1;
        uint256 providerIndex = dinariStorage.providerIndex();
        vm.mockCall(
            address(oracle),
            abi.encodeWithSelector(FunctionsOracle.getCurrentProviderIndexData.selector, indexToken, 0, providerIndex),
            abi.encode(uint256(0), tokens, shares)
        );
        vm.mockCall(
            address(dinariStorage),
            abi.encodeWithSelector(DinariStorage.getVaultDshareValue.selector, indexToken, tokenA),
            abi.encode(uint256(100))
        );
        vm.mockCall(
            address(dinariStorage),
            abi.encodeWithSelector(DinariStorage.getVaultDshareValue.selector, indexToken, tokenB),
            abi.encode(uint256(40))
        );
        vm.mockCall(
            address(globalBalancer),
            abi.encodeWithSelector(IndexFactoryBalancer.completeDinariAskValues.selector, uint256(1), uint256(140)),
            abi.encode()
        );

        vm.prank(owner);
        uint256 reported = balancer.askValues(indexToken);

        assertEq(balancer.rebalanceNonce(indexToken), 1);
        assertEq(balancer.portfolioValueByNonce(indexToken, 1), 140);
        assertEq(balancer.tokenValueByNonce(indexToken, 1, tokenA), 100);
        assertEq(balancer.tokenValueByNonce(indexToken, 1, tokenB), 40);
        assertEq(reported, dinariStorage.updatePortfolioNonce());

        vm.clearMockedCalls();
    }

    function testCheckFirstRebalanceOrdersStatusDetectsIncomplete() public {
        address indexToken = makeAddr("index");
        address underlying = makeAddr("underlying");
        uint256 requestId = 11;
        bytes32 nonceSlot = keccak256(abi.encode(indexToken, uint256(4)));
        vm.store(address(balancer), nonceSlot, bytes32(uint256(1)));
        bytes32 requestOuter = keccak256(abi.encode(indexToken, uint256(5)));
        bytes32 requestMid = keccak256(abi.encode(uint256(1), requestOuter));
        bytes32 requestSlot = keccak256(abi.encode(underlying, requestMid));
        vm.store(address(balancer), requestSlot, bytes32(requestId));
        bytes32 sellOuter = keccak256(abi.encode(indexToken, uint256(7)));
        bytes32 sellSlot = keccak256(abi.encode(requestId, sellOuter));
        vm.store(address(balancer), sellSlot, bytes32(uint256(5)));
        address[] memory tokens = new address[](1);
        tokens[0] = underlying;
        uint256[] memory shares = new uint256[](1);
        shares[0] = 1;
        vm.mockCall(
            address(oracle),
            abi.encodeWithSelector(FunctionsOracle.getCurrentProviderIndexData.selector, indexToken, 0, dinariStorage.providerIndex()),
            abi.encode(uint256(0), tokens, shares)
        );
        vm.mockCall(
            address(dinariStorage.issuer()),
            abi.encodeWithSelector(IOrderProcessor.getOrderStatus.selector, requestId),
            abi.encode(uint8(IOrderProcessor.OrderStatus.ACTIVE))
        );

        assertFalse(balancer.checkFirstRebalanceOrdersStatus(indexToken, 1));

        vm.clearMockedCalls();
        vm.mockCall(
            address(oracle),
            abi.encodeWithSelector(FunctionsOracle.getCurrentProviderIndexData.selector, indexToken, 0, dinariStorage.providerIndex()),
            abi.encode(uint256(0), tokens, shares)
        );
        vm.mockCall(
            address(dinariStorage.issuer()),
            abi.encodeWithSelector(IOrderProcessor.getOrderStatus.selector, requestId),
            abi.encode(uint8(IOrderProcessor.OrderStatus.FULFILLED))
        );

        assertTrue(balancer.checkFirstRebalanceOrdersStatus(indexToken, 1));

        vm.clearMockedCalls();
    }

    function testCheckSecondRebalanceOrdersStatusDetectsIncomplete() public {
        address indexToken = makeAddr("index");
        address underlying = makeAddr("underlying");
        uint256 requestId = 19;
        bytes32 nonceSlot = keccak256(abi.encode(indexToken, uint256(4)));
        vm.store(address(balancer), nonceSlot, bytes32(uint256(1)));
        bytes32 requestOuter = keccak256(abi.encode(indexToken, uint256(5)));
        bytes32 requestMid = keccak256(abi.encode(uint256(1), requestOuter));
        bytes32 requestSlot = keccak256(abi.encode(underlying, requestMid));
        vm.store(address(balancer), requestSlot, bytes32(requestId));
        bytes32 buyOuter = keccak256(abi.encode(indexToken, uint256(6)));
        bytes32 buySlot = keccak256(abi.encode(requestId, buyOuter));
        vm.store(address(balancer), buySlot, bytes32(uint256(7)));
        address[] memory tokens = new address[](1);
        tokens[0] = underlying;
        uint256[] memory shares = new uint256[](1);
        shares[0] = 1;
        vm.mockCall(
            address(oracle),
            abi.encodeWithSelector(FunctionsOracle.getCurrentProviderIndexData.selector, indexToken, 0, dinariStorage.providerIndex()),
            abi.encode(uint256(0), tokens, shares)
        );
        vm.mockCall(
            address(dinariStorage.issuer()),
            abi.encodeWithSelector(IOrderProcessor.getOrderStatus.selector, requestId),
            abi.encode(uint8(IOrderProcessor.OrderStatus.ACTIVE))
        );

        assertFalse(balancer.checkSecondRebalanceOrdersStatus(indexToken, 1));

        vm.clearMockedCalls();
        vm.mockCall(
            address(oracle),
            abi.encodeWithSelector(FunctionsOracle.getCurrentProviderIndexData.selector, indexToken, 0, dinariStorage.providerIndex()),
            abi.encode(uint256(0), tokens, shares)
        );
        vm.mockCall(
            address(dinariStorage.issuer()),
            abi.encodeWithSelector(IOrderProcessor.getOrderStatus.selector, requestId),
            abi.encode(uint8(IOrderProcessor.OrderStatus.FULFILLED))
        );

        assertTrue(balancer.checkSecondRebalanceOrdersStatus(indexToken, 1));

        vm.clearMockedCalls();
    }

    function testSecondRebalanceActionRevertsWhenOrdersPending() public {
        address indexToken = makeAddr("index");
        address underlying = makeAddr("underlying");
        uint256 requestId = 29;
        bytes32 nonceSlot = keccak256(abi.encode(indexToken, uint256(4)));
        vm.store(address(balancer), nonceSlot, bytes32(uint256(1)));
        bytes32 requestOuter = keccak256(abi.encode(indexToken, uint256(5)));
        bytes32 requestMid = keccak256(abi.encode(uint256(1), requestOuter));
        bytes32 requestSlot = keccak256(abi.encode(underlying, requestMid));
        vm.store(address(balancer), requestSlot, bytes32(requestId));
        bytes32 sellOuter = keccak256(abi.encode(indexToken, uint256(7)));
        bytes32 sellSlot = keccak256(abi.encode(requestId, sellOuter));
        vm.store(address(balancer), sellSlot, bytes32(uint256(2)));
        address[] memory tokens = new address[](1);
        tokens[0] = underlying;
        uint256[] memory shares = new uint256[](1);
        shares[0] = 1;
        vm.mockCall(
            address(oracle),
            abi.encodeWithSelector(FunctionsOracle.getCurrentProviderIndexData.selector, indexToken, 0, dinariStorage.providerIndex()),
            abi.encode(uint256(0), tokens, shares)
        );
        vm.mockCall(
            address(dinariStorage.issuer()),
            abi.encodeWithSelector(IOrderProcessor.getOrderStatus.selector, requestId),
            abi.encode(uint8(IOrderProcessor.OrderStatus.ACTIVE))
        );

        vm.prank(owner);
        vm.expectRevert(bytes("Rebalance orders are not completed"));
        balancer.secondRebalanceAction(indexToken, 1, 0);

        vm.clearMockedCalls();
    }
}

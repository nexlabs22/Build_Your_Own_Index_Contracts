// test/integration/FullWorkflow.t.sol
// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../../src/token/IndexToken.sol";
import "../../src/vault/Vault.sol";
import "../../src/orderManager/OrderManager.sol";
import "../../src/oracle/FunctionsOracle.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../utils/TestHelpers.sol";
import "../utils/MockContracts.sol";

contract FullWorkflowTest is Test, TestHelpers {
    IndexToken public indexToken;
    NexVault public vault;
    OrderManager public orderManager;
    FunctionsOracle public oracle;
    
    ERC1967Proxy public tokenProxy;
    ERC1967Proxy public vaultProxy;
    ERC1967Proxy public orderManagerProxy;
    ERC1967Proxy public oracleProxy;
    
    address public owner;
    address public methodologist;
    address public feeReceiver;
    address public operator;
    address public user1;
    address public user2;

    function setUp() public {
        owner = address(this);
        methodologist = makeAddr("methodologist");
        feeReceiver = makeAddr("feeReceiver");
        operator = makeAddr("operator");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        _deployAllContracts();
        _setupRoles();
    }

    function _deployAllContracts() internal {
        // Deploy IndexToken
        IndexToken tokenImplementation = new IndexToken();
        bytes memory tokenInitData = abi.encodeWithSelector(
            IndexToken.initialize.selector,
            "Index Token",
            "IDX",
            1000000000000000000, // 1% daily fee
            feeReceiver,
            1000000000 * 1e18 // 1B supply ceiling
        );
        tokenProxy = new ERC1967Proxy(address(tokenImplementation), tokenInitData);
        indexToken = IndexToken(address(tokenProxy));

        // Deploy Vault
        NexVault vaultImplementation = new NexVault();
        bytes memory vaultInitData = abi.encodeWithSelector(
            NexVault.initialize.selector,
            operator
        );
        vaultProxy = new ERC1967Proxy(address(vaultImplementation), vaultInitData);
        vault = NexVault(address(vaultProxy));

        // Deploy OrderManager
        OrderManager orderManagerImplementation = new OrderManager();
        bytes memory orderManagerInitData = abi.encodeWithSelector(
            OrderManager.initialize.selector,
            makeAddr("usdc")
        );
        orderManagerProxy = new ERC1967Proxy(address(orderManagerImplementation), orderManagerInitData);
        orderManager = OrderManager(address(orderManagerProxy));

        // Deploy Oracle
        FunctionsOracle oracleImplementation = new FunctionsOracle();
        bytes memory oracleInitData = abi.encodeWithSelector(
            FunctionsOracle.initialize.selector,
            makeAddr("functionsRouter"),
            bytes32("donId")
        );
        oracleProxy = new ERC1967Proxy(address(oracleImplementation), oracleInitData);
        oracle = FunctionsOracle(address(oracleProxy));
    }

    function _setupRoles() internal {
        // Set up IndexToken roles
        vm.prank(owner);
        indexToken.setMethodologist(methodologist);
        
        vm.prank(methodologist);
        indexToken.setMethodology("Initial methodology");

        // Set up Oracle roles
        vm.prank(owner);
        oracle.setFactoryBalancer(makeAddr("factoryBalancer"));
    }

    function testFullWorkflow() public {
        // Test token minting
        vm.prank(owner);
        indexToken.mint(user1, 1000000 * 1e18);
        
        assertEq(indexToken.balanceOf(user1), 1000000 * 1e18);
        assertEq(indexToken.totalSupply(), 1000000 * 1e18);

        // Test fee accrual
        vm.warp(block.timestamp + 1 days);
        
        vm.prank(owner);
        indexToken.mintToFeeReceiver();
        
        uint256 expectedFee = (1000000 * 1e18 * indexToken.feeRatePerDayScaled()) / 1e20;
        assertEq(indexToken.balanceOf(feeReceiver), expectedFee);

        // Test order creation
        OrderManager.CreateOrderConfig memory config = OrderManager.CreateOrderConfig({
            inputTokenAddress: makeAddr("usdc"),
            outputTokenAddress: address(indexToken),
            assetType: 1,
            inputTokenAmount: 1000 * 1e6,
            outputTokenAmount: 0,
            isBuyOrder: true
        });

        vm.prank(operator);
        uint256 orderId = orderManager.createOrder(config);

        assertEq(orderId, 1);
        
        // Destructure the tuple returned by orderInfo()
        (address _targetTokenAddress, uint64 _assetType, uint256 _usdcAmount, uint256 _targetTokenAmount, bool _isBuyOrder, bool _isExecuted, uint256 _timestamp) = orderManager.orderInfo(orderId); // Marked unused variables with _
        assertEq(_targetTokenAddress, address(indexToken));
        assertEq(_assetType, 1);
        assertEq(_usdcAmount, 1000 * 1e6);
        assertEq(_targetTokenAmount, 0);
        assertTrue(_isBuyOrder);
        assertFalse(_isExecuted);

        // Test order completion
        vm.prank(operator);
        orderManager.completeOrder(orderId);

        // Destructure the tuple returned by orderInfo() again to check execution status
        ( , , , , , bool isExecutedAfter, ) = orderManager.orderInfo(orderId);
        assertTrue(isExecutedAfter);
    }

    function testFeeAccrualWorkflow() public {
        // First mint some tokens to have a non-zero total supply
        vm.prank(owner);
        indexToken.mint(user1, 1000000 * 1e18);
        
        // Test fee accrual over multiple days
        vm.warp(block.timestamp + 3 days);
        
        vm.prank(owner);
        indexToken.mintToFeeReceiver();
        
        uint256 expectedFee = (1000000 * 1e18 * indexToken.feeRatePerDayScaled()) / 1e20 * 3;
        assertEq(indexToken.balanceOf(feeReceiver), expectedFee);
    }

    function testMultipleOrdersWorkflow() public {
        // Create multiple orders
        for (uint256 i = 0; i < 5; i++) {
            OrderManager.CreateOrderConfig memory config = OrderManager.CreateOrderConfig({
                inputTokenAddress: makeAddr("usdc"),
                outputTokenAddress: address(indexToken),
                assetType: 1,
                inputTokenAmount: 1000 * 1e6,
                outputTokenAmount: 0,
                isBuyOrder: true
            });

            vm.prank(operator);
            uint256 orderId = orderManager.createOrder(config);

            assertEq(orderId, i + 1);
            
            // Destructure the tuple returned by orderInfo()
            (address _targetTokenAddress, uint64 _assetType, uint256 _usdcAmount, uint256 _targetTokenAmount, bool _isBuyOrder, bool _isExecuted, uint256 _timestamp) = orderManager.orderInfo(orderId); // Marked unused variables with _
            assertEq(_targetTokenAddress, address(indexToken));
            assertEq(_assetType, 1);
            assertEq(_usdcAmount, 1000 * 1e6);
            assertEq(_targetTokenAmount, 0);
            assertTrue(_isBuyOrder);
            assertFalse(_isExecuted);
        }
    }
}

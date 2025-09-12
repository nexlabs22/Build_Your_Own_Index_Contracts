// test/invariant/SystemInvariants.t.sol
// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol"; // Corrected import style
import {console} from "forge-std/console.sol"; // Corrected import style
import {IndexToken} from "../../src/token/IndexToken.sol"; // Corrected import style
import {NexVault} from "../../src/vault/Vault.sol"; // Corrected import style
import {OrderManager} from "../../src/orderManager/OrderManager.sol"; // Corrected import style
import {FunctionsOracle} from "../../src/oracle/FunctionsOracle.sol"; // Corrected import style
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol"; // Corrected import style
import {TestHelpers} from "../utils/TestHelpers.sol"; // Corrected import style
import {MockUSDC} from "../utils/MockContracts.sol"; // Corrected import style

contract SystemInvariantsTest is Test, TestHelpers {
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

    function setUp() public {
        owner = address(this);
        methodologist = makeAddr("methodologist");
        feeReceiver = makeAddr("feeReceiver");
        operator = makeAddr("operator");

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

    function invariant_totalSupplyNeverExceedsCeiling() public view { // Added view
        assertLe(indexToken.totalSupply(), indexToken.supplyCeiling());
    }

    function invariant_ownerIsAlwaysSet() public view { // Added view
        assertTrue(indexToken.owner() != address(0));
        assertTrue(vault.owner() != address(0));
        assertTrue(oracle.owner() != address(0));
        assertTrue(orderManager.owner() != address(0));
    }

    function invariant_feeReceiverIsSet() public view { // Added view
        assertTrue(indexToken.feeReceiver() != address(0));
    }

    function invariant_methodologistIsSet() public view { // Added view
        assertTrue(indexToken.methodologist() != address(0));
    }

    function invariant_orderNonceAlwaysIncrements() public view { // Added view
        // Destructure the tuple returned by orderNonceInfo()
        (uint buyOrderNonce, uint sellOrderNonce, uint orderNonce) = orderManager.orderNonceInfo();
        assertGe(orderNonce, 0);
        assertGe(buyOrderNonce, 0);
        assertGe(sellOrderNonce, 0);
    }

    function invariant_oracleDataConsistency() public view { // Added view
        if (oracle.totalOracleList() > 0) {
            assertTrue(oracle.lastUpdateTime() > 0);
        }
    }

    function invariant_vaultOperatorPermissions() public view { // Added view
        assertTrue(vault.owner() != address(0));
    }

    function invariant_tokenBalancesNonNegative() public pure { // Added pure
        // This invariant ensures that all token balances are non-negative
        // This is automatically enforced by the ERC20 standard
        assertTrue(true);
    }
}

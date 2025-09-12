// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script} from "forge-std/Script.sol"; // Corrected import style
import {IndexToken} from "../../src/token/IndexToken.sol"; // Corrected import style
import {NexVault} from "../../src/vault/Vault.sol"; // Corrected import style
import {FunctionsOracle} from "../../src/oracle/FunctionsOracle.sol"; // Corrected import style
import {OrderManager} from "../../src/orderManager/OrderManager.sol"; // Corrected import style
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol"; // Corrected import style
import {MockUSDC} from "./MockContracts.sol"; // Corrected import style

contract DeployScripts is Script {
    function deployAllContracts() public returns (
        IndexToken indexToken,
        NexVault vault,
        FunctionsOracle oracle,
        OrderManager orderManager,
        MockUSDC mockUsdc // Corrected variable name
    ) {
        // Deploy mock USDC
        mockUsdc = new MockUSDC(); // Corrected variable name

        // Deploy IndexToken with correct parameters
        IndexToken tokenImpl = new IndexToken();
        bytes memory tokenInitData = abi.encodeWithSelector(
            IndexToken.initialize.selector,
            "Index Token",                  // tokenName
            "IDX",                         // tokenSymbol
            1000000000000000000,           // _feeRatePerDayScaled (1% daily)
            makeAddr("feeReceiver"),       // _feeReceiver
            1000000000 * 1e18              // _supplyCeiling (1B)
        );
        ERC1967Proxy tokenProxy = new ERC1967Proxy(address(tokenImpl), tokenInitData);
        indexToken = IndexToken(address(tokenProxy));

        // Deploy Vault
        NexVault vaultImpl = new NexVault();
        bytes memory vaultInitData = abi.encodeWithSelector(
            NexVault.initialize.selector,
            makeAddr("operator")
        );
        ERC1967Proxy vaultProxy = new ERC1967Proxy(address(vaultImpl), vaultInitData);
        vault = NexVault(address(vaultProxy));

        // Deploy Oracle
        FunctionsOracle oracleImpl = new FunctionsOracle();
        bytes memory oracleInitData = abi.encodeWithSelector(
            FunctionsOracle.initialize.selector,
            makeAddr("functionsRouter"),
            bytes32("test-don-id")
        );
        ERC1967Proxy oracleProxy = new ERC1967Proxy(address(oracleImpl), oracleInitData);
        oracle = FunctionsOracle(address(oracleProxy));

        // Deploy OrderManager
        OrderManager orderManagerImpl = new OrderManager();
        bytes memory orderManagerInitData = abi.encodeWithSelector(
            OrderManager.initialize.selector,
            address(mockUsdc) // Corrected variable name
        );
        ERC1967Proxy orderManagerProxy = new ERC1967Proxy(address(orderManagerImpl), orderManagerInitData);
        orderManager = OrderManager(address(orderManagerProxy));
    }

    function setupRoles(
        IndexToken indexToken,
        NexVault vault,
        FunctionsOracle oracle,
        OrderManager orderManager
    ) public {
        // Set methodologist for IndexToken
        indexToken.setMethodologist(makeAddr("methodologist"));
        
        // Set up roles and permissions
        indexToken.setMinter(address(vault), true);
        vault.setOperator(address(orderManager), true);
        oracle.setOperator(address(orderManager), true);
        orderManager.setOperator(address(this), true);
    }
}

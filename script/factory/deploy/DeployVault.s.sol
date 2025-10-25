// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/Test.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "openzeppelin-foundry-upgrades/Upgrades.sol";

import "../../../src/vault/Vault.sol";

contract DeployVault is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        address owner = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        address proxy =
            Upgrades.deployTransparentProxy("Vault.sol", owner, abi.encodeCall(Vault.initialize, (address(0))));

        Vault nexVaultImplementation = Vault(proxy);

        address proxyAdmin = Upgrades.getAdminAddress(proxy);

        console.log("NexVault implementation deployed at:", address(nexVaultImplementation));
        console.log("NexVault proxy deployed at:", address(proxy));
        console.log("ProxyAdmin for NexVault deployed at:", address(proxyAdmin));

        vm.stopBroadcast();
    }
}

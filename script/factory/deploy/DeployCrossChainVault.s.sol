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

        string memory targetChain = "arbitrum_sepolia";
        // string memory targetChain = "base";

        address crosschainIndexFactory;
        address crosschainIndexFactoryBalancer;

        address owner = vm.addr(deployerPrivateKey);

        if (keccak256(bytes(targetChain)) == keccak256("arbitrum_sepolia")) {
            crosschainIndexFactory = vm.envAddress("ARBITRUM_SEPOLIA_CROSS_CHAIN_FACTORY_PROXY_ADDRESS");
            crosschainIndexFactoryBalancer =
                vm.envAddress("ARBITRUM_SEPOLIA_CROSS_CHAIN_FACTORY_BALANCER_PROXY_ADDRESS");
        } else if (keccak256(bytes(targetChain)) == keccak256("base")) {
            crosschainIndexFactory = vm.envAddress("");
            crosschainIndexFactoryBalancer = vm.envAddress("");
        } else {
            revert("Unsupported target chain");
        }

        vm.startBroadcast(deployerPrivateKey);

        address proxy =
            Upgrades.deployTransparentProxy("Vault.sol", owner, abi.encodeCall(Vault.initialize, (address(0))));

        Vault nexVaultImplementation = Vault(proxy);

        address proxyAdmin = Upgrades.getAdminAddress(proxy);

        console.log("Vault implementation deployed at:", address(nexVaultImplementation));
        console.log("Vault proxy deployed at:", address(proxy));
        console.log("ProxyAdmin for Vault deployed at:", address(proxyAdmin));

        Vault(proxy).setOperator(crosschainIndexFactory, true);
        Vault(proxy).setOperator(crosschainIndexFactoryBalancer, true);

        console.log("Set operators successfuly!");

        vm.stopBroadcast();
    }
}

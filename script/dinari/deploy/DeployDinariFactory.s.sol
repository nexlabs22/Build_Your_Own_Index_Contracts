// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/Test.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "openzeppelin-foundry-upgrades/Upgrades.sol";

import "../../../src/dinari/DinariFactory.sol";

contract DeployDinariFactory is Script {
    DinariFactory public dinariFactory;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        string memory targetChain = "sepolia";
        address owner = vm.addr(deployerPrivateKey);

        address indexFactoryStorageProxy;
        address dinariStorageProxy;
        address functionsOracleProxy;

        if (keccak256(bytes(targetChain)) == keccak256("sepolia")) {
            indexFactoryStorageProxy = vm.envAddress("SEPOLIA_INDEX_FACTORY_STORAGE_PROXY_ADDRESS");
            dinariStorageProxy = vm.envAddress("SEPOLIA_DINARI_STORAGE_PROXY_ADDRESS");
            functionsOracleProxy = vm.envAddress("SEPOLIA_FUNCTIONS_ORACLE_PROXY_ADDRESS");
        } else if (keccak256(bytes(targetChain)) == keccak256("arbitrum_mainnet")) {
            indexFactoryStorageProxy = vm.envAddress("ARBITRUM_INDEX_FACTORY_STORAGE_PROXY_ADDRESS");
            dinariStorageProxy = vm.envAddress("ARBITRUM_DINARI_STORAGE_PROXY_ADDRESS");
            functionsOracleProxy = vm.envAddress("ARBITRUM_FUNCTIONS_ORACLE_PROXY_ADDRESS");
        } else {
            revert("Unsupported target chain");
        }

        vm.startBroadcast(deployerPrivateKey);

        address proxy = Upgrades.deployTransparentProxy(
            "DinariFactory.sol",
            owner,
            abi.encodeCall(
                DinariFactory.initialize, (indexFactoryStorageProxy, dinariStorageProxy, functionsOracleProxy)
            )
        );

        dinariFactory = DinariFactory(proxy);
        address adminAddr = Upgrades.getAdminAddress(proxy);

        console.log("DinariFactory implementation deployed at:", address(dinariFactory));
        console.log("DinariFactory proxy deployed at:", proxy);
        console.log("ProxyAdmin for DinariFactory deployed at:", adminAddr);

        vm.stopBroadcast();
    }
}

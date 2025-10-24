// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import "openzeppelin-foundry-upgrades/Upgrades.sol";

import {DinariFactoryProcessor} from "../../../src/dinari/DinariFactoryProcessor.sol";

contract DeployDinariFactoryProcessor is Script {
    DinariFactoryProcessor public dinariFactoryProcessor;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.addr(deployerPrivateKey);
        string memory targetChain = "sepolia";

        address indexFactoryStorageProxy;
        address dinariStorageProxy;
        address functionsOracleProxy;
        address orderManagerProxy;

        if (keccak256(bytes(targetChain)) == keccak256("sepolia")) {
            indexFactoryStorageProxy = vm.envAddress("SEPOLIA_INDEX_FACTORY_STORAGE_PROXY_ADDRESS");
            dinariStorageProxy = vm.envAddress("SEPOLIA_DINARI_STORAGE_PROXY_ADDRESS");
            functionsOracleProxy = vm.envAddress("SEPOLIA_FUNCTIONS_ORACLE_PROXY_ADDRESS");
            orderManagerProxy = vm.envAddress("SEPOLIA_DINARI_ORDER_MANAGER_PROXY_ADDRESS");
        } else if (keccak256(bytes(targetChain)) == keccak256("arbitrum_mainnet")) {
            indexFactoryStorageProxy = vm.envAddress("ARBITRUM_INDEX_FACTORY_STORAGE_PROXY_ADDRESS");
            dinariStorageProxy = vm.envAddress("ARBITRUM_DINARI_STORAGE_PROXY_ADDRESS");
            functionsOracleProxy = vm.envAddress("ARBITRUM_FUNCTIONS_ORACLE_PROXY_ADDRESS");
            orderManagerProxy = vm.envAddress("ARBITRUM_DINARI_ORDER_MANAGER_PROXY_ADDRESS");
        } else {
            revert("Unsupported target chain");
        }

        vm.startBroadcast(deployerPrivateKey);

        address proxy = Upgrades.deployTransparentProxy(
            "DinariFactoryProcessor.sol",
            owner,
            abi.encodeCall(
                DinariFactoryProcessor.initialize,
                (indexFactoryStorageProxy, dinariStorageProxy, functionsOracleProxy, orderManagerProxy)
            )
        );

        dinariFactoryProcessor = DinariFactoryProcessor(proxy);
        address adminAddr = Upgrades.getAdminAddress(proxy);

        console.log("DinariFactoryProcessor implementation deployed at:", address(dinariFactoryProcessor));
        console.log("DinariFactoryProcessor proxy deployed at:", proxy);
        console.log("ProxyAdmin for DinariFactoryProcessor deployed at:", adminAddr);

        vm.stopBroadcast();
    }
}

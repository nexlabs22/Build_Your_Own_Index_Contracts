// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import "openzeppelin-foundry-upgrades/Upgrades.sol";

import {OrderManager} from "../../../src/orderManager/OrderManager.sol";

contract DeployOrderManager is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.addr(deployerPrivateKey);
        string memory targetChain = vm.envOr("TARGET_CHAIN", string("arbitrum_mainnet"));

        address usdcToken;
        address indexFactoryProxy;
        address indexFactoryStorageProxy;
        // address mainChainFactoryProxy;
        // address coreSenderProxy;

        if (keccak256(bytes(targetChain)) == keccak256("sepolia")) {
            usdcToken = vm.envAddress("SEPOLIA_USDC_ADDRESS");
            indexFactoryProxy = vm.envAddress("SEPOLIA_INDEX_FACTORY_PROXY_ADDRESS");
            indexFactoryStorageProxy = vm.envAddress("SEPOLIA_INDEX_FACTORY_STORAGE_PROXY_ADDRESS");
            // mainChainFactoryProxy = vm.envAddress("SEPOLIA_MAIN_CHAIN_FACTORY_PROXY_ADDRESS");
            // coreSenderProxy = vm.envAddress("SEPOLIA_CORE_SENDER_PROXY_ADDRESS");
        } else if (keccak256(bytes(targetChain)) == keccak256("arbitrum_mainnet")) {
            usdcToken = vm.envAddress("ARBITRUM_USDC_ADDRESS");
            indexFactoryProxy = vm.envAddress("ARBITRUM_INDEX_FACTORY_PROXY_ADDRESS");
            indexFactoryStorageProxy = vm.envAddress("ARBITRUM_INDEX_FACTORY_STORAGE_PROXY_ADDRESS");
            // mainChainFactoryProxy = vm.envAddress("ARBITRUM_MAIN_CHAIN_FACTORY_PROXY_ADDRESS");
            // coreSenderProxy = vm.envAddress("ARBITRUM_CORE_SENDER_PROXY_ADDRESS");
        } else {
            revert("Unsupported target chain");
        }

        vm.startBroadcast(deployerPrivateKey);

        address proxy = Upgrades.deployTransparentProxy(
            "OrderManager.sol",
            owner,
            abi.encodeCall(OrderManager.initialize, (usdcToken, indexFactoryProxy, indexFactoryStorageProxy))
        );

        address proxyAdmin = Upgrades.getAdminAddress(proxy);
        console.log("OrderManager proxy deployed at:", proxy);
        console.log("OrderManager ProxyAdmin:", proxyAdmin);

        // OrderManager(proxy).setOperator(mainChainFactoryProxy, true);
        // OrderManager(proxy).setOperator(coreSenderProxy, true);

        vm.stopBroadcast();
    }
}


// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import "openzeppelin-foundry-upgrades/Upgrades.sol";

import {IndexFactory} from "../../../src/factory/IndexFactory.sol";

contract DeployIndexFactory is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.addr(deployerPrivateKey);
        string memory targetChain = vm.envOr("TARGET_CHAIN", string("arbitrum_mainnet"));

        address orderManagerProxy;
        address functionsOracleProxy;
        address indexFactoryStorageProxy;

        if (keccak256(bytes(targetChain)) == keccak256("sepolia")) {
            orderManagerProxy = vm.envAddress("SEPOLIA_ORDER_MANAGER_PROXY_ADDRESS");
            functionsOracleProxy = vm.envAddress("SEPOLIA_FUNCTIONS_ORACLE_PROXY_ADDRESS");
            indexFactoryStorageProxy = vm.envAddress("SEPOLIA_INDEX_FACTORY_STORAGE_PROXY_ADDRESS");
        } else if (keccak256(bytes(targetChain)) == keccak256("arbitrum_mainnet")) {
            orderManagerProxy = vm.envAddress("ARBITRUM_ORDER_MANAGER_PROXY_ADDRESS");
            functionsOracleProxy = vm.envAddress("ARBITRUM_FUNCTIONS_ORACLE_PROXY_ADDRESS");
            indexFactoryStorageProxy = vm.envAddress("ARBITRUM_INDEX_FACTORY_STORAGE_PROXY_ADDRESS");
        } else {
            revert("Unsupported target chain");
        }

        vm.startBroadcast(deployerPrivateKey);

        address proxy = Upgrades.deployTransparentProxy(
            "IndexFactory.sol",
            owner,
            abi.encodeCall(IndexFactory.initialize, (orderManagerProxy, functionsOracleProxy, indexFactoryStorageProxy))
        );

        address proxyAdmin = Upgrades.getAdminAddress(proxy);
        console.log("IndexFactory proxy deployed at:", proxy);
        console.log("IndexFactory ProxyAdmin:", proxyAdmin);

        vm.stopBroadcast();
    }
}


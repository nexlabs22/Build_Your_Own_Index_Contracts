// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import "openzeppelin-foundry-upgrades/Upgrades.sol";

import {IndexFactoryBalancer} from "../../../src/factory/IndexFactoryBalancer.sol";

contract DeployIndexFactoryBalancer is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.addr(deployerPrivateKey);
        string memory targetChain = vm.envOr("TARGET_CHAIN", string("sepolia"));

        address functionsOracleProxy;
        address indexFactoryStorageProxy;
        address mainChainBalancerProxy;
        address mainChainBalancer2Proxy;
        address dinariBalancerProxy;

        if (keccak256(bytes(targetChain)) == keccak256("sepolia")) {
            functionsOracleProxy = vm.envAddress("SEPOLIA_FUNCTIONS_ORACLE_PROXY_ADDRESS");
            indexFactoryStorageProxy = vm.envAddress("SEPOLIA_INDEX_FACTORY_STORAGE_PROXY_ADDRESS");
            mainChainBalancerProxy = vm.envAddress("SEPOLIA_MAIN_CHAIN_BALANCER_PROXY_ADDRESS");
            mainChainBalancer2Proxy = vm.envAddress("SEPOLIA_MAIN_CHAIN_BALANCER2_PROXY_ADDRESS");
            dinariBalancerProxy = vm.envAddress("SEPOLIA_DINARI_BALANCER_PROXY_ADDRESS");
        } else if (keccak256(bytes(targetChain)) == keccak256("arbitrum_mainnet")) {
            functionsOracleProxy = vm.envAddress("ARBITRUM_FUNCTIONS_ORACLE_PROXY_ADDRESS");
            indexFactoryStorageProxy = vm.envAddress("ARBITRUM_INDEX_FACTORY_STORAGE_PROXY_ADDRESS");
            mainChainBalancerProxy = vm.envAddress("ARBITRUM_MAIN_CHAIN_BALANCER_PROXY_ADDRESS");
            mainChainBalancer2Proxy = vm.envAddress("ARBITRUM_MAIN_CHAIN_BALANCER2_PROXY_ADDRESS");
            dinariBalancerProxy = vm.envAddress("ARBITRUM_DINARI_BALANCER_PROXY_ADDRESS");
        } else {
            revert("Unsupported target chain");
        }

        vm.startBroadcast(deployerPrivateKey);

        address proxy = Upgrades.deployTransparentProxy(
            "IndexFactoryBalancer.sol",
            owner,
            abi.encodeCall(
                IndexFactoryBalancer.initialize,
                (functionsOracleProxy, indexFactoryStorageProxy, mainChainBalancerProxy, mainChainBalancer2Proxy, dinariBalancerProxy)
            )
        );

        address proxyAdmin = Upgrades.getAdminAddress(proxy);
        console.log("IndexFactoryBalancer proxy deployed at:", proxy);
        console.log("IndexFactoryBalancer ProxyAdmin:", proxyAdmin);

        vm.stopBroadcast();
    }
}


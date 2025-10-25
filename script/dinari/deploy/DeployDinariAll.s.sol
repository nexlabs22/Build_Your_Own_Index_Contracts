// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import "openzeppelin-foundry-upgrades/Upgrades.sol";

import {DinariStorage} from "../../../src/dinari/DinariStorage.sol";
import {DinariBalancer} from "../../../src/dinari/DinariBalancer.sol";
import {DinariFactory} from "../../../src/dinari/DinariFactory.sol";
import {DinariOrderManager} from "../../../src/dinari/DinariOrderManager.sol";
import {DinariFactoryProcessor} from "../../../src/dinari/DinariFactoryProcessor.sol";

contract DeployDinariAll is Script {
    DinariStorage public dinariStorage;
    DinariBalancer public dinariBalancer;
    DinariFactory public dinariFactory;
    DinariOrderManager public dinariOrderManager;
    DinariFactoryProcessor public dinariFactoryProcessor;

    struct DinariConfig {
        address issuer;
        address indexFactoryStorageProxy;
        address indexFactoryBalancerProxy;
        address functionsOracleProxy;
        address usdcToken;
        uint8 usdcDecimals;
        bool isMainnet;
        uint8 providerIndex;
        address coreOrderManagerProxy;
    }

    struct DeployedProxies {
        address storageProxy;
        address balancerProxy;
        address factoryProxy;
        address orderManagerProxy;
        address factoryProcessorProxy;
    }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.addr(deployerPrivateKey);
        string memory targetChain = "sepolia";

        DinariConfig memory cfg = _loadConfig(targetChain);

        vm.startBroadcast(deployerPrivateKey);

        DeployedProxies memory proxies = _deployProxies(owner, cfg);

        dinariStorage = DinariStorage(proxies.storageProxy);
        dinariBalancer = DinariBalancer(proxies.balancerProxy);
        dinariFactory = DinariFactory(proxies.factoryProxy);
        dinariOrderManager = DinariOrderManager(proxies.orderManagerProxy);
        dinariFactoryProcessor = DinariFactoryProcessor(proxies.factoryProcessorProxy);

        dinariStorage.initialize(
            cfg.issuer,
            cfg.indexFactoryStorageProxy,
            proxies.balancerProxy,
            cfg.usdcToken,
            cfg.usdcDecimals,
            cfg.functionsOracleProxy,
            cfg.isMainnet,
            cfg.providerIndex
        );

        dinariStorage.setOrderManager(proxies.orderManagerProxy);
        dinariStorage.setFactoryProcessor(proxies.factoryProcessorProxy);

        dinariBalancer.initialize(
            proxies.storageProxy, cfg.functionsOracleProxy, cfg.indexFactoryStorageProxy, cfg.indexFactoryBalancerProxy
        );

        dinariFactory.initialize(cfg.indexFactoryStorageProxy, proxies.storageProxy, cfg.functionsOracleProxy);

        console.log("DinariOrderManager proxy deployed at:", proxies.orderManagerProxy);
        console.log("DinariOrderManager ProxyAdmin:", Upgrades.getAdminAddress(proxies.orderManagerProxy));

        console.log("DinariFactoryProcessor proxy deployed at:", proxies.factoryProcessorProxy);
        console.log("DinariFactoryProcessor ProxyAdmin:", Upgrades.getAdminAddress(proxies.factoryProcessorProxy));

        console.log("DinariStorage proxy deployed at:", proxies.storageProxy);
        console.log("DinariStorage ProxyAdmin:", Upgrades.getAdminAddress(proxies.storageProxy));

        console.log("DinariBalancer proxy deployed at:", proxies.balancerProxy);
        console.log("DinariBalancer ProxyAdmin:", Upgrades.getAdminAddress(proxies.balancerProxy));

        console.log("DinariFactory proxy deployed at:", proxies.factoryProxy);
        console.log("DinariFactory ProxyAdmin:", Upgrades.getAdminAddress(proxies.factoryProxy));

        vm.stopBroadcast();
    }

    function _loadConfig(string memory targetChain) internal view returns (DinariConfig memory cfg) {
        if (keccak256(bytes(targetChain)) == keccak256("sepolia")) {
            cfg.issuer = vm.envAddress("SEPOLIA_DINARI_ISSUER_ADDRESS");
            cfg.indexFactoryStorageProxy = vm.envAddress("SEPOLIA_INDEX_FACTORY_STORAGE_PROXY_ADDRESS");
            cfg.indexFactoryBalancerProxy = vm.envAddress("SEPOLIA_INDEX_FACTORY_BALANCER_PROXY_ADDRESS");
            cfg.functionsOracleProxy = vm.envAddress("SEPOLIA_FUNCTIONS_ORACLE_PROXY_ADDRESS");
            cfg.usdcToken = vm.envAddress("SEPOLIA_USDC_ADDRESS");
            cfg.usdcDecimals = uint8(vm.envUint("SEPOLIA_USDC_DECIMALS"));
            cfg.isMainnet = vm.envBool("SEPOLIA_IS_MAINNET");
            cfg.providerIndex = uint8(vm.envUint("SEPOLIA_DINARI_PROVIDER_INDEX"));
            cfg.coreOrderManagerProxy = vm.envAddress("SEPOLIA_ORDER_MANAGER_PROXY_ADDRESS");
        } else if (keccak256(bytes(targetChain)) == keccak256("arbitrum_mainnet")) {
            cfg.issuer = vm.envAddress("ARBITRUM_DINARI_ISSUER_ADDRESS");
            cfg.indexFactoryStorageProxy = vm.envAddress("ARBITRUM_INDEX_FACTORY_STORAGE_PROXY_ADDRESS");
            cfg.indexFactoryBalancerProxy = vm.envAddress("ARBITRUM_INDEX_FACTORY_BALANCER_PROXY_ADDRESS");
            cfg.functionsOracleProxy = vm.envAddress("ARBITRUM_FUNCTIONS_ORACLE_PROXY_ADDRESS");
            cfg.usdcToken = vm.envAddress("ARBITRUM_USDC_ADDRESS");
            cfg.usdcDecimals = uint8(vm.envUint("ARBITRUM_USDC_DECIMALS"));
            cfg.isMainnet = vm.envBool("ARBITRUM_IS_MAINNET");
            cfg.providerIndex = uint8(vm.envUint("ARBITRUM_DINARI_PROVIDER_INDEX"));
            cfg.coreOrderManagerProxy = vm.envAddress("ARBITRUM_ORDER_MANAGER_PROXY_ADDRESS");
        } else {
            revert("Unsupported target chain");
        }

        return cfg;
    }

    function _deployProxies(address owner, DinariConfig memory cfg) internal returns (DeployedProxies memory proxies) {
        bytes memory noInitData = "";

        proxies.storageProxy = Upgrades.deployTransparentProxy("DinariStorage.sol", owner, noInitData);
        proxies.balancerProxy = Upgrades.deployTransparentProxy("DinariBalancer.sol", owner, noInitData);
        proxies.factoryProxy = Upgrades.deployTransparentProxy("DinariFactory.sol", owner, noInitData);
        proxies.orderManagerProxy = Upgrades.deployTransparentProxy(
            "DinariOrderManager.sol",
            owner,
            abi.encodeCall(DinariOrderManager.initialize, (cfg.usdcToken, cfg.usdcDecimals, cfg.issuer))
        );
        proxies.factoryProcessorProxy = Upgrades.deployTransparentProxy(
            "DinariFactoryProcessor.sol",
            owner,
            abi.encodeCall(
                DinariFactoryProcessor.initialize,
                (
                    cfg.indexFactoryStorageProxy,
                    proxies.storageProxy,
                    cfg.functionsOracleProxy,
                    cfg.coreOrderManagerProxy
                )
            )
        );

        return proxies;
    }
}

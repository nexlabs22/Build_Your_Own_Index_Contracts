// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import "openzeppelin-foundry-upgrades/Upgrades.sol";

import "../../../src/dinari/DinariStorage.sol";
import "../../../src/dinari/DinariBalancer.sol";
import "../../../src/dinari/DinariFactory.sol";

contract DeployDinariAll is Script {
    DinariStorage public dinariStorage;
    DinariBalancer public dinariBalancer;
    DinariFactory public dinariFactory;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.addr(deployerPrivateKey);
        string memory targetChain = "sepolia";

        address issuer;
        address indexFactoryStorageProxy;
        address indexFactoryBalancerProxy;
        address functionsOracleProxy;
        address usdcToken;
        uint8 usdcDecimals;
        bool isMainnet;
        uint8 providerIndex;

        if (keccak256(bytes(targetChain)) == keccak256("sepolia")) {
            issuer = vm.envAddress("SEPOLIA_DINARI_ISSUER_ADDRESS");
            indexFactoryStorageProxy = vm.envAddress("SEPOLIA_INDEX_FACTORY_STORAGE_PROXY_ADDRESS");
            indexFactoryBalancerProxy = vm.envAddress("SEPOLIA_INDEX_FACTORY_BALANCER_PROXY_ADDRESS");
            functionsOracleProxy = vm.envAddress("SEPOLIA_FUNCTIONS_ORACLE_PROXY_ADDRESS");
            usdcToken = vm.envAddress("SEPOLIA_USDC_ADDRESS");
            usdcDecimals = uint8(vm.envUint("SEPOLIA_USDC_DECIMALS"));
            isMainnet = vm.envBool("SEPOLIA_IS_MAINNET");
            providerIndex = uint8(vm.envUint("SEPOLIA_DINARI_PROVIDER_INDEX"));
        } else if (keccak256(bytes(targetChain)) == keccak256("arbitrum_mainnet")) {
            issuer = vm.envAddress("ARBITRUM_DINARI_ISSUER_ADDRESS");
            indexFactoryStorageProxy = vm.envAddress("ARBITRUM_INDEX_FACTORY_STORAGE_PROXY_ADDRESS");
            indexFactoryBalancerProxy = vm.envAddress("ARBITRUM_INDEX_FACTORY_BALANCER_PROXY_ADDRESS");
            functionsOracleProxy = vm.envAddress("ARBITRUM_FUNCTIONS_ORACLE_PROXY_ADDRESS");
            usdcToken = vm.envAddress("ARBITRUM_USDC_ADDRESS");
            usdcDecimals = uint8(vm.envUint("ARBITRUM_USDC_DECIMALS"));
            isMainnet = vm.envBool("ARBITRUM_IS_MAINNET");
            providerIndex = uint8(vm.envUint("ARBITRUM_DINARI_PROVIDER_INDEX"));
        } else {
            revert("Unsupported target chain");
        }

        vm.startBroadcast(deployerPrivateKey);

        bytes memory noInitData = "";

        address dinariStorageProxy = Upgrades.deployTransparentProxy("DinariStorage.sol", owner, noInitData);
        address dinariBalancerProxy = Upgrades.deployTransparentProxy("DinariBalancer.sol", owner, noInitData);
        address dinariFactoryProxy = Upgrades.deployTransparentProxy("DinariFactory.sol", owner, noInitData);

        dinariStorage = DinariStorage(dinariStorageProxy);
        dinariBalancer = DinariBalancer(dinariBalancerProxy);
        dinariFactory = DinariFactory(dinariFactoryProxy);

        dinariStorage.initialize(
            issuer,
            indexFactoryStorageProxy,
            dinariBalancerProxy,
            usdcToken,
            usdcDecimals,
            functionsOracleProxy,
            isMainnet,
            providerIndex
        );

        dinariBalancer.initialize(
            dinariStorageProxy, functionsOracleProxy, indexFactoryStorageProxy, indexFactoryBalancerProxy
        );

        dinariFactory.initialize(indexFactoryStorageProxy, dinariStorageProxy, functionsOracleProxy);

        console.log("DinariStorage proxy deployed at:", dinariStorageProxy);
        console.log("DinariStorage ProxyAdmin:", Upgrades.getAdminAddress(dinariStorageProxy));

        console.log("DinariBalancer proxy deployed at:", dinariBalancerProxy);
        console.log("DinariBalancer ProxyAdmin:", Upgrades.getAdminAddress(dinariBalancerProxy));

        console.log("DinariFactory proxy deployed at:", dinariFactoryProxy);
        console.log("DinariFactory ProxyAdmin:", Upgrades.getAdminAddress(dinariFactoryProxy));

        vm.stopBroadcast();
    }
}

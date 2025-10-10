// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/Test.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "openzeppelin-foundry-upgrades/Upgrades.sol";

import "../src/dinari/DinariStorage.sol";

contract DeployDinariStorage is Script {
    DinariStorage public dinariStorage;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        string memory targetChain = "sepolia";
        address owner = vm.addr(deployerPrivateKey);

        address issuer;
        address indexFactoryStorageProxy;
        address dinariBalancerProxy;
        address usdcToken;
        uint8 usdcDecimals;
        address functionsOracleProxy;
        bool isMainnet;
        uint8 providerIndex;

        if (keccak256(bytes(targetChain)) == keccak256("sepolia")) {
            issuer = vm.envAddress("SEPOLIA_DINARI_ISSUER_ADDRESS");
            indexFactoryStorageProxy = vm.envAddress("SEPOLIA_INDEX_FACTORY_STORAGE_PROXY_ADDRESS");
            dinariBalancerProxy = vm.envAddress("SEPOLIA_DINARI_BALANCER_PROXY_ADDRESS");
            usdcToken = vm.envAddress("SEPOLIA_USDC_ADDRESS");
            usdcDecimals = uint8(vm.envUint("SEPOLIA_USDC_DECIMALS"));
            functionsOracleProxy = vm.envAddress("SEPOLIA_FUNCTIONS_ORACLE_PROXY_ADDRESS");
            isMainnet = vm.envBool("SEPOLIA_IS_MAINNET");
            providerIndex = uint8(vm.envUint("SEPOLIA_DINARI_PROVIDER_INDEX"));
        } else if (keccak256(bytes(targetChain)) == keccak256("arbitrum_mainnet")) {
            issuer = vm.envAddress("ARBITRUM_DINARI_ISSUER_ADDRESS");
            indexFactoryStorageProxy = vm.envAddress("ARBITRUM_INDEX_FACTORY_STORAGE_PROXY_ADDRESS");
            dinariBalancerProxy = vm.envAddress("ARBITRUM_DINARI_BALANCER_PROXY_ADDRESS");
            usdcToken = vm.envAddress("ARBITRUM_USDC_ADDRESS");
            usdcDecimals = uint8(vm.envUint("ARBITRUM_USDC_DECIMALS"));
            functionsOracleProxy = vm.envAddress("ARBITRUM_FUNCTIONS_ORACLE_PROXY_ADDRESS");
            isMainnet = vm.envBool("ARBITRUM_IS_MAINNET");
            providerIndex = uint8(vm.envUint("ARBITRUM_DINARI_PROVIDER_INDEX"));
        } else {
            revert("Unsupported target chain");
        }

        vm.startBroadcast(deployerPrivateKey);

        address proxy = Upgrades.deployTransparentProxy(
            "DinariStorage.sol",
            owner,
            abi.encodeCall(
                DinariStorage.initialize,
                (
                    issuer,
                    indexFactoryStorageProxy,
                    dinariBalancerProxy,
                    usdcToken,
                    usdcDecimals,
                    functionsOracleProxy,
                    isMainnet,
                    providerIndex
                )
            )
        );

        dinariStorage = DinariStorage(proxy);
        address adminAddr = Upgrades.getAdminAddress(proxy);

        console.log("DinariStorage implementation deployed at:", address(dinariStorage));
        console.log("DinariStorage proxy deployed at:", proxy);
        console.log("ProxyAdmin for DinariStorage deployed at:", adminAddr);

        vm.stopBroadcast();
    }
}

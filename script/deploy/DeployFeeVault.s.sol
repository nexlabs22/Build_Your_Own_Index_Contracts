// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/Test.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "openzeppelin-foundry-upgrades/Upgrades.sol";

import "../../src/ccip/FeeVault.sol";

contract DeployFeeVault is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // string memory targetChain = "sepolia";
        string memory targetChain = "arbitrum_mainnet";

        // address mainchainFactory;
        // address mainchainBalancer;
        // address dinariFactory;
        // address dinariBalancer;

        address owner = vm.addr(deployerPrivateKey);

        // if (keccak256(bytes(targetChain)) == keccak256("sepolia")) {
        //     mainchainFactory = vm.envAddress("SEPOLIA_MAIN_CHAIN_FACTORY_PROXY_ADDRESS");
        //     mainchainBalancer = vm.envAddress("SEPOLIA_MAIN_CHAIN_BALANCER_PROXY_ADDRESS");
        //     dinariFactory = vm.envAddress("SEPOLIA_DINARI_FACTORY_PROXY_ADDRESS");
        //     dinariBalancer = vm.envAddress("SEPOLIA_DINARI_BALANCER_PROXY_ADDRESS");
        // } else if (keccak256(bytes(targetChain)) == keccak256("arbitrum_mainnet")) {
        //     mainchainFactory = vm.envAddress("ARBITRUM_MAIN_CHAIN_FACTORY_PROXY_ADDRESS");
        //     mainchainBalancer = vm.envAddress("ARBITRUM_MAIN_CHAIN_BALANCER_PROXY_ADDRESS");
        //     dinariFactory = vm.envAddress("ARBITRUM_DINARI_FACTORY_PROXY_ADDRESS");
        //     dinariBalancer = vm.envAddress("ARBITRUM_DINARI_BALANCER_PROXY_ADDRESS");
        // } else {
        //     revert("Unsupported target chain");
        // }

        vm.startBroadcast(deployerPrivateKey);

        address proxy = Upgrades.deployTransparentProxy(
            "FeeVault.sol", owner, abi.encodeCall(FeeVault.initialize, (address(0), address(0), address(0), address(0)))
        );

        FeeVault nexVaultImplementation = FeeVault(payable(proxy));

        address proxyAdmin = Upgrades.getAdminAddress(proxy);

        console.log("FeeVault implementation deployed at:", address(nexVaultImplementation));
        console.log("FeeVault proxy deployed at:", address(proxy));
        console.log("ProxyAdmin for FeeVault deployed at:", address(proxyAdmin));

        // FeeVault(proxy).setOperator(mainchainFactory, true);
        // FeeVault(proxy).setOperator(mainchainBalancer, true);
        // FeeVault(proxy).setOperator(dinariFactory, true);
        // FeeVault(proxy).setOperator(dinariBalancer, true);

        console.log("Set operators successfuly!");

        vm.stopBroadcast();
    }
}

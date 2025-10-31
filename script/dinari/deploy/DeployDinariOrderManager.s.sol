// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import "openzeppelin-foundry-upgrades/Upgrades.sol";

import {DinariOrderManager} from "../../../src/dinari/DinariOrderManager.sol";

contract DeployDinariOrderManager is Script {
    DinariOrderManager public dinariOrderManager;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.addr(deployerPrivateKey);
        string memory targetChain = "sepolia";

        address usdcToken;
        uint8 usdcDecimals;
        address issuer;
        address dinariFactoryProcessor;
        address dinariFactory;

        if (keccak256(bytes(targetChain)) == keccak256("sepolia")) {
            usdcToken = vm.envAddress("SEPOLIA_USDC_ADDRESS");
            usdcDecimals = uint8(vm.envUint("SEPOLIA_USDC_DECIMALS"));
            issuer = vm.envAddress("SEPOLIA_DINARI_ISSUER_ADDRESS");
            dinariFactoryProcessor = vm.envAddress("SEPOLIA_DINARI_FACTORY_PROCESSOR_PROXY_ADDRESS");
            dinariFactory = vm.envAddress("SEPOLIA_DINARI_FACTORY_PROXY_ADDRESS");
        } else if (keccak256(bytes(targetChain)) == keccak256("arbitrum_mainnet")) {
            usdcToken = vm.envAddress("ARBITRUM_USDC_ADDRESS");
            usdcDecimals = uint8(vm.envUint("ARBITRUM_USDC_DECIMALS"));
            issuer = vm.envAddress("ARBITRUM_DINARI_ISSUER_ADDRESS");
            dinariFactoryProcessor = vm.envAddress("ARBITRUM_DINARI_FACTORY_PROCESSOR_PROXY_ADDRESS");
            dinariFactory = vm.envAddress("ARBITRUM_DINARI_FACTORY_PROXY_ADDRESS");
        } else {
            revert("Unsupported target chain");
        }

        vm.startBroadcast(deployerPrivateKey);

        address proxy = Upgrades.deployTransparentProxy(
            "DinariOrderManager.sol",
            owner,
            abi.encodeCall(DinariOrderManager.initialize, (usdcToken, usdcDecimals, issuer))
        );

        dinariOrderManager = DinariOrderManager(proxy);
        address adminAddr = Upgrades.getAdminAddress(proxy);

        DinariOrderManager(proxy).setOperator(dinariFactoryProcessor, true);
        DinariOrderManager(proxy).setOperator(dinariFactory, true);

        console.log("DinariOrderManager implementation deployed at:", address(dinariOrderManager));
        console.log("DinariOrderManager proxy deployed at:", proxy);
        console.log("ProxyAdmin for DinariOrderManager deployed at:", adminAddr);

        vm.stopBroadcast();
    }
}

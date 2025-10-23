// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import "openzeppelin-foundry-upgrades/Upgrades.sol";

contract UpgradeIndexFactoryBalancer is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        string memory targetChain = vm.envOr("TARGET_CHAIN", string("sepolia"));

        address proxyAddress;
        address owner = vm.addr(deployerPrivateKey);

        if (keccak256(bytes(targetChain)) == keccak256("sepolia")) {
            proxyAddress = vm.envAddress("SEPOLIA_INDEX_FACTORY_BALANCER_PROXY_ADDRESS");
        } else if (keccak256(bytes(targetChain)) == keccak256("arbitrum_mainnet")) {
            proxyAddress = vm.envAddress("ARBITRUM_INDEX_FACTORY_BALANCER_PROXY_ADDRESS");
        } else {
            revert("Unsupported target chain");
        }

        Upgrades.upgradeProxy(proxyAddress, "IndexFactoryBalancer.sol", "", owner);

        address implAddr = Upgrades.getImplementationAddress(proxyAddress);
        console.log("IndexFactoryBalancer proxy upgraded to new implementation at:", implAddr);

        vm.stopBroadcast();
    }
}


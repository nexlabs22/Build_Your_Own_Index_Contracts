// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "openzeppelin-foundry-upgrades/Upgrades.sol";

contract UpgradeCrossChainIndexFactory is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // string memory targetChain = "arbitrum_sepolia";
        string memory targetChain = "base";
        address proxyAddress;
        address owner = vm.addr(deployerPrivateKey);

        if (keccak256(bytes(targetChain)) == keccak256("arbitrum_sepolia")) {
            proxyAddress = vm.envAddress("ARBITRUM_SEPOLIA_CROSS_CHAIN_FACTORY_PROXY_ADDRESS");
        } else if (keccak256(bytes(targetChain)) == keccak256("base")) {
            proxyAddress = vm.envAddress("BASE_CROSS_CHAIN_INDEX_FACTORY_PROXY_ADDRESS");
        } else {
            revert("Unsupported target chain");
        }

        Upgrades.upgradeProxy(proxyAddress, "CrossChainIndexFactoryV7.sol", "", owner);

        address newImpl = Upgrades.getImplementationAddress(proxyAddress);
        console.log("CrossChainIndexFactory proxy upgraded to new implementation at:", newImpl);

        vm.stopBroadcast();
    }
}


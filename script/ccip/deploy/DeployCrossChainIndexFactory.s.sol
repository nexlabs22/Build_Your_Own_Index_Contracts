// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "openzeppelin-foundry-upgrades/Upgrades.sol";

import "../../../src/ccip/CrossChainIndexFactory.sol";

contract DeployCrossChainIndexFactory is Script {
    CrossChainIndexFactory public crossChainIndexFactory;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        // string memory targetChain = vm.envOr("TARGET_CHAIN", string("arbitrum_sepolia"));
        string memory targetChain = vm.envOr("TARGET_CHAIN", string("optimism_mainnet"));
        address owner = vm.addr(deployerPrivateKey);

        address storageProxy;
        address ccipRouter;
        address linkToken;

        if (keccak256(bytes(targetChain)) == keccak256("arbitrum_sepolia")) {
            storageProxy = vm.envAddress("ARBITRUM_SEPOLIA_CROSS_CHAIN_INDEX_FACTORY_STORAGE_PROXY_ADDRESS");
            ccipRouter = vm.envAddress("ARBITRUM_SEPOLIA_CCIP_ROUTER_ADDRESS");
            linkToken = vm.envAddress("ARBITRUM_SEPOLIA_CHAINLINK_TOKEN_ADDRESS");
        } else if (keccak256(bytes(targetChain)) == keccak256("sepolia")) {
            storageProxy = vm.envAddress("SEPOLIA_CROSS_CHAIN_INDEX_FACTORY_STORAGE_PROXY_ADDRESS");
            ccipRouter = vm.envAddress("SEPOLIA_CCIP_ROUTER_ADDRESS");
            linkToken = vm.envAddress("SEPOLIA_LINK_TOKEN_ADDRESS");
        } else if (keccak256(bytes(targetChain)) == keccak256("arbitrum_mainnet")) {
            storageProxy = vm.envAddress("ARBITRUM_CROSS_CHAIN_INDEX_FACTORY_STORAGE_PROXY_ADDRESS");
            ccipRouter = vm.envAddress("ARBITRUM_CCIP_ROUTER_ADDRESS");
            linkToken = vm.envAddress("ARBITRUM_LINK_TOKEN_ADDRESS");
        } else if (keccak256(bytes(targetChain)) == keccak256("optimism_mainnet")) {
            storageProxy = vm.envAddress("OPTIMISM_CROSS_CHAIN_INDEX_FACTORY_STORAGE_PROXY_ADDRESS");
            ccipRouter = vm.envAddress("OPTIMISM_CCIP_ROUTER_ADDRESS");
            linkToken = vm.envAddress("OPTIMISM_LINK_TOKEN_ADDRESS");
        } else {
            revert("Unsupported target chain");
        }

        vm.startBroadcast(deployerPrivateKey);

        address proxy = Upgrades.deployTransparentProxy(
            "CrossChainIndexFactory.sol",
            owner,
            abi.encodeCall(CrossChainIndexFactory.initialize, (storageProxy, ccipRouter, linkToken))
        );

        crossChainIndexFactory = CrossChainIndexFactory(payable(proxy));
        address adminAddr = Upgrades.getAdminAddress(proxy);

        console.log("CrossChainIndexFactory implementation deployed at:", address(crossChainIndexFactory));
        console.log("CrossChainIndexFactory proxy deployed at:", proxy);
        console.log("ProxyAdmin for CrossChainIndexFactory deployed at:", adminAddr);

        vm.stopBroadcast();
    }
}

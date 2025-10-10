// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/Test.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "openzeppelin-foundry-upgrades/Upgrades.sol";

import "../src/backedfi/BackedFiBalancer.sol";

contract DeployBackedFiBalancer is Script {
    BackedFiBalancer public backedFiBalancer;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        string memory targetChain = "sepolia";
        address owner = vm.addr(deployerPrivateKey);

        address backedFiStorageProxy;
        address functionsOracleProxy;
        address indexFactoryStorageProxy;

        if (keccak256(bytes(targetChain)) == keccak256("sepolia")) {
            backedFiStorageProxy = vm.envAddress("SEPOLIA_BACKEDFI_STORAGE_PROXY_ADDRESS");
            functionsOracleProxy = vm.envAddress("SEPOLIA_FUNCTIONS_ORACLE_PROXY_ADDRESS");
            indexFactoryStorageProxy = vm.envAddress("SEPOLIA_INDEX_FACTORY_STORAGE_PROXY_ADDRESS");
        } else if (keccak256(bytes(targetChain)) == keccak256("arbitrum_mainnet")) {
            backedFiStorageProxy = vm.envAddress("ARBITRUM_BACKEDFI_STORAGE_PROXY_ADDRESS");
            functionsOracleProxy = vm.envAddress("ARBITRUM_FUNCTIONS_ORACLE_PROXY_ADDRESS");
            indexFactoryStorageProxy = vm.envAddress("ARBITRUM_INDEX_FACTORY_STORAGE_PROXY_ADDRESS");
        } else {
            revert("Unsupported target chain");
        }

        vm.startBroadcast(deployerPrivateKey);

        address proxy = Upgrades.deployTransparentProxy(
            "BackedFiBalancer.sol",
            owner,
            abi.encodeCall(
                BackedFiBalancer.initialize,
                (backedFiStorageProxy, functionsOracleProxy, indexFactoryStorageProxy)
            )
        );

        backedFiBalancer = BackedFiBalancer(proxy);
        address adminAddr = Upgrades.getAdminAddress(proxy);

        console.log("BackedFiBalancer implementation deployed at:", address(backedFiBalancer));
        console.log("BackedFiBalancer proxy deployed at:", proxy);
        console.log("ProxyAdmin for BackedFiBalancer deployed at:", adminAddr);

        vm.stopBroadcast();
    }
}

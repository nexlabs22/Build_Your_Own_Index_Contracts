// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/Test.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "openzeppelin-foundry-upgrades/Upgrades.sol";

import "../src/backedfi/BackedFiFactory.sol";

contract DeployBackedFiFactory is Script {
    BackedFiFactory public backedFiFactory;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        string memory targetChain = "sepolia";
        address owner = vm.addr(deployerPrivateKey);

        address backedFiStorageProxy;

        if (keccak256(bytes(targetChain)) == keccak256("sepolia")) {
            backedFiStorageProxy = vm.envAddress("SEPOLIA_BACKEDFI_STORAGE_PROXY_ADDRESS");
        } else if (keccak256(bytes(targetChain)) == keccak256("arbitrum_mainnet")) {
            backedFiStorageProxy = vm.envAddress("ARBITRUM_BACKEDFI_STORAGE_PROXY_ADDRESS");
        } else {
            revert("Unsupported target chain");
        }

        vm.startBroadcast(deployerPrivateKey);

        address proxy = Upgrades.deployTransparentProxy(
            "BackedFiFactory.sol",
            owner,
            abi.encodeCall(BackedFiFactory.initialize, (backedFiStorageProxy))
        );

        backedFiFactory = BackedFiFactory(proxy);
        address adminAddr = Upgrades.getAdminAddress(proxy);

        console.log("BackedFiFactory implementation deployed at:", address(backedFiFactory));
        console.log("BackedFiFactory proxy deployed at:", proxy);
        console.log("ProxyAdmin for BackedFiFactory deployed at:", adminAddr);

        vm.stopBroadcast();
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/Test.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "openzeppelin-foundry-upgrades/Upgrades.sol";

import "../../../src/backedfi/StagingCustodyAccount.sol";

contract DeployStagingCustodyAccount is Script {
    StagingCustodyAccount public stagingCustodyAccount;

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
            "StagingCustodyAccount.sol", owner, abi.encodeCall(StagingCustodyAccount.initialize, (backedFiStorageProxy))
        );

        stagingCustodyAccount = StagingCustodyAccount(proxy);
        address adminAddr = Upgrades.getAdminAddress(proxy);

        console.log("StagingCustodyAccount implementation deployed at:", address(stagingCustodyAccount));
        console.log("StagingCustodyAccount proxy deployed at:", proxy);
        console.log("ProxyAdmin for StagingCustodyAccount deployed at:", adminAddr);

        vm.stopBroadcast();
    }
}

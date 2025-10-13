// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/Test.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "openzeppelin-foundry-upgrades/Upgrades.sol";

import "../../../src/backedfi/BackedFiStorage.sol";

contract DeployBackedFiStorage is Script {
    BackedFiStorage public backedFiStorage;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        string memory targetChain = "sepolia";
        address owner = vm.addr(deployerPrivateKey);

        address indexFactoryProxy;
        address functionsOracleProxy;
        address stagingCustodyAccountProxy;
        address nexBot;
        address usdcToken;
        uint8 providerIndex;

        if (keccak256(bytes(targetChain)) == keccak256("sepolia")) {
            indexFactoryProxy = vm.envAddress("SEPOLIA_INDEX_FACTORY_PROXY_ADDRESS");
            functionsOracleProxy = vm.envAddress("SEPOLIA_FUNCTIONS_ORACLE_PROXY_ADDRESS");
            stagingCustodyAccountProxy = vm.envAddress("SEPOLIA_STAGING_CUSTODY_ACCOUNT_PROXY_ADDRESS");
            nexBot = vm.envAddress("SEPOLIA_NEX_BOT_ADDRESS");
            usdcToken = vm.envAddress("SEPOLIA_USDC_ADDRESS");
            providerIndex = uint8(vm.envUint("SEPOLIA_BACKEDFI_PROVIDER_INDEX"));
        } else if (keccak256(bytes(targetChain)) == keccak256("arbitrum_mainnet")) {
            indexFactoryProxy = vm.envAddress("ARBITRUM_INDEX_FACTORY_PROXY_ADDRESS");
            functionsOracleProxy = vm.envAddress("ARBITRUM_FUNCTIONS_ORACLE_PROXY_ADDRESS");
            stagingCustodyAccountProxy = vm.envAddress("ARBITRUM_STAGING_CUSTODY_ACCOUNT_PROXY_ADDRESS");
            nexBot = vm.envAddress("ARBITRUM_NEX_BOT_ADDRESS");
            usdcToken = vm.envAddress("ARBITRUM_USDC_ADDRESS");
            providerIndex = uint8(vm.envUint("ARBITRUM_BACKEDFI_PROVIDER_INDEX"));
        } else {
            revert("Unsupported target chain");
        }

        vm.startBroadcast(deployerPrivateKey);

        address proxy = Upgrades.deployTransparentProxy(
            "BackedFiStorage.sol",
            owner,
            abi.encodeCall(
                BackedFiStorage.initialize,
                (indexFactoryProxy, functionsOracleProxy, stagingCustodyAccountProxy, nexBot, usdcToken, providerIndex)
            )
        );

        backedFiStorage = BackedFiStorage(proxy);
        address adminAddr = Upgrades.getAdminAddress(proxy);

        console.log("BackedFiStorage implementation deployed at:", address(backedFiStorage));
        console.log("BackedFiStorage proxy deployed at:", proxy);
        console.log("ProxyAdmin for BackedFiStorage deployed at:", adminAddr);

        vm.stopBroadcast();
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "openzeppelin-foundry-upgrades/Upgrades.sol";

import "../../../src/ccip/MainChainFactory.sol";

contract DeployMainChainFactory is Script {
    MainChainFactory public mainChainFactory;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        string memory targetChain = "sepolia";
        address owner = vm.addr(deployerPrivateKey);

        uint64 chainSelector;
        address indexToken;
        address orderManager;
        address mainChainStorage;
        address functionsOracle;
        address coreSender;
        address weth;

        if (keccak256(bytes(targetChain)) == keccak256("sepolia")) {
            chainSelector = uint64(vm.envUint("SEPOLIA_CCIP_CHAIN_SELECTOR"));
            indexToken = vm.envAddress("SEPOLIA_INDEX_TOKEN_PROXY_ADDRESS");
            orderManager = vm.envAddress("SEPOLIA_ORDER_MANAGER_PROXY_ADDRESS");
            mainChainStorage = vm.envAddress("SEPOLIA_MAIN_CHAIN_STORAGE_PROXY_ADDRESS");
            functionsOracle = vm.envAddress("SEPOLIA_FUNCTIONS_ORACLE_PROXY_ADDRESS");
            coreSender = vm.envAddress("SEPOLIA_CORE_SENDER_PROXY_ADDRESS");
            weth = vm.envAddress("SEPOLIA_WETH_ADDRESS");
        } else if (keccak256(bytes(targetChain)) == keccak256("arbitrum_mainnet")) {
            chainSelector = uint64(vm.envUint("ARBITRUM_CCIP_CHAIN_SELECTOR"));
            indexToken = vm.envAddress("ARBITRUM_INDEX_TOKEN_PROXY_ADDRESS");
            orderManager = vm.envAddress("ARBITRUM_ORDER_MANAGER_PROXY_ADDRESS");
            mainChainStorage = vm.envAddress("ARBITRUM_MAIN_CHAIN_STORAGE_PROXY_ADDRESS");
            functionsOracle = vm.envAddress("ARBITRUM_FUNCTIONS_ORACLE_PROXY_ADDRESS");
            coreSender = vm.envAddress("ARBITRUM_CORE_SENDER_PROXY_ADDRESS");
            weth = vm.envAddress("ARBITRUM_WETH_ADDRESS");
        } else {
            revert("Unsupported target chain");
        }

        vm.startBroadcast(deployerPrivateKey);

        address proxy = Upgrades.deployTransparentProxy(
            "MainChainFactory.sol",
            owner,
            abi.encodeCall(
                MainChainFactory.initialize,
                (
                    chainSelector,
                    payable(indexToken),
                    orderManager,
                    mainChainStorage,
                    functionsOracle,
                    payable(coreSender),
                    weth
                )
            )
        );

        mainChainFactory = MainChainFactory(payable(proxy));
        address adminAddr = Upgrades.getAdminAddress(proxy);

        console.log("MainChainFactory implementation deployed at:", address(mainChainFactory));
        console.log("MainChainFactory proxy deployed at:", proxy);
        console.log("ProxyAdmin for MainChainFactory deployed at:", adminAddr);

        vm.stopBroadcast();
    }
}

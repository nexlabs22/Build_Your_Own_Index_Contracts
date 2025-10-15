// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "openzeppelin-foundry-upgrades/Upgrades.sol";

import "../../../src/ccip/MainChainStorage.sol";

contract DeployMainChainStorage is Script {
    MainChainStorage public mainChainStorage;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        string memory targetChain = "sepolia";
        address owner = vm.addr(deployerPrivateKey);

        uint64 chainSelector;
        address functionsOracle;
        address priceFeed;
        address linkToken;
        address weth;
        address swapRouterV3;
        address factoryV3;
        address swapRouterV2;
        address factoryV2;

        if (keccak256(bytes(targetChain)) == keccak256("sepolia")) {
            chainSelector = uint64(vm.envUint("SEPOLIA_CCIP_CHAIN_SELECTOR"));
            functionsOracle = vm.envAddress("SEPOLIA_FUNCTIONS_ORACLE_PROXY_ADDRESS");
            priceFeed = vm.envAddress("SEPOLIA_TO_USD_PRICE_FEED_ADDRESS");
            linkToken = vm.envAddress("SEPOLIA_LINK_TOKEN_ADDRESS");
            weth = vm.envAddress("SEPOLIA_WETH_ADDRESS");
            swapRouterV3 = vm.envAddress("SEPOLIA_SWAP_ROUTER_V3_ADDRESS");
            factoryV3 = vm.envAddress("SEPOLIA_UNISWAP_FACTORY_V3_ADDRESS");
            swapRouterV2 = vm.envAddress("SEPOLIA_SWAP_ROUTER_V2_ADDRESS");
            factoryV2 = vm.envAddress("SEPOLIA_UNISWAP_FACTORY_V2_ADDRESS");
        } else if (keccak256(bytes(targetChain)) == keccak256("arbitrum_mainnet")) {
            chainSelector = uint64(vm.envUint("ARBITRUM_CCIP_CHAIN_SELECTOR"));
            functionsOracle = vm.envAddress("ARBITRUM_FUNCTIONS_ORACLE_PROXY_ADDRESS");
            priceFeed = vm.envAddress("ARBITRUM_TO_USD_PRICE_FEED_ADDRESS");
            linkToken = vm.envAddress("ARBITRUM_LINK_TOKEN_ADDRESS");
            weth = vm.envAddress("ARBITRUM_WETH_ADDRESS");
            swapRouterV3 = vm.envAddress("ARBITRUM_SWAP_ROUTER_V3_ADDRESS");
            factoryV3 = vm.envAddress("ARBITRUM_UNISWAP_FACTORY_V3_ADDRESS");
            swapRouterV2 = vm.envAddress("ARBITRUM_SWAP_ROUTER_V2_ADDRESS");
            factoryV2 = vm.envAddress("ARBITRUM_UNISWAP_FACTORY_V2_ADDRESS");
        } else {
            revert("Unsupported target chain");
        }

        vm.startBroadcast(deployerPrivateKey);

        address proxy = Upgrades.deployTransparentProxy(
            "MainChainStorage.sol",
            owner,
            abi.encodeCall(
                MainChainStorage.initialize,
                (
                    chainSelector,
                    functionsOracle,
                    priceFeed,
                    linkToken,
                    weth,
                    swapRouterV3,
                    factoryV3,
                    swapRouterV2,
                    factoryV2
                )
            )
        );

        mainChainStorage = MainChainStorage(proxy);
        address adminAddr = Upgrades.getAdminAddress(proxy);

        console.log("MainChainStorage implementation deployed at:", address(mainChainStorage));
        console.log("MainChainStorage proxy deployed at:", proxy);
        console.log("ProxyAdmin for MainChainStorage deployed at:", adminAddr);

        vm.stopBroadcast();
    }
}


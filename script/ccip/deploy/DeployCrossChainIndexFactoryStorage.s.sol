// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "openzeppelin-foundry-upgrades/Upgrades.sol";

import "../../../src/ccip/CrossChainIndexFactoryStorage.sol";

contract DeployCrossChainIndexFactoryStorage is Script {
    CrossChainIndexFactoryStorage public factoryStorage;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        string memory targetChain = "sepolia";
        address owner = vm.addr(deployerPrivateKey);

        uint64 chainSelector;
        address vaultAddress;
        address linkToken;
        address ccipRouter;
        address weth;
        address swapRouterV3;
        address factoryV3;
        address swapRouterV2;
        address priceFeed;

        if (keccak256(bytes(targetChain)) == keccak256("sepolia")) {
            chainSelector = uint64(vm.envUint("SEPOLIA_CCIP_CHAIN_SELECTOR"));
            vaultAddress = vm.envAddress("SEPOLIA_VAULT_PROXY_ADDRESS");
            linkToken = vm.envAddress("SEPOLIA_LINK_TOKEN_ADDRESS");
            ccipRouter = vm.envAddress("SEPOLIA_CCIP_ROUTER_ADDRESS");
            weth = vm.envAddress("SEPOLIA_WETH_ADDRESS");
            swapRouterV3 = vm.envAddress("SEPOLIA_SWAP_ROUTER_V3_ADDRESS");
            factoryV3 = vm.envAddress("SEPOLIA_UNISWAP_FACTORY_V3_ADDRESS");
            swapRouterV2 = vm.envAddress("SEPOLIA_SWAP_ROUTER_V2_ADDRESS");
            priceFeed = vm.envAddress("SEPOLIA_TO_USD_PRICE_FEED_ADDRESS");
        } else if (keccak256(bytes(targetChain)) == keccak256("arbitrum_mainnet")) {
            chainSelector = uint64(vm.envUint("ARBITRUM_CCIP_CHAIN_SELECTOR"));
            vaultAddress = vm.envAddress("ARBITRUM_VAULT_PROXY_ADDRESS");
            linkToken = vm.envAddress("ARBITRUM_LINK_TOKEN_ADDRESS");
            ccipRouter = vm.envAddress("ARBITRUM_CCIP_ROUTER_ADDRESS");
            weth = vm.envAddress("ARBITRUM_WETH_ADDRESS");
            swapRouterV3 = vm.envAddress("ARBITRUM_SWAP_ROUTER_V3_ADDRESS");
            factoryV3 = vm.envAddress("ARBITRUM_UNISWAP_FACTORY_V3_ADDRESS");
            swapRouterV2 = vm.envAddress("ARBITRUM_SWAP_ROUTER_V2_ADDRESS");
            priceFeed = vm.envAddress("ARBITRUM_TO_USD_PRICE_FEED_ADDRESS");
        } else {
            revert("Unsupported target chain");
        }

        vm.startBroadcast(deployerPrivateKey);

        address proxy = Upgrades.deployTransparentProxy(
            "CrossChainIndexFactoryStorage.sol",
            owner,
            abi.encodeCall(
                CrossChainIndexFactoryStorage.initialize,
                (
                    chainSelector,
                    payable(vaultAddress),
                    linkToken,
                    ccipRouter,
                    weth,
                    swapRouterV3,
                    factoryV3,
                    swapRouterV2,
                    priceFeed
                )
            )
        );

        factoryStorage = CrossChainIndexFactoryStorage(proxy);
        address adminAddr = Upgrades.getAdminAddress(proxy);

        console.log("CrossChainIndexFactoryStorage implementation deployed at:", address(factoryStorage));
        console.log("CrossChainIndexFactoryStorage proxy deployed at:", proxy);
        console.log("ProxyAdmin for CrossChainIndexFactoryStorage deployed at:", adminAddr);

        vm.stopBroadcast();
    }
}


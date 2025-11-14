// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import "openzeppelin-foundry-upgrades/Upgrades.sol";

import "../../../src/ccip/CrossChainIndexFactoryStorage.sol";
import "../../../src/ccip/CrossChainIndexFactory.sol";
import "../../../src/ccip/CrossChainIndexFactoryBalancer.sol";

contract DeployCCIPAll is Script {
    CrossChainIndexFactoryStorage public crossChainIndexFactoryStorage;
    CrossChainIndexFactory public crossChainIndexFactory;
    CrossChainIndexFactoryBalancer public crossChainIndexFactoryBalancer;

    struct ChainConfig {
        uint64 chainSelector;
        // address functionsOracle;
        address toUsdPriceFeed;
        address linkToken;
        address weth;
        address swapRouterV3;
        address factoryV3;
        address swapRouterV2;
        address factoryV2;
        // address vaultAddress;
        address ccipRouter;
        address indexToken;
        // address orderManager;
        address usdc;
    }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.addr(deployerPrivateKey);
        // string memory targetChain = "sepolia";
        // string memory targetChain = "base_mainnet";
        string memory targetChain = "ethereum_mainnet";
        // string memory targetChain = "bsc_mainnet";

        ChainConfig memory cfg = _loadConfig(targetChain);

        vm.startBroadcast(deployerPrivateKey);

        // if (cfg.vaultAddress != address(0)) {x
        //     mainChainStorage.setVault(cfg.vaultAddress);
        // }
        address ccStorageProxy = _deployCrossChainIndexFactoryStorage(owner, cfg);
        // address ccStorageProxy = 0x0Ea235d241ac4953DF78D81125f524B1F61dcF7B;
        // address ccFactoryProxy = _deployCrossChainIndexFactory(owner, cfg, ccStorageProxy);
        // address ccBalancerProxy = _deployCrossChainIndexFactoryBalancer(owner, cfg, ccStorageProxy);

        console.log("CrossChainIndexFactoryStorage proxy deployed at:", ccStorageProxy);
        console.log("CrossChainIndexFactoryStorage ProxyAdmin:", Upgrades.getAdminAddress(ccStorageProxy));

        // console.log("CrossChainIndexFactory proxy deployed at:", ccFactoryProxy);
        // console.log("CrossChainIndexFactory ProxyAdmin:", Upgrades.getAdminAddress(ccFactoryProxy));

        // console.log("CrossChainIndexFactoryBalancer proxy deployed at:", ccBalancerProxy);
        // console.log("CrossChainIndexFactoryBalancer ProxyAdmin:", Upgrades.getAdminAddress(ccBalancerProxy));

        vm.stopBroadcast();
    }

    function _loadConfig(string memory targetChain) internal view returns (ChainConfig memory cfg) {
        if (keccak256(bytes(targetChain)) == keccak256("sepolia")) {
            cfg.chainSelector = uint64(vm.envUint("SEPOLIA_CCIP_CHAIN_SELECTOR"));
            // cfg.functionsOracle = vm.envAddress("SEPOLIA_FUNCTIONS_ORACLE_PROXY_ADDRESS");
            cfg.toUsdPriceFeed = vm.envAddress("SEPOLIA_TO_USD_PRICE_FEED_ADDRESS");
            cfg.linkToken = vm.envAddress("SEPOLIA_LINK_TOKEN_ADDRESS");
            cfg.weth = vm.envAddress("SEPOLIA_WETH_ADDRESS");
            cfg.swapRouterV3 = vm.envAddress("SEPOLIA_SWAP_ROUTER_V3_ADDRESS");
            cfg.factoryV3 = vm.envAddress("SEPOLIA_UNISWAP_FACTORY_V3_ADDRESS");
            cfg.swapRouterV2 = vm.envAddress("SEPOLIA_SWAP_ROUTER_V2_ADDRESS");
            cfg.factoryV2 = vm.envAddress("SEPOLIA_UNISWAP_FACTORY_V2_ADDRESS");
            cfg.ccipRouter = vm.envAddress("SEPOLIA_CCIP_ROUTER_ADDRESS");
            // cfg.orderManager = vm.envAddress("SEPOLIA_ORDER_MANAGER_PROXY_ADDRESS");
            cfg.usdc = vm.envAddress("SEPOLIA_USDC_ADDRESS");
            cfg.indexToken = vm.envAddress("SEPOLIA_INDEX_TOKEN_PROXY_ADDRESS");
        } else if (keccak256(bytes(targetChain)) == keccak256("base_mainnet")) {
            cfg.chainSelector = uint64(vm.envUint("BASE_CCIP_CHAIN_SELECTOR"));
            // cfg.functionsOracle = vm.envAddress("BASE_FUNCTIONS_ORACLE_PROXY_ADDRESS");
            cfg.toUsdPriceFeed = vm.envAddress("BASE_TO_USD_PRICE_FEED_ADDRESS");
            cfg.linkToken = vm.envAddress("BASE_LINK_TOKEN_ADDRESS");
            cfg.weth = vm.envAddress("BASE_WETH_ADDRESS");
            cfg.swapRouterV3 = vm.envAddress("BASE_SWAP_ROUTER_V3_ADDRESS");
            cfg.factoryV3 = vm.envAddress("BASE_UNISWAP_FACTORY_V3_ADDRESS");
            cfg.swapRouterV2 = vm.envAddress("BASE_SWAP_ROUTER_V2_ADDRESS");
            cfg.factoryV2 = vm.envAddress("BASE_UNISWAP_FACTORY_V2_ADDRESS");
            cfg.ccipRouter = vm.envAddress("BASE_CCIP_ROUTER_ADDRESS");
            // cfg.orderManager = vm.envAddress("BASE_ORDER_MANAGER_PROXY_ADDRESS");
            cfg.usdc = vm.envAddress("BASE_USDC_ADDRESS");
        } else if (keccak256(bytes(targetChain)) == keccak256("ethereum_mainnet")) {
            cfg.chainSelector = uint64(vm.envUint("ETHEREUM_CCIP_CHAIN_SELECTOR"));
            // cfg.functionsOracle = vm.envAddress("ETHEREUM_FUNCTIONS_ORACLE_PROXY_ADDRESS");
            cfg.toUsdPriceFeed = vm.envAddress("ETHEREUM_TO_USD_PRICE_FEED_ADDRESS");
            cfg.linkToken = vm.envAddress("ETHEREUM_CHAINLINK_TOKEN_ADDRESS");
            cfg.weth = vm.envAddress("ETHEREUM_WETH_ADDRESS");
            cfg.swapRouterV3 = vm.envAddress("ETHEREUM_ROUTER_V3_ADDRESS");
            cfg.factoryV3 = vm.envAddress("ETHEREUM_FACTORY_V3_ADDRESS");
            cfg.swapRouterV2 = vm.envAddress("ETHEREUM_ROUTER_V2_ADDRESS");
            cfg.factoryV2 = vm.envAddress("ETHEREUM_FACTORY_V2_ADDRESS");
            cfg.ccipRouter = vm.envAddress("ETHEREUM_CCIP_ROUTER_ADDRESS");
            cfg.usdc = vm.envAddress("ETHEREUM_USDC_ADDRESS");

            // cfg.orderManager = vm.envAddress("BASE_ORDER_MANAGER_PROXY_ADDRESS");
        } else if (keccak256(bytes(targetChain)) == keccak256("bsc_mainnet")) {
            cfg.chainSelector = uint64(vm.envUint("BSC_CCIP_CHAIN_SELECTOR"));
            // cfg.functionsOracle = vm.envAddress("BSC_FUNCTIONS_ORACLE_PROXY_ADDRESS");
            cfg.toUsdPriceFeed = vm.envAddress("BSC_TO_USD_PRICE_FEED_ADDRESS");
            cfg.linkToken = vm.envAddress("BSC_CHAINLINK_TOKEN_ADDRESS");
            cfg.weth = vm.envAddress("BSC_WETH_ADDRESS");
            cfg.swapRouterV3 = vm.envAddress("BSC_ROUTER_V3_ADDRESS");
            cfg.factoryV3 = vm.envAddress("BSC_FACTORY_V3_ADDRESS");
            cfg.swapRouterV2 = vm.envAddress("BSC_ROUTER_V2_ADDRESS");
            cfg.factoryV2 = vm.envAddress("BSC_FACTORY_V2_ADDRESS");
            cfg.ccipRouter = vm.envAddress("BSC_CCIP_ROUTER_ADDRESS");
            // cfg.usdc = vm.envAddress("BSC_USDC_ADDRESS");
        } else {
            revert("Unsupported target chain");
        }
    }

    function _deployCrossChainIndexFactoryStorage(address owner, ChainConfig memory cfg)
        internal
        returns (address proxy)
    {
        proxy = Upgrades.deployTransparentProxy(
            "CrossChainIndexFactoryStorage.sol",
            owner,
            abi.encodeCall(
                CrossChainIndexFactoryStorage.initialize,
                (
                    cfg.chainSelector,
                    cfg.linkToken,
                    cfg.ccipRouter,
                    cfg.weth,
                    cfg.swapRouterV3,
                    cfg.factoryV3,
                    cfg.swapRouterV2,
                    cfg.toUsdPriceFeed
                )
            )
        );
        crossChainIndexFactoryStorage = CrossChainIndexFactoryStorage(proxy);
    }

    function _deployCrossChainIndexFactory(address owner, ChainConfig memory cfg, address ccStorageProxy)
        internal
        returns (address proxy)
    {
        proxy = Upgrades.deployTransparentProxy(
            "CrossChainIndexFactory.sol",
            owner,
            abi.encodeCall(CrossChainIndexFactory.initialize, (ccStorageProxy, cfg.ccipRouter, cfg.linkToken))
        );
        crossChainIndexFactory = CrossChainIndexFactory(payable(proxy));
    }

    function _deployCrossChainIndexFactoryBalancer(address owner, ChainConfig memory cfg, address ccStorageProxy)
        internal
        returns (address proxy)
    {
        proxy = Upgrades.deployTransparentProxy(
            "CrossChainIndexFactoryBalancer.sol",
            owner,
            abi.encodeCall(CrossChainIndexFactoryBalancer.initialize, (ccStorageProxy, cfg.ccipRouter, cfg.linkToken))
        );
        crossChainIndexFactoryBalancer = CrossChainIndexFactoryBalancer(payable(proxy));
    }
}

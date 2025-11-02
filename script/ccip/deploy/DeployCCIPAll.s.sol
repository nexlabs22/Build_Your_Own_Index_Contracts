// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import "openzeppelin-foundry-upgrades/Upgrades.sol";

import "../../../src/ccip/MainChainStorage.sol";
import "../../../src/ccip/CrossChainIndexFactoryStorage.sol";
import "../../../src/ccip/CrossChainIndexFactory.sol";
import "../../../src/ccip/BalancerSender.sol";
import "../../../src/ccip/CoreSender.sol";
import "../../../src/ccip/MainChainBalancer.sol";
import "../../../src/ccip/MainChainFactory.sol";
import "../../../src/ccip/MainChainBalancer2.sol";

contract DeployCCIPAll is Script {
    MainChainStorage public mainChainStorage;
    CrossChainIndexFactoryStorage public crossChainIndexFactoryStorage;
    CrossChainIndexFactory public crossChainIndexFactory;
    BalancerSender public balancerSender;
    CoreSender public coreSender;
    MainChainBalancer public mainChainBalancer;
    MainChainBalancer2 public mainChainBalancer2;
    MainChainFactory public mainChainFactory;

    struct ChainConfig {
        uint64 chainSelector;
        address functionsOracle;
        address toUsdPriceFeed;
        address linkToken;
        address weth;
        address swapRouterV3;
        address factoryV3;
        address swapRouterV2;
        address factoryV2;
        address vaultAddress;
        address ccipRouter;
        address indexToken;
        address orderManager;
        address usdc;
    }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.addr(deployerPrivateKey);
        string memory targetChain = "sepolia";

        ChainConfig memory cfg = _loadConfig(targetChain);

        vm.startBroadcast(deployerPrivateKey);

        address mainChainStorageProxy = _deployMainChainStorage(owner, cfg);
        // if (cfg.vaultAddress != address(0)) {
        //     mainChainStorage.setVault(cfg.vaultAddress);
        // }

        address balancerSenderProxy = _deployBalancerSender(owner, cfg, mainChainStorageProxy);
        address coreSenderProxy = _deployCoreSender(owner, cfg, mainChainStorageProxy);
        address mainChainBalancerProxy =
            _deployMainChainBalancer(owner, cfg, mainChainStorageProxy, balancerSenderProxy);
        address mainChainBalancer2Proxy =
            _deployMainChainBalancer2(owner, cfg, mainChainStorageProxy, balancerSenderProxy);
        address mainChainFactoryProxy = _deployMainChainFactory(owner, cfg, mainChainStorageProxy, coreSenderProxy);

        mainChainStorage.setMainChainBalancer(mainChainBalancerProxy);
        mainChainStorage.setMainChainBalancer2(mainChainBalancer2Proxy);

        console.log("MainChainStorage proxy deployed at:", mainChainStorageProxy);
        console.log("MainChainStorage ProxyAdmin:", Upgrades.getAdminAddress(mainChainStorageProxy));

        console.log("BalancerSender proxy deployed at:", balancerSenderProxy);
        console.log("BalancerSender ProxyAdmin:", Upgrades.getAdminAddress(balancerSenderProxy));

        console.log("CoreSender proxy deployed at:", coreSenderProxy);
        console.log("CoreSender ProxyAdmin:", Upgrades.getAdminAddress(coreSenderProxy));

        console.log("MainChainBalancer proxy deployed at:", mainChainBalancerProxy);
        console.log("MainChainBalancer ProxyAdmin:", Upgrades.getAdminAddress(mainChainBalancerProxy));

        console.log("MainChainBalancer2 proxy deployed at:", mainChainBalancer2Proxy);
        console.log("MainChainBalancer2 ProxyAdmin:", Upgrades.getAdminAddress(mainChainBalancer2Proxy));

        console.log("MainChainFactory proxy deployed at:", mainChainFactoryProxy);
        console.log("MainChainFactory ProxyAdmin:", Upgrades.getAdminAddress(mainChainFactoryProxy));

        vm.stopBroadcast();
    }

    function _loadConfig(string memory targetChain) internal view returns (ChainConfig memory cfg) {
        if (keccak256(bytes(targetChain)) == keccak256("sepolia")) {
            cfg.chainSelector = uint64(vm.envUint("SEPOLIA_CCIP_CHAIN_SELECTOR"));
            cfg.functionsOracle = vm.envAddress("SEPOLIA_FUNCTIONS_ORACLE_PROXY_ADDRESS");
            cfg.toUsdPriceFeed = vm.envAddress("SEPOLIA_TO_USD_PRICE_FEED_ADDRESS");
            cfg.linkToken = vm.envAddress("SEPOLIA_LINK_TOKEN_ADDRESS");
            cfg.weth = vm.envAddress("SEPOLIA_WETH_ADDRESS");
            cfg.swapRouterV3 = vm.envAddress("SEPOLIA_SWAP_ROUTER_V3_ADDRESS");
            cfg.factoryV3 = vm.envAddress("SEPOLIA_UNISWAP_FACTORY_V3_ADDRESS");
            cfg.swapRouterV2 = vm.envAddress("SEPOLIA_SWAP_ROUTER_V2_ADDRESS");
            cfg.factoryV2 = vm.envAddress("SEPOLIA_UNISWAP_FACTORY_V2_ADDRESS");
            cfg.ccipRouter = vm.envAddress("SEPOLIA_CCIP_ROUTER_ADDRESS");
            cfg.orderManager = vm.envAddress("SEPOLIA_ORDER_MANAGER_PROXY_ADDRESS");
            cfg.usdc = vm.envAddress("SEPOLIA_USDC_ADDRESS");
            cfg.indexToken = vm.envAddress("SEPOLIA_INDEX_TOKEN_PROXY_ADDRESS");
        } else if (keccak256(bytes(targetChain)) == keccak256("arbitrum_mainnet")) {
            cfg.chainSelector = uint64(vm.envUint("ARBITRUM_CCIP_CHAIN_SELECTOR"));
            cfg.functionsOracle = vm.envAddress("ARBITRUM_FUNCTIONS_ORACLE_PROXY_ADDRESS");
            cfg.toUsdPriceFeed = vm.envAddress("ARBITRUM_TO_USD_PRICE_FEED_ADDRESS");
            cfg.linkToken = vm.envAddress("ARBITRUM_LINK_TOKEN_ADDRESS");
            cfg.weth = vm.envAddress("ARBITRUM_WETH_ADDRESS");
            cfg.swapRouterV3 = vm.envAddress("ARBITRUM_SWAP_ROUTER_V3_ADDRESS");
            cfg.factoryV3 = vm.envAddress("ARBITRUM_UNISWAP_FACTORY_V3_ADDRESS");
            cfg.swapRouterV2 = vm.envAddress("ARBITRUM_SWAP_ROUTER_V2_ADDRESS");
            cfg.factoryV2 = vm.envAddress("ARBITRUM_UNISWAP_FACTORY_V2_ADDRESS");
            cfg.ccipRouter = vm.envAddress("ARBITRUM_CCIP_ROUTER_ADDRESS");
            cfg.orderManager = vm.envAddress("ARBITRUM_ORDER_MANAGER_PROXY_ADDRESS");
            cfg.usdc = vm.envAddress("ARBITRUM_USDC_ADDRESS");
        } else {
            revert("Unsupported target chain");
        }
    }

    function _deployMainChainStorage(address owner, ChainConfig memory cfg) internal returns (address proxy) {
        proxy = Upgrades.deployTransparentProxy(
            "MainChainStorage.sol",
            owner,
            abi.encodeCall(
                MainChainStorage.initialize,
                (
                    cfg.chainSelector,
                    cfg.functionsOracle,
                    cfg.toUsdPriceFeed,
                    cfg.linkToken,
                    cfg.weth,
                    cfg.swapRouterV3,
                    cfg.factoryV3,
                    cfg.swapRouterV2,
                    cfg.factoryV2
                )
            )
        );
        mainChainStorage = MainChainStorage(proxy);
    }

    // function _deployCrossChainIndexFactoryStorage(address owner, ChainConfig memory cfg)
    //     internal
    //     returns (address proxy)
    // {
    //     proxy = Upgrades.deployTransparentProxy(
    //         "CrossChainIndexFactoryStorage.sol",
    //         owner,
    //         abi.encodeCall(
    //             CrossChainIndexFactoryStorage.initialize,
    //             (
    //                 cfg.chainSelector,
    //                 cfg.linkToken,
    //                 cfg.ccipRouter,
    //                 cfg.weth,
    //                 cfg.swapRouterV3,
    //                 cfg.factoryV3,
    //                 cfg.swapRouterV2,
    //                 cfg.toUsdPriceFeed
    //             )
    //         )
    //     );
    //     crossChainIndexFactoryStorage = CrossChainIndexFactoryStorage(proxy);
    // }

    // function _deployCrossChainIndexFactory(address owner, ChainConfig memory cfg, address ccStorageProxy)
    //     internal
    //     returns (address proxy)
    // {
    //     proxy = Upgrades.deployTransparentProxy(
    //         "CrossChainIndexFactory.sol",
    //         owner,
    //         abi.encodeCall(CrossChainIndexFactory.initialize, (ccStorageProxy, cfg.ccipRouter, cfg.linkToken))
    //     );
    //     crossChainIndexFactory = CrossChainIndexFactory(payable(proxy));
    // }

    function _deployBalancerSender(address owner, ChainConfig memory cfg, address mainChainStorageProxy)
        internal
        returns (address proxy)
    {
        proxy = Upgrades.deployTransparentProxy(
            "BalancerSender.sol",
            owner,
            abi.encodeCall(
                BalancerSender.initialize,
                (cfg.chainSelector, mainChainStorageProxy, cfg.functionsOracle, cfg.linkToken, cfg.ccipRouter, cfg.weth)
            )
        );
        balancerSender = BalancerSender(payable(proxy));
    }

    function _deployCoreSender(address owner, ChainConfig memory cfg, address mainChainStorageProxy)
        internal
        returns (address proxy)
    {
        proxy = Upgrades.deployTransparentProxy(
            "CoreSender.sol",
            owner,
            abi.encodeCall(
                CoreSender.initialize,
                (
                    payable(cfg.indexToken),
                    mainChainStorageProxy,
                    cfg.orderManager,
                    cfg.functionsOracle,
                    cfg.linkToken,
                    cfg.ccipRouter,
                    cfg.weth,
                    cfg.usdc
                )
            )
        );
        coreSender = CoreSender(payable(proxy));
    }

    function _deployMainChainBalancer(
        address owner,
        ChainConfig memory cfg,
        address mainChainStorageProxy,
        address balancerSenderProxy
    ) internal returns (address proxy) {
        proxy = Upgrades.deployTransparentProxy(
            "MainChainBalancer.sol",
            owner,
            abi.encodeCall(
                MainChainBalancer.initialize,
                (
                    cfg.chainSelector,
                    mainChainStorageProxy,
                    cfg.functionsOracle,
                    payable(balancerSenderProxy),
                    cfg.weth,
                    cfg.usdc
                )
            )
        );
        mainChainBalancer = MainChainBalancer(proxy);
    }

    function _deployMainChainBalancer2(
        address owner,
        ChainConfig memory cfg,
        address mainChainStorageProxy,
        address balancerSenderProxy
    ) internal returns (address proxy) {
        proxy = Upgrades.deployTransparentProxy(
            "MainChainBalancer2.sol",
            owner,
            abi.encodeCall(
                MainChainBalancer2.initialize,
                (
                    cfg.chainSelector,
                    mainChainStorageProxy,
                    cfg.functionsOracle,
                    payable(balancerSenderProxy),
                    cfg.weth,
                    cfg.usdc
                )
            )
        );
        mainChainBalancer2 = MainChainBalancer2(proxy);
    }

    function _deployMainChainFactory(
        address owner,
        ChainConfig memory cfg,
        address mainChainStorageProxy,
        address coreSenderProxy
    ) internal returns (address proxy) {
        proxy = Upgrades.deployTransparentProxy(
            "MainChainFactory.sol",
            owner,
            abi.encodeCall(
                MainChainFactory.initialize,
                (
                    cfg.chainSelector,
                    payable(cfg.indexToken),
                    cfg.orderManager,
                    mainChainStorageProxy,
                    cfg.functionsOracle,
                    payable(coreSenderProxy),
                    cfg.weth,
                    cfg.usdc
                )
            )
        );
        mainChainFactory = MainChainFactory(payable(proxy));
    }
}

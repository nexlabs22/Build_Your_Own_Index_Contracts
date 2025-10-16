// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import "openzeppelin-foundry-upgrades/Upgrades.sol";

import {DinariStorage} from "../../src/dinari/DinariStorage.sol";
import {DinariBalancer} from "../../src/dinari/DinariBalancer.sol";
import {DinariFactory} from "../../src/dinari/DinariFactory.sol";

import {BackedFiStorage} from "../../src/backedfi/BackedFiStorage.sol";
import {BackedFiBalancer} from "../../src/backedfi/BackedFiBalancer.sol";
import {BackedFiFactory} from "../../src/backedfi/BackedFiFactory.sol";
import {StagingCustodyAccount} from "../../src/backedfi/StagingCustodyAccount.sol";

import {MainChainStorage} from "../../src/ccip/MainChainStorage.sol";
import {CrossChainIndexFactoryStorage} from "../../src/ccip/CrossChainIndexFactoryStorage.sol";
import {CrossChainIndexFactory} from "../../src/ccip/CrossChainIndexFactory.sol";
import {BalancerSender} from "../../src/ccip/BalancerSender.sol";
import {CoreSender} from "../../src/ccip/CoreSender.sol";
import {MainChainBalancer} from "../../src/ccip/MainChainBalancer.sol";
import {MainChainFactory} from "../../src/ccip/MainChainFactory.sol";

contract DeployAllProviders is Script {
    struct DinariConfig {
        address issuer;
        address indexFactoryStorage;
        address functionsOracle;
        address indexFactoryBalancer;
        address usdc;
        uint8 usdcDecimals;
        bool isMainnet;
        uint8 providerIndex;
    }

    struct DinariAddresses {
        address storageProxy;
        address balancerProxy;
        address factoryProxy;
    }

    struct BackedFiConfig {
        address indexFactory;
        address indexFactoryStorage;
        address functionsOracle;
        address nexBot;
        address usdc;
        uint8 providerIndex;
    }

    struct BackedFiAddresses {
        address storageProxy;
        address scaProxy;
        address balancerProxy;
        address factoryProxy;
    }

    struct CcipConfig {
        uint64 chainSelector;
        address functionsOracle;
        address toUsdPriceFeed;
        address linkToken;
        address weth;
        address swapRouterV3;
        address factoryV3;
        address swapRouterV2;
        address factoryV2;
        address vault;
        address ccipRouter;
        address indexToken;
        address orderManager;
        address indexFactoryBalancer;
    }

    struct CcipAddresses {
        address mainChainStorage;
        address crossChainStorage;
        address crossChainFactory;
        address balancerSender;
        address coreSender;
        address mainChainBalancer;
        address mainChainFactory;
    }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.addr(deployerPrivateKey);
        string memory targetChain = vm.envOr("TARGET_CHAIN", string("sepolia"));

        vm.startBroadcast(deployerPrivateKey);

        DinariConfig memory dinariCfg = _loadDinariConfig(targetChain);
        DinariAddresses memory dinariAddr = _deployDinari(owner, dinariCfg);

        BackedFiConfig memory backedCfg = _loadBackedFiConfig(targetChain);
        BackedFiAddresses memory backedAddr = _deployBackedFi(owner, backedCfg);

        CcipConfig memory ccipCfg = _loadCcipConfig(targetChain);
        CcipAddresses memory ccipAddr = _deployCcip(owner, ccipCfg);

        _logDinariAddresses(dinariAddr);
        _logBackedFiAddresses(backedAddr);
        _logCcipAddresses(ccipAddr);

        vm.stopBroadcast();
    }

    // Dinari
    function _deployDinari(address owner, DinariConfig memory cfg) internal returns (DinariAddresses memory addrs) {
        addrs.storageProxy = Upgrades.deployTransparentProxy("DinariStorage.sol", owner, bytes(""));
        addrs.balancerProxy = Upgrades.deployTransparentProxy("DinariBalancer.sol", owner, bytes(""));
        addrs.factoryProxy = Upgrades.deployTransparentProxy("DinariFactory.sol", owner, bytes(""));

        DinariStorage storageContract = DinariStorage(addrs.storageProxy);
        storageContract.initialize(
            cfg.issuer,
            cfg.indexFactoryStorage,
            addrs.balancerProxy,
            cfg.usdc,
            cfg.usdcDecimals,
            cfg.functionsOracle,
            cfg.isMainnet,
            cfg.providerIndex
        );

        DinariBalancer balancerContract = DinariBalancer(addrs.balancerProxy);
        balancerContract.initialize(
            addrs.storageProxy, cfg.functionsOracle, cfg.indexFactoryStorage, cfg.indexFactoryBalancer
        );

        DinariFactory factoryContract = DinariFactory(addrs.factoryProxy);
        factoryContract.initialize(cfg.indexFactoryStorage, addrs.storageProxy, cfg.functionsOracle);

        storageContract.setFactory(addrs.factoryProxy);
        storageContract.setFactoryBalancer(cfg.indexFactoryBalancer);

        return addrs;
    }

    function _loadDinariConfig(string memory targetChain) internal view returns (DinariConfig memory cfg) {
        string memory prefix = _chainPrefix(targetChain);
        cfg.issuer = vm.envAddress(string.concat(prefix, "_DINARI_ISSUER_ADDRESS"));
        cfg.indexFactoryStorage = vm.envAddress(string.concat(prefix, "_INDEX_FACTORY_STORAGE_PROXY_ADDRESS"));
        cfg.functionsOracle = vm.envAddress(string.concat(prefix, "_FUNCTIONS_ORACLE_PROXY_ADDRESS"));
        cfg.indexFactoryBalancer = vm.envAddress(string.concat(prefix, "_INDEX_FACTORY_BALANCER_PROXY_ADDRESS"));
        cfg.usdc = vm.envAddress(string.concat(prefix, "_USDC_ADDRESS"));
        cfg.usdcDecimals = uint8(vm.envUint(string.concat(prefix, "_USDC_DECIMALS")));
        cfg.isMainnet = vm.envBool(string.concat(prefix, "_IS_MAINNET"));
        cfg.providerIndex = uint8(vm.envUint(string.concat(prefix, "_DINARI_PROVIDER_INDEX")));
    }

    function _logDinariAddresses(DinariAddresses memory addrs) internal view {
        console.log("DinariStorage proxy:", addrs.storageProxy);
        console.log("DinariBalancer proxy:", addrs.balancerProxy);
        console.log("DinariFactory proxy:", addrs.factoryProxy);
    }

    // BackedFi
    function _deployBackedFi(address owner, BackedFiConfig memory cfg)
        internal
        returns (BackedFiAddresses memory addrs)
    {
        addrs.storageProxy = Upgrades.deployTransparentProxy("BackedFiStorage.sol", owner, bytes(""));
        addrs.scaProxy = Upgrades.deployTransparentProxy("StagingCustodyAccount.sol", owner, bytes(""));
        addrs.balancerProxy = Upgrades.deployTransparentProxy("BackedFiBalancer.sol", owner, bytes(""));
        addrs.factoryProxy = Upgrades.deployTransparentProxy("BackedFiFactory.sol", owner, bytes(""));

        BackedFiStorage storageContract = BackedFiStorage(addrs.storageProxy);
        storageContract.initialize(
            cfg.indexFactory, cfg.functionsOracle, addrs.scaProxy, cfg.nexBot, cfg.usdc, cfg.providerIndex
        );

        StagingCustodyAccount scaContract = StagingCustodyAccount(addrs.scaProxy);
        scaContract.initialize(addrs.storageProxy);

        BackedFiBalancer balancerContract = BackedFiBalancer(addrs.balancerProxy);
        balancerContract.initialize(addrs.storageProxy, cfg.functionsOracle, cfg.indexFactoryStorage);

        BackedFiFactory factoryContract = BackedFiFactory(addrs.factoryProxy);
        factoryContract.initialize(addrs.storageProxy);

        storageContract.setSCA(addrs.scaProxy);
        storageContract.setFunctionsOracle(cfg.functionsOracle);
        storageContract.setIndexFactory(cfg.indexFactory);
        storageContract.setNexBotAddress(cfg.nexBot);
        scaContract.setBackedFiStorageAddress(addrs.storageProxy);

        return addrs;
    }

    function _loadBackedFiConfig(string memory targetChain) internal view returns (BackedFiConfig memory cfg) {
        string memory prefix = _chainPrefix(targetChain);
        cfg.indexFactory = vm.envAddress(string.concat(prefix, "_INDEX_FACTORY_PROXY_ADDRESS"));
        cfg.indexFactoryStorage = vm.envAddress(string.concat(prefix, "_INDEX_FACTORY_STORAGE_PROXY_ADDRESS"));
        cfg.functionsOracle = vm.envAddress(string.concat(prefix, "_FUNCTIONS_ORACLE_PROXY_ADDRESS"));
        cfg.nexBot = vm.envAddress(string.concat(prefix, "_NEX_BOT_ADDRESS"));
        cfg.usdc = vm.envAddress(string.concat(prefix, "_USDC_ADDRESS"));
        cfg.providerIndex = uint8(vm.envUint(string.concat(prefix, "_BACKEDFI_PROVIDER_INDEX")));
    }

    function _logBackedFiAddresses(BackedFiAddresses memory addrs) internal view {
        console.log("BackedFiStorage proxy:", addrs.storageProxy);
        console.log("StagingCustodyAccount proxy:", addrs.scaProxy);
        console.log("BackedFiBalancer proxy:", addrs.balancerProxy);
        console.log("BackedFiFactory proxy:", addrs.factoryProxy);
    }

    // CCIP
    function _deployCcip(address owner, CcipConfig memory cfg) internal returns (CcipAddresses memory addrs) {
        addrs.mainChainStorage = _deployMainChainStorage(owner, cfg);
        addrs.crossChainStorage = _deployCrossChainIndexFactoryStorage(owner, cfg);
        addrs.crossChainFactory = _deployCrossChainIndexFactory(owner, cfg, addrs.crossChainStorage);
        addrs.balancerSender = _deployBalancerSender(owner, cfg, addrs.mainChainStorage);
        addrs.coreSender = _deployCoreSender(owner, cfg, addrs.mainChainStorage);
        addrs.mainChainBalancer = _deployMainChainBalancer(owner, cfg, addrs.mainChainStorage, addrs.balancerSender);
        addrs.mainChainFactory = _deployMainChainFactory(owner, cfg, addrs.mainChainStorage, addrs.coreSender);

        _configureCcipSetters(addrs, cfg);
        return addrs;
    }

    function _loadCcipConfig(string memory targetChain) internal view returns (CcipConfig memory cfg) {
        string memory prefix = _chainPrefix(targetChain);
        cfg.chainSelector = uint64(vm.envUint(string.concat(prefix, "_CCIP_CHAIN_SELECTOR")));
        cfg.functionsOracle = vm.envAddress(string.concat(prefix, "_FUNCTIONS_ORACLE_PROXY_ADDRESS"));
        cfg.toUsdPriceFeed = vm.envAddress(string.concat(prefix, "_TO_USD_PRICE_FEED_ADDRESS"));
        cfg.linkToken = vm.envAddress(string.concat(prefix, "_LINK_TOKEN_ADDRESS"));
        cfg.weth = vm.envAddress(string.concat(prefix, "_WETH_ADDRESS"));
        cfg.swapRouterV3 = vm.envAddress(string.concat(prefix, "_SWAP_ROUTER_V3_ADDRESS"));
        cfg.factoryV3 = vm.envAddress(string.concat(prefix, "_UNISWAP_FACTORY_V3_ADDRESS"));
        cfg.swapRouterV2 = vm.envAddress(string.concat(prefix, "_SWAP_ROUTER_V2_ADDRESS"));
        cfg.factoryV2 = vm.envAddress(string.concat(prefix, "_UNISWAP_FACTORY_V2_ADDRESS"));
        cfg.vault = vm.envAddress(string.concat(prefix, "_VAULT_PROXY_ADDRESS"));
        cfg.ccipRouter = vm.envAddress(string.concat(prefix, "_CCIP_ROUTER_ADDRESS"));
        cfg.indexToken = vm.envAddress(string.concat(prefix, "_INDEX_TOKEN_PROXY_ADDRESS"));
        cfg.orderManager = vm.envAddress(string.concat(prefix, "_ORDER_MANAGER_PROXY_ADDRESS"));
        cfg.indexFactoryBalancer = vm.envAddress(string.concat(prefix, "_INDEX_FACTORY_BALANCER_PROXY_ADDRESS"));
    }

    function _deployMainChainStorage(address owner, CcipConfig memory cfg) internal returns (address proxy) {
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
        return proxy;
    }

    function _deployCrossChainIndexFactoryStorage(address owner, CcipConfig memory cfg)
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
                    payable(cfg.vault),
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
        return proxy;
    }

    function _deployCrossChainIndexFactory(address owner, CcipConfig memory cfg, address storageProxy)
        internal
        returns (address proxy)
    {
        proxy = Upgrades.deployTransparentProxy(
            "CrossChainIndexFactory.sol",
            owner,
            abi.encodeCall(CrossChainIndexFactory.initialize, (storageProxy, cfg.ccipRouter, cfg.linkToken))
        );
        return proxy;
    }

    function _deployBalancerSender(address owner, CcipConfig memory cfg, address mainChainStorageProxy)
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
        return proxy;
    }

    function _deployCoreSender(address owner, CcipConfig memory cfg, address mainChainStorageProxy)
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
                    cfg.weth
                )
            )
        );
        return proxy;
    }

    function _deployMainChainBalancer(
        address owner,
        CcipConfig memory cfg,
        address mainChainStorageProxy,
        address balancerSenderProxy
    ) internal returns (address proxy) {
        proxy = Upgrades.deployTransparentProxy(
            "MainChainBalancer.sol",
            owner,
            abi.encodeCall(
                MainChainBalancer.initialize,
                (cfg.chainSelector, mainChainStorageProxy, cfg.functionsOracle, payable(balancerSenderProxy), cfg.weth)
            )
        );
        return proxy;
    }

    function _deployMainChainFactory(
        address owner,
        CcipConfig memory cfg,
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
                    cfg.weth
                )
            )
        );
        return proxy;
    }

    function _configureCcipSetters(CcipAddresses memory addrs, CcipConfig memory cfg) internal {
        MainChainStorage mcs = MainChainStorage(addrs.mainChainStorage);
        mcs.setIndexFactory(addrs.mainChainFactory);
        mcs.setCoreSender(addrs.coreSender);
        mcs.setBalancerSender(addrs.balancerSender);
        mcs.setMainChainBalancer(addrs.mainChainBalancer);
        mcs.setVault(cfg.vault);
        mcs.setCrossChainFactory(addrs.crossChainFactory, cfg.chainSelector);

        CrossChainIndexFactoryStorage ccifs = CrossChainIndexFactoryStorage(addrs.crossChainStorage);
        ccifs.setCrossChainFactory(addrs.crossChainFactory);
        ccifs.setVault(payable(cfg.vault));

        CrossChainIndexFactory(payable(addrs.crossChainFactory)).setCrossChainIndexFactoryStorage(
            addrs.crossChainStorage
        );

        BalancerSender bs = BalancerSender(payable(addrs.balancerSender));
        bs.setMainChainStorage(addrs.mainChainStorage);
        bs.setFunctionsOracle(cfg.functionsOracle);
        bs.setIndexFactoryBalancer(cfg.indexFactoryBalancer);

        CoreSender cs = CoreSender(payable(addrs.coreSender));
        cs.setMainChainStorage(addrs.mainChainStorage);
        cs.setFunctionsOracle(cfg.functionsOracle);

        MainChainBalancer mcb = MainChainBalancer(addrs.mainChainBalancer);
        mcb.setMainChainStorage(addrs.mainChainStorage);
        mcb.setFunctionsOracle(cfg.functionsOracle);
        mcb.setBalancerSender(payable(addrs.balancerSender));
        mcb.setIndexFactoryBalancer(cfg.indexFactoryBalancer);

        MainChainFactory mcf = MainChainFactory(payable(addrs.mainChainFactory));
        mcf.setMainChainStorage(addrs.mainChainStorage);
        mcf.setFunctionsOracle(cfg.functionsOracle);
        mcf.setCoreSender(payable(addrs.coreSender));
        mcf.setIndexToken(cfg.indexToken);
        mcf.setOrderManager(cfg.orderManager);
        mcf.setWethAddress(cfg.weth);
    }

    function _logCcipAddresses(CcipAddresses memory addrs) internal view {
        console.log("MainChainStorage proxy:", addrs.mainChainStorage);
        console.log("CrossChainIndexFactoryStorage proxy:", addrs.crossChainStorage);
        console.log("CrossChainIndexFactory proxy:", addrs.crossChainFactory);
        console.log("BalancerSender proxy:", addrs.balancerSender);
        console.log("CoreSender proxy:", addrs.coreSender);
        console.log("MainChainBalancer proxy:", addrs.mainChainBalancer);
        console.log("MainChainFactory proxy:", addrs.mainChainFactory);
    }

    function _chainPrefix(string memory targetChain) internal pure returns (string memory) {
        if (keccak256(bytes(targetChain)) == keccak256("arbitrum_mainnet")) {
            return "ARBITRUM";
        }
        return "SEPOLIA";
    }
}

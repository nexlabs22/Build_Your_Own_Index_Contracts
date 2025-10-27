// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {DinariStorage} from "../../src/dinari/DinariStorage.sol";
import {DinariFactory} from "../../src/dinari/DinariFactory.sol";
import {DinariBalancer} from "../../src/dinari/DinariBalancer.sol";
import {DinariFactoryProcessor} from "../../src/dinari/DinariFactoryProcessor.sol";
import {DinariOrderManager} from "../../src/dinari/DinariOrderManager.sol";
import {BackedFiStorage} from "../../src/backedfi/BackedFiStorage.sol";
import {StagingCustodyAccount} from "../../src/backedfi/StagingCustodyAccount.sol";
import {MainChainStorage} from "../../src/ccip/MainChainStorage.sol";
import {CrossChainIndexFactoryStorage} from "../../src/ccip/CrossChainIndexFactoryStorage.sol";
import {CrossChainIndexFactory} from "../../src/ccip/CrossChainIndexFactory.sol";
import {BalancerSender} from "../../src/ccip/BalancerSender.sol";
import {CoreSender} from "../../src/ccip/CoreSender.sol";
import {MainChainBalancer} from "../../src/ccip/MainChainBalancer.sol";
import {MainChainBalancer2} from "../../src/ccip/MainChainBalancer2.sol";
import {MainChainFactory} from "../../src/ccip/MainChainFactory.sol";
import {CrossChainIndexFactoryBalancer} from "../../src/ccip/CrossChainIndexFactoryBalancer.sol";

contract ConfigureProviderSetters is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        string memory targetChain = vm.envOr("TARGET_CHAIN", string("sepolia"));

        vm.startBroadcast(deployerPrivateKey);

        // set operator in order manager => mainchain factory
        // set operator in order manager => core sender
        // set operator in dinari order manager => factory processor
        // set operator in dinari order manager => dinari factory
        // set minter in index token => global index factory
        // set price decimal in dinari storage => 18

        _configureDinari(targetChain);
        _configureBackedFi(targetChain);
        _configureCcip(targetChain);

        vm.stopBroadcast();
    }

    function _configureDinari(string memory targetChain) internal {
        string memory prefix = _chainPrefix(targetChain);
        address storageProxy = vm.envAddress(string.concat(prefix, "_DINARI_STORAGE_PROXY_ADDRESS"));
        address factoryProxy = vm.envAddress(string.concat(prefix, "_DINARI_FACTORY_PROXY_ADDRESS"));
        address indexFactoryBalancer = vm.envAddress(string.concat(prefix, "_INDEX_FACTORY_BALANCER_PROXY_ADDRESS"));
        address factoryProcessorProxy = vm.envAddress(string.concat(prefix, "_DINARI_FACTORY_PROCESSOR_PROXY_ADDRESS"));
        address orderManagerProxy = vm.envAddress(string.concat(prefix, "_DINARI_ORDER_MANAGER_PROXY_ADDRESS"));
        address functionsOracle = vm.envAddress(string.concat(prefix, "_FUNCTIONS_ORACLE_PROXY_ADDRESS"));
        address indexFactoryStorage = vm.envAddress(string.concat(prefix, "_INDEX_FACTORY_STORAGE_PROXY_ADDRESS"));
        address dinariBalancerProxy = vm.envAddress(string.concat(prefix, "_DINARI_BALANCER_PROXY_ADDRESS"));
        address issuer = vm.envAddress(string.concat(prefix, "_DINARI_ISSUER_ADDRESS"));

        uint8 usdcDecimals = uint8(vm.envUint(string.concat(prefix, "_USDC_DECIMALS")));
        address usdcToken = vm.envAddress(string.concat(prefix, "_USDC_ADDRESS"));

        DinariStorage storageContract = DinariStorage(storageProxy);
        storageContract.setFactory(factoryProxy);
        storageContract.setFactoryBalancer(indexFactoryBalancer);
        storageContract.setFactoryProcessor(factoryProcessorProxy);
        storageContract.setOrderManager(orderManagerProxy);
        storageContract.setFunctionsOracle(functionsOracle);
        storageContract.setIssuer(issuer);

        DinariFactory factoryContract = DinariFactory(factoryProxy);
        factoryContract.setFunctionsOracle(functionsOracle);

        DinariBalancer balancerContract = DinariBalancer(dinariBalancerProxy);
        balancerContract.setFunctionsOracle(functionsOracle);
        balancerContract.setIndexFactoryStorage(indexFactoryStorage);

        DinariFactoryProcessor processor = DinariFactoryProcessor(factoryProcessorProxy);
        processor.setFunctionsOracle(functionsOracle);

        DinariOrderManager orderManager = DinariOrderManager(orderManagerProxy);
        orderManager.setIssuer(issuer);
        orderManager.setUsdcAddress(usdcToken, usdcDecimals);

        console.log("Configured DinariStorage setters");
    }

    function _configureBackedFi(string memory targetChain) internal {
        string memory prefix = _chainPrefix(targetChain);
        address storageProxy = vm.envAddress(string.concat(prefix, "_BACKEDFI_STORAGE_PROXY_ADDRESS"));
        address scaProxy = vm.envAddress(string.concat(prefix, "_STAGING_CUSTODY_ACCOUNT_PROXY_ADDRESS"));
        address functionsOracle = vm.envAddress(string.concat(prefix, "_FUNCTIONS_ORACLE_PROXY_ADDRESS"));
        address indexFactory = vm.envAddress(string.concat(prefix, "_INDEX_FACTORY_PROXY_ADDRESS"));
        address nexBot = vm.envAddress(string.concat(prefix, "_NEX_BOT_ADDRESS"));

        BackedFiStorage storageContract = BackedFiStorage(storageProxy);
        storageContract.setFunctionsOracle(functionsOracle);
        storageContract.setIndexFactory(indexFactory);
        storageContract.setNexBotAddress(nexBot);
        storageContract.setSCA(scaProxy);

        StagingCustodyAccount(scaProxy).setBackedFiStorageAddress(storageProxy);

        console.log("Configured BackedFi setters");
    }

    function _configureCcip(string memory targetChain) internal {
        string memory prefix = _chainPrefix(targetChain);
        _configureMainChainStorage(prefix);
        // _configureCrossChainIndexFactory(prefix);
        _configureBalancerSender(prefix);
        _configureCoreSender(prefix);
        _configureMainChainBalancer(prefix);
        _configureMainChainBalancer2(prefix);
        // _configureCrossChainIndexFactoryBalancer(prefix);
        _configureMainChainFactory(prefix);

        console.log("Configured CCIP setters");
    }

    function _configureMainChainBalancer2(string memory prefix) internal {
        address mainChainBalancer2Proxy = vm.envAddress(string.concat(prefix, "_MAIN_CHAIN_BALANCER2_PROXY_ADDRESS"));
        address mainChainStorageProxy = vm.envAddress(string.concat(prefix, "_MAIN_CHAIN_STORAGE_PROXY_ADDRESS"));
        address functionsOracle = vm.envAddress(string.concat(prefix, "_FUNCTIONS_ORACLE_PROXY_ADDRESS"));
        address balancerSenderProxy = vm.envAddress(string.concat(prefix, "_BALANCER_SENDER_PROXY_ADDRESS"));
        address indexFactoryStorage = vm.envAddress(string.concat(prefix, "_INDEX_FACTORY_STORAGE_PROXY_ADDRESS"));

        MainChainBalancer2 mcb2 = MainChainBalancer2(mainChainBalancer2Proxy);
        mcb2.setMainChainStorage(mainChainStorageProxy);
        mcb2.setFunctionsOracle(functionsOracle);
        mcb2.setBalancerSender(payable(balancerSenderProxy));
        mcb2.setIndexFactoryStorage(indexFactoryStorage);
    }

    function _configureCrossChainIndexFactoryBalancer(string memory prefix) internal {
        address balancerProxy =
            vm.envAddress(string.concat(prefix, "_CROSS_CHAIN_INDEX_FACTORY_BALANCER_PROXY_ADDRESS"));
        address crossChainStorageProxy =
            vm.envAddress(string.concat(prefix, "_CROSS_CHAIN_INDEX_FACTORY_STORAGE_PROXY_ADDRESS"));

        CrossChainIndexFactoryBalancer balancer = CrossChainIndexFactoryBalancer(payable(balancerProxy));
        balancer.setCrossChainIndexFactoryStorage(crossChainStorageProxy);
    }

    function _configureMainChainStorage(string memory prefix) internal {
        address mainChainStorageProxy = vm.envAddress(string.concat(prefix, "_MAIN_CHAIN_STORAGE_PROXY_ADDRESS"));
        address balancerSenderProxy = vm.envAddress(string.concat(prefix, "_BALANCER_SENDER_PROXY_ADDRESS"));
        address coreSenderProxy = vm.envAddress(string.concat(prefix, "_CORE_SENDER_PROXY_ADDRESS"));
        address mainChainBalancerProxy = vm.envAddress(string.concat(prefix, "_MAIN_CHAIN_BALANCER_PROXY_ADDRESS"));
        address mainChainBalancer2Proxy = vm.envAddress(string.concat(prefix, "_MAIN_CHAIN_BALANCER2_PROXY_ADDRESS"));
        // address crossChainFactoryProxy =
        //     vm.envAddress(string.concat(prefix, "_CROSS_CHAIN_INDEX_FACTORY_PROXY_ADDRESS"));
        // address crossChainFactoryBalancerProxy =
        //     vm.envAddress(string.concat(prefix, "_CROSS_CHAIN_INDEX_FACTORY_BALANCER_PROXY_ADDRESS"));
        uint64 chainSelector = uint64(vm.envUint(string.concat(prefix, "_CCIP_CHAIN_SELECTOR")));
        // address vault = vm.envAddress(string.concat(prefix, "_VAULT_PROXY_ADDRESS"));
        address functionsOracle = vm.envAddress(string.concat(prefix, "_FUNCTIONS_ORACLE_PROXY_ADDRESS"));
        address mainChainFactoryProxy = vm.envAddress(string.concat(prefix, "_MAIN_CHAIN_FACTORY_PROXY_ADDRESS"));

        MainChainStorage mcs = MainChainStorage(mainChainStorageProxy);
        mcs.setCoreSender(coreSenderProxy);
        mcs.setBalancerSender(balancerSenderProxy);
        mcs.setMainChainBalancer(mainChainBalancerProxy);
        mcs.setMainChainBalancer2(mainChainBalancer2Proxy);
        // mcs.setVault(vault);
        // mcs.setCrossChainFactory(crossChainFactoryProxy, chainSelector);
        // mcs.setCrossChainFactoryBalancer(crossChainFactoryBalancerProxy, chainSelector);
        mcs.setFunctionsOracle(functionsOracle);
        mcs.setMainChainFactory(mainChainFactoryProxy);
    }

    function _configureCrossChainIndexFactory(string memory prefix) internal {
        address crossChainStorageProxy =
            vm.envAddress(string.concat(prefix, "_CROSS_CHAIN_INDEX_FACTORY_STORAGE_PROXY_ADDRESS"));
        address crossChainFactoryProxy =
            vm.envAddress(string.concat(prefix, "_CROSS_CHAIN_INDEX_FACTORY_PROXY_ADDRESS"));
        address crossChainFactoryBalancerProxy =
            vm.envAddress(string.concat(prefix, "_CROSS_CHAIN_INDEX_FACTORY_BALANCER_PROXY_ADDRESS"));

        CrossChainIndexFactoryStorage ccifs = CrossChainIndexFactoryStorage(crossChainStorageProxy);
        ccifs.setCrossChainFactory(crossChainFactoryProxy);
        ccifs.setCrossChainFactoryBalancer(crossChainFactoryBalancerProxy);
        CrossChainIndexFactory(payable(crossChainFactoryProxy)).setCrossChainIndexFactoryStorage(crossChainStorageProxy);
    }

    function _configureBalancerSender(string memory prefix) internal {
        address balancerSenderProxy = vm.envAddress(string.concat(prefix, "_BALANCER_SENDER_PROXY_ADDRESS"));
        address mainChainStorageProxy = vm.envAddress(string.concat(prefix, "_MAIN_CHAIN_STORAGE_PROXY_ADDRESS"));
        address functionsOracle = vm.envAddress(string.concat(prefix, "_FUNCTIONS_ORACLE_PROXY_ADDRESS"));
        address indexFactoryBalancer = vm.envAddress(string.concat(prefix, "_INDEX_FACTORY_BALANCER_PROXY_ADDRESS"));

        BalancerSender bs = BalancerSender(payable(balancerSenderProxy));
        bs.setMainChainStorage(mainChainStorageProxy);
        bs.setFunctionsOracle(functionsOracle);
        bs.setIndexFactoryBalancer(indexFactoryBalancer);
    }

    function _configureCoreSender(string memory prefix) internal {
        address coreSenderProxy = vm.envAddress(string.concat(prefix, "_CORE_SENDER_PROXY_ADDRESS"));
        address mainChainStorageProxy = vm.envAddress(string.concat(prefix, "_MAIN_CHAIN_STORAGE_PROXY_ADDRESS"));
        address functionsOracle = vm.envAddress(string.concat(prefix, "_FUNCTIONS_ORACLE_PROXY_ADDRESS"));

        CoreSender cs = CoreSender(payable(coreSenderProxy));
        cs.setMainChainStorage(mainChainStorageProxy);
        cs.setFunctionsOracle(functionsOracle);
    }

    function _configureMainChainBalancer(string memory prefix) internal {
        address mainChainBalancerProxy = vm.envAddress(string.concat(prefix, "_MAIN_CHAIN_BALANCER_PROXY_ADDRESS"));
        address mainChainStorageProxy = vm.envAddress(string.concat(prefix, "_MAIN_CHAIN_STORAGE_PROXY_ADDRESS"));
        address functionsOracle = vm.envAddress(string.concat(prefix, "_FUNCTIONS_ORACLE_PROXY_ADDRESS"));
        address balancerSenderProxy = vm.envAddress(string.concat(prefix, "_BALANCER_SENDER_PROXY_ADDRESS"));
        address indexFactoryBalancer = vm.envAddress(string.concat(prefix, "_INDEX_FACTORY_BALANCER_PROXY_ADDRESS"));

        MainChainBalancer mcb = MainChainBalancer(mainChainBalancerProxy);
        mcb.setMainChainStorage(mainChainStorageProxy);
        mcb.setFunctionsOracle(functionsOracle);
        mcb.setBalancerSender(payable(balancerSenderProxy));
        mcb.setIndexFactoryBalancer(indexFactoryBalancer);
    }

    function _configureMainChainFactory(string memory prefix) internal {
        address mainChainFactoryProxy = vm.envAddress(string.concat(prefix, "_MAIN_CHAIN_FACTORY_PROXY_ADDRESS"));
        address mainChainStorageProxy = vm.envAddress(string.concat(prefix, "_MAIN_CHAIN_STORAGE_PROXY_ADDRESS"));
        address functionsOracle = vm.envAddress(string.concat(prefix, "_FUNCTIONS_ORACLE_PROXY_ADDRESS"));
        address coreSenderProxy = vm.envAddress(string.concat(prefix, "_CORE_SENDER_PROXY_ADDRESS"));
        address indexToken = vm.envAddress(string.concat(prefix, "_INDEX_TOKEN_PROXY_ADDRESS"));
        address orderManager = vm.envAddress(string.concat(prefix, "_ORDER_MANAGER_PROXY_ADDRESS"));
        address weth = vm.envAddress(string.concat(prefix, "_WETH_ADDRESS"));
        address usdc = vm.envAddress(string.concat(prefix, "_USDC_ADDRESS"));
        address indexFactoryStorage = vm.envAddress(string.concat(prefix, "_INDEX_FACTORY_STORAGE_PROXY_ADDRESS"));

        MainChainFactory mcf = MainChainFactory(payable(mainChainFactoryProxy));
        mcf.setMainChainStorage(mainChainStorageProxy);
        mcf.setFunctionsOracle(functionsOracle);
        mcf.setCoreSender(payable(coreSenderProxy));
        mcf.setIndexToken(indexToken);
        mcf.setOrderManager(orderManager);
        mcf.setWethAddress(weth);
        mcf.setUsdcAddress(usdc);
        mcf.setIndexFactoryStorage(indexFactoryStorage);
    }

    function _chainPrefix(string memory targetChain) internal pure returns (string memory) {
        if (keccak256(bytes(targetChain)) == keccak256("arbitrum_mainnet")) {
            return "ARBITRUM";
        }
        return "SEPOLIA";
    }
}

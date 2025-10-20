// // SPDX-License-Identifier: MIT
// pragma solidity 0.8.25;

// import {Script} from "forge-std/Script.sol";
// import {console} from "forge-std/console.sol";

// import {DinariStorage} from "../../src/dinari/DinariStorage.sol";
// import {BackedFiStorage} from "../../src/backedfi/BackedFiStorage.sol";
// import {StagingCustodyAccount} from "../../src/backedfi/StagingCustodyAccount.sol";
// import {MainChainStorage} from "../../src/ccip/MainChainStorage.sol";
// import {CrossChainIndexFactoryStorage} from "../../src/ccip/CrossChainIndexFactoryStorage.sol";
// import {CrossChainIndexFactory} from "../../src/ccip/CrossChainIndexFactory.sol";
// import {BalancerSender} from "../../src/ccip/BalancerSender.sol";
// import {CoreSender} from "../../src/ccip/CoreSender.sol";
// import {MainChainBalancer} from "../../src/ccip/MainChainBalancer.sol";
// import {MainChainFactory} from "../../src/ccip/MainChainFactory.sol";

// contract ConfigureProviderSetters is Script {
//     function run() external {
//         uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
//         string memory targetChain = vm.envOr("TARGET_CHAIN", string("sepolia"));

//         vm.startBroadcast(deployerPrivateKey);

//         _configureDinari(targetChain);
//         _configureBackedFi(targetChain);
//         _configureCcip(targetChain);

//         vm.stopBroadcast();
//     }

//     function _configureDinari(string memory targetChain) internal {
//         string memory prefix = _chainPrefix(targetChain);
//         address storageProxy = vm.envAddress(string.concat(prefix, "_DINARI_STORAGE_PROXY_ADDRESS"));
//         address factoryProxy = vm.envAddress(string.concat(prefix, "_DINARI_FACTORY_PROXY_ADDRESS"));
//         address indexFactoryBalancer = vm.envAddress(string.concat(prefix, "_INDEX_FACTORY_BALANCER_PROXY_ADDRESS"));

//         DinariStorage storageContract = DinariStorage(storageProxy);
//         storageContract.setFactory(factoryProxy);
//         storageContract.setFactoryBalancer(indexFactoryBalancer);

//         console.log("Configured DinariStorage setters");
//     }

//     function _configureBackedFi(string memory targetChain) internal {
//         string memory prefix = _chainPrefix(targetChain);
//         address storageProxy = vm.envAddress(string.concat(prefix, "_BACKEDFI_STORAGE_PROXY_ADDRESS"));
//         address scaProxy = vm.envAddress(string.concat(prefix, "_STAGING_CUSTODY_ACCOUNT_PROXY_ADDRESS"));
//         address functionsOracle = vm.envAddress(string.concat(prefix, "_FUNCTIONS_ORACLE_PROXY_ADDRESS"));
//         address indexFactory = vm.envAddress(string.concat(prefix, "_INDEX_FACTORY_PROXY_ADDRESS"));
//         address nexBot = vm.envAddress(string.concat(prefix, "_NEX_BOT_ADDRESS"));

//         BackedFiStorage storageContract = BackedFiStorage(storageProxy);
//         storageContract.setFunctionsOracle(functionsOracle);
//         storageContract.setIndexFactory(indexFactory);
//         storageContract.setNexBotAddress(nexBot);
//         storageContract.setSCA(scaProxy);

//         StagingCustodyAccount(scaProxy).setBackedFiStorageAddress(storageProxy);

//         console.log("Configured BackedFi setters");
//     }

//     function _configureCcip(string memory targetChain) internal {
//         string memory prefix = _chainPrefix(targetChain);
//         address mainChainStorageProxy = vm.envAddress(string.concat(prefix, "_MAIN_CHAIN_STORAGE_PROXY_ADDRESS"));
//         address crossChainStorageProxy =
//             vm.envAddress(string.concat(prefix, "_CROSS_CHAIN_INDEX_FACTORY_STORAGE_PROXY_ADDRESS"));
//         address crossChainFactoryProxy =
//             vm.envAddress(string.concat(prefix, "_CROSS_CHAIN_INDEX_FACTORY_PROXY_ADDRESS"));
//         address balancerSenderProxy = vm.envAddress(string.concat(prefix, "_BALANCER_SENDER_PROXY_ADDRESS"));
//         address coreSenderProxy = vm.envAddress(string.concat(prefix, "_CORE_SENDER_PROXY_ADDRESS"));
//         address mainChainBalancerProxy = vm.envAddress(string.concat(prefix, "_MAIN_CHAIN_BALANCER_PROXY_ADDRESS"));
//         address mainChainFactoryProxy = vm.envAddress(string.concat(prefix, "_MAIN_CHAIN_FACTORY_PROXY_ADDRESS"));
//         address indexFactoryBalancer = vm.envAddress(string.concat(prefix, "_INDEX_FACTORY_BALANCER_PROXY_ADDRESS"));

//         uint64 chainSelector = uint64(vm.envUint(string.concat(prefix, "_CCIP_CHAIN_SELECTOR")));
//         address functionsOracle = vm.envAddress(string.concat(prefix, "_FUNCTIONS_ORACLE_PROXY_ADDRESS"));
//         address vault = vm.envAddress(string.concat(prefix, "_VAULT_PROXY_ADDRESS"));
//         address indexToken = vm.envAddress(string.concat(prefix, "_INDEX_TOKEN_PROXY_ADDRESS"));
//         address orderManager = vm.envAddress(string.concat(prefix, "_ORDER_MANAGER_PROXY_ADDRESS"));
//         address weth = vm.envAddress(string.concat(prefix, "_WETH_ADDRESS"));

//         MainChainStorage mcs = MainChainStorage(mainChainStorageProxy);
//         mcs.setIndexFactory(mainChainFactoryProxy);
//         mcs.setCoreSender(coreSenderProxy);
//         mcs.setBalancerSender(balancerSenderProxy);
//         mcs.setMainChainBalancer(mainChainBalancerProxy);
//         mcs.setVault(vault);
//         mcs.setCrossChainFactory(crossChainFactoryProxy, chainSelector);

//         CrossChainIndexFactoryStorage ccifs = CrossChainIndexFactoryStorage(crossChainStorageProxy);
//         ccifs.setCrossChainFactory(crossChainFactoryProxy);
//         ccifs.setVault(payable(vault));

//         CrossChainIndexFactory(payable(crossChainFactoryProxy)).setCrossChainIndexFactoryStorage(crossChainStorageProxy);

//         BalancerSender bs = BalancerSender(payable(balancerSenderProxy));
//         bs.setMainChainStorage(mainChainStorageProxy);
//         bs.setFunctionsOracle(functionsOracle);
//         bs.setIndexFactoryBalancer(indexFactoryBalancer);

//         CoreSender cs = CoreSender(payable(coreSenderProxy));
//         cs.setMainChainStorage(mainChainStorageProxy);
//         cs.setFunctionsOracle(functionsOracle);

//         MainChainBalancer mcb = MainChainBalancer(mainChainBalancerProxy);
//         mcb.setMainChainStorage(mainChainStorageProxy);
//         mcb.setFunctionsOracle(functionsOracle);
//         mcb.setBalancerSender(payable(balancerSenderProxy));
//         mcb.setIndexFactoryBalancer(indexFactoryBalancer);

//         MainChainFactory mcf = MainChainFactory(payable(mainChainFactoryProxy));
//         mcf.setMainChainStorage(mainChainStorageProxy);
//         mcf.setFunctionsOracle(functionsOracle);
//         mcf.setCoreSender(payable(coreSenderProxy));
//         mcf.setIndexToken(indexToken);
//         mcf.setOrderManager(orderManager);
//         mcf.setWethAddress(weth);

//         console.log("Configured CCIP setters");
//     }

//     function _chainPrefix(string memory targetChain) internal pure returns (string memory) {
//         if (keccak256(bytes(targetChain)) == keccak256("arbitrum_mainnet")) {
//             return "ARBITRUM";
//         }
//         return "SEPOLIA";
//     }
// }

// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import "openzeppelin-foundry-upgrades/Upgrades.sol";

import "../../../src/backedfi/BackedFiStorage.sol";
import "../../../src/backedfi/BackedFiBalancer.sol";
import {BackedFiFactory} from "../../../src/backedfi/BackedFiFactory.sol";
import {StagingCustodyAccount} from "../../../src/backedfi/StagingCustodyAccount.sol";

contract DeployBackedFiAll is Script {
    BackedFiStorage public backedFiStorage;
    BackedFiBalancer public backedFiBalancer;
    BackedFiFactory public backedFiFactory;
    StagingCustodyAccount public stagingCustodyAccount;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.addr(deployerPrivateKey);
        string memory targetChain = "sepolia";

        address indexFactoryProxy;
        address functionsOracleProxy;
        address indexFactoryStorageProxy;
        address nexBot;
        address usdcToken;
        uint8 providerIndex;

        if (keccak256(bytes(targetChain)) == keccak256("sepolia")) {
            indexFactoryProxy = vm.envAddress("SEPOLIA_INDEX_FACTORY_PROXY_ADDRESS");
            functionsOracleProxy = vm.envAddress("SEPOLIA_FUNCTIONS_ORACLE_PROXY_ADDRESS");
            indexFactoryStorageProxy = vm.envAddress("SEPOLIA_INDEX_FACTORY_STORAGE_PROXY_ADDRESS");
            nexBot = vm.envAddress("SEPOLIA_NEX_BOT_ADDRESS");
            usdcToken = vm.envAddress("SEPOLIA_USDC_ADDRESS");
            providerIndex = uint8(vm.envUint("SEPOLIA_BACKEDFI_PROVIDER_INDEX"));
        } else if (keccak256(bytes(targetChain)) == keccak256("arbitrum_mainnet")) {
            indexFactoryProxy = vm.envAddress("ARBITRUM_INDEX_FACTORY_PROXY_ADDRESS");
            functionsOracleProxy = vm.envAddress("ARBITRUM_FUNCTIONS_ORACLE_PROXY_ADDRESS");
            indexFactoryStorageProxy = vm.envAddress("ARBITRUM_INDEX_FACTORY_STORAGE_PROXY_ADDRESS");
            nexBot = vm.envAddress("ARBITRUM_NEX_BOT_ADDRESS");
            usdcToken = vm.envAddress("ARBITRUM_USDC_ADDRESS");
            providerIndex = uint8(vm.envUint("ARBITRUM_BACKEDFI_PROVIDER_INDEX"));
        } else {
            revert("Unsupported target chain");
        }

        vm.startBroadcast(deployerPrivateKey);

        bytes memory noInitData = "";

        address backedFiStorageProxy = Upgrades.deployTransparentProxy("BackedFiStorage.sol", owner, noInitData);
        address stagingProxy = Upgrades.deployTransparentProxy("StagingCustodyAccount.sol", owner, noInitData);
        address backedFiBalancerProxy = Upgrades.deployTransparentProxy("BackedFiBalancer.sol", owner, noInitData);
        address backedFiFactoryProxy = Upgrades.deployTransparentProxy("BackedFiFactory.sol", owner, noInitData);

        backedFiStorage = BackedFiStorage(backedFiStorageProxy);
        stagingCustodyAccount = StagingCustodyAccount(stagingProxy);
        backedFiBalancer = BackedFiBalancer(backedFiBalancerProxy);
        backedFiFactory = BackedFiFactory(backedFiFactoryProxy);

        backedFiStorage.initialize(
            indexFactoryProxy, functionsOracleProxy, stagingProxy, nexBot, usdcToken, providerIndex
        );

        stagingCustodyAccount.initialize(backedFiStorageProxy);

        backedFiBalancer.initialize(backedFiStorageProxy, functionsOracleProxy, indexFactoryStorageProxy);

        backedFiFactory.initialize(backedFiStorageProxy);

        console.log("BackedFiStorage proxy deployed at:", backedFiStorageProxy);
        console.log("BackedFiStorage ProxyAdmin:", Upgrades.getAdminAddress(backedFiStorageProxy));

        console.log("StagingCustodyAccount proxy deployed at:", stagingProxy);
        console.log("StagingCustodyAccount ProxyAdmin:", Upgrades.getAdminAddress(stagingProxy));

        console.log("BackedFiBalancer proxy deployed at:", backedFiBalancerProxy);
        console.log("BackedFiBalancer ProxyAdmin:", Upgrades.getAdminAddress(backedFiBalancerProxy));

        console.log("BackedFiFactory proxy deployed at:", backedFiFactoryProxy);
        console.log("BackedFiFactory ProxyAdmin:", Upgrades.getAdminAddress(backedFiFactoryProxy));

        vm.stopBroadcast();
    }
}

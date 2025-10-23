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

        vm.startBroadcast(deployerPrivateKey);

        string memory prefix = _envPrefix(targetChain);

        address backedFiStorageProxy = _deployProxy("BackedFiStorage.sol", owner);
        address stagingProxy = _deployProxy("StagingCustodyAccount.sol", owner);
        address backedFiBalancerProxy = _deployProxy("BackedFiBalancer.sol", owner);
        address backedFiFactoryProxy = _deployProxy("BackedFiFactory.sol", owner);

        backedFiStorage = BackedFiStorage(backedFiStorageProxy);
        stagingCustodyAccount = StagingCustodyAccount(stagingProxy);
        backedFiBalancer = BackedFiBalancer(backedFiBalancerProxy);
        backedFiFactory = BackedFiFactory(backedFiFactoryProxy);

        _initializeBackedFiStorage(prefix, backedFiStorageProxy, stagingProxy);
        _initializeStagingCustodyAccount(backedFiStorageProxy, stagingProxy);
        _initializeBackedFiBalancer(prefix, backedFiStorageProxy, backedFiBalancerProxy);
        _initializeBackedFiFactory(backedFiStorageProxy, backedFiFactoryProxy);

        _logAddresses(backedFiStorageProxy, stagingProxy, backedFiBalancerProxy, backedFiFactoryProxy);

        vm.stopBroadcast();
    }

    function _deployProxy(string memory contractName, address owner) internal returns (address) {
        bytes memory noInitData = "";
        return Upgrades.deployTransparentProxy(contractName, owner, noInitData);
    }

    function _envPrefix(string memory targetChain) internal pure returns (string memory) {
        if (keccak256(bytes(targetChain)) == keccak256("arbitrum_mainnet")) {
            return "ARBITRUM";
        }
        return "SEPOLIA";
    }

    function _envAddr(string memory prefix, string memory suffix) internal view returns (address) {
        return vm.envAddress(string.concat(prefix, suffix));
    }

    function _initializeBackedFiStorage(
        string memory prefix,
        address backedFiStorageProxy,
        address stagingProxy
    ) internal {
        BackedFiStorage bfs = BackedFiStorage(backedFiStorageProxy);
        address indexFactoryProxy = _envAddr(prefix, "_INDEX_FACTORY_PROXY_ADDRESS");
        address functionsOracleProxy = _envAddr(prefix, "_FUNCTIONS_ORACLE_PROXY_ADDRESS");
        address nexBot = _envAddr(prefix, "_NEX_BOT_ADDRESS");
        address usdcToken = _envAddr(prefix, "_USDC_ADDRESS");
        uint8 providerIndex = uint8(vm.envUint(string.concat(prefix, "_BACKEDFI_PROVIDER_INDEX")));
        bfs.initialize(indexFactoryProxy, functionsOracleProxy, stagingProxy, nexBot, usdcToken, providerIndex);
    }

    function _initializeStagingCustodyAccount(address backedFiStorageProxy, address stagingProxy) internal {
        StagingCustodyAccount(stagingProxy).initialize(backedFiStorageProxy);
    }

    function _initializeBackedFiBalancer(
        string memory prefix,
        address backedFiStorageProxy,
        address backedFiBalancerProxy
    ) internal {
        address functionsOracleProxy = _envAddr(prefix, "_FUNCTIONS_ORACLE_PROXY_ADDRESS");
        address indexFactoryStorageProxy = _envAddr(prefix, "_INDEX_FACTORY_STORAGE_PROXY_ADDRESS");
        BackedFiBalancer(backedFiBalancerProxy).initialize(
            backedFiStorageProxy, functionsOracleProxy, indexFactoryStorageProxy
        );
    }

    function _initializeBackedFiFactory(address backedFiStorageProxy, address backedFiFactoryProxy) internal {
        BackedFiFactory(backedFiFactoryProxy).initialize(backedFiStorageProxy);
    }

    function _logAddresses(
        address backedFiStorageProxy,
        address stagingProxy,
        address backedFiBalancerProxy,
        address backedFiFactoryProxy
    ) internal view {
        console.log("BackedFiStorage proxy deployed at:", backedFiStorageProxy);
        console.log("BackedFiStorage ProxyAdmin:", Upgrades.getAdminAddress(backedFiStorageProxy));

        console.log("StagingCustodyAccount proxy deployed at:", stagingProxy);
        console.log("StagingCustodyAccount ProxyAdmin:", Upgrades.getAdminAddress(stagingProxy));

        console.log("BackedFiBalancer proxy deployed at:", backedFiBalancerProxy);
        console.log("BackedFiBalancer ProxyAdmin:", Upgrades.getAdminAddress(backedFiBalancerProxy));

        console.log("BackedFiFactory proxy deployed at:", backedFiFactoryProxy);
        console.log("BackedFiFactory ProxyAdmin:", Upgrades.getAdminAddress(backedFiFactoryProxy));
    }
}

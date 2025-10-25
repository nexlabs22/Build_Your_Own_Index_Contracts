// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {CrossChainIndexFactoryStorage} from "../../../src/ccip/CrossChainIndexFactoryStorage.sol";
import {CrossChainIndexFactory} from "../../../src/ccip/CrossChainIndexFactory.sol";
import {CrossChainIndexFactoryBalancer} from "../../../src/ccip/CrossChainIndexFactoryBalancer.sol";

contract ConfigureCrossChainSetters is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        string memory targetChain = vm.envOr("TARGET_CHAIN", string("sepolia"));

        vm.startBroadcast(deployerPrivateKey);

        _configureCrossChainContracts(targetChain);

        vm.stopBroadcast();
    }

    function _configureCrossChainContracts(string memory targetChain) internal {
        string memory prefix = _chainPrefix(targetChain);

        address crossChainStorageProxy =
            vm.envAddress(string.concat(prefix, "_CROSS_CHAIN_INDEX_FACTORY_STORAGE_PROXY_ADDRESS"));
        address crossChainFactoryProxy =
            vm.envAddress(string.concat(prefix, "_CROSS_CHAIN_INDEX_FACTORY_PROXY_ADDRESS"));
        address crossChainBalancerProxy =
            vm.envAddress(string.concat(prefix, "_CROSS_CHAIN_INDEX_FACTORY_BALANCER_PROXY_ADDRESS"));

        CrossChainIndexFactoryStorage storageContract = CrossChainIndexFactoryStorage(crossChainStorageProxy);
        storageContract.setCrossChainFactory(crossChainFactoryProxy);
        storageContract.setCrossChainFactoryBalancer(crossChainBalancerProxy);

        CrossChainIndexFactory(payable(crossChainFactoryProxy)).setCrossChainIndexFactoryStorage(crossChainStorageProxy);

        CrossChainIndexFactoryBalancer balancer = CrossChainIndexFactoryBalancer(payable(crossChainBalancerProxy));
        balancer.setCrossChainIndexFactoryStorage(crossChainStorageProxy);

        console.log("Configured cross-chain contracts for prefix:", prefix);
    }

    function _chainPrefix(string memory targetChain) internal pure returns (string memory) {
        if (keccak256(bytes(targetChain)) == keccak256("arbitrum_mainnet")) {
            return "ARBITRUM";
        }
        return "SEPOLIA";
    }
}

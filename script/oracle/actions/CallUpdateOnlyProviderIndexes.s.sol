// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {FunctionsOracle} from "../../../src/oracle/FunctionsOracle.sol";

contract CallUpdateOnlyProviderIndexes is Script {
    using stdJson for string;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        string memory targetChain = vm.envOr("TARGET_CHAIN", string("arbitrum_mainnet"));
        address oracle = _functionsOracle(targetChain);

        // Dinari
        // address[] memory tokens = new address[](2);
        // tokens[0] = 0xCe38e140fC3982a6bCEbc37b040913EF2Cd6C5a7; // APPLE
        // tokens[1] = 0x77308F8B63A99b24b262D930E0218ED2f49F8475; // MSFT

        // uint64[] memory providerIndexes = new uint64[](2);
        // providerIndexes[0] = 2;
        // providerIndexes[1] = 2;

        address[] memory tokens = new address[](2);
        tokens[0] = 0xCe38e140fC3982a6bCEbc37b040913EF2Cd6C5a7;
        tokens[1] = 0x77308F8B63A99b24b262D930E0218ED2f49F8475;

        uint64[] memory providerIndexes = new uint64[](2);
        providerIndexes[0] = 1;
        providerIndexes[1] = 1;

        console.log("Calling updateOnlyProviderIndexes on:", oracle);
        vm.startBroadcast(deployerPrivateKey);
        FunctionsOracle(oracle).updateOnlyProviderIndexes(tokens, providerIndexes);
        vm.stopBroadcast();
    }

    function _functionsOracle(string memory targetChain) internal view returns (address) {
        string memory prefix = _envPrefix(targetChain);
        return vm.envAddress(string.concat(prefix, "_FUNCTIONS_ORACLE_PROXY_ADDRESS"));
    }

    function _envPrefix(string memory targetChain) internal pure returns (string memory) {
        bytes32 chainHash = keccak256(bytes(targetChain));
        if (chainHash == keccak256("arbitrum_mainnet")) {
            return "ARBITRUM";
        }
        if (chainHash == keccak256("sepolia")) {
            return "SEPOLIA";
        }
        return "";
    }

    function _toUint64Array(uint256[] memory values) internal pure returns (uint64[] memory out) {
        out = new uint64[](values.length);
        for (uint256 i = 0; i < values.length; i++) {
            out[i] = uint64(values[i]);
        }
    }
}


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
        string memory targetChain = vm.envOr("TARGET_CHAIN", string("arbitrum_sepolia"));
        address oracle = _functionsOracle(targetChain);

        string memory jsonPath = vm.envString("UPDATE_PROVIDER_INDEXES_JSON");
        string memory json = vm.readFile(jsonPath);

        address[] memory tokens = abi.decode(json.parseRaw(".tokens"), (address[]));
        uint64[] memory providerIndexes = _toUint64Array(abi.decode(json.parseRaw(".providerIndexes"), (uint256[])));

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
        if (chainHash == keccak256("arbitrum_sepolia")) {
            return "ARBITRUM_SEPOLIA";
        }
        return "SEPOLIA";
    }

    function _toUint64Array(uint256[] memory values) internal pure returns (uint64[] memory out) {
        out = new uint64[](values.length);
        for (uint256 i = 0; i < values.length; i++) {
            out[i] = uint64(values[i]);
        }
    }
}


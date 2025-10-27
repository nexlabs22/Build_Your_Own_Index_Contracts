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
        string memory targetChain = vm.envOr("TARGET_CHAIN", string("sepolia"));
        address oracle = _functionsOracle(targetChain);

        // Dinari
        // address[] memory tokens = new address[](5);
        // tokens[0] = 0xD771a71E5bb303da787b4ba2ce559e39dc6eD85c;
        // tokens[1] = 0x18aD1A35134F813fBEB4526d655D9d39783512D2;
        // tokens[2] = 0x4B47153A241b9d22ae37c2aAEe7A6519fF2Dbfc6;
        // tokens[3] = 0x92d95BCB50B83d488bBFA18776ADC1553d3a8914;
        // tokens[4] = 0x8c7074B3e3DF4C51c52c164b574aD782468eB168;

        // uint64[] memory providerIndexes = new uint64[](5);
        // providerIndexes[0] = 2;
        // providerIndexes[1] = 2;
        // providerIndexes[2] = 2;
        // providerIndexes[3] = 2;
        // providerIndexes[4] = 2;

        // CCIP
        address[] memory tokens = new address[](2);
        tokens[0] = 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14; // WETH
        tokens[1] = 0x6Ea5aD162d5b74Bc9e4C3e4eEB18AE6861407221; // WBTC

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
        return "SEPOLIA";
    }

    function _toUint64Array(uint256[] memory values) internal pure returns (uint64[] memory out) {
        out = new uint64[](values.length);
        for (uint256 i = 0; i < values.length; i++) {
            out[i] = uint64(values[i]);
        }
    }
}


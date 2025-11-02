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
        // address[] memory tokens = new address[](2);
        // tokens[0] = 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14; // WETH
        // tokens[1] = 0x6Ea5aD162d5b74Bc9e4C3e4eEB18AE6861407221; // WBTC

        // uint64[] memory providerIndexes = new uint64[](2);
        // providerIndexes[0] = 1;
        // providerIndexes[1] = 1;

        // Meme Coin
        address[] memory tokens = new address[](16);
        tokens[0] = 0xb98b795Da5c9f393334E6739eEEAB49D6005aA6D; // FLOKI
        tokens[1] = 0x4CD1A3DcB3e78A99bE97efE12E5F128f53A5b461; // Pump fun
        tokens[2] = 0xb011e00dd41C06A342977a16AAE3d25dB054e437; // Shiba Inu
        tokens[3] = 0x6A69e067c01A9833374Cd568A914B2e68C87a7Ca; // DogeCoin
        tokens[4] = 0x279a0D60d4234F9BD6B4e7119F51BBa4894db4A1; // Baby Doge arb sepolia
        tokens[5] = 0x81E0B589284a23366681E14476f37653b23D6d9e; // Trump arb sepolia
        tokens[6] = 0x52cb60E9aef89Df38880B7eB925485b03B345640; // Pepe
        tokens[7] = 0xD771a71E5bb303da787b4ba2ce559e39dc6eD85c; // APPLE
        tokens[8] = 0x18aD1A35134F813fBEB4526d655D9d39783512D2; // MSFT
        tokens[9] = 0x4B47153A241b9d22ae37c2aAEe7A6519fF2Dbfc6; // NVDIA
        tokens[10] = 0x92d95BCB50B83d488bBFA18776ADC1553d3a8914; // AMZN
        tokens[11] = 0x8c7074B3e3DF4C51c52c164b574aD782468eB168; // GOOGLE
        tokens[12] = 0xC470cfBc19Ec46180ceb7D165A064B186d5fDF14; // META
        tokens[13] = 0xa44c4115d7DeF2da38fBc91B0f3A923440610C52; // TSLA
        tokens[14] = 0x6Ea5aD162d5b74Bc9e4C3e4eEB18AE6861407221; // BTC
        tokens[15] = 0x0C3711069cf889Fc47B3Da3700fFFDc2e16A4DaD; // XAUT

        uint64[] memory providerIndexes = new uint64[](16);
        providerIndexes[0] = 1;
        providerIndexes[1] = 1;
        providerIndexes[2] = 1;
        providerIndexes[3] = 1;
        providerIndexes[4] = 1;
        providerIndexes[5] = 1;
        providerIndexes[6] = 1;
        providerIndexes[7] = 2;
        providerIndexes[8] = 2;
        providerIndexes[9] = 2;
        providerIndexes[10] = 2;
        providerIndexes[11] = 2;
        providerIndexes[12] = 2;
        providerIndexes[13] = 2;
        providerIndexes[14] = 1;
        providerIndexes[15] = 1;

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


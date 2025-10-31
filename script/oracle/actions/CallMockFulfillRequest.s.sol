// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {FunctionsOracle} from "../../../src/oracle/FunctionsOracle.sol";

contract CallMockFulfillRequest is Script {
    using stdJson for string;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        string memory targetChain = vm.envOr("TARGET_CHAIN", string("sepolia"));
        address oracle = _functionsOracle(targetChain);

        // Dinari
        // address[] memory indexTokens = new address[](5);
        // indexTokens[0] = 0x4e835FDB96830626e5Ba490f43CFb7274C146691;
        // indexTokens[1] = 0x4e835FDB96830626e5Ba490f43CFb7274C146691;
        // indexTokens[2] = 0x4e835FDB96830626e5Ba490f43CFb7274C146691;
        // indexTokens[3] = 0x4e835FDB96830626e5Ba490f43CFb7274C146691;
        // indexTokens[4] = 0x4e835FDB96830626e5Ba490f43CFb7274C146691;

        // address[] memory tokens = new address[](5);
        // tokens[0] = 0xD771a71E5bb303da787b4ba2ce559e39dc6eD85c;
        // tokens[1] = 0x18aD1A35134F813fBEB4526d655D9d39783512D2;
        // tokens[2] = 0x4B47153A241b9d22ae37c2aAEe7A6519fF2Dbfc6;
        // tokens[3] = 0x92d95BCB50B83d488bBFA18776ADC1553d3a8914;
        // tokens[4] = 0x8c7074B3e3DF4C51c52c164b574aD782468eB168;

        // uint256[] memory marketShares = new uint256[](5);
        // marketShares[0] = 30e18;
        // marketShares[1] = 10e18;
        // marketShares[2] = 20e18;
        // marketShares[3] = 20e18;
        // marketShares[4] = 20e18;

        // CCIP
        // address[] memory indexTokens = new address[](2);
        // indexTokens[0] = 0x3A1696F9A7b3140dB3e328654f914c07e55Ee793;
        // indexTokens[1] = 0x3A1696F9A7b3140dB3e328654f914c07e55Ee793;

        // address[] memory tokens = new address[](2);
        // tokens[0] = 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14; // WETH
        // tokens[1] = 0x6Ea5aD162d5b74Bc9e4C3e4eEB18AE6861407221; // WBTC

        // uint256[] memory marketShares = new uint256[](2);
        // marketShares[0] = 50e18;
        // marketShares[1] = 50e18;

        // CCIP CrossChain
        // address[] memory indexTokens = new address[](2);
        // indexTokens[0] = 0x7f878aD42333E07F122b9f6E1C778C5353e9f1B4;
        // indexTokens[1] = 0x7f878aD42333E07F122b9f6E1C778C5353e9f1B4;

        // address[] memory tokens = new address[](2);
        // tokens[0] = 0xf4A357354fab7DEAC6fAa1992d84138704C01f45; // XRP
        // tokens[1] = 0x0C3711069cf889Fc47B3Da3700fFFDc2e16A4DaD; // XAUT

        // uint256[] memory marketShares = new uint256[](2);
        // marketShares[0] = 50e18;
        // marketShares[1] = 50e18;

        // // CCIP + Stock
        address[] memory indexTokens = new address[](4);
        indexTokens[0] = 0x32d89568718643C212bF8F2dCC0bad76723A64fd;
        indexTokens[1] = 0x32d89568718643C212bF8F2dCC0bad76723A64fd;
        indexTokens[2] = 0x32d89568718643C212bF8F2dCC0bad76723A64fd;
        indexTokens[3] = 0x32d89568718643C212bF8F2dCC0bad76723A64fd;

        address[] memory tokens = new address[](4);
        tokens[0] = 0x6Ea5aD162d5b74Bc9e4C3e4eEB18AE6861407221; // BTC
        tokens[1] = 0xD771a71E5bb303da787b4ba2ce559e39dc6eD85c; // APPLE
        tokens[2] = 0x18aD1A35134F813fBEB4526d655D9d39783512D2; // Advanced Micro Devices
        tokens[3] = 0x0C3711069cf889Fc47B3Da3700fFFDc2e16A4DaD; // XAUT

        uint256[] memory marketShares = new uint256[](4);
        marketShares[0] = 30e18;
        marketShares[1] = 20e18;
        marketShares[2] = 20e18;
        marketShares[3] = 30e18;

        require(indexTokens.length == tokens.length, "length mismatch");
        require(tokens.length == marketShares.length, "length mismatch");

        console.log("Calling mockFulfillRequest on:", oracle);
        vm.startBroadcast(deployerPrivateKey);
        FunctionsOracle(oracle).mockFulfillRequest(indexTokens, tokens, marketShares);
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
}


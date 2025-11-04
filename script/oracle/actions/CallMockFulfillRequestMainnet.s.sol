// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {FunctionsOracle} from "../../../src/oracle/FunctionsOracle.sol";

contract CallMockFulfillRequestMainnet is Script {
    using stdJson for string;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        string memory targetChain = vm.envOr("TARGET_CHAIN", string("arbitrum_mainnet"));
        address oracle = _functionsOracle(targetChain);

        // Dinari
        // address[] memory indexTokens = new address[](2);
        // indexTokens[0] = 0x2E4150CFBdF6A37b55d07e81F6d3f4D47648D52A;
        // indexTokens[1] = 0x2E4150CFBdF6A37b55d07e81F6d3f4D47648D52A;

        // address[] memory tokens = new address[](2);
        // tokens[0] = 0xCe38e140fC3982a6bCEbc37b040913EF2Cd6C5a7; // APPLE
        // tokens[1] = 0x77308F8B63A99b24b262D930E0218ED2f49F8475; // MSFT

        // uint256[] memory marketShares = new uint256[](2);
        // marketShares[0] = 50e18;
        // marketShares[1] = 50e18;

        // CCIP
        address[] memory indexTokens = new address[](2);
        indexTokens[0] = 0x112cdC1651C455032a1bB85C5CdD8Cd0C12A8aE1;
        indexTokens[1] = 0x112cdC1651C455032a1bB85C5CdD8Cd0C12A8aE1;

        address[] memory tokens = new address[](2);
        tokens[0] = 0xFa7F8980b0f1E64A2062791cc3b0871572f1F7f0; // UNI
        tokens[1] = 0xba5DdD1f9d7F570dc94a51479a000E3BCE967196; // AAVE

        uint256[] memory marketShares = new uint256[](2);
        marketShares[0] = 60e18;
        marketShares[1] = 40e18;

        // CrossChain CCIP
        // address[] memory indexTokens = new address[](2);
        // indexTokens[0] = 0x2EC6821b03e2DB6326E585baCbB9df14058eDbd2;
        // indexTokens[1] = 0x2EC6821b03e2DB6326E585baCbB9df14058eDbd2;

        // address[] memory tokens = new address[](2);
        // tokens[0] = 0x1111111111166b7FE7bd91427724B487980aFc69; // ZORA
        // tokens[1] = 0xAC1Bd2486aAf3B5C0fc3Fd868558b082a531B2B4; // TOSHI

        // uint256[] memory marketShares = new uint256[](2);
        // marketShares[0] = 50e18;
        // marketShares[1] = 50e18;

        require(indexTokens.length == tokens.length, "length mismatch");
        require(tokens.length == marketShares.length, "length mismatch");

        console.log("Mainnet Calling mockFulfillRequest on:", oracle);
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
        return "";
    }
}


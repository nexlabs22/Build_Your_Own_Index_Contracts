// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {FunctionsOracle} from "../../../src/oracle/FunctionsOracle.sol";

contract CallUpdatePathData is Script {
    using stdJson for string;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        string memory targetChain = vm.envOr("TARGET_CHAIN", string("sepolia"));
        address oracle = _functionsOracle(targetChain);

        address[] memory assets = new address[](2);

        uint64[] memory providers = new uint64[](assets.length);
        uint64[] memory chains = new uint64[](assets.length);
        bytes[] memory pathBytes = new bytes[](assets.length);
        uint24[] memory fees = new uint24[](1);
        fees[0] = 3000;

        address weth = 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14;

        for (uint256 i = 0; i < assets.length; i++) {
            providers[i] = uint64(2);
            chains[i] = 16015286601757825753;
            address[] memory path = new address[](2);
            path[0] = address(weth);
            path[1] = assets[i];
            pathBytes[i] = abi.encode(path, fees);
        }

        console.log("Calling updatePathData on:", oracle);
        vm.startBroadcast(deployerPrivateKey);
        FunctionsOracle(oracle).updatePathData(providers, chains, pathBytes);
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

    function _toUint24Array(uint256[] memory values) internal pure returns (uint24[] memory out) {
        out = new uint24[](values.length);
        for (uint256 i = 0; i < values.length; i++) {
            out[i] = uint24(values[i]);
        }
    }
}


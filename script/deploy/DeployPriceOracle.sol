// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/Test.sol";

import {PriceOracleByteCode} from "../../src/test/PriceOracleByteCode.sol";

contract DeployPriceOracle is Script, PriceOracleByteCode {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        address priceOracle = deployByteCode(priceOracleByteCode);

        console.log("PriceOracle implementation deployed at:", address(priceOracle));

        vm.stopBroadcast();
    }

    function deployByteCode(bytes memory bytecode) public returns (address) {
        bytes memory bytecodeWithArgs = bytecode;
        address deployedContract;
        assembly {
            deployedContract := create(0, add(bytecodeWithArgs, 0x20), mload(bytecodeWithArgs))
        }

        return deployedContract;
    }
}

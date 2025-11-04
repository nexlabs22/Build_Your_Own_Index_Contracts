// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/Test.sol";

// import {PriceOracleByteCode} from "../../src/test/PriceOracleByteCode.sol";
import "../../src/test/UniswapRouterByteCode.sol";

contract DeploySwapRouter is Script, UniswapRouterByteCode {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        address routerAddress = deployRouter();
        console.log("SwapRouter Address: ", routerAddress);

        vm.stopBroadcast();
    }

    function deployRouter() internal returns (address) {
        // address factoryV3 = 0x33128a8fC17869897dcE68Ed026d694621f6FDfD;
        // address wethAddress = 0x4200000000000000000000000000000000000006;
        address factoryV3 = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
        address wethAddress = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
        address routerAddress = deployByteCodeWithInputs(routerByteCode, abi.encode(factoryV3, wethAddress));
        return routerAddress;
    }

    function deployByteCodeWithInputs(bytes memory bytecode, bytes memory _initData) public returns (address) {
        bytes memory bytecodeWithArgs = abi.encodePacked(bytecode, _initData);
        address deployedContract;
        assembly {
            deployedContract := create(0, add(bytecodeWithArgs, 0x20), mload(bytecodeWithArgs))
        }

        return deployedContract;
    }
}

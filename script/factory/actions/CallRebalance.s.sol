// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IndexFactoryBalancer} from "../../../src/factory/IndexFactoryBalancer.sol";
// import "../../../src/dinari/DinariFactoryProcessor.sol";

contract CallRebalance is Script {
    // CCIP
    // address indexToken = 0x3A1696F9A7b3140dB3e328654f914c07e55Ee793;

    // CCIP CrossChain
    // address indexToken = 0x7f878aD42333E07F122b9f6E1C778C5353e9f1B4;

    // Dinari
    address indexToken = 0x4e835FDB96830626e5Ba490f43CFb7274C146691;

    address indexFactoryBalancer = 0x584c18fe1f57c5589E011b8b56D7b23a78fe9Fab;

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(pk);

        askValues();
        firstRebalance();

        vm.stopBroadcast();
    }

    function askValues() public {
        IndexFactoryBalancer(indexFactoryBalancer).askValues(indexToken);
    }

    function firstRebalance() public {
        IndexFactoryBalancer(indexFactoryBalancer).firstReweightAction(indexToken, 5);
    }
}

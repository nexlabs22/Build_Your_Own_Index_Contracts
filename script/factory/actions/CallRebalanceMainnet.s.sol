// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IndexFactoryBalancer} from "../../../src/factory/IndexFactoryBalancer.sol";
import "../../../src/dinari/DinariBalancer.sol";
import "../../../src/ccip/MainChainBalancer.sol";
// import "../../../src/dinari/DinariFactoryProcessor.sol";

contract CallRebalance is Script {
    // Dinari
    // address indexToken = 0x2E4150CFBdF6A37b55d07e81F6d3f4D47648D52A;

    // CCIP
    // address indexToken = 0x112cdC1651C455032a1bB85C5CdD8Cd0C12A8aE1;

    // CrossChain
    // address indexToken = 0x2EC6821b03e2DB6326E585baCbB9df14058eDbd2;

    // OP CCIP
    // address indexToken = 0x9D00bEc78dD6987c78510d0C410484C5f3c7Ca05;

    // Stock CCIP
    address indexToken = 0xEbdB8179128df18366b9406F401313F72be27a46;

    address indexFactoryBalancer = 0x5258839E9F8aE25B95F2ccfAF8C422369Cf9deeF;
    address dinariBalancer = 0x08b04CE86d42A93C0DE5C25E2fC505f329A7cC5b;
    address ccipBalancer = 0x17048A72b6E88Fc5bF5fD9319F8323Fd647C81E5;
    uint256 updatedPortfolioNonce = 30;

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(pk);

        // askValues();
        // firstRebalance();
        // secondRebalance();
        // completeRebalance();

        secondRebalanceCcip();
        // secondRebalance();
        // secondRebalanceDinari();
        // completeRebalanceDinari();

        vm.stopBroadcast();
    }

    function askValues() public {
        IndexFactoryBalancer(indexFactoryBalancer).askValues(indexToken);
    }

    function firstRebalance() public {
        IndexFactoryBalancer(indexFactoryBalancer).firstReweightAction(indexToken, updatedPortfolioNonce);
    }

    function secondRebalance() public {
        IndexFactoryBalancer(indexFactoryBalancer).secondReweightAction(indexToken, updatedPortfolioNonce);
    }

    function secondRebalanceCcip() public {
        MainChainBalancer(ccipBalancer).secondReweightAction(indexToken, 25);
    }

    function secondRebalanceDinari() public {
        DinariBalancer(dinariBalancer).secondRebalanceAction(indexToken, 7);
    }

    function completeRebalanceDinari() public {
        DinariBalancer(dinariBalancer).completeRebalanceActions(indexToken, 7);
    }
}

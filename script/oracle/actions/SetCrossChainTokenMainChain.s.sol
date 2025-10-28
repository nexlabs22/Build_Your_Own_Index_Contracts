// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IndexFactory} from "../../../src/factory/IndexFactory.sol";
import "../../../src/dinari/DinariFactoryProcessor.sol";
import "../../../src/ccip/MainChainStorage.sol";

contract CallIndexFactoryOrders is Script {
    address mainChainStorage = 0x3898DA0937eF160c0Ed56294f54E03b99276Ef4E;

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(pk);

        setCrossChainTokenTestnet();

        vm.stopBroadcast();

        console.log("set crosschain sent");
    }

    function setCrossChainTokenTestnet() public {
        uint64 otherChainSelector = 3478487238524512106; // arb sepolia
        address weth = 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14; // weth on sepolia
        address crosschainToken = 0xFd57b4ddBf88a4e07fF4e34C487b99af2Fe82a05; // sepolia

        uint24[] memory sepoliaFeesData = new uint24[](1);
        uint24[] memory arbitrumFeesData = new uint24[](2);

        sepoliaFeesData[0] = 3000;

        arbitrumFeesData[0] = 100;
        arbitrumFeesData[1] = 500;

        address[] memory path = new address[](2);
        path[0] = weth;
        path[1] = crosschainToken;

        MainChainStorage(mainChainStorage)
            .setCrossChainToken(otherChainSelector, crosschainToken, path, sepoliaFeesData);
    }
}


// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../../../src/ccip/CrossChainIndexFactoryStorage.sol";

contract CallIndexFactoryOrders is Script {
    address mainChainStorage = 0x2399ddAbc4B1CFE86a44788A7B2aCAf864661C55;

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(pk);

        setCrossChainTokenTestnet();

        vm.stopBroadcast();

        console.log("set crosschain sent");
    }

    function setCrossChainTokenTestnet() public {
        uint64 otherChainSelector = 16015286601757825753; // sepolia
        address weth = 0xE591bf0A0CF924A0674d7792db046B23CEbF5f34; // weth on arb sepolia
        address crosschainToken = 0xA8C0c11bf64AF62CDCA6f93D3769B88BdD7cb93D; // arb sepolia

        uint24[] memory arbSepoliaFeesData = new uint24[](1);

        arbSepoliaFeesData[0] = 3000;

        address[] memory path = new address[](2);
        path[0] = weth;
        path[1] = crosschainToken;

        CrossChainIndexFactoryStorage(mainChainStorage)
            .setCrossChainToken(otherChainSelector, crosschainToken, path, arbSepoliaFeesData);
    }
}


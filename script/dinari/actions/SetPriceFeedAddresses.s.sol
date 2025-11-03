// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/Test.sol";

import {DinariStorage} from "../../../src/dinari/DinariStorage.sol";

contract SetAllValues is Script {
    address public dinariStorageProxy = 0xD2ED87Bc3812b6611090cB973D4F36cF2129e5B0;

    // string public targetChain = "sepolia";
    string public targetChain = "arbitrum_mainnet";

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        _setPriceFeedAddresses();

        vm.stopBroadcast();
    }

    function _setPriceFeedAddresses() public {
        console.log("== Setting Price feed dShares on IndexFactoryStorage ==");

        address[] memory dShares = new address[](7);
        address[] memory wrappedDshares = new address[](7);
        address[] memory priceFeedAddresses = new address[](7);

        dShares[0] = vm.envAddress("ARBITRUM_APPLE_DSHARE_ADDRESS");
        dShares[1] = vm.envAddress("ARBITRUM_MSFT_DSHARE_ADDRESS");
        dShares[2] = vm.envAddress("ARBITRUM_NVDA_DSHARE_ADDRESS");
        dShares[3] = vm.envAddress("ARBITRUM_AMZN_DSHARE_ADDRESS");
        dShares[4] = vm.envAddress("ARBITRUM_GOOG_DSHARE_ADDRESS");
        dShares[5] = vm.envAddress("ARBITRUM_META_DSHARE_ADDRESS");
        dShares[6] = vm.envAddress("ARBITRUM_TSLA_DSHARE_ADDRESS");

        wrappedDshares[0] = vm.envAddress("ARBITRUM_APPLE_WRAPPED_DSHARE_ADDRESS");
        wrappedDshares[1] = vm.envAddress("ARBITRUM_MSFT_WRAPPED_DSHARE_ADDRESS");
        wrappedDshares[2] = vm.envAddress("ARBITRUM_NVDA_WRAPPED_DSHARE_ADDRESS");
        wrappedDshares[3] = vm.envAddress("ARBITRUM_AMZN_WRAPPED_DSHARE_ADDRESS");
        wrappedDshares[4] = vm.envAddress("ARBITRUM_GOOG_WRAPPED_DSHARE_ADDRESS");
        wrappedDshares[5] = vm.envAddress("ARBITRUM_META_WRAPPED_DSHARE_ADDRESS");
        wrappedDshares[6] = vm.envAddress("ARBITRUM_TSLA_WRAPPED_DSHARE_ADDRESS");

        priceFeedAddresses[0] = vm.envAddress("ARBITRUM_APPLE_PRICE_FEED_ADDRESS");
        priceFeedAddresses[1] = vm.envAddress("ARBITRUM_MSFT_PRICE_FEED_ADDRESS");
        priceFeedAddresses[2] = vm.envAddress("ARBITRUM_NVDA_PRICE_FEED_ADDRESS");
        priceFeedAddresses[3] = vm.envAddress("ARBITRUM_AMZN_PRICE_FEED_ADDRESS");
        priceFeedAddresses[4] = vm.envAddress("ARBITRUM_GOOG_PRICE_FEED_ADDRESS");
        priceFeedAddresses[5] = vm.envAddress("ARBITRUM_META_PRICE_FEED_ADDRESS");
        priceFeedAddresses[6] = vm.envAddress("ARBITRUM_TSLA_PRICE_FEED_ADDRESS");

        DinariStorage(dinariStorageProxy)
            .setWrappedDshareAndPriceFeedAddresses(dShares, wrappedDshares, priceFeedAddresses);
    }
}

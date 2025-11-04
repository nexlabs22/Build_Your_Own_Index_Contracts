// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IndexFactory} from "../../../src/factory/IndexFactory.sol";
import "../../../src/dinari/DinariFactoryProcessor.sol";

contract CallIndexFactoryOrders is Script {
    using stdJson for string;

    address usdc = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    address orderProcessor = 0x55AaA2fE5dDd1eFaD23994D0Fa06a6B53ff3c783;

    function run() external {
        _callIssuance();
        // _multical();
        // _callRedemption();
    }

    function _multical() internal {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(pk);
        vm.stopBroadcast();

        console.log("multical sent");
    }

    function _callIssuance() internal {
        address factory = _indexFactory();

        // Dinari
        address indexToken = 0x2E4150CFBdF6A37b55d07e81F6d3f4D47648D52A;
        uint256 amount = 4e6;

        console.log("Calling issuanceIndexTokens on:", factory);
        console.log("Index token:", indexToken);
        console.log("Amount:", amount);

        uint256 pk = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(pk);
        IERC20(usdc).approve(address(factory), 5e6);
        uint256 orderNonce = IndexFactory(factory).issuanceIndexTokens(indexToken, amount);
        vm.stopBroadcast();

        console.log("issuanceIndexTokens order nonce:", orderNonce);
    }

    function _callRedemption() internal {
        address factory = _indexFactory();

        // CCIP
        address indexToken = 0x3A1696F9A7b3140dB3e328654f914c07e55Ee793;
        // uint256 amount = IERC20(indexToken).balanceOf(0x11a8E23DAfbE058e9758c899dAEe0e43f287A96D);
        uint256 amount = 100e18;

        console.log("Calling redemption on:", factory);
        console.log("Index token:", indexToken);
        console.log("Amount:", amount);

        uint256 pk = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(pk);
        IERC20(indexToken).approve(address(factory), amount);
        // uint256 orderNonce = IndexFactory(factory).redemption(indexToken, amount);
        vm.stopBroadcast();

        // console.log("redemption order nonce:", orderNonce);
    }

    function _indexFactory() internal view returns (address) {
        string memory targetChain = vm.envOr("TARGET_CHAIN", string("sepolia"));
        string memory prefix = _envPrefix(targetChain);
        return vm.envAddress(string.concat(prefix, "_INDEX_FACTORY_PROXY_ADDRESS"));
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


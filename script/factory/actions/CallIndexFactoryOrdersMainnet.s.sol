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

    // Dinari
    // address indexToken = 0x2E4150CFBdF6A37b55d07e81F6d3f4D47648D52A;

    // CCIP
    // address indexToken = 0x112cdC1651C455032a1bB85C5CdD8Cd0C12A8aE1;

    // CrossChain
    address indexToken = 0x2EC6821b03e2DB6326E585baCbB9df14058eDbd2;

    // Meme Coin
    // address indexToken = 0x01b536d445e2B2B14e58B5D2469f6b4908E6266A;

    // OP CCIP
    // address indexToken = 0x9D00bEc78dD6987c78510d0C410484C5f3c7Ca05;

    address usdc = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    address orderProcessor = 0x55AaA2fE5dDd1eFaD23994D0Fa06a6B53ff3c783;

    function run() external {
        _callIssuance();
        // _multical();
        // _callRedemption();
    }

    function _multical() internal {
        // address indexToken = 0x2E4150CFBdF6A37b55d07e81F6d3f4D47648D52A;

        uint256 id = 99305343573533343324030039415639664270793484036763770274076914461729067259749;

        uint256 pk = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(pk);
        DinariFactoryProcessor(orderProcessor).multical(id);
        vm.stopBroadcast();

        console.log("multical sent");
    }

    function _callIssuance() internal {
        address factory = _indexFactory();

        uint256 amount = 8e5;
        // uint256 amount = 10e6;

        console.log("Calling issuanceIndexTokens on:", factory);
        console.log("Index token:", indexToken);
        console.log("Amount:", amount);

        uint256 pk = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(pk);
        // IERC20(usdc).approve(address(factory), 12e6);
        uint256 orderNonce = IndexFactory(factory).issuanceIndexTokens(indexToken, amount);
        vm.stopBroadcast();

        console.log("issuanceIndexTokens order nonce:", orderNonce);
    }

    function _callRedemption() internal {
        address factory = _indexFactory();

        // CCIP
        uint256 amount = IERC20(indexToken).balanceOf(0x11a8E23DAfbE058e9758c899dAEe0e43f287A96D);
        // uint256 amount = 100e18;

        console.log("Calling redemption on:", factory);
        console.log("Index token:", indexToken);
        console.log("Amount:", amount);

        uint256 pk = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(pk);
        IERC20(indexToken).approve(address(factory), amount);
        uint256 orderNonce = IndexFactory(factory).redemption(indexToken, amount);
        vm.stopBroadcast();

        console.log("redemption order nonce:", orderNonce);
    }

    function _indexFactory() internal view returns (address) {
        // string memory targetChain = vm.envOr("TARGET_CHAIN", string("sepolia"));
        string memory targetChain = vm.envOr("TARGET_CHAIN", string("arbitrum_mainnet"));
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
        return "";
    }
}


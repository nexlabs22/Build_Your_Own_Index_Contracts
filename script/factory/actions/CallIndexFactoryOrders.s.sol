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

    address usdc = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;
    address dinariUsdc = 0x665b099132d79739462DfDe6874126AFe840F7a3;
    address orderProcessor = 0xab30AeD5cFb5E874cCdc212571ff6843e2D603AD;

    function run() external {
        // _callIssuance();
        _multical();
        // _callRedemption();
    }

    function _multical() internal {
        address indexToken = 0x4e835FDB96830626e5Ba490f43CFb7274C146691;
        uint256 id = 56363541050082005171475772922014067549853542647048762960790269805762203907207;

        DinariFactoryProcessor(orderProcessor).multical(indexToken, id);
    }

    function _callIssuance() internal {
        address factory = _indexFactory();

        // Dinari
        // address indexToken = 0x4e835FDB96830626e5Ba490f43CFb7274C146691;
        // uint256 amount = 30e6;

        // CCIP
        address indexToken = 0x3A1696F9A7b3140dB3e328654f914c07e55Ee793;
        uint256 amount = 30e6;

        console.log("Calling issuanceIndexTokens on:", factory);
        console.log("Index token:", indexToken);
        console.log("Amount:", amount);

        uint256 pk = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(pk);
        IERC20(dinariUsdc).approve(address(factory), 50e6);
        uint256 orderNonce = IndexFactory(factory).issuanceIndexTokens(indexToken, amount);
        vm.stopBroadcast();

        console.log("issuanceIndexTokens order nonce:", orderNonce);
    }

    function _callRedemption() internal {
        address factory = _indexFactory();
        string memory jsonPath = vm.envString("INDEX_FACTORY_REDEMPTION_JSON");
        string memory json = vm.readFile(jsonPath);

        address indexToken = abi.decode(json.parseRaw(".indexToken"), (address));
        uint256 amount = abi.decode(json.parseRaw(".amount"), (uint256));

        console.log("Calling redemption on:", factory);
        console.log("Index token:", indexToken);
        console.log("Amount:", amount);

        uint256 pk = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(pk);
        uint256 orderNonce = IndexFactory(factory).redemption(indexToken, amount);
        vm.stopBroadcast();

        console.log("redemption order nonce:", orderNonce);
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


// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {IndexFactory} from "../../../src/factory/IndexFactory.sol";

contract CallIndexFactoryOrders is Script {
    using stdJson for string;

    function run() external {
        string memory action = vm.envOr("INDEX_FACTORY_ACTION", string("issuance"));
        bytes32 actionHash = keccak256(bytes(action));
        if (actionHash == keccak256("issuance")) {
            _callIssuance();
        } else if (actionHash == keccak256("redemption")) {
            _callRedemption();
        } else {
            revert("Unsupported INDEX_FACTORY_ACTION");
        }
    }

    function _callIssuance() internal {
        address factory = _indexFactory();
        // string memory jsonPath = vm.envString("INDEX_FACTORY_ISSUANCE_JSON");
        // string memory json = vm.readFile(jsonPath);

        // address indexToken = abi.decode(json.parseRaw(".indexToken"), (address));
        // uint256 amount = abi.decode(json.parseRaw(".amount"), (uint256));

        address indexToken = 0x10EF4A1882A771B46F4fe7C9d7dD67418Eb3FE44;
        uint256 amount = 10e6;

        console.log("Calling issuanceIndexTokens on:", factory);
        console.log("Index token:", indexToken);
        console.log("Amount:", amount);

        uint256 pk = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(pk);
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


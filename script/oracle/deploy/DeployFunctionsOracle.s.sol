// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import "openzeppelin-foundry-upgrades/Upgrades.sol";

import {FunctionsOracle} from "../../../src/oracle/FunctionsOracle.sol";

contract DeployFunctionsOracle is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.addr(deployerPrivateKey);
        string memory targetChain = vm.envOr("TARGET_CHAIN", string("sepolia"));

        address functionsRouterAddress;
        bytes32 newDonId;

        if (keccak256(bytes(targetChain)) == keccak256("sepolia")) {
            functionsRouterAddress = vm.envAddress("SEPOLIA_FUNCTIONS_ROUTER_ADDRESS");
            newDonId = vm.envBytes32("SEPOLIA_NEW_DON_ID");
        } else if (keccak256(bytes(targetChain)) == keccak256("arbitrum_mainnet")) {
            functionsRouterAddress = vm.envAddress("ARBITRUM_FUNCTIONS_ROUTER_ADDRESS");
            newDonId = vm.envBytes32("ARBITRUM_NEW_DON_ID");
        } else {
            revert("Unsupported target chain");
        }

        vm.startBroadcast(deployerPrivateKey);

        address proxy = Upgrades.deployTransparentProxy(
            "FunctionsOracle.sol", owner, abi.encodeCall(FunctionsOracle.initialize, (functionsRouterAddress, newDonId))
        );

        FunctionsOracle functionsOracleImplementation = FunctionsOracle(proxy);
        address proxyAdmin = Upgrades.getAdminAddress(proxy);

        console.log("FunctionsOracle implementation deployed at:", address(functionsOracleImplementation));
        console.log("FunctionsOracle proxy deployed at:", address(proxy));
        console.log("ProxyAdmin for FunctionsOracle deployed at:", address(proxyAdmin));

        vm.stopBroadcast();
    }
}


// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import "openzeppelin-foundry-upgrades/Upgrades.sol";

contract UpgradeFunctionsOracle is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        string memory targetChain = vm.envOr("TARGET_CHAIN", string("sepolia"));

        address functionOracleProxyAddress;
        address owner = vm.addr(deployerPrivateKey);

        if (keccak256(bytes(targetChain)) == keccak256("sepolia")) {
            functionOracleProxyAddress = vm.envAddress("SEPOLIA_FUNCTIONS_ORACLE_PROXY_ADDRESS");
        } else if (keccak256(bytes(targetChain)) == keccak256("arbitrum_mainnet")) {
            functionOracleProxyAddress = vm.envAddress("ARBITRUM_FUNCTIONS_ORACLE_PROXY_ADDRESS");
        } else {
            revert("Unsupported target chain");
        }

        Upgrades.upgradeProxy(functionOracleProxyAddress, "FunctionsOracle.sol", "", owner);

        address implAddr = Upgrades.getImplementationAddress(functionOracleProxyAddress);
        console.log("FunctionsOracle proxy upgraded to new implementation at:", implAddr);

        vm.stopBroadcast();
    }
}


// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/Test.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "openzeppelin-foundry-upgrades/Upgrades.sol";

import {IndexToken} from "../../../src/token/IndexToken.sol";

contract DeployIndexToken is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        string memory tokenName = "CCIP BYOI";
        string memory tokenSymbol = "CCIP BYOI";

        string memory targetChain = "sepolia";
        // string memory targetChain = "arbitrum_mainnet";
        uint256 feeRatePerDayScaled;
        address feeReceiver;
        uint256 supplyCeiling;

        address owner = vm.addr(deployerPrivateKey);

        if (keccak256(bytes(targetChain)) == keccak256("sepolia")) {
            feeRatePerDayScaled = vm.envUint("SEPOLIA_FEE_RATE_PER_DAY_SCALED");
            feeReceiver = vm.envAddress("SEPOLIA_FEE_RECEIVER");
            supplyCeiling = vm.envUint("SEPOLIA_SUPPLY_CEILING");
        } else if (keccak256(bytes(targetChain)) == keccak256("arbitrum_mainnet")) {
            feeRatePerDayScaled = vm.envUint("ARBITRUM_FEE_RATE_PER_DAY_SCALED");
            feeReceiver = vm.envAddress("ARBITRUM_FEE_RECEIVER");
            supplyCeiling = vm.envUint("ARBITRUM_SUPPLY_CEILING");
        } else {
            revert("Unsupported target chain");
        }

        vm.startBroadcast(deployerPrivateKey);

        address proxy = Upgrades.deployTransparentProxy(
            "IndexToken.sol",
            owner,
            abi.encodeCall(
                IndexToken.initialize, (tokenName, tokenSymbol, feeRatePerDayScaled, feeReceiver, supplyCeiling)
            )
        );

        IndexToken indexTokenImplementation = IndexToken(proxy);

        address proxyAdmin = Upgrades.getAdminAddress(proxy);

        console.log("IndexToken implementation deployed at:", address(indexTokenImplementation));
        console.log("IndexToken proxy deployed at:", address(proxy));
        console.log("ProxyAdmin for IndexToken deployed at:", address(proxyAdmin));

        vm.stopBroadcast();
    }
}

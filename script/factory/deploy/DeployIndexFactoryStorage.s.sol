// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import "openzeppelin-foundry-upgrades/Upgrades.sol";

import {IndexFactoryStorage} from "../../../src/factory/IndexFactoryStorage.sol";

contract DeployIndexFactoryStorage is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        address proxy = Upgrades.deployTransparentProxy(
            "IndexFactoryStorage.sol", owner, abi.encodeCall(IndexFactoryStorage.initialize, ())
        );

        address proxyAdmin = Upgrades.getAdminAddress(proxy);
        console.log("IndexFactoryStorage proxy deployed at:", proxy);
        console.log("IndexFactoryStorage ProxyAdmin:", proxyAdmin);

        vm.stopBroadcast();
    }
}


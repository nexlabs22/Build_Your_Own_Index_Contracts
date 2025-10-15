// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "openzeppelin-foundry-upgrades/Upgrades.sol";

import "../../../src/ccip/CoreSender.sol";

contract DeployCoreSender is Script {
    CoreSender public coreSender;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        string memory targetChain = "sepolia";
        address owner = vm.addr(deployerPrivateKey);

        address indexToken;
        address mainChainStorage;
        address orderManager;
        address functionsOracle;
        address linkToken;
        address ccipRouter;
        address weth;

        if (keccak256(bytes(targetChain)) == keccak256("sepolia")) {
            indexToken = vm.envAddress("SEPOLIA_INDEX_TOKEN_PROXY_ADDRESS");
            mainChainStorage = vm.envAddress("SEPOLIA_MAIN_CHAIN_STORAGE_PROXY_ADDRESS");
            orderManager = vm.envAddress("SEPOLIA_ORDER_MANAGER_PROXY_ADDRESS");
            functionsOracle = vm.envAddress("SEPOLIA_FUNCTIONS_ORACLE_PROXY_ADDRESS");
            linkToken = vm.envAddress("SEPOLIA_LINK_TOKEN_ADDRESS");
            ccipRouter = vm.envAddress("SEPOLIA_CCIP_ROUTER_ADDRESS");
            weth = vm.envAddress("SEPOLIA_WETH_ADDRESS");
        } else if (keccak256(bytes(targetChain)) == keccak256("arbitrum_mainnet")) {
            indexToken = vm.envAddress("ARBITRUM_INDEX_TOKEN_PROXY_ADDRESS");
            mainChainStorage = vm.envAddress("ARBITRUM_MAIN_CHAIN_STORAGE_PROXY_ADDRESS");
            orderManager = vm.envAddress("ARBITRUM_ORDER_MANAGER_PROXY_ADDRESS");
            functionsOracle = vm.envAddress("ARBITRUM_FUNCTIONS_ORACLE_PROXY_ADDRESS");
            linkToken = vm.envAddress("ARBITRUM_LINK_TOKEN_ADDRESS");
            ccipRouter = vm.envAddress("ARBITRUM_CCIP_ROUTER_ADDRESS");
            weth = vm.envAddress("ARBITRUM_WETH_ADDRESS");
        } else {
            revert("Unsupported target chain");
        }

        vm.startBroadcast(deployerPrivateKey);

        address proxy = Upgrades.deployTransparentProxy(
            "CoreSender.sol",
            owner,
            abi.encodeCall(
                CoreSender.initialize,
                (payable(indexToken), mainChainStorage, orderManager, functionsOracle, linkToken, ccipRouter, weth)
            )
        );

        coreSender = CoreSender(payable(proxy));
        address adminAddr = Upgrades.getAdminAddress(proxy);

        console.log("CoreSender implementation deployed at:", address(coreSender));
        console.log("CoreSender proxy deployed at:", proxy);
        console.log("ProxyAdmin for CoreSender deployed at:", adminAddr);

        vm.stopBroadcast();
    }
}

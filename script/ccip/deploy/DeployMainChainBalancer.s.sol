// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "openzeppelin-foundry-upgrades/Upgrades.sol";

import "../../../src/ccip/MainChainBalancer.sol";

contract DeployMainChainBalancer is Script {
    MainChainBalancer public mainChainBalancer;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        string memory targetChain = "sepolia";
        address owner = vm.addr(deployerPrivateKey);

        uint64 chainSelector;
        address mainChainStorage;
        address functionsOracle;
        address balancerSender;
        address weth;
        address usdc;

        if (keccak256(bytes(targetChain)) == keccak256("sepolia")) {
            chainSelector = uint64(vm.envUint("SEPOLIA_CCIP_CHAIN_SELECTOR"));
            mainChainStorage = vm.envAddress("SEPOLIA_MAIN_CHAIN_STORAGE_PROXY_ADDRESS");
            functionsOracle = vm.envAddress("SEPOLIA_FUNCTIONS_ORACLE_PROXY_ADDRESS");
            balancerSender = vm.envAddress("SEPOLIA_BALANCER_SENDER_PROXY_ADDRESS");
            weth = vm.envAddress("SEPOLIA_WETH_ADDRESS");
            usdc = vm.envAddress("SEPOLIA_USDC_ADDRESS");
        } else if (keccak256(bytes(targetChain)) == keccak256("arbitrum_mainnet")) {
            chainSelector = uint64(vm.envUint("ARBITRUM_CCIP_CHAIN_SELECTOR"));
            mainChainStorage = vm.envAddress("ARBITRUM_MAIN_CHAIN_STORAGE_PROXY_ADDRESS");
            functionsOracle = vm.envAddress("ARBITRUM_FUNCTIONS_ORACLE_PROXY_ADDRESS");
            balancerSender = vm.envAddress("ARBITRUM_BALANCER_SENDER_PROXY_ADDRESS");
            weth = vm.envAddress("ARBITRUM_WETH_ADDRESS");
            usdc = vm.envAddress("ARBITRUM_USDC_ADDRESS");
        } else {
            revert("Unsupported target chain");
        }

        vm.startBroadcast(deployerPrivateKey);

        address proxy = Upgrades.deployTransparentProxy(
            "MainChainBalancer.sol",
            owner,
            abi.encodeCall(
                MainChainBalancer.initialize,
                (chainSelector, mainChainStorage, functionsOracle, payable(balancerSender), weth, usdc)
            )
        );

        mainChainBalancer = MainChainBalancer(proxy);
        address adminAddr = Upgrades.getAdminAddress(proxy);

        console.log("MainChainBalancer implementation deployed at:", address(mainChainBalancer));
        console.log("MainChainBalancer proxy deployed at:", proxy);
        console.log("ProxyAdmin for MainChainBalancer deployed at:", adminAddr);

        vm.stopBroadcast();
    }
}

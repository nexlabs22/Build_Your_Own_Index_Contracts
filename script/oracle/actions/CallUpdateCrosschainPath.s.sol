// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "forge-std/Script.sol";
import "forge-std/Test.sol";

import {IndexFactoryStorage} from "../../../src/factory/IndexFactoryStorage.sol";
import {IndexFactory} from "../../../src/factory/IndexFactory.sol";
import {IndexToken} from "../../../src/token/IndexToken.sol";
import {FunctionsOracle} from "../../../src/oracle/FunctionsOracle.sol";

contract CallUpdateCrosschainPath is Script, Test {
    address functionsOracleProxy = 0xBeB1e7d48718B2f55c2B13c31fB51CF7b1123592;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // string memory targetChain = "sepolia";
        // string memory targetChain = "arbitrum_mainnet";

        // _fillMockAssetsListTestnet();
        // _fillMockAssetsListUSDCWETH();
        _fillMockAssetsListTestnetCrossChain();

        vm.stopBroadcast();

        console.log("All set functions completed successfully!");
    }

    function _fillMockAssetsListUSDCWETH() internal {
        address wethAddress = 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14;
        address token = 0x665b099132d79739462DfDe6874126AFe840F7a3; // USDC

        uint24[] memory feesData = new uint24[](1);
        feesData[0] = 3000;

        address[] memory path = new address[](2);
        path[0] = wethAddress;
        path[1] = token; // usdc

        FunctionsOracle(functionsOracleProxy).updateOnlyPathAndFee(token, path, feesData);
        console.log("Called mockFillAssetsList() [testnet style].");
    }

    function _fillMockAssetsListTestnet() internal {
        uint64 mainChainSelector = 16015286601757825753;

        address wethAddress = 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14;
        address btc = 0x6Ea5aD162d5b74Bc9e4C3e4eEB18AE6861407221;

        uint64[] memory providerIndex = new uint64[](2);
        providerIndex[0] = 1;
        providerIndex[1] = 1;

        uint24[] memory feesData = new uint24[](1);
        feesData[0] = 3000;

        uint64[] memory chainSelectors = new uint64[](2);
        chainSelectors[0] = mainChainSelector;
        chainSelectors[1] = mainChainSelector;

        bytes[] memory pathData = new bytes[](2);
        address[] memory path = new address[](2);
        path[0] = wethAddress;
        path[1] = wethAddress;
        pathData[0] = abi.encode(path, feesData);

        // For Arb Sepolia
        address[] memory path1 = new address[](2);
        path1[0] = wethAddress;
        path1[1] = btc;
        pathData[1] = abi.encode(path1, feesData);

        FunctionsOracle(functionsOracleProxy).updatePathData(providerIndex, chainSelectors, pathData);
        console.log("Called mockFillAssetsList() [testnet style].");
    }

    function _fillMockAssetsListTestnetCrossChain() internal {
        uint64 mainChainSelector = 3478487238524512106; // arb sepolia

        address wethAddress = 0xE591bf0A0CF924A0674d7792db046B23CEbF5f34; // arb sepolia

        address ripple = 0xf4A357354fab7DEAC6fAa1992d84138704C01f45; // arb sepolia
        address xaut = 0x0C3711069cf889Fc47B3Da3700fFFDc2e16A4DaD; // arb sepolia

        uint64[] memory providerIndex = new uint64[](2);
        providerIndex[0] = 1;
        providerIndex[1] = 1;

        uint24[] memory feesData = new uint24[](1);
        feesData[0] = 3000;

        uint64[] memory chainSelectors = new uint64[](2);
        chainSelectors[0] = mainChainSelector;
        chainSelectors[1] = mainChainSelector;

        bytes[] memory pathData = new bytes[](2);
        address[] memory path = new address[](2);
        path[0] = wethAddress;
        path[1] = ripple;
        pathData[0] = abi.encode(path, feesData);

        address[] memory path1 = new address[](2);
        path1[0] = wethAddress;
        path1[1] = xaut;
        pathData[1] = abi.encode(path1, feesData);

        FunctionsOracle(functionsOracleProxy).updatePathData(providerIndex, chainSelectors, pathData);
        console.log("Called mockFillAssetsList() [testnet style].");
    }

    function _fillMockAssetsListMainnet(
        address functionsOracleProxy,
        uint64 mainChainSelector,
        uint64 otherChainSelector,
        address wethAddress,
        address wethEthereumAddress
    ) internal {
        address bitcoinArbitrumAddress = vm.envAddress("ARBITRUM_BITCOIN_ADDRESS");
        address xautEthereumAddress = vm.envAddress("ETHEREUM_XAUT_ADDRESS");
        address usdtEthereumAddress = vm.envAddress("ETHEREUM_USDT_ADDRESS");

        address[] memory assetList = new address[](2);
        assetList[0] = bitcoinArbitrumAddress; // BITCOIN
        assetList[1] = xautEthereumAddress; // XAUT

        uint256[] memory marketShares = new uint256[](2);
        marketShares[0] = 23000000000000000000;
        marketShares[1] = 77000000000000000000;

        uint64[] memory chainSelectors = new uint64[](2);
        chainSelectors[0] = mainChainSelector;
        chainSelectors[1] = otherChainSelector;

        // btc
        uint24[] memory feesData = new uint24[](1);
        feesData[0] = 500;

        bytes[] memory pathData = new bytes[](2);
        address[] memory path = new address[](2);
        path[0] = wethAddress;
        path[1] = assetList[0];
        pathData[0] = abi.encode(path, feesData);

        // xaut
        uint24[] memory feesData1 = new uint24[](2);
        feesData1[0] = 500;
        feesData1[1] = 3000;

        address[] memory path1 = new address[](3);
        path1[0] = wethEthereumAddress;
        path1[1] = usdtEthereumAddress;
        path1[2] = assetList[1];
        pathData[1] = abi.encode(path1, feesData1);

        // FunctionsOracle(functionsOracleProxy).mockFillAssetsList(assetList, pathData, marketShares, chainSelectors);
        console.log("Called mockFillAssetsList() [mainnet style].");
    }
}

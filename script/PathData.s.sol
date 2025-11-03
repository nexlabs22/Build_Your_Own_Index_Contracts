// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "forge-std/Script.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";

import {IndexFactoryStorage} from "../../../src/factory/IndexFactoryStorage.sol";
import {IndexFactory} from "../../../src/factory/IndexFactory.sol";
import {IndexToken} from "../../../src/token/IndexToken.sol";
import {FunctionsOracle} from "../../../src/oracle/FunctionsOracle.sol";

contract CallUpdateCrosschainPath is Script, Test {
    address functionsOracleProxy = 0xBeB1e7d48718B2f55c2B13c31fB51CF7b1123592;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        
        arbeiPathData();

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

    function arbeiPathData() internal {
        address wethAddress = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
        address rain = 0x25118290e6A5f4139381D072181157035864099d;

        uint24[] memory feesData = new uint24[](1);
        feesData[0] = 100;

        bytes[] memory pathData = new bytes[](1);
        address[] memory path = new address[](2);
        path[0] = wethAddress;
        path[1] = rain;
        pathData[0] = abi.encode(path, feesData);

        console.logBytes(pathData[0]);
    }

    function _fillMemeCoinPortfolio() internal {
        // tokens[0] = 0xb98b795Da5c9f393334E6739eEEAB49D6005aA6D; // FLOKI
        // tokens[1] = 0x4CD1A3DcB3e78A99bE97efE12E5F128f53A5b461; // Pump fun
        // tokens[2] = 0xb011e00dd41C06A342977a16AAE3d25dB054e437; // Shiba Inu
        // tokens[3] = 0x6A69e067c01A9833374Cd568A914B2e68C87a7Ca; // DogeCoin
        // tokens[4] = 0x279a0D60d4234F9BD6B4e7119F51BBa4894db4A1; // Baby Doge arb sepolia
        // tokens[5] = 0x81E0B589284a23366681E14476f37653b23D6d9e; // Trump arb sepolia
        // tokens[6] = 0x52cb60E9aef89Df38880B7eB925485b03B345640; // Pepe
        // tokens[7] = 0xD771a71E5bb303da787b4ba2ce559e39dc6eD85c; // APPLE
        // tokens[8] = 0x18aD1A35134F813fBEB4526d655D9d39783512D2; // MSFT
        // tokens[9] = 0x4B47153A241b9d22ae37c2aAEe7A6519fF2Dbfc6; // NVDIA
        // tokens[10] = 0x92d95BCB50B83d488bBFA18776ADC1553d3a8914; // AMZN
        // tokens[11] = 0x8c7074B3e3DF4C51c52c164b574aD782468eB168; // GOOGLE
        // tokens[12] = 0xC470cfBc19Ec46180ceb7D165A064B186d5fDF14; // META
        // tokens[13] = 0xa44c4115d7DeF2da38fBc91B0f3A923440610C52; // TSLA
        // tokens[14] = 0x6Ea5aD162d5b74Bc9e4C3e4eEB18AE6861407221; // BTC
        // tokens[15] = 0x0C3711069cf889Fc47B3Da3700fFFDc2e16A4DaD; // XAUT

        uint64 mainChainSelector = 16015286601757825753;
        uint64 otherChainSelector = 3478487238524512106;

        // address floki = 0xb98b795Da5c9f393334E6739eEEAB49D6005aA6D;
        // address pumpFun = 0x4CD1A3DcB3e78A99bE97efE12E5F128f53A5b461;
        // address shibaInu = 0xb011e00dd41C06A342977a16AAE3d25dB054e437;
        // address dogeCoin = 0x6A69e067c01A9833374Cd568A914B2e68C87a7Ca;
        // address babyDoge = 0x279a0D60d4234F9BD6B4e7119F51BBa4894db4A1;
        // address trump = 0x81E0B589284a23366681E14476f37653b23D6d9e;
        // address pepe = 0x52cb60E9aef89Df38880B7eB925485b03B345640;
        // // address apple = 0xD771a71E5bb303da787b4ba2ce559e39dc6eD85c;
        // // address msft = 0x18aD1A35134F813fBEB4526d655D9d39783512D2;
        // // address nvdia = 0x4B47153A241b9d22ae37c2aAEe7A6519fF2Dbfc6;
        // // address amzn = 0x92d95BCB50B83d488bBFA18776ADC1553d3a8914;
        // // address google = 0x8c7074B3e3DF4C51c52c164b574aD782468eB168;
        // // address meta = 0xC470cfBc19Ec46180ceb7D165A064B186d5fDF14;
        // // address tesla = 0xa44c4115d7DeF2da38fBc91B0f3A923440610C52;
        // address btc = 0x6Ea5aD162d5b74Bc9e4C3e4eEB18AE6861407221;
        // address xaut = 0x0C3711069cf889Fc47B3Da3700fFFDc2e16A4DaD;

        address wethAddress = 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14;
        address wethArbSepolia = 0xE591bf0A0CF924A0674d7792db046B23CEbF5f34; // arb sepolia

        // uint64[] memory providerIndex = new uint64[](16);
        // providerIndex[0] = 1;
        // providerIndex[1] = 1;
        // providerIndex[2] = 1;
        // providerIndex[3] = 1;
        // providerIndex[4] = 1;
        // providerIndex[5] = 1;
        // providerIndex[6] = 1;
        // providerIndex[7] = 2;
        // providerIndex[8] = 2;
        // providerIndex[9] = 2;
        // providerIndex[10] = 2;
        // providerIndex[11] = 2;
        // providerIndex[12] = 2;
        // providerIndex[13] = 2;
        // providerIndex[14] = 1;
        // providerIndex[15] = 1;

        // uint64[] memory chainSelectors = new uint64[](2);
        // chainSelectors[0] = mainChainSelector;
        // chainSelectors[1] = mainChainSelector;
        // chainSelectors[2] = mainChainSelector;
        // chainSelectors[3] = mainChainSelector;
        // chainSelectors[4] = otherChainSelector;
        // chainSelectors[5] = otherChainSelector;
        // chainSelectors[6] = otherChainSelector;
        // chainSelectors[7] = mainChainSelector;
        // chainSelectors[8] = mainChainSelector;
        // chainSelectors[9] = mainChainSelector;
        // chainSelectors[10] = mainChainSelector;
        // chainSelectors[11] = mainChainSelector;
        // chainSelectors[12] = mainChainSelector;
        // chainSelectors[13] = mainChainSelector;
        // chainSelectors[14] = mainChainSelector;
        // chainSelectors[15] = otherChainSelector;

        // bytes[] memory pathData = new bytes[](16);
        // address[] memory path = new address[](2);
        // path[0] = wethAddress;
        // path[1] = floki;
        // pathData[0] = abi.encode(path, feesData);

        // address[] memory path1 = new address[](2);
        // path1[0] = wethAddress;
        // path1[1] = pumpFun;
        // pathData[1] = abi.encode(path1, feesData);

        // address[] memory path2 = new address[](2);
        // path2[0] = wethAddress;
        // path2[1] = shibaInu;
        // pathData[2] = abi.encode(path2, feesData);

        // address[] memory path3 = new address[](2);
        // path3[0] = wethAddress;
        // path3[1] = dogeCoin;
        // pathData[3] = abi.encode(path3, feesData);

        // address[] memory path4 = new address[](2);
        // path4[0] = wethArbSepolia;
        // path4[1] = babyDoge;
        // pathData[4] = abi.encode(path4, feesData);

        // address[] memory path5 = new address[](2);
        // path5[0] = wethArbSepolia;
        // path5[1] = trump;
        // pathData[5] = abi.encode(path5, feesData);

        // address[] memory path6 = new address[](2);
        // path6[0] = wethArbSepolia;
        // path6[1] = pepe;
        // pathData[6] = abi.encode(path6, feesData);

        // address[] memory path7 = new address[](2);
        // path7[0] = wethAddress;
        // path7[1] = wethAddress;
        // pathData[7] = abi.encode(path7, feesData);

        // address[] memory path8 = new address[](2);
        // path8[0] = wethAddress;
        // path8[1] = wethAddress;
        // pathData[8] = abi.encode(path8, feesData);

        // address[] memory path9 = new address[](2);
        // path9[0] = wethAddress;
        // path9[1] = wethAddress;
        // pathData[9] = abi.encode(path9, feesData);

        // address[] memory path10 = new address[](2);
        // path10[0] = wethAddress;
        // path10[1] = wethAddress;
        // pathData[10] = abi.encode(path10, feesData);

        // address[] memory path11 = new address[](2);
        // path11[0] = wethAddress;
        // path11[1] = wethAddress;
        // pathData[11] = abi.encode(path11, feesData);

        // address[] memory path12 = new address[](2);
        // path12[0] = wethAddress;
        // path12[1] = wethAddress;
        // pathData[12] = abi.encode(path12, feesData);

        // address[] memory path13 = new address[](2);
        // path13[0] = wethAddress;
        // path13[1] = wethAddress;
        // pathData[13] = abi.encode(path13, feesData);

        // address[] memory path14 = new address[](2);
        // path14[0] = wethAddress;
        // path14[1] = btc;
        // pathData[14] = abi.encode(path14, feesData);

        // address[] memory path15 = new address[](2);
        // path15[0] = wethArbSepolia;
        // path15[1] = xaut;
        // pathData[15] = abi.encode(path15, feesData);

        // // For Arb Sepolia
        // address[] memory path1 = new address[](2);
        // path1[0] = wethAddress;
        // path1[1] = btc;
        // pathData[1] = abi.encode(path1, feesData);

        uint64[] memory providerIndex = setProviderIndexed();

        uint64[] memory chainSelectors = setChainSelectorMemePortfolio(mainChainSelector, otherChainSelector);

        uint24[] memory feesData = new uint24[](1);
        feesData[0] = 3000;

        bytes[] memory pathData = setPathData(feesData);

        FunctionsOracle(functionsOracleProxy).updatePathData(providerIndex, chainSelectors, pathData);
        console.log("Called mockFillAssetsList() [testnet style].");
    }

    function setChainSelectorMemePortfolio(uint64 mainChainSelector, uint64 otherChainSelector)
        internal
        returns (uint64[] memory)
    {
        uint64[] memory chainSelectors = new uint64[](16);
        chainSelectors[0] = mainChainSelector;
        chainSelectors[1] = mainChainSelector;
        chainSelectors[2] = mainChainSelector;
        chainSelectors[3] = mainChainSelector;
        chainSelectors[4] = otherChainSelector;
        chainSelectors[5] = otherChainSelector;
        chainSelectors[6] = otherChainSelector;
        chainSelectors[7] = mainChainSelector;
        chainSelectors[8] = mainChainSelector;
        chainSelectors[9] = mainChainSelector;
        chainSelectors[10] = mainChainSelector;
        chainSelectors[11] = mainChainSelector;
        chainSelectors[12] = mainChainSelector;
        chainSelectors[13] = mainChainSelector;
        chainSelectors[14] = mainChainSelector;
        chainSelectors[15] = otherChainSelector;

        return chainSelectors;
    }

    function setProviderIndexed() internal returns (uint64[] memory) {
        uint64[] memory providerIndex = new uint64[](16);
        providerIndex[0] = 1;
        providerIndex[1] = 1;
        providerIndex[2] = 1;
        providerIndex[3] = 1;
        providerIndex[4] = 1;
        providerIndex[5] = 1;
        providerIndex[6] = 1;
        providerIndex[7] = 2;
        providerIndex[8] = 2;
        providerIndex[9] = 2;
        providerIndex[10] = 2;
        providerIndex[11] = 2;
        providerIndex[12] = 2;
        providerIndex[13] = 2;
        providerIndex[14] = 1;
        providerIndex[15] = 1;

        return providerIndex;
    }

    function setArbitrumPathData(uint24[] memory feesData) internal pure returns (bytes[] memory) {
        address[20] memory arbTokens = [
            address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1), // WETH
            address(0xaf88d065e77c8cC2239327C5EDb3A432268e5831), // USDC - WETH => 500
            address(0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f), // WBTC - WETH => 500
            address(0xf97f4df75117a78c1A5a0DBb814Af92458539FB4), // LINK - WETH => 3000
            address(0x912ce59144191c1204e64559fe8253a0e49e6548), // ARB - WETH => 500
            address(0xba5ddd1f9d7f570dc94a51479a000e3bce967196), // AAVE - WETH => 500
            address(0x0c880f6761f1af8d9aa9c466984b80dab9a8c9e8), // PENDLE - WETH => 500
            address(0xFa7F8980b0f1E64A2062791cc3b0871572f1F7f0), // UNI - WETH => 3000
            address(0x11cDb42B0EB46D95f990BeDD4695A6e3fA034978), // CRV - WETH => 3000
            address(0xfc5a1a6eb076a2c7ad06ed22c90d7e710e35ad0a), // GMX - WETH => 3000
            address(0x18c11FD286C5EC11c3b683Caa813B77f5163A122), // GNS - WETH => 3000
            address(0x431402e8b9dE9aa016C743880e04E517074D8cEC), // HEGIC - WETH => 500
            address(0x25118290e6A5f4139381D072181157035864099d), // RAIN - WETH => 100

            address(0xCe38e140fC3982a6bCEbc37b040913EF2Cd6C5a7), // AAPL
            address(0x77308F8B63A99b24b262D930E0218ED2f49F8475), // MSFT
            address(0x4DaFFfDDEa93DdF1e0e7B61E844331455053Ce5c), // NVDA
            address(0x8240aFFe697CdE618AD05c3c8963f5Bfe152650b), // AMZN
            address(0x8E50D11a54CFF859b202b7Fe5225353bE0646410), // GOOG
            address(0x519062155B0591627C8A0C0958110A8C5639DcA6), // META
            address(0x36d37B6cbCA364Cf1D843efF8C2f6824491bcF81)  // TSLA
        ];

        address[20] memory baseTokens = [
            address(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913), // USDC - WETH => 500
            address(0x1111111111166b7FE7bd91427724B487980aFc69), // ZORA - WETH => 3000
            address(0xAC1Bd2486aAf3B5C0fc3Fd868558b082a531B2B4),  // TOSHI - WETH => 3000
            address(0x27D2DECb4bFC9C76F0309b8E88dec3a601Fe25a8),  // BARD - WETH => 100
        ];
        return pathData;
    }

    // function setPathData(uint24[] memory feesData) internal returns (bytes[] memory) {
    //     // uint24[] memory feesData = new uint24[](1);
    //     // feesData[0] = 3000;

    //     address floki = 0xb98b795Da5c9f393334E6739eEEAB49D6005aA6D;
    //     address pumpFun = 0x4CD1A3DcB3e78A99bE97efE12E5F128f53A5b461;
    //     address shibaInu = 0xb011e00dd41C06A342977a16AAE3d25dB054e437;
    //     address dogeCoin = 0x6A69e067c01A9833374Cd568A914B2e68C87a7Ca;
    //     address babyDoge = 0x279a0D60d4234F9BD6B4e7119F51BBa4894db4A1;
    //     address trump = 0x81E0B589284a23366681E14476f37653b23D6d9e;
    //     address pepe = 0x52cb60E9aef89Df38880B7eB925485b03B345640;
    //     // address apple = 0xD771a71E5bb303da787b4ba2ce559e39dc6eD85c;
    //     // address msft = 0x18aD1A35134F813fBEB4526d655D9d39783512D2;
    //     // address nvdia = 0x4B47153A241b9d22ae37c2aAEe7A6519fF2Dbfc6;
    //     // address amzn = 0x92d95BCB50B83d488bBFA18776ADC1553d3a8914;
    //     // address google = 0x8c7074B3e3DF4C51c52c164b574aD782468eB168;
    //     // address meta = 0xC470cfBc19Ec46180ceb7D165A064B186d5fDF14;
    //     // address tesla = 0xa44c4115d7DeF2da38fBc91B0f3A923440610C52;
    //     address btc = 0x6Ea5aD162d5b74Bc9e4C3e4eEB18AE6861407221;
    //     address xaut = 0x0C3711069cf889Fc47B3Da3700fFFDc2e16A4DaD;

    //     address wethAddress = 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14;
    //     address wethArbSepolia = 0xE591bf0A0CF924A0674d7792db046B23CEbF5f34; // arb sepolia

    //     bytes[] memory pathData = new bytes[](16);
    //     address[] memory path = new address[](2);
    //     path[0] = wethAddress;
    //     path[1] = floki;
    //     pathData[0] = abi.encode(path, feesData);

    //     address[] memory path1 = new address[](2);
    //     path1[0] = wethAddress;
    //     path1[1] = pumpFun;
    //     pathData[1] = abi.encode(path1, feesData);

    //     address[] memory path2 = new address[](2);
    //     path2[0] = wethAddress;
    //     path2[1] = shibaInu;
    //     pathData[2] = abi.encode(path2, feesData);

    //     address[] memory path3 = new address[](2);
    //     path3[0] = wethAddress;
    //     path3[1] = dogeCoin;
    //     pathData[3] = abi.encode(path3, feesData);

    //     address[] memory path4 = new address[](2);
    //     path4[0] = wethArbSepolia;
    //     path4[1] = babyDoge;
    //     pathData[4] = abi.encode(path4, feesData);

    //     address[] memory path5 = new address[](2);
    //     path5[0] = wethArbSepolia;
    //     path5[1] = trump;
    //     pathData[5] = abi.encode(path5, feesData);

    //     address[] memory path6 = new address[](2);
    //     path6[0] = wethArbSepolia;
    //     path6[1] = pepe;
    //     pathData[6] = abi.encode(path6, feesData);

    //     address[] memory path7 = new address[](2);
    //     path7[0] = wethAddress;
    //     path7[1] = wethAddress;
    //     pathData[7] = abi.encode(path7, feesData);

    //     address[] memory path8 = new address[](2);
    //     path8[0] = wethAddress;
    //     path8[1] = wethAddress;
    //     pathData[8] = abi.encode(path8, feesData);

    //     address[] memory path9 = new address[](2);
    //     path9[0] = wethAddress;
    //     path9[1] = wethAddress;
    //     pathData[9] = abi.encode(path9, feesData);

    //     address[] memory path10 = new address[](2);
    //     path10[0] = wethAddress;
    //     path10[1] = wethAddress;
    //     pathData[10] = abi.encode(path10, feesData);

    //     address[] memory path11 = new address[](2);
    //     path11[0] = wethAddress;
    //     path11[1] = wethAddress;
    //     pathData[11] = abi.encode(path11, feesData);

    //     address[] memory path12 = new address[](2);
    //     path12[0] = wethAddress;
    //     path12[1] = wethAddress;
    //     pathData[12] = abi.encode(path12, feesData);

    //     address[] memory path13 = new address[](2);
    //     path13[0] = wethAddress;
    //     path13[1] = wethAddress;
    //     pathData[13] = abi.encode(path13, feesData);

    //     address[] memory path14 = new address[](2);
    //     path14[0] = wethAddress;
    //     path14[1] = btc;
    //     pathData[14] = abi.encode(path14, feesData);

    //     address[] memory path15 = new address[](2);
    //     path15[0] = wethArbSepolia;
    //     path15[1] = xaut;
    //     pathData[15] = abi.encode(path15, feesData);

    //     return pathData;
    // }

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
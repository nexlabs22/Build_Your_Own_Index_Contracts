// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {FunctionsOracle} from "../../../src/oracle/FunctionsOracle.sol";

contract CallMockFulfillRequestMainnet is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        string memory targetChain = vm.envOr("TARGET_CHAIN", string("arbitrum_mainnet"));
        address oracle = _functionsOracle(targetChain);

        // Dinari
        // address[] memory indexTokens = new address[](2);
        // indexTokens[0] = 0x2E4150CFBdF6A37b55d07e81F6d3f4D47648D52A;
        // indexTokens[1] = 0x2E4150CFBdF6A37b55d07e81F6d3f4D47648D52A;

        // address[] memory tokens = new address[](2);
        // tokens[0] = 0xCe38e140fC3982a6bCEbc37b040913EF2Cd6C5a7; // APPLE
        // // tokens[1] = 0x77308F8B63A99b24b262D930E0218ED2f49F8475; // MSFT
        // tokens[1] = 0x4DaFFfDDEa93DdF1e0e7B61E844331455053Ce5c; // NVIDIA

        // uint256[] memory marketShares = new uint256[](2);
        // marketShares[0] = 50e18;
        // marketShares[1] = 50e18;

        // CCIP
        // address[] memory indexTokens = new address[](2);
        // indexTokens[0] = 0x112cdC1651C455032a1bB85C5CdD8Cd0C12A8aE1;
        // indexTokens[1] = 0x112cdC1651C455032a1bB85C5CdD8Cd0C12A8aE1;

        // address[] memory tokens = new address[](2);
        // tokens[0] = 0xFa7F8980b0f1E64A2062791cc3b0871572f1F7f0; // UNI
        // tokens[1] = 0xba5DdD1f9d7F570dc94a51479a000E3BCE967196; // AAVE

        // uint256[] memory marketShares = new uint256[](2);
        // marketShares[0] = 50e18;
        // marketShares[1] = 50e18;

        // CrossChain CCIP
        // address[] memory indexTokens = new address[](2);
        // indexTokens[0] = 0x2EC6821b03e2DB6326E585baCbB9df14058eDbd2;
        // indexTokens[1] = 0x2EC6821b03e2DB6326E585baCbB9df14058eDbd2;

        // address[] memory tokens = new address[](2);
        // tokens[0] = 0x1111111111166b7FE7bd91427724B487980aFc69; // ZORA
        // tokens[1] = 0xAC1Bd2486aAf3B5C0fc3Fd868558b082a531B2B4; // TOSHI

        // uint256[] memory marketShares = new uint256[](2);
        // marketShares[0] = 60e18;
        // marketShares[1] = 40e18;

        // Meme coin portfolio
        // address[] memory indexTokens = new address[](6);
        // indexTokens[0] = 0x01b536d445e2B2B14e58B5D2469f6b4908E6266A;
        // indexTokens[1] = 0x01b536d445e2B2B14e58B5D2469f6b4908E6266A;
        // indexTokens[2] = 0x01b536d445e2B2B14e58B5D2469f6b4908E6266A;
        // indexTokens[3] = 0x01b536d445e2B2B14e58B5D2469f6b4908E6266A;
        // indexTokens[4] = 0x01b536d445e2B2B14e58B5D2469f6b4908E6266A;
        // indexTokens[5] = 0x01b536d445e2B2B14e58B5D2469f6b4908E6266A;

        // address[] memory tokens = new address[](6);
        // tokens[0] = 0x1111111111166b7FE7bd91427724B487980aFc69; // ZORA
        // tokens[1] = 0xAC1Bd2486aAf3B5C0fc3Fd868558b082a531B2B4; // TOSHI
        // tokens[2] = 0xFa7F8980b0f1E64A2062791cc3b0871572f1F7f0; // UNI
        // tokens[3] = 0xba5DdD1f9d7F570dc94a51479a000E3BCE967196; // AAVE
        // tokens[4] = 0xCe38e140fC3982a6bCEbc37b040913EF2Cd6C5a7; // APPLE
        // tokens[5] = 0x77308F8B63A99b24b262D930E0218ED2f49F8475; // MSFT

        // uint256[] memory marketShares = new uint256[](6);
        // marketShares[0] = 5e18;
        // marketShares[1] = 5e18;
        // marketShares[2] = 5e18;
        // marketShares[3] = 5e18;
        // marketShares[4] = 40e18;
        // marketShares[5] = 40e18;

        // require(indexTokens.length == tokens.length, "length mismatch");
        // require(tokens.length == marketShares.length, "length mismatch");

        // console.log("Mainnet Calling mockFulfillRequest on:", oracle);
        vm.startBroadcast(deployerPrivateKey);
        // setMockForOPCCIPPortfolio(oracle);
        // setMockForOPMultiAssetPortfolio(oracle);
        // FunctionsOracle(oracle).mockFulfillRequest(indexTokens, tokens, marketShares);
        // setMockMultiAssetCCIP(oracle);
        // setCCIPPortfolioMainnet(oracle);
        // setCrossChainStockPortfolioMainnet(oracle);
        // setCrossChainOPBaseStock(oracle);
        set30AssetPortfolio(oracle);
        vm.stopBroadcast();
    }

    function set30AssetPortfolio(address oracle) internal {
        // address weth = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
        // address link = 0xf97f4df75117a78c1A5a0DBb814Af92458539FB4;
        // address gns = 0x18c11FD286C5EC11c3b683Caa813B77f5163A122;
        // address hegic = 0x431402e8b9dE9aa016C743880e04E517074D8cEC;
        // address rain = 0x25118290e6A5f4139381D072181157035864099d;
        // address krom = 0x55fF62567f09906A85183b866dF84bf599a4bf70;
        // address mor = 0x092bAaDB7DEf4C3981454dD9c0A0D7FF07bCFc86;
        // address peas = 0x02f92800F57BCD74066F5709F1Daa1A4302Df875;
        // address lava = 0x11e969e9B3f89cB16D686a03Cd8508C9fC0361AF;
        // address anime = 0x37a645648dF29205C6261289983FB04ECD70b4B3;
        // address lpt = 0x289ba1701C2F088cf0faf8B3705246331cB8A839;
        // address bdt = 0x21CCbc5e7f353EC43b2F5b1Fb12c3E9D89D30Dca;
        // address arc = 0x7F465507f058e17Ad21623927a120ac05CA32741;

        address[] memory indexTokens = new address[](30);
        indexTokens[0] = 0x12334Dcb7bf99379Eb79c61935e18AD816fDf651;
        indexTokens[1] = 0x12334Dcb7bf99379Eb79c61935e18AD816fDf651;
        indexTokens[2] = 0x12334Dcb7bf99379Eb79c61935e18AD816fDf651;
        indexTokens[3] = 0x12334Dcb7bf99379Eb79c61935e18AD816fDf651;
        indexTokens[4] = 0x12334Dcb7bf99379Eb79c61935e18AD816fDf651;
        indexTokens[5] = 0x12334Dcb7bf99379Eb79c61935e18AD816fDf651;
        indexTokens[6] = 0x12334Dcb7bf99379Eb79c61935e18AD816fDf651;
        indexTokens[7] = 0x12334Dcb7bf99379Eb79c61935e18AD816fDf651;
        indexTokens[8] = 0x12334Dcb7bf99379Eb79c61935e18AD816fDf651;
        indexTokens[9] = 0x12334Dcb7bf99379Eb79c61935e18AD816fDf651;
        indexTokens[10] = 0x12334Dcb7bf99379Eb79c61935e18AD816fDf651;
        indexTokens[11] = 0x12334Dcb7bf99379Eb79c61935e18AD816fDf651;
        indexTokens[12] = 0x12334Dcb7bf99379Eb79c61935e18AD816fDf651;
        indexTokens[13] = 0x12334Dcb7bf99379Eb79c61935e18AD816fDf651;
        indexTokens[14] = 0x12334Dcb7bf99379Eb79c61935e18AD816fDf651;
        indexTokens[15] = 0x12334Dcb7bf99379Eb79c61935e18AD816fDf651;
        indexTokens[16] = 0x12334Dcb7bf99379Eb79c61935e18AD816fDf651;
        indexTokens[17] = 0x12334Dcb7bf99379Eb79c61935e18AD816fDf651;
        indexTokens[18] = 0x12334Dcb7bf99379Eb79c61935e18AD816fDf651;
        indexTokens[19] = 0x12334Dcb7bf99379Eb79c61935e18AD816fDf651;
        indexTokens[20] = 0x12334Dcb7bf99379Eb79c61935e18AD816fDf651;
        indexTokens[21] = 0x12334Dcb7bf99379Eb79c61935e18AD816fDf651;
        indexTokens[22] = 0x12334Dcb7bf99379Eb79c61935e18AD816fDf651;
        indexTokens[23] = 0x12334Dcb7bf99379Eb79c61935e18AD816fDf651;
        indexTokens[24] = 0x12334Dcb7bf99379Eb79c61935e18AD816fDf651;
        indexTokens[25] = 0x12334Dcb7bf99379Eb79c61935e18AD816fDf651;
        indexTokens[26] = 0x12334Dcb7bf99379Eb79c61935e18AD816fDf651;
        indexTokens[27] = 0x12334Dcb7bf99379Eb79c61935e18AD816fDf651;
        indexTokens[28] = 0x12334Dcb7bf99379Eb79c61935e18AD816fDf651;
        indexTokens[29] = 0x12334Dcb7bf99379Eb79c61935e18AD816fDf651;

        address[] memory tokens = new address[](30);
        tokens[0] = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f; // WBTC
        tokens[1] = 0x912CE59144191C1204E64559FE8253a0e49E6548; // ARB
        tokens[2] = 0x0c880f6761F1af8d9Aa9C466984b80DAb9a8c9e8; // PENDLE
        tokens[3] = 0x11cDb42B0EB46D95f990BeDD4695A6e3fA034978; // CURVE
        tokens[4] = 0xfc5A1A6EB076a2C7aD06eD22C90d7E710E35ad0a; // GMX
        tokens[5] = 0xFa7F8980b0f1E64A2062791cc3b0871572f1F7f0; // UNI
        tokens[6] = 0xba5DdD1f9d7F570dc94a51479a000E3BCE967196; // AAVE
        // tokens[7] = 0xCe38e140fC3982a6bCEbc37b040913EF2Cd6C5a7; // APPLE
        // tokens[8] = 0x4DaFFfDDEa93DdF1e0e7B61E844331455053Ce5c; // NVIDIA
        tokens[7] = 0x1111111111166b7FE7bd91427724B487980aFc69; // ZORA
        tokens[8] = 0xAC1Bd2486aAf3B5C0fc3Fd868558b082a531B2B4; // TOSHI
        tokens[9] = 0x4200000000000000000000000000000000000042; // OP
        tokens[10] = 0x38F9bf9dCe51833Ec7f03C9dC218197999999999; // NYA
        tokens[11] = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
        tokens[12] = 0xf97f4df75117a78c1A5a0DBb814Af92458539FB4;
        tokens[13] = 0x18c11FD286C5EC11c3b683Caa813B77f5163A122;
        tokens[14] = 0x431402e8b9dE9aa016C743880e04E517074D8cEC;
        tokens[15] = 0x25118290e6A5f4139381D072181157035864099d;
        tokens[16] = 0x55fF62567f09906A85183b866dF84bf599a4bf70;
        tokens[17] = 0x092bAaDB7DEf4C3981454dD9c0A0D7FF07bCFc86;
        tokens[18] = 0x02f92800F57BCD74066F5709F1Daa1A4302Df875;
        tokens[19] = 0x11e969e9B3f89cB16D686a03Cd8508C9fC0361AF;
        tokens[20] = 0x37a645648dF29205C6261289983FB04ECD70b4B3;
        tokens[21] = 0x289ba1701C2F088cf0faf8B3705246331cB8A839;
        tokens[22] = 0x21CCbc5e7f353EC43b2F5b1Fb12c3E9D89D30Dca;
        tokens[23] = 0x7F465507f058e17Ad21623927a120ac05CA32741;
        tokens[24] = 0x8700dAec35aF8Ff88c16BdF0418774CB3D7599B4;
        tokens[25] = 0xdC6fF44d5d932Cbd77B52E5612Ba0529DC6226F1;
        tokens[26] = 0x4ed4E862860beD51a9570b96d89aF5E1B0Efefed; // DEGEN
        tokens[27] = 0x1B68244B100A6713ca7F540697b1bE12148a8bf9; // YES
        tokens[28] = 0x1D2F0da169ceB9fC7B3144628dB156f3F6c60dBE; // XRP
        tokens[29] = 0x570A5D26f7765Ecb712C0924E4De545B89fD43dF; // SOLANA

        uint256[] memory marketShares = new uint256[](30);
        // marketShares[0] = 100e18;
        marketShares[0] = 3e18;
        marketShares[1] = 3e18;
        marketShares[2] = 3e18;
        marketShares[3] = 3e18;
        marketShares[4] = 3e18;
        marketShares[5] = 3e18;
        marketShares[6] = 3e18;
        marketShares[7] = 3e18;
        marketShares[8] = 3e18;
        marketShares[9] = 3e18;
        marketShares[10] = 3e18;
        marketShares[11] = 3e18;
        marketShares[12] = 3e18;
        marketShares[13] = 3e18;
        marketShares[14] = 3e18;
        marketShares[15] = 3e18;
        marketShares[16] = 3e18;
        marketShares[17] = 3e18;
        marketShares[18] = 3e18;
        marketShares[19] = 3e18;
        marketShares[20] = 4e18;
        marketShares[21] = 4e18;
        marketShares[22] = 4e18;
        marketShares[23] = 4e18;
        marketShares[24] = 4e18;
        marketShares[25] = 4e18;
        marketShares[26] = 4e18;
        marketShares[27] = 4e18;
        marketShares[28] = 4e18;
        marketShares[29] = 4e18;

        require(indexTokens.length == tokens.length, "length mismatch");
        require(tokens.length == marketShares.length, "length mismatch");

        console.log("Mainnet Calling mockFulfillRequest on:", oracle);

        FunctionsOracle(oracle).mockFulfillRequest(indexTokens, tokens, marketShares);
    }

    function setCrossChainOPBaseStock(address oracle) internal {
        // 0x5B29Bc3BE79C3910Dfc82337595a8a521241f073
        address[] memory indexTokens = new address[](13);
        indexTokens[0] = 0x5B29Bc3BE79C3910Dfc82337595a8a521241f073;
        indexTokens[1] = 0x5B29Bc3BE79C3910Dfc82337595a8a521241f073;
        indexTokens[2] = 0x5B29Bc3BE79C3910Dfc82337595a8a521241f073;
        indexTokens[3] = 0x5B29Bc3BE79C3910Dfc82337595a8a521241f073;
        indexTokens[4] = 0x5B29Bc3BE79C3910Dfc82337595a8a521241f073;
        indexTokens[5] = 0x5B29Bc3BE79C3910Dfc82337595a8a521241f073;
        indexTokens[6] = 0x5B29Bc3BE79C3910Dfc82337595a8a521241f073;
        indexTokens[7] = 0x5B29Bc3BE79C3910Dfc82337595a8a521241f073;
        indexTokens[8] = 0x5B29Bc3BE79C3910Dfc82337595a8a521241f073;
        indexTokens[9] = 0x5B29Bc3BE79C3910Dfc82337595a8a521241f073;
        indexTokens[10] = 0x5B29Bc3BE79C3910Dfc82337595a8a521241f073;
        indexTokens[11] = 0x5B29Bc3BE79C3910Dfc82337595a8a521241f073;
        indexTokens[12] = 0x5B29Bc3BE79C3910Dfc82337595a8a521241f073;

        address[] memory tokens = new address[](13);
        tokens[0] = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f; // WBTC
        tokens[1] = 0x912CE59144191C1204E64559FE8253a0e49E6548; // ARB
        tokens[2] = 0x0c880f6761F1af8d9Aa9C466984b80DAb9a8c9e8; // PENDLE
        tokens[3] = 0x11cDb42B0EB46D95f990BeDD4695A6e3fA034978; // CURVE
        tokens[4] = 0xfc5A1A6EB076a2C7aD06eD22C90d7E710E35ad0a; // GMX
        tokens[5] = 0xFa7F8980b0f1E64A2062791cc3b0871572f1F7f0; // UNI
        tokens[6] = 0xba5DdD1f9d7F570dc94a51479a000E3BCE967196; // AAVE
        tokens[7] = 0xCe38e140fC3982a6bCEbc37b040913EF2Cd6C5a7; // APPLE
        tokens[8] = 0x4DaFFfDDEa93DdF1e0e7B61E844331455053Ce5c; // NVIDIA
        tokens[9] = 0x1111111111166b7FE7bd91427724B487980aFc69; // ZORA
        tokens[10] = 0xAC1Bd2486aAf3B5C0fc3Fd868558b082a531B2B4; // TOSHI
        tokens[11] = 0x4200000000000000000000000000000000000042; // OP
        tokens[12] = 0x38F9bf9dCe51833Ec7f03C9dC218197999999999; // NYA

        // tokens[5] = 0x4DaFFfDDEa93DdF1e0e7B61E844331455053Ce5c; // NVIDIA

        uint256[] memory marketShares = new uint256[](13);
        // marketShares[0] = 100e18;
        marketShares[0] = 2e18;
        marketShares[1] = 3e18;
        marketShares[2] = 2e18;
        marketShares[3] = 3e18;
        marketShares[4] = 5e18;
        marketShares[5] = 5e18;
        marketShares[6] = 5e18;
        marketShares[7] = 30e18;
        marketShares[8] = 30e18;
        marketShares[9] = 5e18;
        marketShares[10] = 5e18;
        marketShares[11] = 3e18;
        marketShares[12] = 2e18;

        require(indexTokens.length == tokens.length, "length mismatch");
        require(tokens.length == marketShares.length, "length mismatch");

        console.log("Mainnet Calling mockFulfillRequest on:", oracle);

        FunctionsOracle(oracle).mockFulfillRequest(indexTokens, tokens, marketShares);
    }

    function setCrossChainStockPortfolioMainnet(address oracle) internal {
        address[] memory indexTokens = new address[](11);
        indexTokens[0] = 0xA9D65c20E04aDBDf9B7d4236207D826C9ABAE90f;
        indexTokens[1] = 0xA9D65c20E04aDBDf9B7d4236207D826C9ABAE90f;
        indexTokens[2] = 0xA9D65c20E04aDBDf9B7d4236207D826C9ABAE90f;
        indexTokens[3] = 0xA9D65c20E04aDBDf9B7d4236207D826C9ABAE90f;
        indexTokens[4] = 0xA9D65c20E04aDBDf9B7d4236207D826C9ABAE90f;
        indexTokens[5] = 0xA9D65c20E04aDBDf9B7d4236207D826C9ABAE90f;
        indexTokens[6] = 0xA9D65c20E04aDBDf9B7d4236207D826C9ABAE90f;
        indexTokens[7] = 0xA9D65c20E04aDBDf9B7d4236207D826C9ABAE90f;
        indexTokens[8] = 0xA9D65c20E04aDBDf9B7d4236207D826C9ABAE90f;
        indexTokens[9] = 0xA9D65c20E04aDBDf9B7d4236207D826C9ABAE90f;
        indexTokens[10] = 0xA9D65c20E04aDBDf9B7d4236207D826C9ABAE90f;

        address[] memory tokens = new address[](11);
        tokens[0] = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f; // WBTC
        tokens[1] = 0x912CE59144191C1204E64559FE8253a0e49E6548; // ARB
        tokens[2] = 0x0c880f6761F1af8d9Aa9C466984b80DAb9a8c9e8; // PENDLE
        tokens[3] = 0x11cDb42B0EB46D95f990BeDD4695A6e3fA034978; // CURVE
        tokens[4] = 0xfc5A1A6EB076a2C7aD06eD22C90d7E710E35ad0a; // GMX
        tokens[5] = 0xFa7F8980b0f1E64A2062791cc3b0871572f1F7f0; // UNI
        tokens[6] = 0xba5DdD1f9d7F570dc94a51479a000E3BCE967196; // AAVE
        tokens[7] = 0xCe38e140fC3982a6bCEbc37b040913EF2Cd6C5a7; // APPLE
        tokens[8] = 0x4DaFFfDDEa93DdF1e0e7B61E844331455053Ce5c; // NVIDIA
        tokens[9] = 0x1111111111166b7FE7bd91427724B487980aFc69; // ZORA
        tokens[10] = 0xAC1Bd2486aAf3B5C0fc3Fd868558b082a531B2B4; // TOSHI

        // tokens[5] = 0x4DaFFfDDEa93DdF1e0e7B61E844331455053Ce5c; // NVIDIA

        uint256[] memory marketShares = new uint256[](11);
        // marketShares[0] = 100e18;
        marketShares[0] = 2e18;
        marketShares[1] = 3e18;
        marketShares[2] = 5e18;
        marketShares[3] = 5e18;
        marketShares[4] = 5e18;
        marketShares[5] = 5e18;
        marketShares[6] = 5e18;
        marketShares[7] = 30e18;
        marketShares[8] = 30e18;
        marketShares[9] = 5e18;
        marketShares[10] = 5e18;

        require(indexTokens.length == tokens.length, "length mismatch");
        require(tokens.length == marketShares.length, "length mismatch");

        console.log("Mainnet Calling mockFulfillRequest on:", oracle);

        FunctionsOracle(oracle).mockFulfillRequest(indexTokens, tokens, marketShares);
    }

    function setCCIPPortfolioMainnet(address oracle) internal {
        //     address btc = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f;
        // // address weth = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
        // address arbitrum = 0x912CE59144191C1204E64559FE8253a0e49E6548;
        // address pendle = 0x0c880f6761F1af8d9Aa9C466984b80DAb9a8c9e8;
        // address curve = 0x11cDb42B0EB46D95f990BeDD4695A6e3fA034978;
        // address gmx = 0xfc5A1A6EB076a2C7aD06eD22C90d7E710E35ad0a;

        address[] memory indexTokens = new address[](9);
        indexTokens[0] = 0x0017329c4A4fD1289935D27777291A94dA006D46;
        indexTokens[1] = 0x0017329c4A4fD1289935D27777291A94dA006D46;
        indexTokens[2] = 0x0017329c4A4fD1289935D27777291A94dA006D46;
        indexTokens[3] = 0x0017329c4A4fD1289935D27777291A94dA006D46;
        indexTokens[4] = 0x0017329c4A4fD1289935D27777291A94dA006D46;
        indexTokens[5] = 0x0017329c4A4fD1289935D27777291A94dA006D46;
        indexTokens[6] = 0x0017329c4A4fD1289935D27777291A94dA006D46;
        indexTokens[7] = 0x0017329c4A4fD1289935D27777291A94dA006D46;
        indexTokens[8] = 0x0017329c4A4fD1289935D27777291A94dA006D46;

        address[] memory tokens = new address[](9);
        tokens[0] = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f; // WBTC
        tokens[1] = 0x912CE59144191C1204E64559FE8253a0e49E6548; // ARB
        tokens[2] = 0x0c880f6761F1af8d9Aa9C466984b80DAb9a8c9e8; // PENDLE
        tokens[3] = 0x11cDb42B0EB46D95f990BeDD4695A6e3fA034978; // CURVE
        tokens[4] = 0xfc5A1A6EB076a2C7aD06eD22C90d7E710E35ad0a; // GMX
        tokens[5] = 0xFa7F8980b0f1E64A2062791cc3b0871572f1F7f0; // UNI
        tokens[6] = 0xba5DdD1f9d7F570dc94a51479a000E3BCE967196; // AAVE
        tokens[7] = 0xCe38e140fC3982a6bCEbc37b040913EF2Cd6C5a7; // APPLE
        tokens[8] = 0x4DaFFfDDEa93DdF1e0e7B61E844331455053Ce5c; // NVIDIA

        // tokens[5] = 0x4DaFFfDDEa93DdF1e0e7B61E844331455053Ce5c; // NVIDIA

        uint256[] memory marketShares = new uint256[](9);
        // marketShares[0] = 100e18;
        marketShares[0] = 2e18;
        marketShares[1] = 3e18;
        marketShares[2] = 5e18;
        marketShares[3] = 5e18;
        marketShares[4] = 5e18;
        marketShares[5] = 5e18;
        marketShares[6] = 5e18;
        marketShares[7] = 35e18;
        marketShares[8] = 35e18;

        require(indexTokens.length == tokens.length, "length mismatch");
        require(tokens.length == marketShares.length, "length mismatch");

        console.log("Mainnet Calling mockFulfillRequest on:", oracle);

        FunctionsOracle(oracle).mockFulfillRequest(indexTokens, tokens, marketShares);
    }

    function setMockMultiAssetCCIP(address oracle) internal {
        address[] memory indexTokens = new address[](3);
        indexTokens[0] = 0xEbdB8179128df18366b9406F401313F72be27a46;
        indexTokens[1] = 0xEbdB8179128df18366b9406F401313F72be27a46;
        indexTokens[2] = 0xEbdB8179128df18366b9406F401313F72be27a46;

        address[] memory tokens = new address[](3);
        // tokens[0] = 0xFa7F8980b0f1E64A2062791cc3b0871572f1F7f0; // UNI
        tokens[0] = 0xCe38e140fC3982a6bCEbc37b040913EF2Cd6C5a7; // APPLE
        tokens[1] = 0xba5DdD1f9d7F570dc94a51479a000E3BCE967196; // AAVE
        tokens[2] = 0x4200000000000000000000000000000000000042; // OP

        // tokens[5] = 0x4DaFFfDDEa93DdF1e0e7B61E844331455053Ce5c; // NVIDIA

        uint256[] memory marketShares = new uint256[](3);
        // marketShares[0] = 100e18;
        marketShares[0] = 30e18;
        marketShares[1] = 40e18;
        marketShares[2] = 30e18;

        require(indexTokens.length == tokens.length, "length mismatch");
        require(tokens.length == marketShares.length, "length mismatch");

        console.log("Mainnet Calling mockFulfillRequest on:", oracle);

        FunctionsOracle(oracle).mockFulfillRequest(indexTokens, tokens, marketShares);
    }

    function setMockForOPMultiAssetPortfolio(address oracle) internal {
        address[] memory indexTokens = new address[](6);
        indexTokens[0] = 0x1Bd5E430fb059FF30bf0ec089629f6164646CCCd;
        indexTokens[1] = 0x1Bd5E430fb059FF30bf0ec089629f6164646CCCd;
        indexTokens[2] = 0x1Bd5E430fb059FF30bf0ec089629f6164646CCCd;
        indexTokens[3] = 0x1Bd5E430fb059FF30bf0ec089629f6164646CCCd;
        indexTokens[4] = 0x1Bd5E430fb059FF30bf0ec089629f6164646CCCd;
        indexTokens[5] = 0x1Bd5E430fb059FF30bf0ec089629f6164646CCCd;

        address[] memory tokens = new address[](6);
        tokens[0] = 0x38F9bf9dCe51833Ec7f03C9dC218197999999999; // NYA
        tokens[1] = 0x4200000000000000000000000000000000000042; // OP
        tokens[2] = 0xFa7F8980b0f1E64A2062791cc3b0871572f1F7f0; // UNI
        tokens[3] = 0xba5DdD1f9d7F570dc94a51479a000E3BCE967196; // AAVE
        tokens[4] = 0xCe38e140fC3982a6bCEbc37b040913EF2Cd6C5a7; // APPLE
        tokens[5] = 0x4DaFFfDDEa93DdF1e0e7B61E844331455053Ce5c; // NVIDIA

        uint256[] memory marketShares = new uint256[](6);
        marketShares[0] = 5e18;
        marketShares[1] = 5e18;
        marketShares[2] = 5e18;
        marketShares[3] = 5e18;
        marketShares[4] = 40e18;
        marketShares[5] = 40e18;

        require(indexTokens.length == tokens.length, "length mismatch");
        require(tokens.length == marketShares.length, "length mismatch");

        console.log("Mainnet Calling mockFulfillRequest on:", oracle);

        FunctionsOracle(oracle).mockFulfillRequest(indexTokens, tokens, marketShares);
    }

    function setMockForOPCCIPPortfolio(address oracle) internal {
        address[] memory indexTokens = new address[](2);
        indexTokens[0] = 0x9D00bEc78dD6987c78510d0C410484C5f3c7Ca05;
        // indexTokens[1] = 0x9D00bEc78dD6987c78510d0C410484C5f3c7Ca05;
        indexTokens[1] = 0x9D00bEc78dD6987c78510d0C410484C5f3c7Ca05;

        address[] memory tokens = new address[](2);
        tokens[0] = 0x38F9bf9dCe51833Ec7f03C9dC218197999999999; // NYA
        // tokens[1] = 0x17Aabf6838a6303fc6E9C5A227DC1EB6d95c829A; // TUX
        tokens[1] = 0x4200000000000000000000000000000000000042; // OP

        uint256[] memory marketShares = new uint256[](2);
        marketShares[0] = 40e18;
        // marketShares[1] = 0;
        marketShares[1] = 60e18;

        require(indexTokens.length == tokens.length, "length mismatch");
        require(tokens.length == marketShares.length, "length mismatch");

        console.log("Mainnet Calling mockFulfillRequest on:", oracle);

        FunctionsOracle(oracle).mockFulfillRequest(indexTokens, tokens, marketShares);

        //     address nya = 0x38F9bf9dCe51833Ec7f03C9dC218197999999999;
        // address tux = 0x17Aabf6838a6303fc6E9C5A227DC1EB6d95c829A;
        // address op = 0x4200000000000000000000000000000000000042;
    }

    function _functionsOracle(string memory targetChain) internal view returns (address) {
        string memory prefix = _envPrefix(targetChain);
        return vm.envAddress(string.concat(prefix, "_FUNCTIONS_ORACLE_PROXY_ADDRESS"));
    }

    function _envPrefix(string memory targetChain) internal pure returns (string memory) {
        bytes32 chainHash = keccak256(bytes(targetChain));
        if (chainHash == keccak256("arbitrum_mainnet")) {
            return "ARBITRUM";
        }
        if (chainHash == keccak256("sepolia")) {
            return "SEPOLIA";
        }
        return "";
    }
}


// // SPDX-License-Identifier: MIT
// pragma solidity 0.8.25;

// import "forge-std/Test.sol";
// import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// import "../ccip/CCIPDeployer.sol";

// import {IndexFactoryStorage} from "../../src/factory/IndexFactoryStorage.sol";
// import {IndexFactoryBalancer} from "../../src/factory/IndexFactoryBalancer.sol";
// import {MainChainBalancer} from "../../src/ccip/MainChainBalancer.sol";
// import {FunctionsOracle} from "../../src/oracle/FunctionsOracle.sol";
// import {Vault} from "../../src/vault/Vault.sol";

// import {DinariStorage} from "../../src/dinari/DinariStorage.sol";
// import {DinariBalancer} from "../../src/dinari/DinariBalancer.sol";
// import {DinariOrderManager} from "../../src/dinari/DinariOrderManager.sol";
// import {OrderProcessor} from "../../src/dinari/dinari/orders/OrderProcessor.sol";
// import {IDShareFactory} from "../../src/dinari/dinari/interfaces/IDShareFactory.sol";
// import {IOrderProcessor} from "../../src/dinari/dinari/interfaces/IOrderProcessor.sol";
// import {DShare} from "../../src/dinari/dinari/DShare.sol";
// import {WrappedDShare} from "../../src/dinari/dinari/WrappedDShare.sol";
// import {TransferRestrictor} from "../../src/dinari/dinari/TransferRestrictor.sol";
// import {MockV3Aggregator} from "../../src/test/MockV3Aggregator.sol";

// /// Minimal stub for IDShareFactory to satisfy OrderProcessor.initialize
// contract DShareFactoryStub2 is IDShareFactory {
//     function isTokenDShare(address) external pure returns (bool) {
//         return true;
//     }

//     function isTokenWrappedDShare(address) external pure returns (bool) {
//         return true;
//     }

//     function getDShares() external pure returns (address[] memory, address[] memory) {
//         address[] memory a;
//         address[] memory b;
//         return (a, b);
//     }
// }

// contract RebalanceDinariIntegrationTest is Test, CCIPDeployer {
//     using stdStorage for StdStorage;

//     IndexFactoryBalancer public factoryBalancer2;
//     DinariStorage public dinariStorage;
//     DinariBalancer public dinariBalancer;

//     // Two Dinari assets (DShare + Wrapped)
//     DShare public dshareA;
//     DShare public dshareB;
//     WrappedDShare public wDShareA;
//     WrappedDShare public wDShareB;
//     MockV3Aggregator public priceFeedA;
//     MockV3Aggregator public priceFeedB;

//     address public indexTokenAddr;
//     uint8 constant DINARI_PROVIDER = 2;

//     function setUp() public {
//         deployAllContracts(1_000_000e18);
//         indexTokenAddr = address(indexToken);

//         // Dinari storage/balancer
//         dinariStorage = DinariStorage(address(new ERC1967Proxy(address(new DinariStorage()), "")));
//         dinariBalancer = DinariBalancer(address(new ERC1967Proxy(address(new DinariBalancer()), "")));

//         // Fresh global balancer that knows Dinari
//         factoryBalancer2 = IndexFactoryBalancer(
//             address(
//                 new ERC1967Proxy(
//                     address(new IndexFactoryBalancer()),
//                     abi.encodeWithSelector(
//                         IndexFactoryBalancer.initialize.selector,
//                         address(functionsOracle),
//                         address(indexFactoryStorage),
//                         address(mainChainBalancer),
//                         address(mainChainBalancer),
//                         address(dinariBalancer)
//                     )
//                 )
//             )
//         );

//         vm.startPrank(dinariStorage.owner());
//         dinariStorage.setFunctionsOracle(address(functionsOracle));
//         vm.stopPrank();

//         dinariBalancer.initialize(
//             address(dinariStorage), address(functionsOracle), address(indexFactoryStorage), address(factoryBalancer2)
//         );

//         // Route MainChain balancers to the new global balancer
//         mainChainBalancer.setIndexFactoryBalancer(address(factoryBalancer2));
//         balancerSender.setIndexFactoryBalancer(address(factoryBalancer2));
//         functionsOracle.setOperator(address(factoryBalancer2), true);
//     }

//     function _deployDinariAssetsAndFundVault(uint256 amountA, uint256 amountB) internal {
//         // DShare A via proxy
//         DShare dImplA = new DShare();
//         dshareA = DShare(
//             address(
//                 new ERC1967Proxy(
//                     address(dImplA),
//                     abi.encodeCall(DShare.initialize, (address(this), "DShareA", "DSA", TransferRestrictor(address(0))))
//                 )
//             )
//         );
//         // WrappedDShare A via proxy
//         WrappedDShare wImplA = new WrappedDShare();
//         wDShareA = WrappedDShare(
//             address(
//                 new ERC1967Proxy(
//                     address(wImplA), abi.encodeCall(WrappedDShare.initialize, (address(this), dshareA, "wDSA", "wDSA"))
//                 )
//             )
//         );
//         // Grant minter role to this test to mint underlying
//         dshareA.grantRole(dshareA.MINTER_ROLE(), address(this));

//         // DShare B via proxy
//         DShare dImplB = new DShare();
//         dshareB = DShare(
//             address(
//                 new ERC1967Proxy(
//                     address(dImplB),
//                     abi.encodeCall(DShare.initialize, (address(this), "DShareB", "DSB", TransferRestrictor(address(0))))
//                 )
//             )
//         );
//         // WrappedDShare B via proxy
//         WrappedDShare wImplB = new WrappedDShare();
//         wDShareB = WrappedDShare(
//             address(
//                 new ERC1967Proxy(
//                     address(wImplB), abi.encodeCall(WrappedDShare.initialize, (address(this), dshareB, "wDSB", "wDSB"))
//                 )
//             )
//         );
//         dshareB.grantRole(dshareB.MINTER_ROLE(), address(this));

//         priceFeedA = new MockV3Aggregator(18, 1e18);
//         priceFeedB = new MockV3Aggregator(18, 1e18);

//         address[] memory dShares = new address[](2);
//         address[] memory wrappeds = new address[](2);
//         address[] memory feeds = new address[](2);
//         dShares[0] = address(dshareA);
//         dShares[1] = address(dshareB);
//         wrappeds[0] = address(wDShareA);
//         wrappeds[1] = address(wDShareB);
//         feeds[0] = address(priceFeedA);
//         feeds[1] = address(priceFeedB);
//         vm.prank(dinariStorage.owner());
//         dinariStorage.setWrappedDshareAndPriceFeedAddresses(dShares, wrappeds, feeds);

//         address vaultAddr = indexFactoryStorage.indexTokenToVault(indexTokenAddr);
//         dshareA.mint(address(this), amountA);
//         dshareB.mint(address(this), amountB);
//         dshareA.approve(address(wDShareA), amountA);
//         dshareB.approve(address(wDShareB), amountB);
//         wDShareA.deposit(amountA, vaultAddr);
//         wDShareB.deposit(amountB, vaultAddr);
//     }

//     function _fillSellOrders(OrderProcessor issuer_, address indexToken_, uint256 nonce_) internal {
//         (, address[] memory underlyings,) =
//             functionsOracle.getCurrentProviderIndexData(indexToken_, functionsOracle.currentFilledCount(indexToken_), uint64(DINARI_PROVIDER));
//         for (uint256 i = 0; i < underlyings.length; i++) {
//             address token = underlyings[i];
//             uint256 sellReqId = dinariBalancer.rebalanceRequestId(indexToken_, nonce_, token);
//             if (sellReqId == 0) continue;
//             IOrderProcessor.Order memory ord = dinariStorage.getOrderInstanceById(indexToken_, sellReqId);
//             uint256 assetAmt = ord.assetTokenQuantity;
//             if (assetAmt == 0) continue;
//             issuer_.fillOrder(ord, assetAmt, assetAmt, 0);
//         }
//     }

//     function _fillBuyOrders(OrderProcessor issuer_, address indexToken_, uint256 nonce_) internal {
//         (, address[] memory underlyings,) =
//             functionsOracle.getCurrentProviderIndexData(indexToken_, functionsOracle.currentFilledCount(indexToken_), uint64(DINARI_PROVIDER));
//         for (uint256 i = 0; i < underlyings.length; i++) {
//             address token = underlyings[i];
//             uint256 buyReqId = dinariBalancer.rebalanceRequestId(indexToken_, nonce_, token);
//             uint256 payed = dinariBalancer.rebalanceBuyPayedAmountById(indexToken_, buyReqId);
//             if (buyReqId == 0 || payed == 0) continue;
//             IOrderProcessor.Order memory buyOrd = dinariStorage.getOrderInstanceById(indexToken_, buyReqId);
//             issuer_.fillOrder(buyOrd, payed, payed, 0);
//         }
//     }

//     function _updateOracleWithDinariOnly(address[] memory assets, uint256[] memory shares) internal {
//         uint64[] memory providers = new uint64[](assets.length);
//         uint64[] memory chains = new uint64[](assets.length);
//         bytes[] memory pathBytes = new bytes[](assets.length);
//         uint24[] memory fees = new uint24[](1);
//         fees[0] = 3000;
//         for (uint256 i = 0; i < assets.length; i++) {
//             providers[i] = uint64(DINARI_PROVIDER);
//             chains[i] = 2; // arbitrary non-zero
//             address[] memory path = new address[](2);
//             path[0] = address(weth);
//             path[1] = assets[i];
//             pathBytes[i] = abi.encode(path, fees);
//         }
//         functionsOracle.updatePathData(providers, chains, pathBytes);
//         address[] memory usdcPath = new address[](2);
//         usdcPath[0] = address(weth);
//         usdcPath[1] = address(usdc);
//         functionsOracle.updateOnlyPathAndFee(address(usdc), usdcPath, fees);

//         link.transfer(address(functionsOracle), 1e16);
//         address[] memory indexTokens = new address[](assets.length);
//         for (uint256 i2 = 0; i2 < assets.length; i2++) {
//             indexTokens[i2] = indexTokenAddr;
//         }
//         bytes32 reqId = functionsOracle.requestAssetsData("// update", 0, 0);
//         bytes memory data = abi.encode(indexTokens, assets, shares);
//         bool ok = oracle.fulfillRequest(address(functionsOracle), reqId, data);
//         require(ok, "oracle fulfill failed");
//     }

//     // function test_rebalance_askvalues_records_global_and_provider() public {
//     //     _deployDinariAssetsAndFundVault(500e18, 300e18);

//     //     address[] memory assets = new address[](2);
//     //     assets[0] = address(dshareA);
//     //     assets[1] = address(dshareB);
//     //     uint256[] memory weights = new uint256[](2);
//     //     weights[0] = 60e18;
//     //     weights[1] = 40e18;
//     //     _updateOracleWithDinariOnly(assets, weights);

//     //     uint256 nextProviderNonce = dinariBalancer.rebalanceNonce(indexTokenAddr) + 1;
//     //     // providerNonceToGlobalNonce[DINARI_PROVIDER][nextProviderNonce] = 1;
//     //     bytes32 outer = keccak256(abi.encode(uint64(DINARI_PROVIDER), uint256(7)));
//     //     bytes32 leaf = keccak256(abi.encode(nextProviderNonce, outer));
//     //     vm.store(address(factoryBalancer2), leaf, bytes32(uint256(1)));

//     //     functionsOracle.setOperator(address(this), true);
//     //     // Compute portfolio via storage and complete on global balancer
//     //     uint256 expectedUsd = dinariStorage.getPortfolioValue(indexTokenAddr);
//     //     // provider nonce -> global nonce already mapped above
//     //     factoryBalancer2.completeDinariAskValues(nextProviderNonce, expectedUsd);

//     //     uint256 expectedUsd1 = 800e18;
//     //     assertEq(factoryBalancer2.portfolioTotalValueByNonce(1), expectedUsd1);
//     //     assertEq(factoryBalancer2.providerTotalValueByNonce(1, uint64(DINARI_PROVIDER)), expectedUsd1);
//     // }

//     /// End-to-end flow without mocks:
//     /// 1) askValues via IndexFactoryBalancer (records Dinari provider value)
//     /// 2) firstReweightAction on IndexFactoryBalancer (routes to Dinari firstRebalanceAction)
//     /// 3) Fill sell orders on issuer, then run Dinari secondRebalanceAction
//     /// 4) Fill buy orders and complete via Dinari completeRebalanceActions
//     function test_dinari_reweight_end_to_end() public {
//         // 1) Deploy two Dinari assets and fund the shared vault
//         _deployDinariAssetsAndFundVault(500e18, 300e18); // Overweight A relative to B

//         // 2) Wire a real issuer and order manager so orders can be created and filled
//         //    Use the same setup pattern used in IssuanceDinariIntegration
//         DShareFactoryStub2 dshareFactoryStub = new DShareFactoryStub2();
//         OrderProcessor issuerImpl = new OrderProcessor();
//         OrderProcessor issuer = OrderProcessor(
//             address(
//                 new ERC1967Proxy(
//                     address(issuerImpl),
//                     abi.encodeCall(
//                         OrderProcessor.initialize,
//                         (address(this), address(this), address(this), dshareFactoryStub)
//                     )
//                 )
//             )
//         );
//         issuer.setPaymentToken(address(usdc), 0x00000000, 0, 0, 0, 0); // zero fees for simplicity

//         DinariOrderManager om = DinariOrderManager(address(new ERC1967Proxy(address(new DinariOrderManager()), "")));
//         om.initialize(address(usdc), uint8(18), address(issuer));

//         // Initialize DinariStorage fully and link OM + issuer
//         dinariStorage.initialize(
//             address(issuer),
//             address(indexFactoryStorage),
//             address(dinariBalancer),
//             address(usdc),
//             18,
//             address(functionsOracle),
//             true,
//             DINARI_PROVIDER
//         );
//         dinariStorage.setOrderManager(address(om));
//         // Allow DinariBalancer to operate OM + Vault
//         om.setOperator(address(dinariBalancer), true);
//         vault.setOperator(address(dinariBalancer), true);

//         // Test contract acts as issuer operator to fill orders
//         issuer.setOperator(address(this), true);
//         usdc.approve(address(issuer), type(uint256).max);

//         // 3) Prepare oracle with both provider=2 (Dinari) and a provider=1 token so Dinari target share < 100%
//         address[] memory assets = new address[](3);
//         assets[0] = address(dshareA);
//         assets[1] = address(dshareB);
//         assets[2] = address(crossChainToken); // provider 1 asset just to create target split across providers
//         uint256[] memory shares = new uint256[](3);
//         shares[0] = 40e18; // A 40%
//         shares[1] = 40e18; // B 40%
//         shares[2] = 20e18; // provider 1 token 20%

//         // Path data encodes providerIndex + chainSelector per token
//         uint24[] memory fees = new uint24[](1);
//         fees[0] = 3000;
//         uint64[] memory providers = new uint64[](3);
//         uint64[] memory chains = new uint64[](3);
//         bytes[] memory pathBytes = new bytes[](3);
//         for (uint256 i = 0; i < 3; i++) {
//             address[] memory path = new address[](2);
//             path[0] = address(weth);
//             path[1] = assets[i];
//             pathBytes[i] = abi.encode(path, fees);
//         }
//         providers[0] = uint64(DINARI_PROVIDER);
//         providers[1] = uint64(DINARI_PROVIDER);
//         providers[2] = 1; // CCIP provider index
//         chains[0] = 2; // arbitrary non-zero chain ids
//         chains[1] = 2;
//         chains[2] = 1;
//         functionsOracle.updatePathData(providers, chains, pathBytes);

//         // Ensure USDC path exists for fee computation
//         address[] memory usdcPath = new address[](2);
//         usdcPath[0] = address(weth);
//         usdcPath[1] = address(usdc);
//         functionsOracle.updateOnlyPathAndFee(address(usdc), usdcPath, fees);

//         // Push oracle data through real request/fulfill
//         link.transfer(address(functionsOracle), 1e16);
//         address[] memory indexTokens = new address[](assets.length);
//         for (uint256 i2 = 0; i2 < assets.length; i2++) indexTokens[i2] = indexTokenAddr;
//         bytes32 reqId = functionsOracle.requestAssetsData("// update", 0, 0);
//         bytes memory data = abi.encode(indexTokens, assets, shares);
//         bool ok = oracle.fulfillRequest(address(functionsOracle), reqId, data);
//         require(ok, "oracle fulfill failed");

//         // 4) askValues via global balancer -> routes to Dinari.askValues which completes back
//         // Map factory balancer as operator for Dinari entrypoints
//         functionsOracle.setOperator(address(factoryBalancer2), true);
//         factoryBalancer2.askValues(indexTokenAddr);

//         // Global update nonce should be 1 after first askValues
//         uint256 globalNonce = factoryBalancer2.updatePortfolioNonce();
//         assertEq(globalNonce, 1);

//         // 5) First reweight action at global level; with provider1 presence, Dinari share > target so it triggers Dinari firstRebalanceAction
//         factoryBalancer2.firstReweightAction(indexTokenAddr, globalNonce);

//         // Identify Dinari nonce and fill all sells on issuer
//         uint256 dinariNonce = dinariBalancer.rebalanceNonce(indexTokenAddr);
//         _fillSellOrders(issuer, indexTokenAddr, dinariNonce);

//         // 6) Run second rebalance (use only proceeds from sells; no extra global USDC)
//         dinariBalancer.secondRebalanceAction(indexTokenAddr, dinariNonce, 0);

//         // There should be buy orders for underweighted assets; fill them and then complete
//         _fillBuyOrders(issuer, indexTokenAddr, dinariNonce);

//         // Allow DinariBalancer to update oracle current list on completion
//         functionsOracle.setFactoryBalancer(address(dinariBalancer));
//         dinariBalancer.completeRebalanceActions(indexTokenAddr, dinariNonce);

//         // Basic sanity: some USDC should have been realized/spent and pending reduced
//         uint256 realized = dinariBalancer.usdcRealizedByNonce(indexTokenAddr, dinariNonce);
//         // either realized > 0 or we had no overweight; in our setup, expect realized > 0
//         assertGt(realized, 0, "USDC realized must be > 0 after sells");
//     }
// }

// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "../ccip/CCIPDeployer.sol";

import {IndexFactory} from "../../src/factory/IndexFactory.sol";
import {IndexFactoryStorage} from "../../src/factory/IndexFactoryStorage.sol";
import {OrderManager} from "../../src/orderManager/OrderManager.sol";
import {FunctionsOracle} from "../../src/oracle/FunctionsOracle.sol";
import {Vault} from "../../src/vault/Vault.sol";

import {DinariStorage} from "../../src/dinari/DinariStorage.sol";
import {DinariBalancer} from "../../src/dinari/DinariBalancer.sol";
import {DinariFactory} from "../../src/dinari/DinariFactory.sol";
import {DinariOrderManager} from "../../src/dinari/DinariOrderManager.sol";
import {OrderProcessor} from "../../src/dinari/dinari/orders/OrderProcessor.sol";
import {IDShareFactory} from "../../src/dinari/dinari/interfaces/IDShareFactory.sol";
import {IOrderProcessor} from "../../src/dinari/dinari/interfaces/IOrderProcessor.sol";
import {DShare} from "../../src/dinari/dinari/DShare.sol";
import {WrappedDShare} from "../../src/dinari/dinari/WrappedDShare.sol";
import {TransferRestrictor} from "../../src/dinari/dinari/TransferRestrictor.sol";
import {MockV3Aggregator} from "../../src/test/MockV3Aggregator.sol";

contract DShareFactoryStubHL is IDShareFactory {
    function isTokenDShare(address) external pure returns (bool) { return true; }
    function isTokenWrappedDShare(address) external pure returns (bool) { return true; }
    function getDShares() external pure returns (address[] memory, address[] memory) { address[] memory a; address[] memory b; return (a,b); }
}

contract HighLevelIndexFactoryFlowsTest is Test, CCIPDeployer {
    using stdStorage for StdStorage;

    // Core
    DinariStorage public dinariStorage;
    DinariBalancer public dinariBalancer;
    DinariFactory public dinariFactory;
    DinariOrderManager public dinariOrderManager;
    OrderProcessor public issuer;
    DShareFactoryStubHL public dshareFactoryStub;

    // Assets
    DShare public dshareA;
    DShare public dshareB;
    WrappedDShare public wDShareA;
    WrappedDShare public wDShareB;
    MockV3Aggregator public priceFeedA;
    MockV3Aggregator public priceFeedB;

    address public indexTokenAddr;
    uint8 constant DINARI_PROVIDER = 2;

    function setUp() public {
        deployAllContracts(1_000_000e18);
        indexTokenAddr = address(indexToken);

        // Dinari storage/balancer
        dinariStorage = DinariStorage(address(new ERC1967Proxy(address(new DinariStorage()), "")));
        dinariBalancer = DinariBalancer(address(new ERC1967Proxy(address(new DinariBalancer()), "")));
        dinariBalancer.initialize(address(dinariStorage), address(functionsOracle), address(indexFactoryStorage), address(factoryBalancer));

        // OrderProcessor via proxy
        dshareFactoryStub = new DShareFactoryStubHL();
        OrderProcessor issuerImpl = new OrderProcessor();
        issuer = OrderProcessor(address(new ERC1967Proxy(address(issuerImpl), abi.encodeCall(OrderProcessor.initialize,(address(this), address(this), address(this), dshareFactoryStub)))));
        issuer.setPaymentToken(address(usdc), 0x00000000, 0, 0, 0, 0);

        // OM and DinariFactory
        dinariOrderManager = DinariOrderManager(address(new ERC1967Proxy(address(new DinariOrderManager()), "")));
        dinariOrderManager.initialize(address(usdc), uint8(18), address(issuer));
        dinariFactory = DinariFactory(address(new ERC1967Proxy(address(new DinariFactory()), "")));

        // Wire storages
        dinariStorage.initialize(address(issuer), address(indexFactoryStorage), address(dinariBalancer), address(usdc), 18, address(functionsOracle), true, DINARI_PROVIDER);
        dinariStorage.setOrderManager(address(dinariOrderManager));
        dinariStorage.setFactory(address(dinariFactory));
        dinariStorage.setFactoryBalancer(address(factoryBalancer));
        dinariFactory.initialize(address(indexFactoryStorage), address(dinariStorage), address(functionsOracle));
        orderManager.setDinariFactory(address(dinariFactory));

        // Oracle paths: USDC and Dinari assets
        uint24[] memory fees = new uint24[](1); fees[0]=3000;
        address[] memory usdcPath = new address[](2); usdcPath[0]=address(weth); usdcPath[1]=address(usdc);
        functionsOracle.updateOnlyPathAndFee(address(usdc), usdcPath, fees);
        addLiquidityETH(positionManager, factoryV3Address, usdc, wethAddress, 100000e18, 100e18);

        // DShare + Wrapped via proxies with roles
        DShare dImplA = new DShare();
        dshareA = DShare(address(new ERC1967Proxy(address(dImplA), abi.encodeCall(DShare.initialize,(address(this),"DShareA","DSA", TransferRestrictor(address(0)))))));
        WrappedDShare wImplA = new WrappedDShare();
        wDShareA = WrappedDShare(address(new ERC1967Proxy(address(wImplA), abi.encodeCall(WrappedDShare.initialize,(address(this), dshareA, "wDSA","wDSA")))));
        DShare dImplB = new DShare();
        dshareB = DShare(address(new ERC1967Proxy(address(dImplB), abi.encodeCall(DShare.initialize,(address(this),"DShareB","DSB", TransferRestrictor(address(0)))))));
        WrappedDShare wImplB = new WrappedDShare();
        wDShareB = WrappedDShare(address(new ERC1967Proxy(address(wImplB), abi.encodeCall(WrappedDShare.initialize,(address(this), dshareB, "wDSB","wDSB")))));
        priceFeedA = new MockV3Aggregator(18, 1e18);
        priceFeedB = new MockV3Aggregator(18, 1e18);
        dshareA.grantRole(dshareA.MINTER_ROLE(), address(this));
        dshareB.grantRole(dshareB.MINTER_ROLE(), address(this));
        dshareA.grantRole(dshareA.MINTER_ROLE(), address(issuer));
        dshareB.grantRole(dshareB.MINTER_ROLE(), address(issuer));
        dshareA.grantRole(dshareA.BURNER_ROLE(), address(issuer));
        dshareB.grantRole(dshareB.BURNER_ROLE(), address(issuer));

        // Map wrapped + feeds, fund vault with wrapped
        address[] memory dShares = new address[](2); dShares[0]=address(dshareA); dShares[1]=address(dshareB);
        address[] memory wrappeds = new address[](2); wrappeds[0]=address(wDShareA); wrappeds[1]=address(wDShareB);
        address[] memory feeds = new address[](2); feeds[0]=address(priceFeedA); feeds[1]=address(priceFeedB);
        vm.prank(dinariStorage.owner()); dinariStorage.setWrappedDshareAndPriceFeedAddresses(dShares, wrappeds, feeds);
        address vaultAddr = indexFactoryStorage.indexTokenToVault(indexTokenAddr);
        dshareA.mint(address(this), 500e18); dshareA.approve(address(wDShareA), 500e18); wDShareA.deposit(500e18, vaultAddr);
        dshareB.mint(address(this), 300e18); dshareB.approve(address(wDShareB), 300e18); wDShareB.deposit(300e18, vaultAddr);

        // Oracle provider list: set provider=2 assets and shares
        address[] memory assets = new address[](2); assets[0]=address(dshareA); assets[1]=address(dshareB);
        uint64[] memory providers = new uint64[](2); providers[0]=DINARI_PROVIDER; providers[1]=DINARI_PROVIDER;
        uint64[] memory chains = new uint64[](2); chains[0]=2; chains[1]=2;
        bytes[] memory pathBytes = new bytes[](2);
        for (uint256 i = 0; i < assets.length; i++) {
            pathBytes[i] = _encodePathFor(assets[i], fees);
        }
        functionsOracle.updatePathData(providers, chains, pathBytes);
        address[] memory indexTokens = new address[](2); indexTokens[0]=indexTokenAddr; indexTokens[1]=indexTokenAddr;
        link.transfer(address(functionsOracle), 1e16);
        bytes32 reqId = functionsOracle.requestAssetsData("// update", 0, 0);
        uint256[] memory shares = new uint256[](2); shares[0]=60e18; shares[1]=40e18;
        bool ok = oracle.fulfillRequest(address(functionsOracle), reqId, abi.encode(indexTokens, assets, shares));
        require(ok, "oracle fulfill failed");
    }

    function _encodePathFor(address token, uint24[] memory fees)
        internal
        view
        returns (bytes memory)
    {
        address[] memory p = new address[](2);
        p[0] = address(weth);
        p[1] = token;
        return abi.encode(p, fees);
    }

    function test_IndexFactory_Issuance_Dinari_FullFlow() public {
        // user has USDC, approve factory
        usdc.approve(address(factory), type(uint256).max);
        usdc.approve(address(orderManager), type(uint256).max);

        uint256 supplyBefore = indexToken.totalSupply();
        uint256 issueNonce = factory.issuanceIndexTokens(indexTokenAddr, 1_000e18);

        // Fill each buy order (issuer mints DShare and OM escrows fees)
        (, address[] memory uls,) = functionsOracle.getCurrentProviderIndexData(indexTokenAddr, functionsOracle.currentFilledCount(indexTokenAddr), uint64(DINARI_PROVIDER));
        for (uint256 i = 0; i < uls.length; i++) {
            // Simulate a fill: 10 dShare minted for 1000 USDC
            IOrderProcessor.Order memory ord = dinariStorage.getOrderInstanceById(indexTokenAddr, dinariStorage.issuanceRequestId(indexTokenAddr, issueNonce, uls[i]));
            issuer.fillOrder(ord, 10e18, ord.paymentTokenQuantity, 0);
        }

        // Complete via OrderManager callbacks (bypass processor)
        // Provide plausible values (old=0, new>0); IndexFactory will mint newTotal/100 since supplyBefore==0
        for (uint256 i = 0; i < uls.length; i++) {
            orderManager.completeIssuance(uint64(DINARI_PROVIDER), issueNonce, indexTokenAddr, uls[i], 0, 100e18);
        }
        // After last token, IndexFactory.completeIssuance mints to requester
        assertGt(indexToken.totalSupply(), supplyBefore, "should mint index token after completion");
        assertGt(indexToken.balanceOf(tx.origin), 0); // requester is msg.sender in issuanceIndexTokens
    }

    function test_IndexFactory_Redemption_Dinari_CreatesSellOrders() public {
        // Mint a large supply and burn a small amount so burnPercent << 1e18 (safe for Dinari)
        vm.prank(indexToken.owner()); indexToken.setMinter(address(this), true);
        indexToken.mint(address(this), 100_000e18);
        indexToken.approve(address(factory), type(uint256).max);
        usdc.approve(address(factory), type(uint256).max);

        uint256 redOrderNonce = factory.redemption(indexTokenAddr, 100e18); // 0.1% of supply
        // Assert Dinari created sell orders
        (, address[] memory uls,) = functionsOracle.getCurrentProviderIndexData(indexTokenAddr, functionsOracle.currentFilledCount(indexTokenAddr), uint64(DINARI_PROVIDER));
        for (uint256 i = 0; i < uls.length; i++) {
            uint256 rid = dinariStorage.redemptionRequestId(indexTokenAddr, redOrderNonce, uls[i]);
            assertGt(rid, 0, "sell requestId set for each asset");
        }
        // requester recorded by IndexFactory
        address requester = indexFactoryStorage.redemptionRequester(indexTokenAddr, redOrderNonce);
        assertEq(requester, address(this), "requester set in storage");
    }
}

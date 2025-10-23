// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "../ccip/CCIPDeployer.sol";

import {IndexFactory} from "../../src/factory/IndexFactory.sol";
import {IndexFactoryStorage} from "../../src/factory/IndexFactoryStorage.sol";
import {IndexFactoryBalancer} from "../../src/factory/IndexFactoryBalancer.sol";
import {MainChainBalancer} from "../../src/ccip/MainChainBalancer.sol";
import {OrderManager} from "../../src/orderManager/OrderManager.sol";
import {FunctionsOracle} from "../../src/oracle/FunctionsOracle.sol";

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
import {DinariFactoryProcessor} from "../../src/dinari/DinariFactoryProcessor.sol";

/// Minimal stub for IDShareFactory to satisfy OrderProcessor.initialize
contract DShareFactoryStub2 is IDShareFactory {
    function isTokenDShare(address) external pure returns (bool) {
        return true;
    }

    function isTokenWrappedDShare(address) external pure returns (bool) {
        return true;
    }

    function getDShares() external pure returns (address[] memory, address[] memory) {
        address[] memory a;
        address[] memory b;
        return (a, b);
    }
}

contract IssuanceDinariIntegrationTest is Test, CCIPDeployer {
    using stdStorage for StdStorage;

    IndexFactoryBalancer public factoryBalancer2;
    DinariStorage public dinariStorage;
    DinariBalancer public dinariBalancer;
    DinariFactory public dinariFactory;
    DinariOrderManager public dinariOrderManager;
    OrderProcessor public issuer;
    DShareFactoryStub2 public dshareFactoryStub;
    DinariFactoryProcessor public processor;

    DShare public dshareA;
    DShare public dshareB;
    WrappedDShare public wDShareA;
    WrappedDShare public wDShareB;
    MockV3Aggregator public priceFeedA;
    MockV3Aggregator public priceFeedB;
    uint8 constant DINARI_PROVIDER = 2;

    address public indexTokenAddr;

    function setUp() public {
        deployAllContracts(1_000_000e18);
        indexTokenAddr = address(indexToken);

        dinariStorage = DinariStorage(address(new ERC1967Proxy(address(new DinariStorage()), "")));
        dinariBalancer = DinariBalancer(address(new ERC1967Proxy(address(new DinariBalancer()), "")));
        factoryBalancer2 = IndexFactoryBalancer(
            address(
                new ERC1967Proxy(
                    address(new IndexFactoryBalancer()),
                    abi.encodeWithSelector(
                        IndexFactoryBalancer.initialize.selector,
                        address(functionsOracle),
                        address(indexFactoryStorage),
                        address(mainChainBalancer),
                        address(mainChainBalancer),
                        address(dinariBalancer)
                    )
                )
            )
        );

        dinariBalancer.initialize(
            address(dinariStorage), address(functionsOracle), address(indexFactoryStorage), address(factoryBalancer2)
        );

        dshareFactoryStub = new DShareFactoryStub2();
        OrderProcessor issuerImpl = new OrderProcessor();
        issuer = OrderProcessor(
            address(
                new ERC1967Proxy(
                    address(issuerImpl),
                    abi.encodeCall(
                        OrderProcessor.initialize, (address(this), address(this), address(this), dshareFactoryStub)
                    )
                )
            )
        );
        issuer.setPaymentToken(address(usdc), 0x00000000, 0, 0, 0, 0);

        dinariOrderManager = DinariOrderManager(address(new ERC1967Proxy(address(new DinariOrderManager()), "")));
        dinariOrderManager.initialize(address(usdc), uint8(18), address(issuer));
        dinariFactory = DinariFactory(address(new ERC1967Proxy(address(new DinariFactory()), "")));

        dinariStorage.initialize(
            address(issuer),
            address(indexFactoryStorage),
            address(dinariBalancer),
            address(usdc),
            18,
            address(functionsOracle),
            true,
            DINARI_PROVIDER
        );
        dinariStorage.setOrderManager(address(dinariOrderManager));
        dinariStorage.setFactory(address(dinariFactory));
        dinariStorage.setFactoryBalancer(address(factoryBalancer2));

        dinariFactory.initialize(address(indexFactoryStorage), address(dinariStorage), address(functionsOracle));
        orderManager.setDinariFactory(address(dinariFactory));
        // Allow DinariFactory to use DinariOrderManager
        dinariOrderManager.setOperator(address(dinariFactory), true);

        // Processor used to complete issuance (calls back into OrderManager)
        processor = DinariFactoryProcessor(address(new ERC1967Proxy(address(new DinariFactoryProcessor()), "")));
        processor.initialize(
            address(indexFactoryStorage), address(dinariStorage), address(functionsOracle), address(orderManager)
        );
        // Grant processor required operator roles
        orderManager.setOperator(address(processor), true);
        dinariOrderManager.setOperator(address(processor), true);
        // Allow us to operate issuer for fills
        issuer.setOperator(address(this), true);

        // Pre-approve DinariFactory to pull USDC from OrderManager for provider=2 path
        vm.prank(address(orderManager));
        usdc.approve(address(dinariFactory), type(uint256).max);

        // Provide USDC/WETH V3 liquidity for fee estimation path
        addLiquidityETH(positionManager, factoryV3Address, usdc, wethAddress, 100000e18, 100e18);
    }

    function _updateOracleWithDinariOnly(address[] memory assets, uint256[] memory shares) internal {
        uint64[] memory providers = new uint64[](assets.length);
        uint64[] memory chains = new uint64[](assets.length);
        bytes[] memory pathBytes = new bytes[](assets.length);
        uint24[] memory fees = new uint24[](1);
        fees[0] = 3000;
        for (uint256 i = 0; i < assets.length; i++) {
            providers[i] = uint64(DINARI_PROVIDER);
            chains[i] = 2;
            address[] memory path = new address[](2);
            path[0] = address(weth);
            path[1] = assets[i];
            pathBytes[i] = abi.encode(path, fees);
        }
        functionsOracle.updatePathData(providers, chains, pathBytes);

        // Ensure USDC path exists for fee computation
        address[] memory usdcPath = new address[](2);
        usdcPath[0] = address(weth);
        usdcPath[1] = address(usdc);
        functionsOracle.updateOnlyPathAndFee(address(usdc), usdcPath, fees);

        link.transfer(address(functionsOracle), 1e16);
        address[] memory indexTokens = new address[](assets.length);
        for (uint256 i2 = 0; i2 < assets.length; i2++) {
            indexTokens[i2] = indexTokenAddr;
        }
        bytes32 reqId = functionsOracle.requestAssetsData("// update", 0, 0);
        bytes memory data = abi.encode(indexTokens, assets, shares);
        bool ok = oracle.fulfillRequest(address(functionsOracle), reqId, data);
        require(ok, "oracle fulfill failed");
    }

    function test_issuance_index_to_dinari_provider2() public {
        // Use two distinct asset addresses (DShares) and register wrappers + price feeds
        // DShare and WrappedDShare via proxies
        DShare dImplA = new DShare();
        dshareA = DShare(
            address(
                new ERC1967Proxy(
                    address(dImplA),
                    abi.encodeCall(DShare.initialize, (address(this), "DShareA", "DSA", TransferRestrictor(address(0))))
                )
            )
        );
        DShare dImplB = new DShare();
        dshareB = DShare(
            address(
                new ERC1967Proxy(
                    address(dImplB),
                    abi.encodeCall(DShare.initialize, (address(this), "DShareB", "DSB", TransferRestrictor(address(0))))
                )
            )
        );
        WrappedDShare wImplA = new WrappedDShare();
        wDShareA = WrappedDShare(
            address(
                new ERC1967Proxy(
                    address(wImplA), abi.encodeCall(WrappedDShare.initialize, (address(this), dshareA, "wDSA", "wDSA"))
                )
            )
        );
        WrappedDShare wImplB = new WrappedDShare();
        wDShareB = WrappedDShare(
            address(
                new ERC1967Proxy(
                    address(wImplB), abi.encodeCall(WrappedDShare.initialize, (address(this), dshareB, "wDSB", "wDSB"))
                )
            )
        );
        // Grant minter role to test and issuer for minting during fills and deposits
        dshareA.grantRole(dshareA.MINTER_ROLE(), address(this));
        dshareB.grantRole(dshareB.MINTER_ROLE(), address(this));
        dshareA.grantRole(dshareA.MINTER_ROLE(), address(issuer));
        dshareB.grantRole(dshareB.MINTER_ROLE(), address(issuer));
        priceFeedA = new MockV3Aggregator(18, 1e18);
        priceFeedB = new MockV3Aggregator(18, 1e18);
        address[] memory ds = new address[](2);
        address[] memory ws = new address[](2);
        address[] memory pf = new address[](2);
        ds[0] = address(dshareA);
        ds[1] = address(dshareB);
        ws[0] = address(wDShareA);
        ws[1] = address(wDShareB);
        pf[0] = address(priceFeedA);
        pf[1] = address(priceFeedB);
        vm.prank(dinariStorage.owner());
        dinariStorage.setWrappedDshareAndPriceFeedAddresses(ds, ws, pf);

        address[] memory assets = new address[](2);
        assets[0] = address(dshareA);
        assets[1] = address(dshareB);
        uint256[] memory weights = new uint256[](2);
        weights[0] = 60e18;
        weights[1] = 40e18;
        _updateOracleWithDinariOnly(assets, weights);

        // User approvals to allow factory to collect USDC
        usdc.approve(address(factory), type(uint256).max);
        // Also approve OM in case factory uses it (already set in linkAllContracts)
        usdc.approve(address(orderManager), type(uint256).max);

        uint256 omBefore = orderManager.getOrderNonce();
        uint256 dinariIssBefore = dinariStorage.issuanceNonce(indexTokenAddr);

        uint256 retOrderNonce = factory.issuanceIndexTokens(indexTokenAddr, 1_000e18);

        assertEq(orderManager.getOrderNonce(), omBefore + 1, "one order created for provider2");
        assertEq(dinariStorage.issuanceNonce(indexTokenAddr), dinariIssBefore + 1, "dinari issuance nonce");
        uint256 mapped = orderManager.providerNonceToBuyOrderNonce(indexTokenAddr, DINARI_PROVIDER, dinariIssBefore + 1);
        assertEq(mapped, retOrderNonce, "provider nonce maps to order nonce");
    }

    function test_completeIssuance_mints_indexToken_to_requester_and_logs() public {
        // Setup DShares, wrappers and price feeds
        DShare iA = new DShare();
        dshareA = DShare(
            address(
                new ERC1967Proxy(
                    address(iA),
                    abi.encodeCall(DShare.initialize, (address(this), "DShareA", "DSA", TransferRestrictor(address(0))))
                )
            )
        );
        DShare iB = new DShare();
        dshareB = DShare(
            address(
                new ERC1967Proxy(
                    address(iB),
                    abi.encodeCall(DShare.initialize, (address(this), "DShareB", "DSB", TransferRestrictor(address(0))))
                )
            )
        );
        WrappedDShare wiA = new WrappedDShare();
        wDShareA = WrappedDShare(
            address(
                new ERC1967Proxy(
                    address(wiA), abi.encodeCall(WrappedDShare.initialize, (address(this), dshareA, "wDSA", "wDSA"))
                )
            )
        );
        WrappedDShare wiB = new WrappedDShare();
        wDShareB = WrappedDShare(
            address(
                new ERC1967Proxy(
                    address(wiB), abi.encodeCall(WrappedDShare.initialize, (address(this), dshareB, "wDSB", "wDSB"))
                )
            )
        );
        dshareA.grantRole(dshareA.MINTER_ROLE(), address(this));
        dshareB.grantRole(dshareB.MINTER_ROLE(), address(this));
        dshareA.grantRole(dshareA.MINTER_ROLE(), address(issuer));
        dshareB.grantRole(dshareB.MINTER_ROLE(), address(issuer));
        priceFeedA = new MockV3Aggregator(18, 1e18); // 1 USD
        priceFeedB = new MockV3Aggregator(18, 1e18); // 1 USD
        address[] memory ds = new address[](2);
        address[] memory ws = new address[](2);
        address[] memory pf = new address[](2);
        ds[0] = address(dshareA);
        ds[1] = address(dshareB);
        ws[0] = address(wDShareA);
        ws[1] = address(wDShareB);
        pf[0] = address(priceFeedA);
        pf[1] = address(priceFeedB);
        vm.prank(dinariStorage.owner());
        dinariStorage.setWrappedDshareAndPriceFeedAddresses(ds, ws, pf);

        address[] memory assets = new address[](2);
        assets[0] = address(dshareA);
        assets[1] = address(dshareB);
        uint256[] memory weights = new uint256[](2);
        weights[0] = 50e18;
        weights[1] = 50e18;
        _updateOracleWithDinariOnly(assets, weights);

        // Initial balances
        console.log("IndexToken initial totalSupply:", indexToken.totalSupply());
        console.log("Requester initial IndexToken balance:", indexToken.balanceOf(address(this)));

        // Create issuance via IndexFactory (provider=2 only)
        usdc.approve(address(factory), type(uint256).max);
        uint256 ixBefore = indexToken.balanceOf(address(this));
        uint256 nonce = factory.issuanceIndexTokens(indexTokenAddr, 2_000e18);
        console.log("Issuance nonce:", nonce);

        // Fill each Dinari buy order fully
        (, address[] memory uls,) = functionsOracle.getCurrentProviderIndexData(
            indexTokenAddr, functionsOracle.currentFilledCount(indexTokenAddr), uint64(DINARI_PROVIDER)
        );
        for (uint256 i = 0; i < uls.length; i++) {
            uint256 rid = dinariStorage.issuanceRequestId(indexTokenAddr, nonce, uls[i]);
            IOrderProcessor.Order memory ord = dinariStorage.getOrderInstanceById(indexTokenAddr, rid);
            // Pay full USDC amount; mint 10e18 asset units to OM
            issuer.fillOrder(ord, ord.paymentTokenQuantity, 1000e18, 0);
            // OM now holds DShare; log
            console.log(
                "OM received asset for token", i, ":", IERC20(ord.assetToken).balanceOf(address(dinariOrderManager))
            );
        }

        // Allow processor to act as factory for completion
        vm.prank(dinariStorage.owner());
        dinariStorage.setFactory(address(processor));
        // Complete issuance via processor → OrderManager → IndexFactory
        processor.completeIssuance(indexTokenAddr, nonce);

        uint256 portfolioValue = dinariStorage.getPortfolioValue(address(indexToken));
        console.log("Portfolio value: ", portfolioValue);

        // Check mint
        uint256 ixAfter = indexToken.balanceOf(address(this));
        console.log("Requester IndexToken after completeIssuance:", ixAfter);
        assertGt(ixAfter, ixBefore, "index token must be minted to requester");
    }
}

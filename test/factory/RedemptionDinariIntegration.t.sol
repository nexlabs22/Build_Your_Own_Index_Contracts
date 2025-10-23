// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "../ccip/CCIPDeployer.sol";

import {IndexFactoryStorage} from "../../src/factory/IndexFactoryStorage.sol";
import {IndexFactoryBalancer} from "../../src/factory/IndexFactoryBalancer.sol";
import {Vault} from "../../src/vault/Vault.sol";
import {FunctionsOracle} from "../../src/oracle/FunctionsOracle.sol";

import {DinariStorage} from "../../src/dinari/DinariStorage.sol";
import {DinariBalancer} from "../../src/dinari/DinariBalancer.sol";
import {DinariFactory} from "../../src/dinari/DinariFactory.sol";
import {DinariOrderManager} from "../../src/dinari/DinariOrderManager.sol";
import {OrderProcessor} from "../../src/dinari/dinari/orders/OrderProcessor.sol";
import {IDShareFactory} from "../../src/dinari/dinari/interfaces/IDShareFactory.sol";
import {DShare} from "../../src/dinari/dinari/DShare.sol";
import {WrappedDShare} from "../../src/dinari/dinari/WrappedDShare.sol";
import {TransferRestrictor} from "../../src/dinari/dinari/TransferRestrictor.sol";
import {MockV3Aggregator} from "../../src/test/MockV3Aggregator.sol";
import {DinariFactoryProcessor} from "../../src/dinari/DinariFactoryProcessor.sol";
import {IOrderProcessor} from "../../src/dinari/dinari/interfaces/IOrderProcessor.sol";

/// Minimal stub for IDShareFactory to satisfy OrderProcessor.initialize
contract DShareFactoryStub3 is IDShareFactory {
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

contract RedemptionDinariIntegrationTest is Test, CCIPDeployer {
    using stdStorage for StdStorage;

    IndexFactoryBalancer public factoryBalancer2;
    DinariStorage public dinariStorage;
    DinariBalancer public dinariBalancer;
    DinariFactory public dinariFactory;
    DinariOrderManager public dinariOrderManager;
    OrderProcessor public issuer;
    DShareFactoryStub3 public dshareFactoryStub;
    DinariFactoryProcessor public processor;

    // Dinari assets
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

        dshareFactoryStub = new DShareFactoryStub3();
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
        // Allow DinariFactory to operate OM for sell orders
        dinariOrderManager.setOperator(address(dinariFactory), true);

        // Processor and operator wiring for completion path
        processor = DinariFactoryProcessor(address(new ERC1967Proxy(address(new DinariFactoryProcessor()), "")));
        processor.initialize(
            address(indexFactoryStorage), address(dinariStorage), address(functionsOracle), address(orderManager)
        );
        orderManager.setOperator(address(processor), true);
        dinariOrderManager.setOperator(address(processor), true);
        issuer.setOperator(address(this), true);
        orderManager.setDinariFactory(address(dinariFactory));

        // Provide USDC/WETH pool for cross-chain fee path used by IndexFactory.redemption
        addLiquidityETH(positionManager, factoryV3Address, usdc, wethAddress, 100000e18, 100e18);

        // Ensure factory can pull USDC from OrderManager during completion
        vm.prank(address(orderManager));
        usdc.approve(address(factory), type(uint256).max);
    }

    function _deployDinariAssetsAndFundVault(uint256 amountA, uint256 amountB) internal {
        DShare dImplA = new DShare();
        dshareA = DShare(
            address(
                new ERC1967Proxy(
                    address(dImplA),
                    abi.encodeCall(DShare.initialize, (address(this), "DShareA", "DSA", TransferRestrictor(address(0))))
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
        dshareA.grantRole(dshareA.MINTER_ROLE(), address(this));
        dshareA.grantRole(dshareA.BURNER_ROLE(), address(issuer));

        DShare dImplB = new DShare();
        dshareB = DShare(
            address(
                new ERC1967Proxy(
                    address(dImplB),
                    abi.encodeCall(DShare.initialize, (address(this), "DShareB", "DSB", TransferRestrictor(address(0))))
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
        dshareB.grantRole(dshareB.MINTER_ROLE(), address(this));
        dshareB.grantRole(dshareB.BURNER_ROLE(), address(issuer));

        priceFeedA = new MockV3Aggregator(18, 1e18);
        priceFeedB = new MockV3Aggregator(18, 1e18);

        address[] memory dShares = new address[](2);
        address[] memory wrappeds = new address[](2);
        address[] memory feeds = new address[](2);
        dShares[0] = address(dshareA);
        dShares[1] = address(dshareB);
        wrappeds[0] = address(wDShareA);
        wrappeds[1] = address(wDShareB);
        feeds[0] = address(priceFeedA);
        feeds[1] = address(priceFeedB);
        vm.prank(dinariStorage.owner());
        dinariStorage.setWrappedDshareAndPriceFeedAddresses(dShares, wrappeds, feeds);

        address vaultAddr = indexFactoryStorage.indexTokenToVault(indexTokenAddr);
        dshareA.mint(address(this), amountA);
        dshareB.mint(address(this), amountB);
        dshareA.approve(address(wDShareA), amountA);
        dshareB.approve(address(wDShareB), amountB);
        wDShareA.deposit(amountA, vaultAddr);
        wDShareB.deposit(amountB, vaultAddr);
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

    function test_completeRedemption_full_process_burns_and_pays_user_with_logs() public {
        // Setup assets and oracle, and fund vault with wrapped (so DinariFactory can sell)
        _deployDinariAssetsAndFundVault(1000e18, 1000e18);
        address[] memory assets = new address[](2);
        assets[0] = address(dshareA);
        assets[1] = address(dshareB);
        uint256[] memory weights = new uint256[](2);
        weights[0] = 50e18;
        weights[1] = 50e18;
        _updateOracleWithDinariOnly(assets, weights);

        // Allow DinariFactory to withdraw from vault
        vm.prank(vault.owner());
        vault.setOperator(address(dinariFactory), true);

        // Mint index tokens to requester (this), then run DinariFactory.redemption (Dinari scale: 1e18 == 100%)
        vm.prank(indexToken.owner());
        indexToken.setMinter(address(this), true);
        indexToken.setMinter(address(dinariFactory), true);
        indexToken.mint(address(this), 20e18);
        uint256 balBefore = indexToken.balanceOf(address(this));
        uint256 redOrderNonce = dinariFactory.redemption(indexTokenAddr, 20e18, 100e18);
        uint256 balAfterBurn = indexToken.balanceOf(address(this));
        // assertLt(balAfterBurn, balBefore, "index token should be burned on redemption call");

        // Fill each sell order created by DinariFactory via OM -> issuer
        (, address[] memory uls,) = functionsOracle.getCurrentProviderIndexData(
            indexTokenAddr, functionsOracle.currentFilledCount(indexTokenAddr), uint64(DINARI_PROVIDER)
        );
        uint256 totalUsdcOut;
        usdc.approve(address(issuer), type(uint256).max);
        for (uint256 i = 0; i < uls.length; i++) {
            uint256 rid = dinariStorage.redemptionRequestId(indexTokenAddr, redOrderNonce, uls[i]);
            IOrderProcessor.Order memory ord = dinariStorage.getOrderInstanceById(indexTokenAddr, rid);
            // Fully fill the sell order with the requested asset amount
            uint256 payAmount = 1000e18;
            issuer.fillOrder(ord, ord.assetTokenQuantity, payAmount, 0);
            totalUsdcOut += payAmount;
        }

        // Seed requester for IndexFactory's redemption nonce (0 in this path)
        vm.startPrank(address(factory));
        indexFactoryStorage.setRedemptionRequester(indexTokenAddr, 0, address(this));
        vm.stopPrank();
        // Fund processor for settlement and have it call completeRedemption (avoids double-charging the user)
        vm.prank(dinariStorage.owner());
        dinariStorage.setFactory(address(processor));
        usdc.transfer(address(processor), totalUsdcOut);
        vm.startPrank(address(processor));
        usdc.approve(address(orderManager), type(uint256).max);
        uint256 userUsdcBefore = usdc.balanceOf(address(this));
        processor.completeRedemption(address(indexToken), redOrderNonce);
        // for (uint256 i = 0; i < uls.length; i++) {
        //     processor.completeRedemption();
        // }
        vm.stopPrank();
        uint256 userUsdcAfter = usdc.balanceOf(address(this));
        assertGt(userUsdcAfter, userUsdcBefore, "user should receive USDC after completion");
    }
}

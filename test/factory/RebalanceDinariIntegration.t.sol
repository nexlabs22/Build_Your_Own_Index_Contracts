// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "../ccip/CCIPDeployer.sol";

import {IndexFactoryStorage} from "../../src/factory/IndexFactoryStorage.sol";
import {IndexFactoryBalancer} from "../../src/factory/IndexFactoryBalancer.sol";
import {MainChainBalancer} from "../../src/ccip/MainChainBalancer.sol";
import {FunctionsOracle} from "../../src/oracle/FunctionsOracle.sol";
import {Vault} from "../../src/vault/Vault.sol";

import {DinariStorage} from "../../src/dinari/DinariStorage.sol";
import {DinariBalancer} from "../../src/dinari/DinariBalancer.sol";
import {DShare} from "../../src/dinari/dinari/DShare.sol";
import {WrappedDShare} from "../../src/dinari/dinari/WrappedDShare.sol";
import {TransferRestrictor} from "../../src/dinari/dinari/TransferRestrictor.sol";
import {MockV3Aggregator} from "../../src/test/MockV3Aggregator.sol";

contract RebalanceDinariIntegrationTest is Test, CCIPDeployer {
    using stdStorage for StdStorage;

    IndexFactoryBalancer public factoryBalancer2;
    DinariStorage public dinariStorage;
    DinariBalancer public dinariBalancer;

    // Two Dinari assets (DShare + Wrapped)
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

        // Fresh global balancer that knows Dinari
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

        vm.startPrank(dinariStorage.owner());
        dinariStorage.setFunctionsOracle(address(functionsOracle));
        vm.stopPrank();

        dinariBalancer.initialize(
            address(dinariStorage), address(functionsOracle), address(indexFactoryStorage), address(factoryBalancer2)
        );

        // Route MainChain balancers to the new global balancer
        mainChainBalancer.setIndexFactoryBalancer(address(factoryBalancer2));
        balancerSender.setIndexFactoryBalancer(address(factoryBalancer2));
        functionsOracle.setOperator(address(factoryBalancer2), true);
    }

    function _deployDinariAssetsAndFundVault(uint256 amountA, uint256 amountB) internal {
        // DShare A via proxy
        DShare dImplA = new DShare();
        dshareA = DShare(
            address(
                new ERC1967Proxy(
                    address(dImplA),
                    abi.encodeCall(DShare.initialize, (address(this), "DShareA", "DSA", TransferRestrictor(address(0))))
                )
            )
        );
        // WrappedDShare A via proxy
        WrappedDShare wImplA = new WrappedDShare();
        wDShareA = WrappedDShare(
            address(
                new ERC1967Proxy(
                    address(wImplA), abi.encodeCall(WrappedDShare.initialize, (address(this), dshareA, "wDSA", "wDSA"))
                )
            )
        );
        // Grant minter role to this test to mint underlying
        dshareA.grantRole(dshareA.MINTER_ROLE(), address(this));

        // DShare B via proxy
        DShare dImplB = new DShare();
        dshareB = DShare(
            address(
                new ERC1967Proxy(
                    address(dImplB),
                    abi.encodeCall(DShare.initialize, (address(this), "DShareB", "DSB", TransferRestrictor(address(0))))
                )
            )
        );
        // WrappedDShare B via proxy
        WrappedDShare wImplB = new WrappedDShare();
        wDShareB = WrappedDShare(
            address(
                new ERC1967Proxy(
                    address(wImplB), abi.encodeCall(WrappedDShare.initialize, (address(this), dshareB, "wDSB", "wDSB"))
                )
            )
        );
        dshareB.grantRole(dshareB.MINTER_ROLE(), address(this));

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
            chains[i] = 2; // arbitrary non-zero
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

    function test_rebalance_askvalues_records_global_and_provider() public {
        _deployDinariAssetsAndFundVault(500e18, 300e18);

        address[] memory assets = new address[](2);
        assets[0] = address(dshareA);
        assets[1] = address(dshareB);
        uint256[] memory weights = new uint256[](2);
        weights[0] = 60e18;
        weights[1] = 40e18;
        _updateOracleWithDinariOnly(assets, weights);

        uint256 nextProviderNonce = dinariBalancer.rebalanceNonce(indexTokenAddr) + 1;
        // providerNonceToGlobalNonce[DINARI_PROVIDER][nextProviderNonce] = 1;
        bytes32 outer = keccak256(abi.encode(uint64(DINARI_PROVIDER), uint256(7)));
        bytes32 leaf = keccak256(abi.encode(nextProviderNonce, outer));
        vm.store(address(factoryBalancer2), leaf, bytes32(uint256(1)));

        functionsOracle.setOperator(address(this), true);
        // Compute portfolio via storage and complete on global balancer
        uint256 expectedUsd = dinariStorage.getPortfolioValue(indexTokenAddr);
        // provider nonce -> global nonce already mapped above
        factoryBalancer2.completeDinariAskValues(nextProviderNonce, expectedUsd);

        uint256 expectedUsd1 = 800e18;
        assertEq(factoryBalancer2.portfolioTotalValueByNonce(1), expectedUsd1);
        assertEq(factoryBalancer2.providerTotalValueByNonce(1, uint64(DINARI_PROVIDER)), expectedUsd1);
    }
}

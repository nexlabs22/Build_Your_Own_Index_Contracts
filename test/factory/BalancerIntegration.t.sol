// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {DinariBalancer} from "../../src/dinari/DinariBalancer.sol";
import {DinariStorage} from "../../src/dinari/DinariStorage.sol";
import {BackedFiBalancer} from "../../src/backedfi/BackedFiBalancer.sol";
import {BackedFiStorage} from "../../src/backedfi/BackedFiStorage.sol";
import {StagingCustodyAccount} from "../../src/backedfi/StagingCustodyAccount.sol";
import {IndexFactoryBalancer} from "../../src/factory/IndexFactoryBalancer.sol";
import {IndexFactoryStorage} from "../../src/factory/IndexFactoryStorage.sol";
import {FunctionsOracle} from "../../src/oracle/FunctionsOracle.sol";
import {OrderProcessor} from "../../src/dinari/dinari/orders/OrderProcessor.sol";
import {DinariOrderManager} from "../../src/dinari/DinariOrderManager.sol";
import {TestERC20} from "../utils/TestERC20.sol";
import {Vault} from "../../src/vault/Vault.sol";

contract MockMainChainBalancer {
    address public lastIndexToken;
    uint256 public askCount;

    function askValues(address indexToken) external returns (uint256) {
        lastIndexToken = indexToken;
        askCount += 1;
        return askCount;
    }
}

contract BalancerIntegrationTest is Test {
    address internal owner = makeAddr("owner");
    address internal operator = makeAddr("operator");
    address internal nexBot = makeAddr("nexBot");
    address internal indexToken = makeAddr("index-token");

    DinariBalancer internal dinariBalancer;
    DinariStorage internal dinariStorage;
    DinariOrderManager internal dinariOrderManager;
    BackedFiBalancer internal backedFiBalancer;
    BackedFiStorage internal backedFiStorage;
    StagingCustodyAccount internal sca;
    IndexFactoryBalancer internal factoryBalancer;
    IndexFactoryStorage internal factoryStorage;
    FunctionsOracle internal oracle;
    TestERC20 internal usdc;
    Vault internal vault;

    uint8 internal constant DINARI_PROVIDER = 2;
    uint8 internal constant BACKED_PROVIDER = 3;

    function setUp() public {
        vm.startPrank(owner);

        // Functions oracle
        FunctionsOracle oracleImpl = new FunctionsOracle();
        oracle = FunctionsOracle(
            address(
                new ERC1967Proxy(
                    address(oracleImpl),
                    abi.encodeWithSelector(FunctionsOracle.initialize.selector, address(0x01), bytes32("DON"))
                )
            )
        );
        oracle.setOperator(operator, true);

        // Global storage
        IndexFactoryStorage factoryStorageImpl = new IndexFactoryStorage();
        factoryStorage = IndexFactoryStorage(
            address(
                new ERC1967Proxy(
                    address(factoryStorageImpl), abi.encodeWithSelector(IndexFactoryStorage.initialize.selector)
                )
            )
        );

        // Dinari components
        DinariStorage dinariStorageImpl = new DinariStorage();
        dinariStorage = DinariStorage(address(new ERC1967Proxy(address(dinariStorageImpl), "")));

        DinariBalancer dinariBalancerImpl = new DinariBalancer();
        dinariBalancer = DinariBalancer(address(new ERC1967Proxy(address(dinariBalancerImpl), "")));

        // Main-chain balancer stub
        MockMainChainBalancer mockMainChain = new MockMainChainBalancer();

        // Index factory balancer
        IndexFactoryBalancer factoryBalancerImpl = new IndexFactoryBalancer();
        factoryBalancer = IndexFactoryBalancer(
            address(
                new ERC1967Proxy(
                    address(factoryBalancerImpl),
                    abi.encodeWithSelector(
                        IndexFactoryBalancer.initialize.selector,
                        address(oracle),
                        address(factoryStorage),
                        address(mockMainChain),
                        address(mockMainChain),
                        address(dinariBalancer)
                    )
                )
            )
        );

        // Finish Dinari wiring
        dinariBalancer.initialize(
            address(dinariStorage), address(oracle), address(factoryStorage), address(factoryBalancer)
        );

        OrderProcessor orderProcessor = new OrderProcessor();
        usdc = new TestERC20("USD Coin", "USDC");
        dinariStorage.initialize(
            address(orderProcessor),
            address(factoryStorage),
            address(dinariBalancer),
            address(usdc),
            6,
            address(oracle),
            false,
            DINARI_PROVIDER
        );

        DinariOrderManager orderManagerImpl = new DinariOrderManager();
        dinariOrderManager = DinariOrderManager(
            address(
                new ERC1967Proxy(
                    address(orderManagerImpl),
                    abi.encodeWithSelector(
                        DinariOrderManager.initialize.selector, address(usdc), uint8(6), address(orderProcessor)
                    )
                )
            )
        );
        dinariStorage.setOrderManager(address(dinariOrderManager));
        dinariStorage.setFactory(address(dinariBalancer));
        dinariStorage.setFactoryBalancer(address(factoryBalancer));

        // BackedFi components
        BackedFiStorage backedStorageImpl = new BackedFiStorage();
        backedFiStorage = BackedFiStorage(address(new ERC1967Proxy(address(backedStorageImpl), "")));

        StagingCustodyAccount scaImpl = new StagingCustodyAccount();
        sca = StagingCustodyAccount(address(new ERC1967Proxy(address(scaImpl), "")));

        backedFiStorage.initialize(
            address(0xFACADE), address(oracle), address(sca), nexBot, address(usdc), BACKED_PROVIDER
        );
        sca.initialize(address(backedFiStorage));

        BackedFiBalancer backedBalancerImpl = new BackedFiBalancer();
        backedFiBalancer = BackedFiBalancer(address(new ERC1967Proxy(address(backedBalancerImpl), "")));
        backedFiBalancer.initialize(address(backedFiStorage), address(oracle), address(factoryStorage));

        vm.stopPrank();

        // Map index token to shared vault
        vault = new Vault();
        bytes32 vaultSlot = keccak256(abi.encode(indexToken, uint256(5)));
        vm.store(address(factoryStorage), vaultSlot, bytes32(uint256(uint160(address(vault)))));
    }

    function testDinariSurplusBecomesAvailableForBackedFi() public {
        // Arrange Dinari state
        uint256 nonce = 1;
        bytes32 nonceSlot = keccak256(abi.encode(indexToken, uint256(4)));
        vm.store(address(dinariBalancer), nonceSlot, bytes32(nonce));

        vm.mockCall(
            address(oracle), abi.encodeWithSignature("currentFilledCount(address)", indexToken), abi.encode(uint256(0))
        );
        address[] memory tokens = new address[](0);
        uint256[] memory shares = new uint256[](0);
        vm.mockCall(
            address(oracle),
            abi.encodeWithSelector(
                FunctionsOracle.getCurrentProviderIndexData.selector, indexToken, uint256(0), DINARI_PROVIDER
            ),
            abi.encode(uint256(0), tokens, shares)
        );

        usdc.mint(address(dinariBalancer), 1_000e18);
        bytes32 realizedBase = keccak256(abi.encode(indexToken, uint256(15)));
        bytes32 realizedSlot = keccak256(abi.encode(nonce, realizedBase));
        vm.store(address(dinariBalancer), realizedSlot, bytes32(uint256(750e18)));

        vm.prank(owner);
        dinariBalancer.secondRebalanceAction(indexToken, nonce, 0);

        assertEq(usdc.balanceOf(address(factoryBalancer)), 750e18, "global balancer should hold forwarded USDC");
        assertEq(
            dinariBalancer.usdcForwardedByNonce(indexToken, nonce), 750e18, "dinari forwarded bookkeeping should update"
        );

        // Now BackedFi pulls liquidity from the global balancer
        vm.prank(owner);
        uint256 granted =
            factoryBalancer.provideUsdc(indexToken, BACKED_PROVIDER, nonce, address(backedFiBalancer), 600e18);

        assertEq(granted, 600e18, "expected amount granted");
        assertEq(usdc.balanceOf(address(backedFiBalancer)), 600e18, "backedfi balancer receives USDC");
        assertEq(usdc.balanceOf(address(factoryBalancer)), 150e18, "global balancer retains surplus");

        vm.clearMockedCalls();
    }
}

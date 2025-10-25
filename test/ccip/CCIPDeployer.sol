// SPDX-License-Identifier: UNLICENSED
// pragma solidity ^0.8.13;
pragma solidity ^0.8.7;

import "forge-std/Test.sol";

import "../../src/token/IndexToken.sol";
import "../../src/test/MockV3Aggregator.sol";
import "../../src/test/MockApiOracle.sol";
import "../../src/test/LinkToken.sol";
import "../../src/test/MockRouter.sol";
import "../../src/test/MockRouter2.sol";
import "../../src/test/MockRouter3.sol";
import "../../src/test/UniswapFactoryByteCode.sol";
import "../../src/test/PriceOracleByteCode.sol";
import "../../src/test/UniswapWETHByteCode.sol";
import "../../src/test/UniswapRouterByteCode.sol";
import "../../src/test/UniswapPositionManagerByteCode.sol";
import "../../src/ccip/CoreSender.sol";
import "../../src/factory/IndexFactory.sol";
import "../../src/factory/IndexFactoryBalancer.sol";
import "../../src/factory/IndexFactoryStorage.sol";
import "../../src/ccip/MainChainFactory.sol";
import "../../src/ccip/MainChainStorage.sol";
import "../../src/ccip/MainChainBalancer.sol";
import "../../src/ccip/MainChainBalancer2.sol";
import "../../src/oracle/FunctionsOracle.sol";
import "../../src/ccip/MainChainStorage.sol";
import "../../src/orderManager/OrderManager.sol";
import "../../src/vault/Vault.sol";
import "../../src/ccip/CrossChainIndexFactory.sol";
import "../../src/ccip/CrossChainIndexFactoryStorage.sol";
import "../../src/ccip/CrossChainIndexFactoryBalancer.sol";

import "../../src/test/Token.sol";
// import "../../src/ccip/CrossChainFeeSender.sol";
// import "../../src/ccip/CrossChainFeeReceiver.sol";

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import "@uniswap/v3-periphery/contracts/interfaces/IQuoter.sol";

import "../../src/interfaces/INonfungiblePositionManager.sol";
import "../../src/interfaces/IUniswapV3Factory2.sol";
import "../../src/interfaces/IWETH.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract CCIPDeployer is
    Test,
    UniswapFactoryByteCode,
    UniswapWETHByteCode,
    UniswapRouterByteCode,
    UniswapPositionManagerByteCode,
    PriceOracleByteCode
{
    bytes32 jobId = "6b88e0402e5d415eb946e528b8e0c7ba";

    address feeReceiver = vm.addr(1);
    address newFeeReceiver = vm.addr(2);
    address minter = vm.addr(3);
    address newMinter = vm.addr(4);
    address methodologist = vm.addr(5);
    address owner = vm.addr(6);
    address add1 = vm.addr(7);

    Token token0;
    Token token1;
    Token token2;
    Token token3;
    Token token4;
    Token token5;
    Token token6;
    Token token7;
    Token token8;
    Token token9;

    Token usdc;

    // Token crossChainToken;

    address priceOracleAddress;
    address factoryV3Address;
    address mainChainFactoryAddress;
    address wethAddress;
    address router;
    address positionManager;
    IndexToken public indexToken;
    MockApiOracle public oracle;
    LinkToken link;
    CoreSender public coreSender;
    MainChainFactory public mainChainFactory;
    IndexFactory public factory;
    IndexFactoryBalancer public factoryBalancer;
    OrderManager public orderManager;
    BalancerSender public balancerSender;
    MainChainBalancer public mainChainBalancer;
    MainChainBalancer2 public mainChainBalancer2;
    // CrossChainFeeSender public crossChainFeeSender;
    // CrossChainFeeReceiver public crossChainFeeReceiver;

    CrossChainIndexFactoryStorage public crossChainIndexFactoryStorage;
    CrossChainIndexFactoryStorage public crossChainIndexFactoryStorage1;
    CrossChainIndexFactoryStorage public crossChainIndexFactoryStorage2;
    CrossChainIndexFactoryStorage public crossChainIndexFactoryStorage3;
    CrossChainIndexFactoryStorage public crossChainIndexFactoryStorage4;

    CrossChainIndexFactory public crossChainIndexFactory;
    CrossChainIndexFactory public crossChainIndexFactory1;
    CrossChainIndexFactory public crossChainIndexFactory2;
    CrossChainIndexFactory public crossChainIndexFactory3;
    CrossChainIndexFactory public crossChainIndexFactory4;

    CrossChainIndexFactoryBalancer public crossChainIndexFactoryBalancer;
    CrossChainIndexFactoryBalancer public crossChainIndexFactoryBalancer1;
    CrossChainIndexFactoryBalancer public crossChainIndexFactoryBalancer2;
    CrossChainIndexFactoryBalancer public crossChainIndexFactoryBalancer3;
    CrossChainIndexFactoryBalancer public crossChainIndexFactoryBalancer4;

    Vault public vault;
    Vault public crossChainVault;
    Vault public crossChainVault1;
    Vault public crossChainVault2;
    Vault public crossChainVault3;
    Vault public crossChainVault4;
    FunctionsOracle public functionsOracle;
    IndexFactoryStorage public indexFactoryStorage;
    MainChainStorage public mainChainStorage;
    Token public crossChainToken;
    // TestSwap public testSwap;
    MockV3Aggregator public ethPriceOracle;
    ERC20 public dai;
    IWETH public weth;
    IQuoter public quoter;

    IUniswapV3Factory public factoryV3 = IUniswapV3Factory(factoryV3Address);
    ISwapRouter public swapRouter = ISwapRouter(router);
    // MockRouter mockRouter;
    MockRouter3 mockRouter;
    MockRouter3 mockRouter1;
    MockRouter3 mockRouter2;
    MockRouter3 mockRouter3;
    MockRouter3 mockRouter4;

    function getMinTick(int24 tickSpacing) public pure returns (int24) {
        return int24((int256(-887272) / int256(tickSpacing) + 1) * int256(tickSpacing));
    }

    function getMaxTick(int24 tickSpacing) public pure returns (int24) {
        return int24((int256(887272) / int256(tickSpacing)) * int256(tickSpacing));
    }

    function encodePriceSqrt(uint256 reserve1, uint256 reserve0) public pure returns (uint160) {
        uint256 sqrtPriceX96 = sqrt((reserve1 * 2 ** 192) / reserve0);
        return uint160(sqrtPriceX96);
    }

    function sqrt(uint256 y) public pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    function deployInternalContracts() public returns (LinkToken, MockApiOracle, MockV3Aggregator, MockRouter3) {
        LinkToken link = new LinkToken();
        MockApiOracle oracle = new MockApiOracle();

        MockV3Aggregator ethPriceOracle = new MockV3Aggregator(
            18, //decimals
            2000e18 //initial data
        );

        MockRouter3 mockRouter = new MockRouter3();

        return (link, oracle, ethPriceOracle, mockRouter);
    }

    function deployContracts() public returns (IndexToken, Vault, FunctionsOracle, IndexFactoryStorage) {
        IndexToken indexTokenImpl = new IndexToken();
        indexToken = IndexToken(
            payable(address(
                    new ERC1967Proxy(
                        address(indexTokenImpl),
                        abi.encodeCall(IndexToken.initialize, ("Anti Inflation", "ANFI", 1e18, feeReceiver, 1000000e18))
                    )
                ))
        );

        Vault vaultImpl = new Vault();
        vault = Vault(
            payable(address(new ERC1967Proxy(address(vaultImpl), abi.encodeCall(Vault.initialize, (address(this))))))
        );

        FunctionsOracle functionsOracleImpl = new FunctionsOracle();
        functionsOracle = FunctionsOracle(
            payable(address(
                    new ERC1967Proxy(
                        address(functionsOracleImpl),
                        abi.encodeCall(FunctionsOracle.initialize, (address(oracle), jobId))
                    )
                ))
        );

        IndexFactoryStorage indexFactoryStorageImpl = new IndexFactoryStorage();
        indexFactoryStorage = IndexFactoryStorage(
            payable(address(
                    new ERC1967Proxy(
                        address(indexFactoryStorageImpl), abi.encodeCall(IndexFactoryStorage.initialize, ())
                    )
                ))
        );

        return (indexToken, vault, functionsOracle, indexFactoryStorage);
    }

    function deployContracts2()
        public
        returns (
            Vault,
            MainChainStorage,
            CrossChainIndexFactory,
            CrossChainIndexFactoryBalancer,
            CrossChainIndexFactoryStorage
        )
    {
        Vault crossChainVaultImpl = new Vault();
        crossChainVault = Vault(
            payable(address(
                    new ERC1967Proxy(address(crossChainVaultImpl), abi.encodeCall(Vault.initialize, (address(this))))
                ))
        );

        CrossChainIndexFactoryStorage crossChainIndexFactoryStorageImpl = new CrossChainIndexFactoryStorage();
        crossChainIndexFactoryStorage = CrossChainIndexFactoryStorage(
            payable(address(
                    new ERC1967Proxy(
                        address(crossChainIndexFactoryStorageImpl),
                        abi.encodeCall(
                            CrossChainIndexFactoryStorage.initialize,
                            (
                                2,
                                address(link),
                                address(mockRouter),
                                wethAddress,
                                router,
                                factoryV3Address,
                                router,
                                address(ethPriceOracle)
                            )
                        )
                    )
                ))
        );

        CrossChainIndexFactory crossChainIndexFactoryImpl = new CrossChainIndexFactory();
        crossChainIndexFactory = CrossChainIndexFactory(
            payable(address(
                    new ERC1967Proxy(
                        address(crossChainIndexFactoryImpl),
                        abi.encodeCall(
                            CrossChainIndexFactory.initialize,
                            (address(crossChainIndexFactoryStorage), address(mockRouter), address(link))
                        )
                    )
                ))
        );

        CrossChainIndexFactoryBalancer crossChainIndexFactoryBalancerImpl = new CrossChainIndexFactoryBalancer();
        crossChainIndexFactoryBalancer = CrossChainIndexFactoryBalancer(
            payable(address(
                    new ERC1967Proxy(
                        address(crossChainIndexFactoryBalancerImpl),
                        abi.encodeCall(
                            CrossChainIndexFactoryBalancer.initialize,
                            (address(crossChainIndexFactoryStorage), address(mockRouter), address(link))
                        )
                    )
                ))
        );

        MainChainStorage mainChainStorageImpl = new MainChainStorage();
        mainChainStorage = MainChainStorage(
            payable(address(
                    new ERC1967Proxy(
                        address(mainChainStorageImpl),
                        abi.encodeCall(
                            MainChainStorage.initialize,
                            (
                                1,
                                address(functionsOracle),
                                address(ethPriceOracle),
                                address(link),
                                wethAddress,
                                router,
                                factoryV3Address,
                                router,
                                factoryV3Address
                            )
                        )
                    )
                ))
        );

        return (
            crossChainVault,
            mainChainStorage,
            crossChainIndexFactory,
            crossChainIndexFactoryBalancer,
            crossChainIndexFactoryStorage
        );
    }

    function deployContracts3()
        public
        returns (OrderManager, CoreSender, IndexFactory, MainChainFactory, BalancerSender)
    {
        OrderManager orderManagerImpl = new OrderManager();
        orderManager = OrderManager(
            payable(address(
                    new ERC1967Proxy(
                        address(orderManagerImpl),
                        abi.encodeCall(OrderManager.initialize, (address(usdc), address(0), address(0)))
                    )
                ))
        );

        CoreSender coreSenderImpl = new CoreSender();
        coreSender = CoreSender(
            payable(address(
                    new ERC1967Proxy(
                        address(coreSenderImpl),
                        abi.encodeCall(
                            CoreSender.initialize,
                            (
                                payable(address(indexToken)),
                                address(mainChainStorage),
                                address(orderManager), // order manager
                                address(functionsOracle),
                                address(link),
                                address(mockRouter), // ccip router
                                wethAddress,
                                address(usdc)
                            )
                        )
                    )
                ))
        );

        IndexFactory indexFactoryImpl = new IndexFactory();
        IndexFactory indexFactory = IndexFactory(
            payable(address(
                    new ERC1967Proxy(
                        address(indexFactoryImpl),
                        abi.encodeCall(
                            IndexFactory.initialize,
                            (address(orderManager), address(functionsOracle), address(indexFactoryStorage))
                        )
                    )
                ))
        );

        MainChainFactory mainChainFactoryImpl = new MainChainFactory();
        MainChainFactory mainChainFactory = MainChainFactory(
            payable(address(
                    new ERC1967Proxy(
                        address(mainChainFactoryImpl),
                        abi.encodeCall(
                            MainChainFactory.initialize,
                            (
                                1,
                                payable(address(indexToken)),
                                address(orderManager), // order manager
                                address(mainChainStorage),
                                address(functionsOracle),
                                payable(address(coreSender)),
                                wethAddress,
                                address(usdc)
                            )
                        )
                    )
                ))
        );

        BalancerSender balancerSenderImpl = new BalancerSender();
        balancerSender = BalancerSender(
            payable(address(
                    new ERC1967Proxy(
                        address(balancerSenderImpl),
                        abi.encodeCall(
                            BalancerSender.initialize,
                            (
                                1,
                                address(mainChainStorage),
                                address(functionsOracle),
                                address(link),
                                address(mockRouter), // ccip router
                                wethAddress
                            )
                        )
                    )
                ))
        );

        return (orderManager, coreSender, indexFactory, mainChainFactory, balancerSender);
    }

    function deployContracts4() public returns (MainChainBalancer, MainChainBalancer2, IndexFactoryBalancer) {
        MainChainBalancer mainChainBalancerImpl = new MainChainBalancer();
        MainChainBalancer mainChainBalancer = MainChainBalancer(
            payable(address(
                    new ERC1967Proxy(
                        address(mainChainBalancerImpl),
                        abi.encodeCall(
                            MainChainBalancer.initialize,
                            (
                                1,
                                address(mainChainStorage),
                                address(functionsOracle),
                                payable(address(balancerSender)),
                                wethAddress,
                                address(usdc)
                            )
                        )
                    )
                ))
        );

        MainChainBalancer2 mainChainBalancer2Impl = new MainChainBalancer2();
        MainChainBalancer2 mainChainBalancer2 = MainChainBalancer2(
            payable(address(
                    new ERC1967Proxy(
                        address(mainChainBalancer2Impl),
                        abi.encodeCall(
                            MainChainBalancer2.initialize,
                            (
                                1,
                                address(mainChainStorage),
                                address(functionsOracle),
                                payable(address(balancerSender)),
                                wethAddress,
                                address(usdc)
                            )
                        )
                    )
                ))
        );

        IndexFactoryBalancer indexFactoryBalancerImpl = new IndexFactoryBalancer();
        IndexFactoryBalancer indexFactoryBalancer = IndexFactoryBalancer(
            payable(address(
                    new ERC1967Proxy(
                        address(indexFactoryBalancerImpl),
                        abi.encodeCall(
                            IndexFactoryBalancer.initialize,
                            (
                                address(functionsOracle),
                                address(indexFactoryStorage),
                                address(mainChainBalancer),
                                address(mainChainBalancer2),
                                address(0)
                            )
                        )
                    )
                ))
        );

        return (mainChainBalancer, mainChainBalancer2, indexFactoryBalancer);
    }

    // function deployContracts3() public returns (CrossChainFeeSender, CrossChainFeeReceiver) {
    //     CrossChainFeeSender crossChainFeeSenderImpl = new CrossChainFeeSender();
    //     crossChainFeeSender = CrossChainFeeSender(
    //         payable(
    //             address(
    //                 new ERC1967Proxy(
    //                     address(crossChainFeeSenderImpl),
    //                     abi.encodeCall(CrossChainFeeSender.initialize, (
    //                         address(indexFactoryStorage),
    //                         address(link),
    //                         address(mockRouter), // ccip router
    //                         wethAddress
    //                     ))
    //                 )
    //             )
    //         )
    //     );

    //     CrossChainFeeReceiver crossChainFeeReceiverImpl = new CrossChainFeeReceiver();
    //     crossChainFeeReceiver = CrossChainFeeReceiver(
    //         payable(
    //             address(
    //                 new ERC1967Proxy(
    //                     address(crossChainFeeReceiverImpl),
    //                     abi.encodeCall(CrossChainFeeReceiver.initialize, (
    //                         address(crossChainIndexFactoryStorage),
    //                         address(mockRouter), // ccip router
    //                         address(link)
    //                     ))
    //                 )
    //             )
    //         )
    //     );

    //     return (crossChainFeeSender, crossChainFeeReceiver);
    // }

    function linkAllContracts() public {
        indexToken.setMinter(address(factory), true);
        indexToken.setMinter(address(coreSender), true);

        uint24[] memory feesData = new uint24[](1);
        feesData[0] = 3000;
        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = address(crossChainToken);

        functionsOracle.setFactoryBalancer(address(factoryBalancer));
        functionsOracle.setOperator(address(factoryBalancer), true);
        functionsOracle.setOperator(address(balancerSender), true);
        // functionsOracle.setBalancerSender(address(balancerSender));
        orderManager.setFactoryAddress(address(factory));
        orderManager.setFactoryStorage(address(indexFactoryStorage));
        orderManager.setMainChainFactory(payable(address(mainChainFactory)));
        orderManager.setOperator(address(factory), true);
        orderManager.setOperator(address(coreSender), true);
        orderManager.setOperator(address(mainChainFactory), true);
        indexFactoryStorage.setOrderManager(address(orderManager));
        indexFactoryStorage.setIndexFactory(address(factory));
        indexFactoryStorage.setUsdcAddress(address(usdc));
        indexFactoryStorage.setToUsdPriceFeed(address(ethPriceOracle));
        indexFactoryStorage.setIndexTokenToVault(address(indexToken), address(vault));
        mainChainBalancer.setIndexFactoryBalancer(address(factoryBalancer));
        mainChainBalancer.setIndexFactoryStorage(address(indexFactoryStorage));
        mainChainBalancer2.setIndexFactoryBalancer(address(factoryBalancer));
        mainChainBalancer2.setIndexFactoryStorage(address(indexFactoryStorage));
        balancerSender.setIndexFactoryBalancer(address(factoryBalancer));
        mainChainFactory.setIndexFactoryStorage(address(indexFactoryStorage));
        mainChainStorage.setCrossChainToken(2, address(crossChainToken), path, feesData);
        // indexFactoryStorage.setCrossChainToken(1, address(crossChainToken), path, feesData);
        mainChainStorage.setCrossChainFactory(address(crossChainIndexFactory), 2);
        mainChainStorage.setCrossChainFactoryBalancer(address(crossChainIndexFactoryBalancer), 2);
        mainChainStorage.setMainChainFactory(address(mainChainFactory));
        mainChainStorage.setIndexFactoryStorage(address(indexFactoryStorage));
        mainChainStorage.setCoreSender(address(coreSender));
        mainChainStorage.setPriceOracle(address(priceOracleAddress));
        mainChainStorage.setVault(address(vault));
        // indexFactoryStorage.setBalancerSender(address(balancerSender));
        // indexFactoryStorage.setMainChainBalancer(address(mainChainBalancer));
        mainChainStorage.setBalancerSender(address(balancerSender));
        mainChainStorage.setMainChainBalancer(address(mainChainBalancer));
        mainChainStorage.setMainChainBalancer2(address(mainChainBalancer2));
        mainChainStorage.setCoreSenderAndBalancerSenderGasLimits(2000000, 2000000);
        mainChainStorage.setIssuanceAndRedemptionFeePercentages(20, 20);
        mainChainStorage.setIsCrossChainFeeSponsered(false);
        vault.setOperator(address(mainChainFactory), true);
        vault.setOperator(address(mainChainBalancer), true);

        // factory.setIndexFactoryStorage(address(indexFactoryStorage));

        crossChainIndexFactoryStorage.setCrossChainToken(1, address(crossChainToken), path, feesData);
        crossChainIndexFactoryStorage.setPriceOracle(priceOracleAddress);
        crossChainIndexFactoryStorage.setCrossChainFactory(address(crossChainIndexFactory));
        crossChainIndexFactoryStorage.setCrossChainFactoryBalancer(address(crossChainIndexFactoryBalancer));
        crossChainIndexFactoryStorage.setVerifiedFactory(address(coreSender), 1, true);
        crossChainIndexFactoryStorage.setVerifiedFactory(address(balancerSender), 1, true);
        crossChainIndexFactoryStorage.setIndexTokenToVault(address(indexToken), address(crossChainVault));

        crossChainVault.setOperator(address(crossChainIndexFactory), true);
        crossChainVault.setOperator(address(crossChainIndexFactoryBalancer), true);

        mockRouter.setFactoryChainSelector(1, address(coreSender));
        mockRouter.setFactoryChainSelector(1, address(factory));
        mockRouter.setFactoryChainSelector(1, address(mainChainFactory));
        mockRouter.setFactoryChainSelector(1, address(mainChainBalancer));
        mockRouter.setFactoryChainSelector(1, address(mainChainBalancer2));
        mockRouter.setFactoryChainSelector(1, address(balancerSender));
        mockRouter.setFactoryChainSelector(2, address(crossChainIndexFactory));
        mockRouter.setFactoryChainSelector(2, address(crossChainIndexFactoryBalancer));
        // mockRouter.setFactoryChainSelector(1, address(crossChainFeeSender));
        // mockRouter.setFactoryChainSelector(2, address(crossChainFeeReceiver));

        link.transfer(address(coreSender), 10e18);
        // link.transfer(address(factory), 10e18);
        link.transfer(address(crossChainIndexFactory), 10e18);
        link.transfer(address(crossChainIndexFactoryBalancer), 10e18);

        // set corsender gas limit and balancer sender gas limit
    }

    function deployTokens(uint256 initialSupply) public returns (Token[12] memory) {
        Token[12] memory tokens;

        for (uint256 i = 0; i < 12; i++) {
            tokens[i] = new Token(initialSupply);
        }

        return tokens;
    }

    function deployUniswap() public returns (address, address, address, address, address) {
        // bytes memory bytecode = factoryByteCode;
        address priceOracleAddress = deployByteCode(priceOracleByteCode);
        address factoryV3Address = deployByteCode(factoryByteCode);
        address wethAddress = deployByteCode(WETHByteCode);
        address routerAddress = deployByteCodeWithInputs(routerByteCode, abi.encode(factoryV3Address, wethAddress));
        address positionManagerAddress = deployByteCodeWithInputs(
            positionManagerByteCode,
            abi.encode(factoryV3Address, wethAddress, 0x5FC8d32690cc91D4c39d9d3abcBD16989F875707)
        );
        // bytes memory bytecodeWithArgs = abi.encodePacked(bytecode, abi.encode(_initData));
        return (priceOracleAddress, factoryV3Address, wethAddress, routerAddress, positionManagerAddress);
    }

    function deployAllContracts(uint256 initialSupply) public {
        Token[12] memory tokens = deployTokens(initialSupply);
        token0 = tokens[0];
        token1 = tokens[1];
        token2 = tokens[2];
        token3 = tokens[3];
        token4 = tokens[4];
        token5 = tokens[5];
        token6 = tokens[6];
        token7 = tokens[7];
        token8 = tokens[8];
        token9 = tokens[9];
        usdc = tokens[10];
        crossChainToken = tokens[11];

        (priceOracleAddress, factoryV3Address, wethAddress, router, positionManager) = deployUniswap();
        factoryV3 = IUniswapV3Factory(factoryV3Address);
        swapRouter = ISwapRouter(router);
        weth = IWETH(wethAddress);
        // (link, oracle, indexToken, ethPriceOracle, factory, testSwap, crossChainIndexFactory, crossChainVault, indexFactoryStorage, crossChainToken) = deployContracts();
        (link, oracle, ethPriceOracle, mockRouter) = deployInternalContracts();

        (indexToken, vault, functionsOracle, indexFactoryStorage) = deployContracts();
        (
            crossChainVault,
            mainChainStorage,
            crossChainIndexFactory,
            crossChainIndexFactoryBalancer,
            crossChainIndexFactoryStorage
        ) = deployContracts2();
        (orderManager, coreSender, factory, mainChainFactory, balancerSender) = deployContracts3();
        (
            mainChainBalancer,
            mainChainBalancer2,
            factoryBalancer // indexFactoryBalancer
        ) = deployContracts4();

        linkAllContracts();
    }

    function deployByteCode(bytes memory bytecode) public returns (address) {
        bytes memory bytecodeWithArgs = bytecode;
        address deployedContract;
        assembly {
            deployedContract := create(0, add(bytecodeWithArgs, 0x20), mload(bytecodeWithArgs))
        }

        return deployedContract;
    }

    function deployByteCodeWithInputs(bytes memory bytecode, bytes memory _initData) public returns (address) {
        bytes memory bytecodeWithArgs = abi.encodePacked(bytecode, _initData);
        address deployedContract;
        assembly {
            deployedContract := create(0, add(bytecodeWithArgs, 0x20), mload(bytecodeWithArgs))
        }

        return deployedContract;
    }

    function addLiquidity(
        address positionManager,
        address factory,
        Token token0,
        Token token1,
        uint256 amount0,
        uint256 amount1
    ) public {
        Token[] memory tokens = new Token[](2);
        tokens[0] = address(token0) < address(token1) ? token0 : token1;
        tokens[1] = address(token0) > address(token1) ? token0 : token1;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = address(tokens[0]) == address(token0) ? amount0 : amount1;
        amounts[1] = address(tokens[1]) == address(token1) ? amount1 : amount0;
        INonfungiblePositionManager(positionManager)
            .createAndInitializePoolIfNecessary(address(tokens[0]), address(tokens[1]), 3000, encodePriceSqrt(1, 1));
        address poolAddress = IUniswapV3Factory2(factory).getPool(address(tokens[0]), address(tokens[1]), 3000);
        tokens[0].approve(positionManager, amounts[0]);
        tokens[1].approve(positionManager, amounts[1]);
        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams(
            address(tokens[0]),
            address(tokens[1]),
            3000,
            getMinTick(3000),
            getMaxTick(3000),
            amounts[0],
            amounts[1],
            0,
            0,
            address(this),
            block.timestamp
        );
        INonfungiblePositionManager(positionManager).mint(params);
    }

    function addLiquidityETH(
        address positionManager,
        address factory,
        Token token0,
        address weth,
        uint256 amount0,
        uint256 amount1
    ) public {
        Token[] memory tokens = new Token[](2);
        tokens[0] = address(token0) < address(weth) ? token0 : Token(weth);
        tokens[1] = address(token0) > address(weth) ? token0 : Token(weth);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = address(token0) < address(weth) ? amount0 : amount1;
        amounts[1] = address(token0) > address(weth) ? amount0 : amount1;
        INonfungiblePositionManager(positionManager)
            .createAndInitializePoolIfNecessary(
                address(tokens[0]), address(tokens[1]), 3000, encodePriceSqrt(amounts[1] / 1e10, amounts[0] / 1e10)
            );
        address poolAddress = IUniswapV3Factory2(factory).getPool(address(tokens[0]), address(tokens[1]), 3000);
        IWETH(weth).deposit{value: amount1}();
        tokens[0].approve(positionManager, amounts[0]);
        tokens[1].approve(positionManager, amounts[1]);
        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams(
            address(tokens[0]),
            address(tokens[1]),
            3000,
            getMinTick(3000),
            getMaxTick(3000),
            amounts[0],
            amounts[1],
            0,
            0,
            address(this),
            block.timestamp
        );
        INonfungiblePositionManager(positionManager).mint(params);
    }
}

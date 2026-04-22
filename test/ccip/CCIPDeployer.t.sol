// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";

import {IndexToken} from "../../src/token/IndexToken.sol";
import {MockV3Aggregator} from "../../src/test/MockV3Aggregator.sol";
import {MockApiOracle} from "../../src/test/MockApiOracle.sol";
import {LinkToken} from "../../src/test/LinkToken.sol";
import {MockRouter3} from "../../src/test/MockRouter3.sol";
import {UniswapFactoryByteCode} from "../../src/test/UniswapFactoryByteCode.sol";
import {PriceOracleByteCode} from "../../src/test/PriceOracleByteCode.sol";
import {UniswapWETHByteCode} from "../../src/test/UniswapWETHByteCode.sol";
import {UniswapRouterByteCode} from "../../src/test/UniswapRouterByteCode.sol";
import {UniswapPositionManagerByteCode} from "../../src/test/UniswapPositionManagerByteCode.sol";
import {CoreSender} from "../../src/ccip/CoreSender.sol";
import {IndexFactory} from "../../src/factory/IndexFactory.sol";
import {IndexFactoryStorage} from "../../src/factory/IndexFactoryStorage.sol";
import {MainChainFactory} from "../../src/ccip/MainChainFactory.sol";
import {MainChainStorage} from "../../src/ccip/MainChainStorage.sol";
import {FunctionsOracle} from "../../src/oracle/FunctionsOracle.sol";
import {OrderManager} from "../../src/orderManager/OrderManager.sol";
import {Vault} from "../../src/vault/Vault.sol";
import {CrossChainIndexFactory} from "../../src/ccip/CrossChainIndexFactory.sol";
import {CrossChainIndexFactoryStorage} from "../../src/ccip/CrossChainIndexFactoryStorage.sol";
import {Token} from "../../src/test/Token.sol";

import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

import {INonfungiblePositionManager} from "../../src/interfaces/INonfungiblePositionManager.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Factory2} from "../../src/interfaces/IUniswapV3Factory2.sol";
import {IWETH} from "../../src/interfaces/IWETH.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// solhint-disable-next-line max-states-count
/// @title ContractDeployer
/// @author NexLabs
/// @notice Utility harness for deploying and wiring CCIP contracts within tests
contract ContractDeployer is
    Test,
    UniswapFactoryByteCode,
    UniswapWETHByteCode,
    UniswapRouterByteCode,
    UniswapPositionManagerByteCode,
    PriceOracleByteCode
{
    /// @notice Error thrown when a Uniswap V3 pool is unexpectedly missing
    error PoolNotCreated();

    /// @notice Chainlink Functions job identifier used during oracle initialisation
    bytes32 internal constant JOB_ID = "6b88e0402e5d415eb946e528b8e0c7ba";

    /// @notice Account designated to collect fees from index token deployments
    address internal feeReceiver = vm.addr(1);

    /// @notice Mock USDC token leveraged when initialising the OrderManager
    Token internal usdc;

    /// @notice Address of the deployed Chainlink price oracle bytecode proxy
    address internal priceOracleAddress;

    /// @notice Address of the Uniswap V3 factory contract deployed for tests
    address internal factoryV3Address;

    /// @notice Address of the deployed main-chain factory proxy
    address internal mainChainFactoryAddress;

    /// @notice Address of the wrapped native token contract instance
    address internal wethAddress;

    /// @notice Address of the Uniswap router contract deployed for swaps
    address internal router;

    /// @notice Address of the Uniswap position manager used for liquidity provisioning
    address internal positionManager;

    /// @notice Deployed instance of the IndexToken under test
    IndexToken internal indexToken;

    /// @notice Mock API oracle used by FunctionsOracle during deployment
    MockApiOracle internal oracle;

    /// @notice LINK token instance supporting CCIP related interactions
    LinkToken internal link;

    /// @notice CoreSender contract responsible for CCIP message dispatch
    CoreSender internal coreSender;

    /// @notice Main chain factory orchestrating issuance flows
    MainChainFactory internal mainChainFactory;

    /// @notice IndexFactory instance managing index deployments
    IndexFactory internal factory;

    /// @notice OrderManager contract coordinating mint and burn requests
    OrderManager internal orderManager;

    /// @notice Storage contract backing cross-chain index factory operations
    CrossChainIndexFactoryStorage internal crossChainIndexFactoryStorage;

    /// @notice Cross-chain index factory responsible for remote deployments
    CrossChainIndexFactory internal crossChainIndexFactory;

    /// @notice Vault contract holding assets on the main chain
    Vault internal vault;

    /// @notice Cross-chain vault deployed on the destination chain
    Vault internal crossChainVault;

    /// @notice Functions oracle proxy mediating Chainlink function requests
    FunctionsOracle internal functionsOracle;

    /// @notice Storage contract maintaining index factory configuration
    IndexFactoryStorage internal indexFactoryStorage;

    /// @notice Storage contract for main-chain CCIP configuration
    MainChainStorage internal mainChainStorage;

    /// @notice Token representing the cross-chain asset utilised in tests
    Token internal crossChainToken;

    /// @notice Mock ETH/USD price oracle feeding on-chain pricing data
    MockV3Aggregator internal ethPriceOracle;

    /// @notice Wrapped native token interface used for Uniswap liquidity provisioning
    IWETH internal weth;

    /// @notice Uniswap V3 factory interface used for pool interactions
    IUniswapV3Factory internal factoryV3;

    /// @notice Swap router interface facilitating Uniswap executions
    ISwapRouter internal swapRouter;

    /// @notice Mock CCIP router utilised for cross-chain messaging
    MockRouter3 internal mockRouter;

    /// @notice Computes the minimum allowable tick for a given spacing
    /// @param tickSpacing Distance in ticks between Uniswap V3 price levels
    /// @return minTick Minimum tick index supported by the spacing
    function getMinTick(int24 tickSpacing) public pure returns (int24 minTick) {
        minTick = int24((int256(-887272) / int256(tickSpacing) + 1) * int256(tickSpacing));
    }

    /// @notice Computes the maximum allowable tick for a given spacing
    /// @param tickSpacing Distance in ticks between Uniswap V3 price levels
    /// @return maxTick Maximum tick index supported by the spacing
    function getMaxTick(int24 tickSpacing) public pure returns (int24 maxTick) {
        maxTick = int24((int256(887272) / int256(tickSpacing)) * int256(tickSpacing));
    }

    /// @notice Derives the square root price encoded as Q64.96 for given reserves
    /// @param reserve1 Reserve amount for token1
    /// @param reserve0 Reserve amount for token0
    /// @return sqrtPriceX96 Encoded square root price in Q64.96 format
    function encodePriceSqrt(uint256 reserve1, uint256 reserve0) public pure returns (uint160 sqrtPriceX96) {
        uint256 rawPrice = (reserve1 * 2 ** 192) / reserve0;
        sqrtPriceX96 = uint160(sqrt(rawPrice));
    }

    /// @notice Calculates the integer square root using the Babylonian method
    /// @param y Value to compute the square root for
    /// @return z Integer square root approximation
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

    /// @notice Deploys mock contracts required across subsequent setup routines
    /// @return linkToken freshly deployed LINK token
    /// @return apiOracle mock API oracle used by FunctionsOracle
    /// @return priceOracle mock ETH/USD feed supplying price data
    /// @return routerInstance mock CCIP router simulating cross-chain messaging
    function deployInternalContracts()
        public
        returns (LinkToken linkToken, MockApiOracle apiOracle, MockV3Aggregator priceOracle, MockRouter3 routerInstance)
    {
        linkToken = new LinkToken();
        apiOracle = new MockApiOracle();

        priceOracle = new MockV3Aggregator(
            18, //decimals
            2000e18 //initial data
        );

        routerInstance = new MockRouter3();
    }

    /// @notice Deploys core contracts required for main-chain index operations
    /// @return deployedIndexToken Proxy-backed index token instance
    /// @return deployedVault Vault instance secured behind a proxy
    /// @return deployedFunctionsOracle Functions oracle configured with mocks
    /// @return deployedIndexFactoryStorage Storage contract supporting the factory
    function deployContracts()
        public
        returns (
            IndexToken deployedIndexToken,
            Vault deployedVault,
            FunctionsOracle deployedFunctionsOracle,
            IndexFactoryStorage deployedIndexFactoryStorage
        )
    {
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
                        abi.encodeCall(FunctionsOracle.initialize, (address(oracle), JOB_ID))
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

        deployedIndexToken = indexToken;
        deployedVault = vault;
        deployedFunctionsOracle = functionsOracle;
        deployedIndexFactoryStorage = indexFactoryStorage;
    }

    /// @notice Deploys cross-chain vault, storage, and factory contracts
    /// @return deployedCrossChainVault Proxy-backed vault on the remote chain
    /// @return deployedMainChainStorage Storage contract for main-chain cross-chain config
    /// @return deployedCrossChainIndexFactory Cross-chain factory coordinating remote issuances
    /// @return deployedCrossChainIndexFactoryStorage Storage backing the cross-chain factory
    function deployContracts2()
        public
        returns (
            Vault deployedCrossChainVault,
            MainChainStorage deployedMainChainStorage,
            CrossChainIndexFactory deployedCrossChainIndexFactory,
            CrossChainIndexFactoryStorage deployedCrossChainIndexFactoryStorage
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
                                payable(address(crossChainVault)),
                                address(link),
                                address(mockRouter),
                                wethAddress,
                                router,
                                mainChainFactoryAddress,
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
                                mainChainFactoryAddress,
                                router,
                                mainChainFactoryAddress
                            )
                        )
                    )
                ))
        );

        deployedCrossChainVault = crossChainVault;
        deployedMainChainStorage = mainChainStorage;
        deployedCrossChainIndexFactory = crossChainIndexFactory;
        deployedCrossChainIndexFactoryStorage = crossChainIndexFactoryStorage;
    }

    /// @notice Deploys order manager, core sender, index factory and main chain factory
    /// @return deployedOrderManager Order manager coordinating asset flows
    /// @return deployedCoreSender Core sender contract for CCIP
    /// @return deployedIndexFactory Factory for launching index tokens
    /// @return deployedMainChainFactory Main chain factory coordinating deployments
    function deployContracts3()
        public
        returns (
            OrderManager deployedOrderManager,
            CoreSender deployedCoreSender,
            IndexFactory deployedIndexFactory,
            MainChainFactory deployedMainChainFactory
        )
    {
        OrderManager orderManagerImpl = new OrderManager();
        orderManager = OrderManager(
            payable(address(
                    new ERC1967Proxy(
                        address(orderManagerImpl), abi.encodeCall(OrderManager.initialize, (address(usdc), address(0)))
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
                                address(0), // order manager
                                address(indexFactoryStorage),
                                address(functionsOracle),
                                address(link),
                                address(mockRouter), // ccip router
                                wethAddress
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
        MainChainFactory mainChainFactoryProxy = MainChainFactory(
            payable(address(
                    new ERC1967Proxy(
                        address(mainChainFactoryImpl),
                        abi.encodeCall(
                            MainChainFactory.initialize,
                            (
                                1,
                                payable(address(indexToken)),
                                address(0), // order manager
                                address(indexFactoryStorage),
                                address(functionsOracle),
                                payable(address(coreSender)),
                                wethAddress
                            )
                        )
                    )
                ))
        );

        deployedOrderManager = orderManager;
        deployedCoreSender = coreSender;
        deployedIndexFactory = indexFactory;
        deployedMainChainFactory = mainChainFactoryProxy;

        // BalancerSender balancerSenderImpl = new BalancerSender();
        // balancerSender = BalancerSender(
        //     payable(
        //         address(
        //             new ERC1967Proxy(
        //                 address(balancerSenderImpl),
        //                 abi.encodeCall(BalancerSender.initialize, (
        //                     1,
        //                     address(indexFactoryStorage),
        //                     address(functionsOracle),
        //                     address(link),
        //                     address(mockRouter), // ccip router
        //                     wethAddress
        //                 ))
        //             )
        //         )
        //     )
        // );

        // IndexFactoryBalancer indexFactoryBalancerImpl = new IndexFactoryBalancer();
        // IndexFactoryBalancer indexFactoryBalancer = IndexFactoryBalancer(
        //     payable(
        //         address(
        //             new ERC1967Proxy(
        //                 address(indexFactoryBalancerImpl),
        //                 abi.encodeCall(IndexFactoryBalancer.initialize, (
        //                     1,
        //                     address(indexFactoryStorage),
        //                     address(functionsOracle),
        //                     payable(address(balancerSender)),
        //                     wethAddress
        //                 ))
        //             )
        //         )
        //     )
        // );

        return (orderManager, coreSender, indexFactory, mainChainFactory);
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

    /// @notice Wires together deployed contracts to emulate production topology
    function linkAllContracts() public {
        indexToken.setMinter(address(factory), true);
        indexToken.setMinter(address(coreSender), true);

        uint24[] memory feesData = new uint24[](1);
        feesData[0] = 3000;
        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = address(crossChainToken);

        // functionsOracle.setIndexFactoryBalancer(address(factoryBalancer));
        // functionsOracle.setBalancerSender(address(balancerSender));
        orderManager.setFactoryAddress(address(factory));
        mainChainStorage.setCrossChainToken(2, address(crossChainToken), path, feesData);
        // indexFactoryStorage.setCrossChainToken(1, address(crossChainToken), path, feesData);
        mainChainStorage.setCrossChainFactory(address(crossChainIndexFactory), 2);
        mainChainStorage.setIndexFactory(address(factory));
        mainChainStorage.setCoreSender(address(coreSender));
        mainChainStorage.setPriceOracle(address(priceOracleAddress));
        mainChainStorage.setVault(address(vault));
        // indexFactoryStorage.setBalancerSender(address(balancerSender));
        // indexFactoryStorage.setIndexFactoryBalancer(address(factoryBalancer));
        mainChainStorage.setCoreSenderAndBalancerSenderGasLimits(2000000, 2000000);
        mainChainStorage.setIssuanceAndRedemptionFeePercentages(20, 20);

        vault.setOperator(address(factory), true);
        // vault.setOperator(address(factoryBalancer), true);

        // factory.setIndexFactoryStorage(address(indexFactoryStorage));

        crossChainIndexFactoryStorage.setCrossChainToken(1, address(crossChainToken), path, feesData);
        crossChainIndexFactoryStorage.setPriceOracle(priceOracleAddress);
        crossChainIndexFactoryStorage.setCrossChainFactory(address(crossChainIndexFactory));
        crossChainIndexFactoryStorage.setVerifiedFactory(address(coreSender), 1, true);
        // crossChainIndexFactoryStorage.setVerifiedFactory(
        //     address(balancerSender),
        //     1,
        //     true
        // );

        crossChainVault.setOperator(address(crossChainIndexFactory), true);

        mockRouter.setFactoryChainSelector(1, address(coreSender));
        mockRouter.setFactoryChainSelector(1, address(factory));
        // mockRouter.setFactoryChainSelector(1, address(factoryBalancer));
        // mockRouter.setFactoryChainSelector(1, address(balancerSender));
        mockRouter.setFactoryChainSelector(2, address(crossChainIndexFactory));
        // mockRouter.setFactoryChainSelector(1, address(crossChainFeeSender));
        // mockRouter.setFactoryChainSelector(2, address(crossChainFeeReceiver));

        link.transfer(address(coreSender), 10e18);
        // link.transfer(address(factory), 10e18);
        link.transfer(address(crossChainIndexFactory), 10e18);

        // set corsender gas limit and balancer sender gas limit
    }

    /// @notice Deploys a fixed set of mock tokens with identical supplies
    /// @param initialSupply Balance minted to each token on creation
    /// @return tokens Array containing the deployed token instances
    function deployTokens(uint256 initialSupply) public returns (Token[12] memory tokens) {
        for (uint256 i = 0; i < 12; ++i) {
            tokens[i] = new Token(initialSupply);
        }
    }

    /// @notice Deploys Uniswap core contracts and returns their addresses
    /// @return priceOracleAddr Address of the deployed price oracle contract
    /// @return factoryV3Addr Address of the deployed Uniswap V3 factory
    /// @return wethAddr Address of the deployed wrapped native token
    /// @return routerAddress Address of the deployed Uniswap router
    /// @return positionManagerAddress Address of the deployed position manager
    function deployUniswap()
        public
        returns (
            address priceOracleAddr,
            address factoryV3Addr,
            address wethAddr,
            address routerAddress,
            address positionManagerAddress
        )
    {
        priceOracleAddr = deployByteCode(priceOracleByteCode);
        factoryV3Addr = deployByteCode(factoryByteCode);
        wethAddr = deployByteCode(WETHByteCode);
        routerAddress = deployByteCodeWithInputs(routerByteCode, abi.encode(factoryV3Addr, wethAddr));
        positionManagerAddress = deployByteCodeWithInputs(
            positionManagerByteCode, abi.encode(factoryV3Addr, wethAddr, 0x5FC8d32690cc91D4c39d9d3abcBD16989F875707)
        );
    }

    /// @notice Deploys all contracts and links them for comprehensive end-to-end tests
    /// @param initialSupply Initial token supply assigned to each mock token
    function deployAllContracts(uint256 initialSupply) public {
        Token[12] memory tokens = deployTokens(initialSupply);
        usdc = tokens[10];
        crossChainToken = tokens[11];

        (priceOracleAddress, factoryV3Address, wethAddress, router, positionManager) = deployUniswap();
        factoryV3 = IUniswapV3Factory(factoryV3Address);
        swapRouter = ISwapRouter(router);
        weth = IWETH(wethAddress);
        (link, oracle, ethPriceOracle, mockRouter) = deployInternalContracts();

        (indexToken, vault, functionsOracle, indexFactoryStorage) = deployContracts();
        (crossChainVault, mainChainStorage, crossChainIndexFactory, crossChainIndexFactoryStorage) = deployContracts2();
        (orderManager, coreSender, factory, mainChainFactory) = deployContracts3();

        linkAllContracts();
    }

    /// @notice Deploys raw bytecode without constructor arguments
    /// @param bytecode Compiled bytecode to deploy
    /// @return deployedContract Address of the deployed contract
    function deployByteCode(bytes memory bytecode) public returns (address deployedContract) {
        bytes memory bytecodeWithArgs = bytecode;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            deployedContract := create(0, add(bytecodeWithArgs, 0x20), mload(bytecodeWithArgs))
        }
    }

    /// @notice Deploys bytecode with constructor arguments appended
    /// @param bytecode Compiled bytecode to deploy
    /// @param initData ABI encoded constructor arguments
    /// @return deployedContract Address of the deployed contract
    function deployByteCodeWithInputs(bytes memory bytecode, bytes memory initData)
        public
        returns (address deployedContract)
    {
        bytes memory bytecodeWithArgs = abi.encodePacked(bytecode, initData);
        // solhint-disable-next-line no-inline-assembly
        assembly {
            deployedContract := create(0, add(bytecodeWithArgs, 0x20), mload(bytecodeWithArgs))
        }
    }

    /// @notice Adds liquidity to a Uniswap V3 pool for two ERC20 tokens
    /// @param positionManagerAddress Address of the Uniswap position manager
    /// @param factoryAddress Address of the Uniswap factory
    /// @param token0 First token in the pair
    /// @param token1 Second token in the pair
    /// @param amount0 Desired amount of the first token
    /// @param amount1 Desired amount of the second token
    function addLiquidity(
        address positionManagerAddress,
        address factoryAddress,
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
        INonfungiblePositionManager(positionManagerAddress)
            .createAndInitializePoolIfNecessary(address(tokens[0]), address(tokens[1]), 3000, encodePriceSqrt(1, 1));
        address poolAddress = IUniswapV3Factory2(factoryAddress).getPool(address(tokens[0]), address(tokens[1]), 3000);
        if (poolAddress == address(0)) revert PoolNotCreated();
        tokens[0].approve(positionManagerAddress, amounts[0]);
        tokens[1].approve(positionManagerAddress, amounts[1]);
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
        INonfungiblePositionManager(positionManagerAddress).mint(params);
    }

    /// @notice Adds liquidity to a token/WETH pool on Uniswap V3
    /// @param positionManagerAddress Address of the Uniswap position manager
    /// @param factoryAddress Address of the Uniswap factory
    /// @param token0 ERC20 token paired with WETH
    /// @param wethAddr Address of the WETH contract
    /// @param amount0 Desired amount of the ERC20 token
    /// @param amount1 Desired amount of WETH
    function addLiquidityETH(
        address positionManagerAddress,
        address factoryAddress,
        Token token0,
        address wethAddr,
        uint256 amount0,
        uint256 amount1
    ) public {
        Token[] memory tokens = new Token[](2);
        tokens[0] = address(token0) < wethAddr ? token0 : Token(wethAddr);
        tokens[1] = address(token0) > wethAddr ? token0 : Token(wethAddr);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = address(token0) < wethAddr ? amount0 : amount1;
        amounts[1] = address(token0) > wethAddr ? amount0 : amount1;
        INonfungiblePositionManager(positionManagerAddress)
            .createAndInitializePoolIfNecessary(
                address(tokens[0]), address(tokens[1]), 3000, encodePriceSqrt(amounts[1] / 1e10, amounts[0] / 1e10)
            );
        address poolAddress = IUniswapV3Factory2(factoryAddress).getPool(address(tokens[0]), address(tokens[1]), 3000);
        if (poolAddress == address(0)) revert PoolNotCreated();
        IWETH(wethAddr).deposit{value: amount1}();
        tokens[0].approve(positionManagerAddress, amounts[0]);
        tokens[1].approve(positionManagerAddress, amounts[1]);
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
        INonfungiblePositionManager(positionManagerAddress).mint(params);
    }
}

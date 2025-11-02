// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "../utils/proposable/ProposableOwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "contracts-ccip/contracts/libraries/Client.sol";
import "contracts-ccip/contracts/interfaces/IRouterClient.sol";
import "../ccip/CCIPReceiver.sol";
import "./MainChainStorage.sol";
import "../oracle/FunctionsOracle.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "../libraries/SwapHelpers.sol";
import "../interfaces/IWETH.sol";
import "../libraries/MessageSender.sol";
import "./MainChainFactory.sol";
import "../factory/IndexFactoryBalancer.sol";
import "./MainChainBalancer.sol";

/// @title Index Token
/// @author NEX Labs Protocol
/// @notice The main token contract for Index Token (NEX Labs Protocol)
/// @dev This contract uses an upgradeable pattern

/// @custom:oz-upgrades-from BalancerSender
contract BalancerSenderV2 is Initializable, CCIPReceiver, ProposableOwnableUpgradeable {
    using MessageSender for *;

    MainChainStorage public mainChainStorage;
    FunctionsOracle public functionsOracle;
    IndexFactoryBalancer public indexFactoryBalancer;

    uint64 public currentChainSelector;
    IWETH public weth;
    uint256 public reweightCalled;

    event MessageSent(bytes32 messageId);
    event AskValuesCompleted(uint256 time);
    event FirstReweightActionCompleted(uint256 time);
    event SecondReweightActionCompleted(uint256 time);

    modifier onlyMainChainBalancer() {
        require(
            msg.sender == mainChainStorage.mainChainBalancer() || msg.sender == mainChainStorage.mainChainBalancer2(),
            "Only factory balancer can call this function"
        );
        _;
    }

    /**
     * @dev Initializes the contract with the given parameters.
     * @param _currentChainSelector The current chain selector.
     * @param _mainChainStorage The address of the MainChainStorage contract.
     * @param _chainlinkToken The address of the Chainlink token.
     * @param _router The address of the router.
     * @param _weth The address of the WETH token.
     */
    function initialize(
        uint64 _currentChainSelector,
        address _mainChainStorage,
        address _functionsOracle,
        address _chainlinkToken,
        //ccip
        address _router,
        //addresses
        address _weth
    ) external initializer {
        // Validate input parameters
        require(_currentChainSelector > 0, "Invalid chain selector");
        require(_mainChainStorage != address(0), "Invalid factory storage address");
        require(_chainlinkToken != address(0), "Invalid Chainlink token address");
        require(_router != address(0), "Invalid router address");
        require(_weth != address(0), "Invalid WETH address");
        __ccipReceiver_init(_router);
        __Ownable_init(msg.sender);
        //set chain selector
        currentChainSelector = _currentChainSelector;
        mainChainStorage = MainChainStorage(_mainChainStorage);
        functionsOracle = FunctionsOracle(_functionsOracle);
        //approve router
        IERC20(_chainlinkToken).approve(i_router, type(uint256).max);
        //set addresses
        weth = IWETH(_weth);
    }

    /**
     * @dev Sets the MainChainStorage contract address.
     * @param _mainChainStorage The address of the MainChainStorage contract.
     */
    function setMainChainStorage(address _mainChainStorage) public onlyOwner {
        mainChainStorage = MainChainStorage(_mainChainStorage);
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Sets the FunctionsOracle contract address.
     * @param _functionsOracle The address of the FunctionsOracle contract.
     */
    function setFunctionsOracle(address _functionsOracle) public onlyOwner {
        functionsOracle = FunctionsOracle(_functionsOracle);
    }

    /**
     * @dev Sets the IndexFactoryBalancer contract address.
     * @param _indexFactoryBalancer The address of the IndexFactoryBalancer contract.
     */
    function setIndexFactoryBalancer(address _indexFactoryBalancer) public onlyOwner {
        indexFactoryBalancer = IndexFactoryBalancer(_indexFactoryBalancer);
    }

    function withdrawLink() external onlyOwner {
        IERC20(mainChainStorage.linkToken())
            .transfer(msg.sender, IERC20(mainChainStorage.linkToken()).balanceOf(address(this)));
    }

    /**
     * @dev Fallback function to receive ETH.
     */
    receive() external payable {}

    function emitFirstReweightActionCompleted() external onlyMainChainBalancer {
        emit FirstReweightActionCompleted(block.timestamp);
    }

    function emitSecondReweightActionCompleted() external onlyMainChainBalancer {
        emit SecondReweightActionCompleted(block.timestamp);
    }

    function pauseMainChainFactory() internal {
        address mainChainFactoryAddress = mainChainStorage.mainChainFactory();
        MainChainFactory mainChainFactory = MainChainFactory(payable(mainChainFactoryAddress));
        if (!mainChainFactory.paused()) {
            mainChainFactory.pause();
        }
    }

    // unpause main chain factory when rebalance is done
    function unpauseMainChainFactory() internal {
        address mainChainFactoryAddress = mainChainStorage.mainChainFactory();
        MainChainFactory mainChainFactory = MainChainFactory(payable(mainChainFactoryAddress));
        if (mainChainFactory.paused()) {
            mainChainFactory.unpause();
        }
    }

    /**
     * @dev Swaps tokens.
     * @param path The path of the swap.
     * @param fees The fees of the swap.
     * @param amountIn The amount of input token.
     * @param _recipient The address of the recipient.
     * @return outputAmount The amount of output token.
     */
    function swap(address[] memory path, uint24[] memory fees, uint256 amountIn, address _recipient)
        public
        returns (uint256 outputAmount)
    {
        // Validate input parameters
        require(amountIn > 0, "Amount must be greater than zero");
        require(_recipient != address(0), "Invalid recipient address");
        ISwapRouter swapRouterV3 = mainChainStorage.swapRouterV3();
        IUniswapV2Router02 swapRouterV2 = mainChainStorage.swapRouterV2();
        uint256 amountOutMinimum = mainChainStorage.getMinAmountOut(path, fees, amountIn);
        outputAmount = SwapHelpers.swap(swapRouterV3, swapRouterV2, path, fees, amountIn, amountOutMinimum, _recipient);
    }

    function sendAskValues(address _indexToken, uint64 chainSelector) public onlyMainChainBalancer {
        address crossChainIndexFactoryBalancer = mainChainStorage.crossChainFactoryBalancerBySelector(chainSelector);

        address[] memory tokenAddresses = functionsOracle.allCurrentChainSelectorTokens(_indexToken, chainSelector);

        bytes memory data = abi.encode(
            2,
            _indexToken,
            tokenAddresses,
            new address[](0),
            functionsOracle.getFromETHPathBytesForTokens(tokenAddresses),
            functionsOracle.getFromETHPathBytesForTokens(new address[](0)),
            // new bytes[](0),
            mainChainStorage.updatePortfolioNonce(),
            new uint256[](0),
            new uint256[](0)
        );
        sendMessage(chainSelector, crossChainIndexFactoryBalancer, data, MessageSender.PayFeesIn.Native);
    }

    function _encodeFirstReweightAction(
        address _indexToken,
        uint64 chainSelector,
        uint256 nonce,
        uint256[] memory oracleTokenShares,
        uint256[] memory extraData
    ) internal view returns (bytes memory) {
        address[] memory currentTokenAddresses =
            functionsOracle.allCurrentChainSelectorTokens(_indexToken, chainSelector);
        address[] memory newTokenAddresses = functionsOracle.allOracleChainSelectorTokens(_indexToken, chainSelector);

        return abi.encode(
            3,
            _indexToken,
            currentTokenAddresses,
            newTokenAddresses,
            functionsOracle.getFromETHPathBytesForTokens(currentTokenAddresses),
            functionsOracle.getFromETHPathBytesForTokens(newTokenAddresses),
            nonce,
            oracleTokenShares,
            extraData
        );
    }

    function sendFirstReweightAction(
        address _indexToken,
        uint256 nonce,
        uint256 portfolioValue,
        uint256 _targetPortfolioValue,
        uint64 chainSelector,
        uint256 oracleChainSelectorTotalShares,
        uint256 chainValue,
        uint256[] memory oracleTokenShares
    ) public onlyMainChainBalancer {
        uint256 chainCurrentRealShare = (chainValue * 100e18)
            / indexFactoryBalancer.getGlobalPortfolioValueByProviderNonce(1, nonce);
        mainChainStorage.increaseReweightExtraPercentage(nonce, chainCurrentRealShare - oracleChainSelectorTotalShares);
        address crossChainIndexFactoryBalancer = mainChainStorage.crossChainFactoryBalancerBySelector(chainSelector);

        uint256[] memory extraData = new uint256[](4);
        extraData[0] = portfolioValue;
        extraData[1] = oracleChainSelectorTotalShares;
        extraData[2] = chainValue;
        extraData[3] = _targetPortfolioValue;

        bytes memory data = _encodeFirstReweightAction(_indexToken, chainSelector, nonce, oracleTokenShares, extraData);

        sendMessage(chainSelector, crossChainIndexFactoryBalancer, data, MessageSender.PayFeesIn.Native);
    }

    function _encodeSecondReweightAction(
        address _indexToken,
        uint64 _chainSelector,
        uint256 _nonce,
        uint256[] memory _oracleTokenShares,
        uint256[] memory _extraData
    ) internal view returns (bytes memory) {
        address[] memory currentTokenAddresses =
            functionsOracle.allCurrentChainSelectorTokens(_indexToken, _chainSelector);
        address[] memory newTokenAddresses = functionsOracle.allOracleChainSelectorTokens(_indexToken, _chainSelector);

        return abi.encode(
            4,
            _indexToken,
            currentTokenAddresses,
            newTokenAddresses,
            functionsOracle.getFromETHPathBytesForTokens(currentTokenAddresses),
            functionsOracle.getFromETHPathBytesForTokens(newTokenAddresses),
            _nonce,
            _oracleTokenShares,
            _extraData
        );
    }

    function sendSecondReweightAction(
        address _indexToken,
        uint256 nonce,
        uint256 _portfolioValue,
        uint64 _chainSelector,
        uint256 _oracleChainSelectorTotalShares,
        uint256[] memory _oracleTokenShares,
        uint256 _extraWethAmount
    ) public onlyMainChainBalancer {
        weth.transferFrom(msg.sender, address(this), _extraWethAmount);
        (address[] memory fromETHPath, uint24[] memory fromETHFees) =
            mainChainStorage.getFromETHPathData(mainChainStorage.crossChainToken(_chainSelector));
        uint256 crossChainTokenAmount = swap(fromETHPath, fromETHFees, _extraWethAmount, address(this));
        reweightCalled = _oracleTokenShares.length;
        uint256[] memory extraData = new uint256[](2);
        extraData[0] = _portfolioValue;
        extraData[1] = _oracleChainSelectorTotalShares;

        address crossChainIndexFactoryBalancer = mainChainStorage.crossChainFactoryBalancerBySelector(_chainSelector);

        bytes memory data =
            _encodeSecondReweightAction(_indexToken, _chainSelector, nonce, _oracleTokenShares, extraData);

        Client.EVMTokenAmount[] memory tokensToSendArray = new Client.EVMTokenAmount[](1);
        tokensToSendArray[0].token = mainChainStorage.crossChainToken(_chainSelector);
        tokensToSendArray[0].amount = crossChainTokenAmount;

        sendToken(
            _chainSelector, data, crossChainIndexFactoryBalancer, tokensToSendArray, MessageSender.PayFeesIn.Native
        );
    }

    /**
     * @dev Sends tokens to another chain.
     * @param destinationChainSelector The destination chain selector.
     * @param _data The data to send.
     * @param receiver The address of the receiver.
     * @param tokensToSendDetails The details of the tokens to send.
     * @param payFeesIn The fee payment method.
     */
    function sendToken(
        uint64 destinationChainSelector,
        bytes memory _data,
        address receiver,
        Client.EVMTokenAmount[] memory tokensToSendDetails,
        MessageSender.PayFeesIn payFeesIn
    ) internal returns (bytes32) {
        mainChainStorage.increaseTotalSentAmount(tokensToSendDetails[0].token, tokensToSendDetails[0].amount);
        bytes32 messageId = MessageSender.sendToken(
            // i_router,
            getRouter(),
            // i_link,
            mainChainStorage.linkToken(),
            mainChainStorage.MAX_TOKENS_LENGTH(),
            destinationChainSelector,
            _data,
            receiver,
            tokensToSendDetails,
            payFeesIn,
            mainChainStorage.balancerSenderGasLimit()
        );
        emit MessageSent(messageId);
        return messageId;
    }

    /**
     * @dev Sends a message to another chain.
     * @param destinationChainSelector The destination chain selector.
     * @param receiver The address of the receiver.
     * @param _data The data to send.
     * @param payFeesIn The fee payment method.
     */
    function sendMessage(
        uint64 destinationChainSelector,
        address receiver,
        bytes memory _data,
        MessageSender.PayFeesIn payFeesIn
    ) public returns (bytes32) {
        // Validate input parameters
        require(destinationChainSelector > 0, "Invalid destination chain selector");
        require(receiver != address(0), "Invalid receiver address");
        require(_data.length > 0, "Data cannot be empty");
        return MessageSender.sendMessage(
            getRouter(),
            mainChainStorage.linkToken(),
            destinationChainSelector,
            receiver,
            _data,
            payFeesIn,
            mainChainStorage.balancerSenderGasLimit()
        );
    }

    function _handleCompleteFirstReweight(uint256 nonce) internal {
        // get total chainSelectors
        mainChainStorage.increaseReweightTotalExtraCompletedChains(nonce, 1);
        if (
            mainChainStorage.totalReweightExtraCompletedChains(nonce)
                == mainChainStorage.totalReweightExtraPendingChains(nonce)
        ) {
            // MainChainBalancer(mainChainStorage.mainChainBalancer()).completeFirstReweightAction(nonce);
            emit FirstReweightActionCompleted(block.timestamp);
        }
    }

    function _handleCompleteSecondReweight(uint256 nonce) internal {
        // get total chainSelectors
        mainChainStorage.increaseReweightTotalLowerCompletedChains(nonce, 1);
        if (
            mainChainStorage.totalReweightLowerCompletedChains(nonce)
                == mainChainStorage.totalReweightLowerPendingChains(nonce)
        ) {
            MainChainBalancer(mainChainStorage.mainChainBalancer()).completeSecondReweightAction(nonce);
            unpauseMainChainFactory();
            emit SecondReweightActionCompleted(block.timestamp);
        }
    }

    /**
     * @dev Handles received messages.
     * @param any2EvmMessage The received message.
     */
    function _ccipReceive(Client.Any2EVMMessage memory any2EvmMessage) internal override {
        // bytes32 messageId = any2EvmMessage.messageId; // fetch the messageId
        uint64 sourceChainSelector = any2EvmMessage.sourceChainSelector; // fetch the source chain identifier (aka selector)
        address sender = abi.decode(any2EvmMessage.sender, (address)); // abi-decoding of the sender address
        require(
            sender == mainChainStorage.crossChainFactoryBySelector(sourceChainSelector)
                || sender == mainChainStorage.crossChainFactoryBalancerBySelector(sourceChainSelector),
            "Invalid sender for the factory balancer ccip recieve"
        );
        (
            uint256 actionType,
            address[] memory tokenAddresses,
            address[] memory _tokenAddresses2,
            bytes[] memory _tokenPaths,
            bytes[] memory _tokenPaths2,
            uint256 nonce,
            uint256[] memory value1,
            uint256[] memory _value2
        ) = abi.decode(
            any2EvmMessage.data, (uint256, address[], address[], bytes[], bytes[], uint256, uint256[], uint256[])
        ); // abi-decoding of the sent string message
        // no-op references to avoid unused local warnings
        if (_tokenAddresses2.length + _tokenPaths.length + _tokenPaths2.length + _value2.length == 2 ** 256 - 1) {
            revert("unreachable");
        }
        if (any2EvmMessage.destTokenAmounts.length > 0) {
            mainChainStorage.increaseTotalReceivedAmount(
                any2EvmMessage.destTokenAmounts[0].token, any2EvmMessage.destTokenAmounts[0].amount
            );
        }
        if (actionType == 0) {} else if (actionType == 1) {} else if (actionType == 2) {
            for (uint256 i = 0; i < value1.length; i++) {
                mainChainStorage.increasePortfolioTotalValueByNonce(nonce, value1[i]);
                mainChainStorage.increaseTokenValueByNonce(nonce, tokenAddresses[i], value1[i]);
                mainChainStorage.increaseChainValueByNonce(nonce, sourceChainSelector, value1[i]);
                mainChainStorage.increaseUpdatedTokensValueCount(nonce);
                indexFactoryBalancer.completeAskValueCCIP(nonce, value1[i]);
                emit AskValuesCompleted(block.timestamp);
            }
        } else if (actionType == 3) {
            if (any2EvmMessage.destTokenAmounts.length > 0) {
                Client.EVMTokenAmount[] memory tokenAmounts = any2EvmMessage.destTokenAmounts;
                address token = tokenAmounts[0].token;
                uint256 amount = tokenAmounts[0].amount;
                (address[] memory toETHPath, uint24[] memory toETHFees) = mainChainStorage.getToETHPathData(token);
                uint256 wethAmount = swap(toETHPath, toETHFees, amount, address(this));
                mainChainStorage.increaseExtraWethByNonce(nonce, wethAmount);
                mainChainStorage.increasePendingExtraWethByNonce(nonce, wethAmount);
                weth.transfer(mainChainStorage.mainChainBalancer(), wethAmount);
            }
            _handleCompleteFirstReweight(nonce);
        } else if (actionType == 4) {
            _handleCompleteSecondReweight(nonce);
        }
    }
}

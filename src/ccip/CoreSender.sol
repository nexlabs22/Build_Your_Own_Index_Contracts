// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "../token/IndexToken.sol";
import "../utils/proposable/ProposableOwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "contracts-ccip/contracts/libraries/Client.sol";
import "contracts-ccip/contracts/interfaces/IRouterClient.sol";
// import "contracts-ccip/contracts/applications/CCIPReceiver.sol";
import "./CCIPReceiver.sol";
import "./CCIPStorage.sol";
import "../oracle/FunctionsOracle.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "../libraries/FeeCalculation.sol";
import "../libraries/MessageSender.sol";
import "../libraries/SwapHelpers.sol";
import "../interfaces/IUniswapV2Router02.sol";
import "../interfaces/IWETH.sol";
/// @title Index Token
/// @author NEX Labs Protocol
/// @notice The main token contract for Index Token (NEX Labs Protocol)
/// @dev This contract uses an upgradeable pattern

contract CoreSender is Initializable, CCIPReceiver, ProposableOwnableUpgradeable, ReentrancyGuardUpgradeable {
    using MessageSender for *;

    IndexToken public indexToken;
    CCIPStorage public factoryStorage;
    FunctionsOracle public functionsOracle;

    IWETH public weth;

    event Issuanced(
        bytes32 indexed messageId,
        uint256 indexed nonce,
        address indexed user,
        address inputToken,
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 price,
        uint256 time
    );

    event Redemption(
        bytes32 indexed messageId,
        uint256 indexed nonce,
        address indexed user,
        address outputToken,
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 price,
        uint256 time
    );
    event MessageSent(bytes32 messageId);

    modifier onlyFactory() {
        require(msg.sender == factoryStorage.indexFactory(), "Only factory can call this function");
        _;
    }

    modifier onlyOwnerOrOperator() {
        require(
            msg.sender == owner() || functionsOracle.isOperator(msg.sender),
            "Only owner or operator can call this function"
        );
        _;
    }

    /**
     * @dev Initializes the contract with the given parameters.
     * @param _token The address of the IndexToken contract.
     * @param _chainlinkToken The address of the Chainlink token.
     * @param _router The address of the router.
     * @param _weth The address of the WETH token.
     */
    function initialize(
        address payable _token,
        address _indexFactoryStorage,
        address _functionsOracle,
        address _chainlinkToken,
        //ccip
        address _router,
        //addresses
        address _weth
    ) external initializer {
        // Validate input parameters
        require(_token != address(0), "Invalid token address");
        require(_chainlinkToken != address(0), "Invalid Chainlink token address");
        require(_router != address(0), "Invalid router address");
        require(_weth != address(0), "Invalid WETH address");

        __ccipReceiver_init(_router);
        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();
        __ReentrancyGuard_init_unchained();
        indexToken = IndexToken(_token);
        factoryStorage = CCIPStorage(_indexFactoryStorage);
        functionsOracle = FunctionsOracle(_functionsOracle);

        IERC20(_chainlinkToken).approve(i_router, type(uint256).max);
        //set addresses
        weth = IWETH(_weth);
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Sets the IndexFactoryStorage contract address.
     * @param _factoryStorage The address of the IndexFactoryStorage contract.
     */
    function setIndexFactoryStorage(address _factoryStorage) public onlyOwner {
        factoryStorage = CCIPStorage(_factoryStorage);
    }

    /**
     * @dev Sets the FunctionsOracle contract address.
     * @param _functionsOracle The address of the FunctionsOracle contract.
     */
    function setFunctionsOracle(address _functionsOracle) public onlyOwner {
        functionsOracle = FunctionsOracle(_functionsOracle);
    }

    function withdrawLink() external onlyOwnerOrOperator {
        IERC20(factoryStorage.linkToken()).transfer(
            msg.sender, IERC20(factoryStorage.linkToken()).balanceOf(address(this))
        );
    }

    /**
     * @dev Fallback function to receive ETH.
     */
    receive() external payable {}

    function withdrawEther() external onlyOwnerOrOperator {
        uint256 balance = address(this).balance;
        require(balance > 0, "No Ether to withdraw");

        (bool success,) = payable(msg.sender).call{value: balance}("");
        require(success, "Ether transfer failed");
    }

    /**
     * @dev Swaps tokens.
     * @param path The path of the tokens.
     * @param fees The fees of the tokens.
     * @param amountIn The amount of input token.
     * @param _recipient The address of the recipient.
     * @return outputAmount The amount of output token.
     */
    function swap(address[] memory path, uint24[] memory fees, uint256 amountIn, address _recipient)
        internal
        returns (uint256 outputAmount)
    {
        ISwapRouter swapRouterV3 = factoryStorage.swapRouterV3();
        IUniswapV2Router02 swapRouterV2 = factoryStorage.swapRouterV2();
        uint256 amountOutMinimum = factoryStorage.getMinAmountOut(path, fees, amountIn);
        outputAmount = SwapHelpers.swap(swapRouterV3, swapRouterV2, path, fees, amountIn, amountOutMinimum, _recipient);
    }

    function _encodeIssuanceData(
        uint256 _issuanceNonce,
        address[] memory _tokenAddresses,
        uint256[] memory _tokenShares,
        uint256[] memory _totalSharesArr
    ) internal view returns (bytes memory) {
        return abi.encode(
            0,
            _tokenAddresses,
            new address[](0),
            functionsOracle.getFromETHPathBytesForTokens(_tokenAddresses),
            functionsOracle.getFromETHPathBytesForTokens(new address[](0)),
            _issuanceNonce,
            _tokenShares,
            _totalSharesArr
        );
    }

    function sendIssuanceRequest(
        uint256 _wethAmount,
        uint256 _issuanceNonce,
        uint64 _chainSelector,
        uint256 _latestCount
    ) public onlyFactory {
        weth.transferFrom(msg.sender, address(this), _wethAmount);
        // swap to cross chain token
        (address[] memory fromETHPath, uint24[] memory fromETHFees) =
            factoryStorage.getFromETHPathData(factoryStorage.crossChainToken(_chainSelector));
        uint256 crossChainTokenAmount = swap(
            fromETHPath,
            fromETHFees,
            // (_wethAmount * totalShares) / 100e18,
            _wethAmount,
            address(this)
        );

        uint256[] memory totalSharesArr = new uint256[](1);
        totalSharesArr[0] = functionsOracle.getCurrentChainSelectorTotalShares(address(0), _latestCount, _chainSelector);
        address crossChainIndexFactory = factoryStorage.crossChainFactoryBySelector(_chainSelector);
        //encode data
        bytes memory data = _encodeIssuanceData(
            _issuanceNonce,
            functionsOracle.allCurrentChainSelectorTokens(address(0), _chainSelector),
            functionsOracle.allCurrentChainSelectorTokenShares(address(0), _chainSelector),
            totalSharesArr
        );
        // send issuance request
        Client.EVMTokenAmount[] memory tokensToSendArray = new Client.EVMTokenAmount[](1);
        tokensToSendArray[0].token = factoryStorage.crossChainToken(_chainSelector);
        tokensToSendArray[0].amount = crossChainTokenAmount;

        // send token and data
        bytes32 messageId =
            sendToken(_chainSelector, data, crossChainIndexFactory, tokensToSendArray, MessageSender.PayFeesIn.Native);
        emit MessageSent(messageId);
        factoryStorage.setIssuanceMessageId(_issuanceNonce, messageId);
    }

    function calculateIssuanceFee(uint64 _chainSelector, uint _wethAmount) public view returns (uint256 totalFee) {
        
        // get cross chain token amount
        (address[] memory fromETHPath, uint24[] memory fromETHFees) =
            factoryStorage.getFromETHPathData(factoryStorage.crossChainToken(_chainSelector));
        uint256 crossChainTokenAmount = factoryStorage.getAmountOut(fromETHPath, fromETHFees, _wethAmount);
        // get cross chain factory
        address crossChainFactory = factoryStorage.crossChainFactoryBySelector(_chainSelector);
        uint256[] memory totalSharesArr = new uint256[](1);
        totalSharesArr[0] = functionsOracle.getCurrentChainSelectorTotalShares(address(0), functionsOracle.currentFilledCount(address(0)), _chainSelector);
        address crossChainIndexFactory = factoryStorage.crossChainFactoryBySelector(_chainSelector);

        //encode data
        bytes memory data = _encodeIssuanceData(
            factoryStorage.issuanceNonce(),
            functionsOracle.allCurrentChainSelectorTokens(address(0), _chainSelector),
            functionsOracle.allCurrentChainSelectorTokenShares(address(0), _chainSelector),
            totalSharesArr
        );

        // send issuance request
        Client.EVMTokenAmount[] memory tokensToSendArray = new Client.EVMTokenAmount[](1);
        tokensToSendArray[0].token = factoryStorage.crossChainToken(_chainSelector);
        tokensToSendArray[0].amount = crossChainTokenAmount;

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(crossChainFactory),
            data: data,
            tokenAmounts: tokensToSendArray,
            feeToken: address(0),
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: factoryStorage.coreSenderGasLimit()}))
        });

        return IRouterClient(i_router).getFee(_chainSelector, message);
    }

    function completeIssuanceRequest(uint256 _issuanceNonce, bytes32 _messageId) internal {
        factoryStorage.decreasePendingIssuanceInputByNonce(_issuanceNonce);
        uint256 totalOldVaules;
        uint256 totalNewVaules;
        uint256 totalCurrentList = functionsOracle.totalCurrentList(address(0));
        for (uint256 i = 0; i < totalCurrentList; i++) {
            address tokenAddress = functionsOracle.currentList(address(0), i);
            totalOldVaules += factoryStorage.getIssuanceOldTokenValue(_issuanceNonce, tokenAddress);
            totalNewVaules += factoryStorage.getIssuanceNewTokenValue(_issuanceNonce, tokenAddress);
        }

        uint256 amountToMint;
        if (indexToken.totalSupply() > 0) {
            amountToMint = (indexToken.totalSupply() * totalNewVaules) / totalOldVaules - indexToken.totalSupply();
        } else {
            amountToMint = (totalNewVaules) / 100;
        }
        indexToken.mint(factoryStorage.getIssuanceRequester(_issuanceNonce), amountToMint);
        uint256 indexTokenPrice = (totalNewVaules * 1e18) / indexToken.totalSupply();
        emit Issuanced(
            _messageId,
            _issuanceNonce,
            factoryStorage.getIssuanceRequester(_issuanceNonce),
            factoryStorage.getIssuanceInputToken(_issuanceNonce),
            factoryStorage.getIssuanceInputAmount(_issuanceNonce),
            amountToMint,
            indexTokenPrice,
            block.timestamp
        );
    }

    function _handleReceivedIssuance(
        uint256 nonce,
        address[] memory tokenAddresses,
        uint256[] memory value1,
        uint256[] memory value2,
        uint256 totalCurrentList,
        bytes32 messageId
    ) internal {
        uint256 requestIssuanceNonce = nonce;
        for (uint256 i; i < tokenAddresses.length; i++) {
            uint256 oldTokenValue = value1[i];
            uint256 newTokenValue = value2[i];
            factoryStorage.setIssuanceOldTokenValue(requestIssuanceNonce, tokenAddresses[i], oldTokenValue);
            factoryStorage.setIssuanceNewTokenValue(requestIssuanceNonce, tokenAddresses[i], newTokenValue);
            factoryStorage.issuanceIncreaseCompletedTokensCount(requestIssuanceNonce);
        }
        if (
            // totalCurrentList
            factoryStorage.getIssuanceCompletedTokensCount(requestIssuanceNonce) == totalCurrentList
        ) {
            completeIssuanceRequest(requestIssuanceNonce, messageId);
        }
    }

    function sendRedemptionRequest(uint256 _burnPercent, uint256 _redemptionNonce, uint64 _chainSelector)
        public
        onlyFactory
    {
        // get data
        address crossChainIndexFactory = factoryStorage.crossChainFactoryBySelector(_chainSelector);
        address[] memory tokenAddresses = functionsOracle.allCurrentChainSelectorTokens(address(0), _chainSelector);
        uint256[] memory burnPercentages = new uint256[](1);
        burnPercentages[0] = _burnPercent;
        //encode data
        bytes memory data = abi.encode(
            1,
            tokenAddresses,
            new address[](0),
            functionsOracle.getFromETHPathBytesForTokens(tokenAddresses),
            new bytes[](0),
            _redemptionNonce,
            new uint256[](0),
            burnPercentages
        );
        // send message
        bytes32 messageId = sendMessage(_chainSelector, crossChainIndexFactory, data, MessageSender.PayFeesIn.Native);

        factoryStorage.setRedemptionMessageId(_redemptionNonce, messageId);
    }

    function calculateRedemptionFee(uint64 _chainSelector) public view returns (uint256 totalFee) {
        // get data
        address crossChainIndexFactory = factoryStorage.crossChainFactoryBySelector(_chainSelector);
        address[] memory tokenAddresses = functionsOracle.allCurrentChainSelectorTokens(address(0), _chainSelector);
        uint256[] memory burnPercentages = new uint256[](1);
        burnPercentages[0] = 0;
        //encode data
        bytes memory data = abi.encode(
            1,
            tokenAddresses,
            new address[](0),
            functionsOracle.getFromETHPathBytesForTokens(tokenAddresses),
            new bytes[](0),
            factoryStorage.redemptionNonce(),
            new uint256[](0),
            burnPercentages
        );
        // send message
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(crossChainIndexFactory),
            data: data,
            tokenAmounts: new Client.EVMTokenAmount[](0),
            feeToken: address(0),
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: factoryStorage.balancerSenderGasLimit()}))
        });

        return IRouterClient(i_router).getFee(_chainSelector, message);
    }


    function completeRedemptionRequest(uint256 nonce, bytes32 _messageId) internal {
        factoryStorage.decreasePendingRedemptionInputByNonce(nonce);
        factoryStorage.decreasePendingRedemptionHoldValueByNonce(nonce);
        uint256 wethAmount = factoryStorage.getRedemptionTotalValue(nonce);
        uint256 totalPortfolioValues = factoryStorage.getRedemptionTotalPortfolioValues(nonce);
        address requester = factoryStorage.getRedemptionRequester(nonce);
        address outputToken = factoryStorage.getRedemptionOutputToken(nonce);
        // uint256 fee = FeeCalculation.calculateFee(wethAmount, factoryStorage.feeRate());
        uint256 fee;
        
        require(weth.transfer(address(0), fee), "Fee transfer failed");
        uint256 indexTokenPrice =
            indexToken.totalSupply() != 0 ? (totalPortfolioValues * 1e18) / indexToken.totalSupply() : 0;
        if (outputToken == address(weth)) {
            weth.withdraw(wethAmount - fee);
            (bool _requesterSuccess,) = requester.call{value: wethAmount - fee}("");
            require(_requesterSuccess, "transfer eth to the requester failed");
            emit Redemption(
                _messageId,
                nonce,
                requester,
                outputToken,
                factoryStorage.getRedemptionInputAmount(nonce),
                wethAmount - fee,
                indexTokenPrice,
                block.timestamp
            );
        } else {
            uint256 reallOut = swap(
                factoryStorage.getRedemptionOutputTokenPath(nonce),
                factoryStorage.getRedemptionOutputTokenFees(nonce),
                wethAmount - fee,
                requester
            );
            emit Redemption(
                _messageId,
                nonce,
                requester,
                outputToken,
                factoryStorage.getRedemptionInputAmount(nonce),
                reallOut,
                indexTokenPrice,
                block.timestamp
            );
        }
    }


    function _handleReceivedRedemption(
        uint256 nonce,
        Client.Any2EVMMessage memory any2EvmMessage,
        address[] memory tokenAddresses,
        uint256 totalCurrentList,
        uint256 crossChainPortfolioValue,
        uint64 sourceChainSelector,
        bytes32 messageId
    ) internal {
        uint256 requestRedemptionNonce = nonce;
        Client.EVMTokenAmount[] memory tokenAmounts = any2EvmMessage.destTokenAmounts;
        address token = tokenAmounts[0].token;
        uint256 amount = tokenAmounts[0].amount;
        (address[] memory toETHPath, uint24[] memory toETHFees) = factoryStorage.getToETHPathData(token);
        uint256 wethAmount = swap(toETHPath, toETHFees, amount, address(this));

        factoryStorage.increaseRedemptionTotalValue(requestRedemptionNonce, wethAmount);
        
        factoryStorage.increaseRedemptionTotalPortfolioValues(requestRedemptionNonce, crossChainPortfolioValue);
        factoryStorage.increaseRedemptionCompletedTokensCount(requestRedemptionNonce, tokenAddresses.length);
        if (factoryStorage.getRedemptionCompletedTokensCount(requestRedemptionNonce) == totalCurrentList) {
            completeRedemptionRequest(requestRedemptionNonce, messageId);
        }
    }

    /**
     * @dev Sends tokens to another chain.
     * @param destinationChainSelector The destination chain selector.
     * @param _data The data to send.
     * @param receiver The address of the receiver.
     * @param tokensToSendDetails The details of the tokens to send.
     * @param payFeesIn The fee payment method.
     * @return The message ID.
     */
    function sendToken(
        uint64 destinationChainSelector,
        bytes memory _data,
        address receiver,
        Client.EVMTokenAmount[] memory tokensToSendDetails,
        MessageSender.PayFeesIn payFeesIn
    ) internal nonReentrant returns (bytes32) {
        factoryStorage.increaseTotalSentAmount(tokensToSendDetails[0].token, tokensToSendDetails[0].amount);
        bytes32 messageId = MessageSender.sendToken(
            getRouter(),
            factoryStorage.linkToken(),
            factoryStorage.MAX_TOKENS_LENGTH(),
            destinationChainSelector,
            _data,
            receiver,
            tokensToSendDetails,
            payFeesIn,
            factoryStorage.coreSenderGasLimit()
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
     * @return The message ID.
     */
    function sendMessage(
        uint64 destinationChainSelector,
        address receiver,
        bytes memory _data,
        MessageSender.PayFeesIn payFeesIn
    ) internal returns (bytes32) {
        // Validate input parameters
        require(destinationChainSelector > 0, "Invalid destination chain selector");
        require(receiver != address(0), "Invalid receiver address");
        require(_data.length > 0, "Data cannot be empty");
        return MessageSender.sendMessage(
            getRouter(), factoryStorage.linkToken(), destinationChainSelector, receiver, _data, payFeesIn, factoryStorage.coreSenderGasLimit()
        );
    }
    /**
     * @dev Handles received messages.
     * @param any2EvmMessage The received message.
     */

    function _ccipReceive(Client.Any2EVMMessage memory any2EvmMessage) internal override {
        bytes32 messageId = any2EvmMessage.messageId;
        uint64 sourceChainSelector = any2EvmMessage.sourceChainSelector;
        uint256 totalCurrentList = functionsOracle.totalCurrentList(address(0));
        address sender = abi.decode(any2EvmMessage.sender, (address)); // abi-decoding of the sender address
        require(
            sender == factoryStorage.crossChainFactoryBySelector(sourceChainSelector),
            "Invalid sender for the factory ccip recieve"
        );
        (
            uint256 actionType,
            address[] memory tokenAddresses,
            ,
            ,
            ,
            uint256 nonce,
            uint256[] memory value1,
            uint256[] memory value2
        ) = abi.decode(
            any2EvmMessage.data, (uint256, address[], address[], bytes[], bytes[], uint256, uint256[], uint256[])
        );
        if(any2EvmMessage.destTokenAmounts.length > 0) {
            factoryStorage.increaseTotalReceivedAmount(any2EvmMessage.destTokenAmounts[0].token, any2EvmMessage.destTokenAmounts[0].amount);
        }
        if (actionType == 0) {
            _handleReceivedIssuance(nonce, tokenAddresses, value1, value2, totalCurrentList, messageId);
        } else if (actionType == 1) {
            _handleReceivedRedemption(
                nonce, any2EvmMessage, tokenAddresses, totalCurrentList, value1[0], sourceChainSelector, messageId
            );
        }
    }
}

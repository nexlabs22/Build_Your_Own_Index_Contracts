// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// import "../token/IndexToken.sol";
import "../utils/proposable/ProposableOwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import "@uniswap/v3-periphery/contracts/interfaces/IQuoter.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
// import "../libraries/OracleLibrary.sol";
import "contracts-ccip/contracts/libraries/Client.sol";
import "contracts-ccip/contracts/interfaces/IRouterClient.sol";
import "./CCIPReceiver.sol";
import "../vault/Vault.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./IPriceOracle.sol";
import "../libraries/SwapHelpers.sol";
import "../libraries/PathHelpers.sol";
import "../interfaces/IWETH.sol";
import "../libraries/MessageSender.sol";
import "./CrossChainIndexFactoryStorage.sol";

/// @title Index Token
/// @author NEX Labs Protocol
/// @notice The main token contract for Index Token (NEX Labs Protocol)
/// @dev This contract uses an upgradeable pattern
/// @custom:oz-upgrades-from CrossChainIndexFactory
contract CrossChainIndexFactoryV2 is
    Initializable,
    CCIPReceiver,
    ContextUpgradeable,
    ProposableOwnableUpgradeable,
    PausableUpgradeable
{
    struct DecodedMessage {
        uint256 actionType;
        address indexToken;
        address[] targetAddresses;
        address[] targetAddresses2;
        bytes[] targetPaths;
        bytes[] targetPaths2;
        uint256 nonce;
        uint256[] percentages;
        uint256[] extraValues;
    }

    struct Message {
        uint64 sourceChainSelector; // The chain selector of the source chain.
        address sender; // The address of the sender.
        string message; // The content of the message.
        address token; // received token.
        uint256 amount; // received amount.
    }

    CrossChainIndexFactoryStorage public factoryStorage;

    event Issuanced(bytes32 indexed messageId, uint256 indexed nonce, uint256 time);
    event Redemption(bytes32 indexed messageId, uint256 indexed nonce, uint256 time);
    event MessageSent(bytes32 messageId);

    function initialize(address _crossChainFactoryStorage, address _router, address _chainlinkToken)
        external
        initializer
    {
        require(_crossChainFactoryStorage != address(0), "CrossChainFactoryStorage address cannot be zero address");
        require(_router != address(0), "Router address cannot be zero address");
        require(_chainlinkToken != address(0), "Chainlink token address cannot be zero address");
        factoryStorage = CrossChainIndexFactoryStorage(_crossChainFactoryStorage);
        __ccipReceiver_init(_router);
        __Ownable_init(msg.sender);
        __Pausable_init();

        IERC20(_chainlinkToken).approve(_router, type(uint256).max);
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function withdrawLink() external onlyOwner {
        IERC20(factoryStorage.i_link()).transfer(msg.sender, IERC20(factoryStorage.i_link()).balanceOf(address(this)));
    }

    /**
     * @dev The contract's fallback function that does not allow direct payments to the contract.
     * @notice Prevents users from sending ether directly to the contract by reverting the transaction.
     */
    receive() external payable {
        // revert DoNotSendFundsDirectlyToTheContract();
    }

    function withdrawEther() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No Ether to withdraw");

        (bool success,) = payable(owner()).call{value: balance}("");
        require(success, "Ether transfer failed");
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function vault(address _indexToken) public view returns (Vault) {
        return Vault(factoryStorage.indexTokenToVault(_indexToken));
    }

    function weth() public view returns (IWETH) {
        return factoryStorage.weth();
    }

    function fromETHPath(address token) public view returns (address[] memory) {
        return factoryStorage.getAllFromETHPath(token);
    }

    function fromETHFees(address token) public view returns (uint24[] memory) {
        return factoryStorage.getAllFromETHFees(token);
    }

    function toETHPath(address token) public view returns (address[] memory) {
        return factoryStorage.getAllToETHPath(token);
    }

    function toETHFees(address token) public view returns (uint24[] memory) {
        return factoryStorage.getAllToETHFees(token);
    }

    function setCrossChainIndexFactoryStorage(address _crossChainFactoryStorage) external onlyOwner {
        require(_crossChainFactoryStorage != address(0), "CrossChainFactoryStorage address cannot be zero address");
        factoryStorage = CrossChainIndexFactoryStorage(_crossChainFactoryStorage);
    }

    function swap(address[] memory path, uint24[] memory fees, uint256 amountIn, address _recipient)
        public
        returns (uint256 outputAmount)
    {
        // Validate input parameters
        require(amountIn > 0, "Amount must be greater than zero");
        require(_recipient != address(0), "Invalid recipient address");
        uint256 amountOutMinimum = factoryStorage.getMinAmountOut(path, fees, amountIn);
        outputAmount = SwapHelpers.swap(
            factoryStorage.swapRouterV3(),
            factoryStorage.swapRouterV2(),
            path,
            fees,
            amountIn,
            amountOutMinimum,
            _recipient
        );
    }

    function sendToken(
        uint64 destinationChainSelector,
        bytes memory _data,
        address receiver,
        Client.EVMTokenAmount[] memory tokensToSendDetails,
        MessageSender.PayFeesIn payFeesIn
    ) internal returns (bytes32) {
        factoryStorage.increaseTotalSentAmount(tokensToSendDetails[0].token, tokensToSendDetails[0].amount);
        bytes32 messageId = MessageSender.sendToken(
            factoryStorage.i_router(),
            factoryStorage.i_link(),
            factoryStorage.MAX_TOKENS_LENGTH(),
            destinationChainSelector,
            _data,
            receiver,
            tokensToSendDetails,
            payFeesIn,
            factoryStorage.factoryGasLimit()
        );
        emit MessageSent(messageId);
        return messageId;
    }

    function _decodeReceive(Client.Any2EVMMessage memory any2EvmMessage)
        internal
        pure
        returns (DecodedMessage memory m)
    {
        (
            uint256 _actionType,
            address _indexToken,
            address[] memory _targetAddresses,
            address[] memory _targetAddresses2,
            bytes[] memory _targetPaths,
            bytes[] memory _targetPaths2,
            uint256 _nonce,
            uint256[] memory _percentages,
            uint256[] memory _extraValues
        ) = abi.decode(
            any2EvmMessage.data,
            (uint256, address, address[], address[], bytes[], bytes[], uint256, uint256[], uint256[])
        );
        m = DecodedMessage({
            actionType: _actionType,
            indexToken: _indexToken,
            targetAddresses: _targetAddresses,
            targetAddresses2: _targetAddresses2,
            targetPaths: _targetPaths,
            targetPaths2: _targetPaths2,
            nonce: _nonce,
            percentages: _percentages,
            extraValues: _extraValues
        });
    }

    /// handle a received message
    function _ccipReceive(Client.Any2EVMMessage memory any2EvmMessage) internal override {
        // bytes32 messageId = any2EvmMessage.messageId; // fetch the messageId
        uint64 sourceChainSelector = any2EvmMessage.sourceChainSelector; // fetch the source chain identifier (aka selector)
        address sender = abi.decode(any2EvmMessage.sender, (address)); // abi-decoding of the sender address
        require(
            factoryStorage.verifiedFactory(sender, sourceChainSelector), "sender to the cross chain is not verified"
        );
        DecodedMessage memory m = _decodeReceive(any2EvmMessage);
        // DecodedMessage memory m = abi.decode(any2EvmMessage.data, (uint256, address, address[], address[], bytes[], bytes[], uint256, uint256[], uint256)); // abi-decoding of the sent message
        if (any2EvmMessage.destTokenAmounts.length > 0) {
            factoryStorage.increaseTotalReceivedAmount(
                any2EvmMessage.destTokenAmounts[0].token, any2EvmMessage.destTokenAmounts[0].amount
            );
        }
        if (m.actionType == 0) {
            {
                Client.EVMTokenAmount[] memory tokenAmounts = any2EvmMessage.destTokenAmounts;
                _handleIssuance(
                    HandleIssuanceInputs({
                        indexToken: m.indexToken,
                        tokenAmounts: tokenAmounts,
                        targetAddresses: m.targetAddresses,
                        targetPaths: m.targetPaths,
                        nonce: m.nonce,
                        sourceChainSelector: sourceChainSelector,
                        sender: sender,
                        percentages: m.percentages,
                        extraValues: m.extraValues
                    })
                );
            }
        } else if (m.actionType == 1) {
            _handleRedemption(
                HandleRedemptionInputs({
                    indexToken: m.indexToken,
                    targetAddresses: m.targetAddresses,
                    targetPaths: m.targetPaths,
                    nonce: m.nonce,
                    sourceChainSelector: sourceChainSelector,
                    sender: sender,
                    extraValues: m.extraValues
                })
            );
        }
    }

    struct HandleIssuanceLocalVars {
        uint256 wethAmount;
        address[] indexTokens;
        uint256[] oldTokenValues;
        uint256[] newTokenValues;
        bytes data;
        Vault vault;
        IWETH weth;
    }

    struct HandleIssuanceInputs {
        address indexToken;
        Client.EVMTokenAmount[] tokenAmounts;
        address[] targetAddresses;
        bytes[] targetPaths;
        uint256 nonce;
        uint64 sourceChainSelector;
        address sender;
        uint256[] percentages;
        uint256[] extraValues;
    }

    function _handleIssuance(HandleIssuanceInputs memory input) private {
        HandleIssuanceLocalVars memory vars;
        vars.vault = vault(input.indexToken);
        vars.weth = weth();

        vars.wethAmount = swap(
            toETHPath(input.tokenAmounts[0].token),
            toETHFees(input.tokenAmounts[0].token),
            input.tokenAmounts[0].amount,
            address(this)
        );
        vars.oldTokenValues = new uint256[](input.targetAddresses.length);
        vars.newTokenValues = new uint256[](input.targetAddresses.length);
        // for (uint256 i = 0; i < input.targetAddresses.length; i++) {
        //     uint256 wethToSwap = (vars.wethAmount * input.percentages[i]) / input.extraValues[0];
        //     (address[] memory _fromETHPath, uint24[] memory _fromETHFees) =
        //         PathHelpers.decodePathBytes(input.targetPaths[i]);
        //     uint256 oldTokenValue;
        //     uint256 newTokenValue;
        //     if (input.targetAddresses[i] == address(vars.weth)) {
        //         oldTokenValue = IERC20(input.targetAddresses[i]).balanceOf(address(vars.vault));
        //         vars.weth.transfer(address(vars.vault), wethToSwap);
        //         newTokenValue = IERC20(input.targetAddresses[i]).balanceOf(address(vars.vault));
        //     } else {
        //         oldTokenValue = factoryStorage.getTokenCurrentValue(
        //             input.indexToken, input.targetAddresses[i], _fromETHPath, _fromETHFees
        //         );
        //         swap(_fromETHPath, _fromETHFees, wethToSwap, address(vars.vault));
        //         newTokenValue = factoryStorage.getTokenCurrentValue(
        //             input.indexToken, input.targetAddresses[i], _fromETHPath, _fromETHFees
        //         );
        //     }

        //     vars.oldTokenValues[i] = factoryStorage.convertEthToUsd(oldTokenValue);
        //     vars.newTokenValues[i] = factoryStorage.convertEthToUsd(newTokenValue);
        // }
        // vars.indexTokens = new address[](1);
        // vars.indexTokens[0] = input.indexToken;
        // vars.data = abi.encode(
        //     0,
        //     input.targetAddresses,
        //     vars.indexTokens,
        //     new bytes[](0),
        //     new bytes[](0),
        //     input.nonce,
        //     vars.oldTokenValues,
        //     vars.newTokenValues
        // );

        // bytes32 messageId =
        //     sendMessage(input.sourceChainSelector, address(input.sender), vars.data, MessageSender.PayFeesIn.Native);
        // factoryStorage.setIssuanceMessageIdByNonce(input.nonce, messageId);
        // emit Issuanced(messageId, input.nonce, block.timestamp);
    }

    uint256 public receivedCount;

    struct HandleRedemptionInputs {
        address indexToken;
        address[] targetAddresses;
        bytes[] targetPaths;
        uint256 nonce;
        uint64 sourceChainSelector;
        address sender;
        uint256[] extraValues;
    }

    struct HandleRedemptionLocalVars {
        uint256 wethSwapAmountOut;
        address[] indexTokens;
        uint256[] newTokenValues;
        Vault v;
    }

    function _handleRedemption(HandleRedemptionInputs memory input) private {
        receivedCount += input.targetAddresses.length;
        HandleRedemptionLocalVars memory vars;
        vars.v = vault(input.indexToken);
        vars.wethSwapAmountOut = 0;
        vars.newTokenValues = new uint256[](1);
        for (uint256 i = 0; i < input.targetAddresses.length; i++) {
            uint256 swapAmount =
                (input.extraValues[0] * IERC20(address(input.targetAddresses[i])).balanceOf(address(vars.v))) / 100e18;
            (address[] memory fromETHPath0, uint24[] memory fromETHFees0) =
                PathHelpers.decodePathBytes(input.targetPaths[i]);
            if (address(input.targetAddresses[i]) == address(factoryStorage.weth())) {
                vars.v.withdrawFunds(address(weth()), address(this), swapAmount);
                vars.wethSwapAmountOut += swapAmount;
                vars.newTokenValues[0] += IERC20(address(input.targetAddresses[i])).balanceOf(address(vars.v));
            } else {
                vars.v.withdrawFunds(address(input.targetAddresses[i]), address(this), swapAmount);
                vars.wethSwapAmountOut += swap(
                    PathHelpers.reverseAddressArray(fromETHPath0), // toETHPath
                    PathHelpers.reverseUint24Array(fromETHFees0), // toETHFees
                    swapAmount,
                    address(this)
                );

                vars.newTokenValues[
                    0
                ] += factoryStorage.getTokenCurrentValue(
                    input.indexToken, input.targetAddresses[i], fromETHPath0, fromETHFees0
                );
            }
        }
        uint256 crossChainTokenAmount = swap(
            fromETHPath(factoryStorage.crossChainToken(input.sourceChainSelector)),
            fromETHFees(factoryStorage.crossChainToken(input.sourceChainSelector)),
            vars.wethSwapAmountOut,
            address(this)
        );
        Client.EVMTokenAmount[] memory tokensToSendArray = new Client.EVMTokenAmount[](1);
        tokensToSendArray[0].token = factoryStorage.crossChainToken(input.sourceChainSelector);
        tokensToSendArray[0].amount = crossChainTokenAmount;
        vars.indexTokens = new address[](1);
        vars.indexTokens[0] = input.indexToken;
        uint256[] memory zeroArr = new uint256[](0);
        bytes memory data = abi.encode(
            1,
            input.targetAddresses,
            vars.indexTokens,
            new bytes[](0),
            new bytes[](0),
            input.nonce,
            vars.newTokenValues,
            zeroArr
        );
        bytes32 messageId =
            sendToken(input.sourceChainSelector, data, input.sender, tokensToSendArray, MessageSender.PayFeesIn.Native);

        factoryStorage.setRedemptionMessageIdByNonce(input.nonce, messageId);
        emit Redemption(messageId, input.nonce, block.timestamp);
    }

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

        // bytes32 data;

        // return data;

        return MessageSender.sendMessage(
            factoryStorage.i_router(),
            factoryStorage.i_link(),
            destinationChainSelector,
            receiver,
            _data,
            payFeesIn,
            factoryStorage.factoryGasLimit()
        );
    }
}

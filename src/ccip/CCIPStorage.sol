// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "../token/IndexToken.sol";
import "../utils/proposable/ProposableOwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import "@uniswap/v3-periphery/contracts/interfaces/IQuoter.sol";
import "@chainlink/contracts/src/v0.8/functions/v1_0_0/libraries/FunctionsRequest.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import "../libraries/PathHelpers.sol";
// import "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
// import "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "../interfaces/IUniswapV2Router02.sol";
import "../interfaces/IUniswapV2Factory.sol";
import "./IPriceOracle.sol";
import "../oracle/FunctionsOracle.sol";
import "../vault/Vault.sol";
import "../interfaces/IWETH.sol";

/// @title Index Token
/// @author NEX Labs Protocol
/// @notice The main token contract for Index Token (NEX Labs Protocol)
/// @dev This contract uses an upgradeable pattern
contract CCIPStorage is Initializable, ProposableOwnableUpgradeable {
    //nonce
    struct TokenOldAndNewValues {
        uint256 oldTokenValue;
        uint256 newTokenValue;
    }

    struct IssuanceData {
        mapping(address => TokenOldAndNewValues) tokenOldAndNewValues;
        uint256 completedTokensCount;
        address requester;
        uint256 inputAmount;
        address inputToken;
        bytes32 messageId;
    }

    struct RedemptionData {
        uint256 totalValue;
        uint256 totalPortfolioValues;
        uint256 completedTokensCount;
        address requester;
        address outputToken;
        address[] outputTokenPath;
        uint24[] outputTokenFees;
        uint256 inputAmount;
        bytes32 messageId;
    }

    uint256 public issuanceNonce;
    uint256 public redemptionNonce;
    uint256 public updatePortfolioNonce;

    address public indexFactory;
    address public indexFactoryBalancer;
    address public coreSender;
    address public balancerSender;
    FunctionsOracle public functionsOracle;

    mapping(uint256 => IssuanceData) public issuanceData;
    mapping(uint256 => RedemptionData) public redemptionData;

    mapping(uint64 => address) public crossChainToken;
    mapping(uint64 => address) public crossChainFactoryBySelector;

    mapping(address => address[]) public fromETHPath;
    mapping(address => address[]) public toETHPath;
    mapping(address => uint24[]) public fromETHFees;
    mapping(address => uint24[]) public toETHFees;

    mapping(uint256 => uint256) public portfolioTotalValueByNonce;
    mapping(uint256 => uint256) public extraWethByNonce;
    mapping(uint256 => uint256) public updatedTokensValueCount;
    mapping(uint256 => mapping(address => uint256)) public tokenValueByNonce;
    mapping(uint256 => mapping(uint64 => uint256)) public chainValueByNonce;

    mapping(uint256 => uint256) public reweightExtraPercentage;

    address public linkToken;
    uint64 public currentChainSelector;
    address public priceOracle;

    AggregatorV3Interface public toUsdPriceFeed;

    // address public i_link;
    uint16 public constant MAX_TOKENS_LENGTH = 5;
    uint8 public constant MIN_FEE_RATE = 1;
    uint8 public constant MAX_FEE_RATE = 100;
    uint256 public constant MIN_FEE_UPDATE_INTERVAL = 12 hours;

    ISwapRouter public swapRouterV3;
    IUniswapV3Factory public factoryV3;
    IUniswapV2Router02 public swapRouterV2;
    IUniswapV2Factory public factoryV2;
    IWETH public weth;
    IQuoter public quoter;
    Vault public vault;

    //slipage tolerance
    uint256 public slippageTolerance; // 2000/10000 = 20%

    uint256 public totalPendingIssuanceInput;
    uint256 public totalPendingRedemptionInput;
    uint256 public totalPendingRedemptionHoldValue;
    uint256 public totalPendingExtraWeth;
    mapping(uint256 => uint256) public pendingIssuanceInputByNonce;
    mapping(uint256 => uint256) public pendingRedemptionInputByNonce;
    mapping(uint256 => uint256) public pendingRedemptionHoldValueByNonce;
    mapping(uint256 => uint256) public pendingExtraWethByNonce;
    mapping(address => uint256) public totalSentAmount;
    mapping(address => uint256) public totalReceivedAmount;

    modifier onlyIndexFactory() {
        require(msg.sender == indexFactory || msg.sender == coreSender, "Caller is not index factory contract.");
        _;
    }

    modifier onlyIndexFactoryBalancer() {
        require(
            msg.sender == indexFactoryBalancer || msg.sender == balancerSender,
            "Caller is not index factory balancer contract."
        );
        _;
    }

    modifier onlySenders() {
        require(
            msg.sender == coreSender || msg.sender == balancerSender, "Caller is not core sender or balancer sender."
        );
        _;
    }

    bool public isCrossChainFeeSponsered;
    uint256 public coreSenderGasLimit;
    uint256 public balancerSenderGasLimit;

    uint256 public issuanceFeePercentage;
    uint256 public redemptionFeePercentage;

    /**
     * @dev Initializes the contract with the given parameters.
     * @param _currentChainSelector The current chain selector.
     * @param _functionsOracle The address of the Functions Oracle contract.
     * @param _toUsdPriceFeed The address of the USD price feed.
     * @param _weth The address of the WETH token.
     * @param _swapRouterV3 The address of the Uniswap V3 swap router.
     * @param _factoryV3 The address of the Uniswap V3 factory.
     * @param _swapRouterV2 The address of the Uniswap V2 swap router.
     * @param _factoryV2 The address of the Uniswap V2 factory.
     */
    function initialize(
        uint64 _currentChainSelector,
        address _functionsOracle,
        address _toUsdPriceFeed,
        address _linkToken,
        address _weth,
        address _swapRouterV3,
        address _factoryV3,
        address _swapRouterV2,
        address _factoryV2
    ) external initializer {
        // Validate input parameters
        require(_currentChainSelector > 0, "Invalid chain selector");
        require(_toUsdPriceFeed != address(0), "Invalid price feed address");
        require(_weth != address(0), "Invalid WETH address");
        require(_swapRouterV3 != address(0), "Invalid Uniswap V3 swap router address");
        require(_factoryV3 != address(0), "Invalid Uniswap V3 factory address");
        require(_swapRouterV2 != address(0), "Invalid Uniswap V2 swap router address");
        require(_factoryV2 != address(0), "Invalid Uniswap V2 factory address");

        __Ownable_init(msg.sender);
        //set chain selector
        currentChainSelector = _currentChainSelector;
        functionsOracle = FunctionsOracle(_functionsOracle);
        toUsdPriceFeed = AggregatorV3Interface(_toUsdPriceFeed);
        //set addressesd
        weth = IWETH(_weth);
        linkToken = _linkToken;
        swapRouterV3 = ISwapRouter(_swapRouterV3);
        factoryV3 = IUniswapV3Factory(_factoryV3);
        swapRouterV2 = IUniswapV2Router02(_swapRouterV2);
        factoryV2 = IUniswapV2Factory(_factoryV2);
        // update fee
        slippageTolerance = 2000; // 20%
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Modifier to restrict access to only the IndexFactory contract.
     * @param _coreSenderGasLimit The gas limit for the core sender.
     * @param _balancerSenderGasLimit The gas limit for the balancer sender.
     */
    function setCoreSenderAndBalancerSenderGasLimits(uint256 _coreSenderGasLimit, uint256 _balancerSenderGasLimit)
        public
    {
        require(msg.sender == owner() || functionsOracle.isOperator(msg.sender));
        coreSenderGasLimit = _coreSenderGasLimit;
        balancerSenderGasLimit = _balancerSenderGasLimit;
    }

    /**
     * @dev Sets the issuance and redemption fee percentages.
     * @param _issuanceFeePercentage The issuance fee percentage.
     * @param _redemptionFeePercentage The redemption fee percentage.
     */
    function setIssuanceAndRedemptionFeePercentages(uint256 _issuanceFeePercentage, uint256 _redemptionFeePercentage)
        public
    {
        require(msg.sender == owner() || functionsOracle.isOperator(msg.sender));
        issuanceFeePercentage = _issuanceFeePercentage;
        redemptionFeePercentage = _redemptionFeePercentage;
    }

    function setIsCrossChainFeeSponsered(bool _isCrossChainFeeSponsered) public {
        require(msg.sender == owner() || functionsOracle.isOperator(msg.sender));
        isCrossChainFeeSponsered = _isCrossChainFeeSponsered;
    }

    function setSlippageTolerance(uint256 _slippageTolerance) public onlyOwner {
        slippageTolerance = _slippageTolerance;
    }

    /**
     * @dev Sets the cross-chain token and its swap version.
     * @param _chainSelector The chain selector.
     * @param _crossChainToken The address of the cross-chain token.
     */
    function setCrossChainToken(
        uint64 _chainSelector,
        address _crossChainToken,
        address[] memory _fromETHPath,
        uint24[] memory _fromETHFees
    ) public onlyOwner {
        crossChainToken[_chainSelector] = _crossChainToken;
        fromETHPath[_crossChainToken] = _fromETHPath;
        fromETHFees[_crossChainToken] = _fromETHFees;
        toETHPath[_crossChainToken] = PathHelpers.reverseAddressArray(_fromETHPath);
        toETHFees[_crossChainToken] = PathHelpers.reverseUint24Array(_fromETHFees);
    }

    /**
     * @dev Sets the cross-chain factory address for a given chain selector.
     * @param _crossChainFactoryAddress The address of the cross-chain factory.
     * @param _chainSelector The chain selector.
     */
    function setCrossChainFactory(address _crossChainFactoryAddress, uint64 _chainSelector) public onlyOwner {
        crossChainFactoryBySelector[_chainSelector] = _crossChainFactoryAddress;
    }

    function setFunctionsOracle(address _functionsOracle) public onlyOwner {
        functionsOracle = FunctionsOracle(_functionsOracle);
    }

    /**
     * @dev Sets the price feed address of the native coin to USD from the Chainlink oracle.
     * @param _toUsdPricefeed The address of native coin to USD price feed.
     */
    function setPriceFeed(address _toUsdPricefeed) external onlyOwner {
        require(_toUsdPricefeed != address(0), "ICO: Price feed address cannot be zero address");
        toUsdPriceFeed = AggregatorV3Interface(_toUsdPricefeed);
    }

    function setPriceOracle(address _priceOracle) external onlyOwner {
        require(_priceOracle != address(0), "Price oracle address cannot be zero address");
        priceOracle = _priceOracle;
    }

    /**
     * @dev Sets the IndexFactory contract address.
     * @param _indexFactory The address of the IndexFactory contract.
     */
    function setIndexFactory(address _indexFactory) public onlyOwner {
        indexFactory = _indexFactory;
    }

    /**
     * @dev Sets the core sender address.
     * @param _coreSender The address of the core sender.
     */
    function setCoreSender(address _coreSender) public onlyOwner {
        coreSender = _coreSender;
    }

    /**
     * @dev Sets the BalancerSender address.
     * @param _balancerSender The address of the BalancerSender.
     */
    function setBalancerSender(address _balancerSender) public onlyOwner {
        balancerSender = _balancerSender;
    }

    /**
     * @dev Sets the vault address.
     * @param _vaultAddress The address of the vault.
     */
    function setVault(address _vaultAddress) public onlyOwner {
        vault = Vault(_vaultAddress);
    }

    function increaseIssuanceNonce() public onlyIndexFactory {
        issuanceNonce++;
    }

    function issuanceIncreaseCompletedTokensCount(uint256 _issuanceNonce) public onlyIndexFactory {
        issuanceData[_issuanceNonce].completedTokensCount++;
    }

    function setIssuanceData(
        uint256 _issuanceNonce,
        address _requester,
        address _inputToken,
        uint256 _inputAmount,
        bytes32 _messageId
    ) public onlyIndexFactory {
        issuanceData[_issuanceNonce].requester = _requester;
        issuanceData[_issuanceNonce].inputToken = _inputToken;
        issuanceData[_issuanceNonce].inputAmount = _inputAmount;
        issuanceData[_issuanceNonce].messageId = _messageId;
    }

    function setIssuanceMessageId(uint256 _issuanceNonce, bytes32 _messageId) public onlyIndexFactory {
        issuanceData[_issuanceNonce].messageId = _messageId;
    }

    function setIssuanceOldTokenValue(uint256 _issuanceNonce, address _token, uint256 _oldTokenValue)
        public
        onlyIndexFactory
    {
        issuanceData[_issuanceNonce].tokenOldAndNewValues[_token].oldTokenValue = _oldTokenValue;
    }

    function setIssuanceNewTokenValue(uint256 _issuanceNonce, address _token, uint256 _newTokenValue)
        public
        onlyIndexFactory
    {
        issuanceData[_issuanceNonce].tokenOldAndNewValues[_token].newTokenValue = _newTokenValue;
    }

    function increaseRedemptionNonce() public onlyIndexFactory {
        redemptionNonce++;
    }

    function redemptionIncreaseCompletedTokensCount(uint256 _redemptionNonce) public onlyIndexFactory {
        redemptionData[_redemptionNonce].completedTokensCount++;
    }

    function setRedemptionData(
        uint256 _redemptionNonce,
        address _requester,
        address _outputToken,
        uint256 _inputAmount,
        address[] memory _outputTokenPath,
        uint24[] memory _outputTokenFees,
        bytes32 _messageId
    ) public onlyIndexFactory {
        redemptionData[_redemptionNonce].requester = _requester;
        redemptionData[_redemptionNonce].outputToken = _outputToken;
        redemptionData[_redemptionNonce].outputTokenPath = _outputTokenPath;
        redemptionData[_redemptionNonce].outputTokenFees = _outputTokenFees;
        redemptionData[_redemptionNonce].inputAmount = _inputAmount;
        redemptionData[_redemptionNonce].messageId = _messageId;
    }

    function increaseRedemptionTotalValue(uint256 _redemptionNonce, uint256 _totalValue) public onlyIndexFactory {
        redemptionData[_redemptionNonce].totalValue += _totalValue;
    }

    function increaseRedemptionTotalPortfolioValues(uint256 _redemptionNonce, uint256 _totalPortfolioValues)
        public
        onlyIndexFactory
    {
        redemptionData[_redemptionNonce].totalPortfolioValues += _totalPortfolioValues;
    }

    function increaseRedemptionCompletedTokensCount(uint256 _redemptionNonce, uint256 _completedTokensCount)
        public
        onlyIndexFactory
    {
        redemptionData[_redemptionNonce].completedTokensCount += _completedTokensCount;
    }

    function setRedemptionMessageId(uint256 _redemptionNonce, bytes32 _messageId) public onlyIndexFactory {
        redemptionData[_redemptionNonce].messageId = _messageId;
    }

    function getIssuanceMessageId(uint256 _issuanceNonce) public view returns (bytes32) {
        return issuanceData[_issuanceNonce].messageId;
    }

    function getIssuanceInputToken(uint256 _issuanceNonce) public view returns (address) {
        return issuanceData[_issuanceNonce].inputToken;
    }

    function getIssuanceInputAmount(uint256 _issuanceNonce) public view returns (uint256) {
        return issuanceData[_issuanceNonce].inputAmount;
    }

    function getIssuanceRequester(uint256 _issuanceNonce) public view returns (address) {
        return issuanceData[_issuanceNonce].requester;
    }

    function getIssuanceOldTokenValue(uint256 _issuanceNonce, address _token) public view returns (uint256) {
        return issuanceData[_issuanceNonce].tokenOldAndNewValues[_token].oldTokenValue;
    }

    function getIssuanceNewTokenValue(uint256 _issuanceNonce, address _token) public view returns (uint256) {
        return issuanceData[_issuanceNonce].tokenOldAndNewValues[_token].newTokenValue;
    }

    function getIssuanceCompletedTokensCount(uint256 _issuanceNonce) public view returns (uint256) {
        return issuanceData[_issuanceNonce].completedTokensCount;
    }

    function getRedemptionMessageId(uint256 _redemptionNonce) public view returns (bytes32) {
        return redemptionData[_redemptionNonce].messageId;
    }

    function getRedemptionRequester(uint256 _redemptionNonce) public view returns (address) {
        return redemptionData[_redemptionNonce].requester;
    }

    function getRedemptionOutputToken(uint256 _redemptionNonce) public view returns (address) {
        return redemptionData[_redemptionNonce].outputToken;
    }

    function getRedemptionOutputTokenPath(uint256 _redemptionNonce) public view returns (address[] memory) {
        return redemptionData[_redemptionNonce].outputTokenPath;
    }

    function getRedemptionOutputTokenFees(uint256 _redemptionNonce) public view returns (uint24[] memory) {
        return redemptionData[_redemptionNonce].outputTokenFees;
    }

    function getRedemptionInputAmount(uint256 _redemptionNonce) public view returns (uint256) {
        return redemptionData[_redemptionNonce].inputAmount;
    }

    function getRedemptionTotalValue(uint256 _redemptionNonce) public view returns (uint256) {
        return redemptionData[_redemptionNonce].totalValue;
    }

    function getRedemptionTotalPortfolioValues(uint256 _redemptionNonce) public view returns (uint256) {
        return redemptionData[_redemptionNonce].totalPortfolioValues;
    }

    function getRedemptionCompletedTokensCount(uint256 _redemptionNonce) public view returns (uint256) {
        return redemptionData[_redemptionNonce].completedTokensCount;
    }

    function increaseUpdatePortfolioNonce() public onlyIndexFactoryBalancer {
        updatePortfolioNonce++;
    }

    function increasePortfolioTotalValueByNonce(uint256 _updatePortfolioNonce, uint256 _totalValue)
        public
        onlyIndexFactoryBalancer
    {
        portfolioTotalValueByNonce[_updatePortfolioNonce] += _totalValue;
    }

    function increaseExtraWethByNonce(uint256 _updatePortfolioNonce, uint256 _extraWeth)
        public
        onlyIndexFactoryBalancer
    {
        extraWethByNonce[_updatePortfolioNonce] += _extraWeth;
    }

    function increaseUpdatedTokensValueCount(uint256 _updatePortfolioNonce) public onlyIndexFactoryBalancer {
        updatedTokensValueCount[_updatePortfolioNonce]++;
    }

    function increaseTokenValueByNonce(uint256 _updatePortfolioNonce, address _token, uint256 _value)
        public
        onlyIndexFactoryBalancer
    {
        tokenValueByNonce[_updatePortfolioNonce][_token] += _value;
    }

    function increaseChainValueByNonce(uint256 _updatePortfolioNonce, uint64 _chainSelector, uint256 _value)
        public
        onlyIndexFactoryBalancer
    {
        chainValueByNonce[_updatePortfolioNonce][_chainSelector] += _value;
    }

    function increaseTotalSentAmount(address _tokenAddress, uint256 _amount) public onlySenders {
        totalSentAmount[_tokenAddress] += _amount;
    }

    function increaseTotalReceivedAmount(address _tokenAddress, uint256 _amount) public onlySenders {
        totalReceivedAmount[_tokenAddress] += _amount;
    }

    function increasePendingIssuanceInputByNonce(uint256 _issuanceNonce, uint256 _amount) public onlyIndexFactory {
        pendingIssuanceInputByNonce[_issuanceNonce] += _amount;
        totalPendingIssuanceInput += _amount;
    }

    function increasePendingRedemptionInputByNonce(uint256 _redemptionNonce, uint256 _amount) public onlyIndexFactory {
        pendingRedemptionInputByNonce[_redemptionNonce] += _amount;
        totalPendingRedemptionInput += _amount;
    }

    function decreasePendingIssuanceInputByNonce(uint256 _issuanceNonce) public onlyIndexFactory {
        totalPendingIssuanceInput -= pendingIssuanceInputByNonce[_issuanceNonce];
        pendingIssuanceInputByNonce[_issuanceNonce] = 0;
    }

    function decreasePendingRedemptionInputByNonce(uint256 _redemptionNonce) public onlyIndexFactory {
        totalPendingRedemptionInput -= pendingRedemptionInputByNonce[_redemptionNonce];
        pendingRedemptionInputByNonce[_redemptionNonce] = 0;
    }

    function increasePendingRedemptionHoldValueByNonce(uint256 _redemptionNonce, uint256 _amount)
        public
        onlyIndexFactory
    {
        pendingRedemptionHoldValueByNonce[_redemptionNonce] += _amount;
        totalPendingRedemptionHoldValue += _amount;
    }

    function decreasePendingRedemptionHoldValueByNonce(uint256 _redemptionNonce) public onlyIndexFactory {
        totalPendingRedemptionHoldValue -= pendingRedemptionHoldValueByNonce[_redemptionNonce];
        pendingRedemptionHoldValueByNonce[_redemptionNonce] = 0;
    }

    function increasePendingExtraWethByNonce(uint256 _updatePortfolioNonce, uint256 _amount)
        public
        onlyIndexFactoryBalancer
    {
        pendingExtraWethByNonce[_updatePortfolioNonce] += _amount;
        totalPendingExtraWeth += _amount;
    }

    function decreasePendingExtraWethByNonce(uint256 _updatePortfolioNonce) public onlyIndexFactoryBalancer {
        totalPendingExtraWeth -= pendingExtraWethByNonce[_updatePortfolioNonce];
        pendingExtraWethByNonce[_updatePortfolioNonce] = 0;
    }

    function increaseReweightExtraPercentage(uint256 _reweightNonce, uint256 _extraPercentage)
        public
        onlyIndexFactoryBalancer
    {
        reweightExtraPercentage[_reweightNonce] += _extraPercentage;
    }

    /**
     * @dev Converts an amount to Wei.
     * @param _amount The amount to convert.
     * @param _amountDecimals The decimals of the amount.
     * @param _chainDecimals The decimals of the chain.
     * @return The amount in Wei.
     */
    function _toWei(int256 _amount, uint8 _amountDecimals, uint8 _chainDecimals) private pure returns (int256) {
        if (_chainDecimals > _amountDecimals) {
            return _amount * int256(10 ** (_chainDecimals - _amountDecimals));
        } else {
            return _amount * int256(10 ** (_amountDecimals - _chainDecimals));
        }
    }

    function getCurrentTokenValue(address tokenAddress) external view returns (uint256) {
        (address[] memory toETHPath, uint24[] memory toETHFees) = functionsOracle.getToETHPathData(tokenAddress);

        uint256 oldTokenValue = tokenAddress == address(weth)
            ? convertEthToUsd(IERC20(tokenAddress).balanceOf(address(vault)))
            : convertEthToUsd(getAmountOut(toETHPath, toETHFees, IERC20(tokenAddress).balanceOf(address(vault))));

        return oldTokenValue;
    }

    /**
     * @dev Converts ETH amount to USD.
     * @param _ethAmount The amount of ETH.
     * @return The equivalent amount in USD.
     */
    function convertEthToUsd(uint256 _ethAmount) public view returns (uint256) {
        return (_ethAmount * priceInWei()) / 1e18;
    }

    /**
     * @dev Returns the price in Wei.
     * @return The price in Wei.
     */
    function priceInWei() public view returns (uint256) {
        (uint80 roundId, int256 price,, uint256 _updatedAt,) = toUsdPriceFeed.latestRoundData();
        require(roundId != 0, "invalid round id");
        require(_updatedAt != 0 && _updatedAt <= block.timestamp, "invalid updated time");
        require(price > 0, "invalid price");
        require(block.timestamp - _updatedAt < 1 days, "invalid updated time");

        uint8 priceFeedDecimals = toUsdPriceFeed.decimals();
        price = _toWei(price, priceFeedDecimals, 18);
        return uint256(price);
    }

    function getFromETHPathData(address _tokenAddress) public view returns (address[] memory, uint24[] memory) {
        return (fromETHPath[_tokenAddress], fromETHFees[_tokenAddress]);
    }

    function getToETHPathData(address _tokenAddress) public view returns (address[] memory, uint24[] memory) {
        return (toETHPath[_tokenAddress], toETHFees[_tokenAddress]);
    }

    /**
     * @dev Gets the minimum amount out.
     * @return The minimum amount out.
     */
    function getMinAmountOut(address[] memory path, uint24[] memory fees, uint256 amountIn)
        public
        view
        returns (uint256)
    {
        uint256 amountOut = getAmountOut(path, fees, amountIn);
        return (amountOut * (10000 - slippageTolerance)) / 10000;
    }

    /**
     * @dev Returns the amount out for a given swap.
     * @param path The path of the swap.
     * @param fees The fees of the swap.
     * @param amountIn The amount of input token.
     * @return finalAmountOutValue The amount of output token.
     */
    function getAmountOut(address[] memory path, uint24[] memory fees, uint256 amountIn)
        public
        view
        returns (uint256 finalAmountOutValue)
    {
        require(amountIn < type(uint128).max, "AmountIn exceeds uint128");
        uint256 finalAmountOut;
        if (amountIn > 0) {
            if (fees.length > 0) {
                finalAmountOut = estimateAmountOutWithPath(path, fees, amountIn);
            } else {
                uint256[] memory v2amountOut = swapRouterV2.getAmountsOut(amountIn, path);
                finalAmountOut = v2amountOut[v2amountOut.length - 1];
            }
        }
        finalAmountOutValue = finalAmountOut;
    }

    /**
     * @dev Returns the portfolio balance.
     * @return The total portfolio balance.
     */
    function getPortfolioBalance(address _indexToken) public view returns (uint256) {
        uint256 totalValue;
        for (uint256 i = 0; i < functionsOracle.totalCurrentList(_indexToken); i++) {
            address tokenAddress = functionsOracle.currentList(_indexToken, i);
            if (functionsOracle.tokenChainSelector(tokenAddress) == currentChainSelector) {
                if (tokenAddress == address(weth)) {
                    totalValue += IERC20(tokenAddress).balanceOf(address(vault));
                } else {
                    (address[] memory path, uint24[] memory fees) = functionsOracle.getToETHPathData(tokenAddress);
                    uint256 value = getAmountOut(
                        // toETHPath[tokenAddress],
                        // toETHFees[tokenAddress],
                        path,
                        fees,
                        IERC20(tokenAddress).balanceOf(address(vault))
                    );
                    totalValue += value;
                }
            }
        }
        return totalValue;
    }

    /**
     * @dev Estimates the amount out for a given swap.
     * @param tokenIn The address of the input token.
     * @param tokenOut The address of the output token.
     * @param amountIn The amount of input token.
     * @return amountOut The estimated amount of output token.
     */
    function estimateAmountOut(address tokenIn, address tokenOut, uint128 amountIn, uint24 fee)
        public
        view
        returns (uint256 amountOut)
    {
        amountOut = IPriceOracle(priceOracle).estimateAmountOut(address(factoryV3), tokenIn, tokenOut, amountIn, fee);
    }

    function estimateAmountOutWithPath(address[] memory path, uint24[] memory fees, uint256 amountIn)
        public
        view
        returns (uint256 amountOut)
    {
        uint256 lastAmount = amountIn;
        for (uint256 i = 0; i < path.length - 1; i++) {
            lastAmount = IPriceOracle(priceOracle).estimateAmountOut(
                address(factoryV3), path[i], path[i + 1], uint128(lastAmount), fees[i]
            );
        }
        amountOut = lastAmount;
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "../token/IndexToken.sol";
import "../utils/proposable/ProposableOwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./CCIPReceiver.sol";
import "./MainChainStorage.sol";
import "./CoreSender.sol";
import "../oracle/FunctionsOracle.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "../libraries/FeeCalculation.sol";
import "../libraries/MessageSender.sol";
import "../libraries/SwapHelpers.sol";
import "../interfaces/IUniswapV2Router02.sol";
import "../interfaces/IWETH.sol";
import "../orderManager/OrderManager.sol";
/// @title Index Token
/// @author NEX Labs Protocol
/// @notice The main token contract for Index Token (NEX Labs Protocol)
/// @dev This contract uses an upgradeable pattern

contract MainChainFactory is Initializable, ProposableOwnableUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
    // using MessageSender for *;

    struct IssuanceSendLocalVars {
        address[] tokenAddresses;
        uint256[] tokenVersions;
        uint256[] tokenShares;
        address[] zeroAddresses;
        uint256[] zeroNumbers;
    }

    IndexToken public indexToken;
    MainChainStorage public mainChainStorage;
    FunctionsOracle public functionsOracle;
    CoreSender public coreSender;
    OrderManager public orderManager;

    uint64 public currentChainSelector;

    IWETH public weth;

    event RequestIssuance(
        bytes32 indexed messageId,
        uint256 indexed nonce,
        address indexed user,
        address inputToken,
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 time
    );

    event RequestRedemption(
        bytes32 indexed messageId,
        uint256 indexed nonce,
        address indexed user,
        address outputToken,
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 time
    );

    modifier onlyOwnerOrBalancers() {
        require(
            msg.sender == owner() || functionsOracle.isOperator(msg.sender)
                || msg.sender == address(mainChainStorage.balancerSender())
                || msg.sender == address(mainChainStorage.mainChainFactoryBalancer()),
            "Not owner or balancer"
        );
        _;
    }

    /**
     * @dev Pauses the contract.
     */
    function pause() external onlyOwnerOrBalancers {
        _pause();
    }

    /**
     * @dev Unpauses the contract.
     */
    function unpause() external onlyOwnerOrBalancers {
        _unpause();
    }

    /**
     * @dev Initializes the contract with the given parameters.
     * @param _currentChainSelector The current chain selector.
     * @param _token The address of the IndexToken contract..
     * @param _weth The address of the WETH token.
     */
    function initialize(
        uint64 _currentChainSelector,
        address payable _token,
        address _orderManager,
        address _mainChainStorage,
        address _functionsOracle,
        address payable _coreSender,
        //addresses
        address _weth
    ) external initializer {
        // Validate input parameters
        require(_currentChainSelector > 0, "Invalid chain selector");
        require(_token != address(0), "Invalid token address");
        require(_weth != address(0), "Invalid WETH address");

        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();
        __ReentrancyGuard_init_unchained();
        //set chain selector
        currentChainSelector = _currentChainSelector;
        indexToken = IndexToken(_token);
        orderManager = OrderManager(_orderManager);
        mainChainStorage = MainChainStorage(_mainChainStorage);
        functionsOracle = FunctionsOracle(_functionsOracle);
        coreSender = CoreSender(_coreSender);

        //set addresses
        weth = IWETH(_weth);
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // set WETH address
    function setWethAddress(address _weth) public onlyOwner {
        require(_weth != address(0), "Invalid WETH address");
        weth = IWETH(_weth);
    }

    /**
     * @dev Sets the IndexToken contract address.
     * @param _token The address of the IndexToken contract.
     */
    function setIndexToken(address _token) public onlyOwner {
        require(_token != address(0), "Invalid token address");
        indexToken = IndexToken(payable(_token));
    }

    function setOrderManager(address _orderManager) public onlyOwner {
        require(_orderManager != address(0), "Invalid order manager address");
        orderManager = OrderManager(_orderManager);
    }

    /**
     * @dev Sets the current chain selector.
     * @param _currentChainSelector The current chain selector.
     */
    function setCurrentChainSelector(uint64 _currentChainSelector) public onlyOwner {
        require(_currentChainSelector > 0, "Invalid chain selector");
        currentChainSelector = _currentChainSelector;
    }

    /**
     * @dev Sets the MainChainStorage contract address.
     * @param _mainChainStorage The address of the MainChainStorage contract.
     */
    function setMainChainStorage(address _mainChainStorage) public onlyOwner {
        mainChainStorage = MainChainStorage(_mainChainStorage);
    }

    /**
     * @dev Sets the FunctionsOracle contract address.
     * @param _functionsOracle The address of the FunctionsOracle contract.
     */
    function setFunctionsOracle(address _functionsOracle) public onlyOwner {
        functionsOracle = FunctionsOracle(_functionsOracle);
    }

    function setCoreSender(address payable _coreSender) public onlyOwner {
        coreSender = CoreSender(_coreSender);
    }

    /**
     * @dev Fallback function to receive ETH.
     */
    receive() external payable {}

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
        ISwapRouter swapRouterV3 = mainChainStorage.swapRouterV3();
        IUniswapV2Router02 swapRouterV2 = mainChainStorage.swapRouterV2();
        uint256 amountOutMinimum = mainChainStorage.getMinAmountOut(path, fees, amountIn);
        outputAmount = SwapHelpers.swap(swapRouterV3, swapRouterV2, path, fees, amountIn, amountOutMinimum, _recipient);
    }

    function getIssuanceFee(
        address _indexToken,
        address _tokenIn,
        address[] memory _tokenInPath,
        uint24[] memory _tokenInFees,
        uint256 _inputAmount
    ) public view returns (uint256) {
        // get weth amount
        uint256 wethAmount;
        if (_tokenIn == address(weth)) {
            wethAmount = _inputAmount;
        } else {
            wethAmount = mainChainStorage.getAmountOut(_tokenInPath, _tokenInFees, _inputAmount);
        }

        // get fee for other chains
        uint256 totalChains = functionsOracle.currentChainSelectorsCount(_indexToken);
        uint256 latestCount = functionsOracle.currentFilledCount(_indexToken);
        (,, uint64[] memory chainSelectors) = functionsOracle.getCurrentData(_indexToken, latestCount);

        uint256 totalCrossChainFee;
        /**
         * for (uint256 i = 0; i < totalChains; i++) {
         *         uint64 chainSelector = chainSelectors[i];
         *         uint256 chainSelectorTokensCount = functionsOracle.currentChainSelectorTokensCount(_indexToken, chainSelector);
         *         if (chainSelector != currentChainSelector) {
         *             uint256 totalShares = functionsOracle.getCurrentChainSelectorTotalShares(_indexToken, latestCount, chainSelector);
         *             uint256 chainWethAmount = (wethAmount * totalShares) / 100e18;
         *             //get the fee
         *             uint256 fee = coreSender.calculateIssuanceFee(chainSelector, chainWethAmount);
         *             totalCrossChainFee += fee;
         *         }
         *     }
         */
        return (totalCrossChainFee * (100 + 20)) / 100;
    }

    function getRedemptionFee(address _indexToken, uint256 amountIn) public view returns (uint256) {
        uint256 burnPercent = (amountIn * 1e18) / indexToken.totalSupply();
        uint256 totalChains = functionsOracle.currentChainSelectorsCount(_indexToken);
        uint256 latestCount = functionsOracle.currentFilledCount(_indexToken);
        (,, uint64[] memory chainSelectors) = functionsOracle.getCurrentData(_indexToken, latestCount);
        uint256 totalCrossChainFee;
        for (uint256 i = 0; i < totalChains; i++) {
            uint64 chainSelector = chainSelectors[i];
            if (chainSelector != currentChainSelector) {
                //get the fee
                uint256 fee = coreSender.calculateRedemptionFee(chainSelector);
                totalCrossChainFee += fee;
            }
        }
        return (totalCrossChainFee * (100 + 20)) / 100;
    }

    /**
     * @dev Issues index tokens.
     * @param _indexToken The address of the index token.
     * @param _tokenIn The address of the input token.
     * @param _inputAmount The amount of input token.
     */
    function issuanceIndexTokens(
        address _indexToken,
        address _tokenIn,
        uint256 _inputAmount
    ) public payable whenNotPaused {
        // Validate input parameters
        require(_tokenIn != address(0), "Invalid input token address");
        require(_inputAmount > 0, "Input amount must be greater than zero");
        (address[] memory _tokenInPath, uint24[] memory _tokenInFees) =
                functionsOracle.getToETHPathData(_tokenIn);
        require(_tokenInPath[_tokenInPath.length - 1] == address(weth), "Invalid token path");
        if (!mainChainStorage.isCrossChainFeeSponsered()) {
            require(
                getIssuanceFee(_indexToken, _tokenIn, _tokenInPath, _tokenInFees, _inputAmount) == msg.value,
                "Insufficient ETH sent for cross chain fee"
            );
            (bool success,) = mainChainStorage.coreSender().call{value: msg.value}("");
            require(success, "Cross chain fee transfer failed");
        }
        IWETH weth = mainChainStorage.weth();
        Vault vault = mainChainStorage.vault();

        

        mainChainStorage.increaseIssuanceNonce();
        mainChainStorage.setIssuanceData(mainChainStorage.issuanceNonce(), msg.sender, _tokenIn, _inputAmount, bytes32(0));

        require(
            IERC20(_tokenIn).transferFrom(msg.sender, address(this), _inputAmount), "Token transfer failed"
        );
        uint256 wethAmount = swap(_tokenInPath, _tokenInFees, _inputAmount, address(this));
        
        //run issuance
        _issuance(_indexToken, _tokenIn, wethAmount);
    }

    /**
     * @dev Issues index tokens with ETH.
     * @param _indexToken The address of the index token.
     * @param _inputAmount The amount of input token.
     */
    function issuanceIndexTokensWithEth(address _indexToken, uint256 _inputAmount) external payable whenNotPaused {
        // Validate input parameters
        require(_inputAmount > 0, "Input amount must be greater than zero");
        require(msg.value >= _inputAmount, "Insufficient ETH sent");

        uint256 feeAmount = FeeCalculation.calculateFee(_inputAmount, 10);
        uint256 crossChainFee =
            getIssuanceFee(_indexToken, address(weth), new address[](0), new uint24[](0), _inputAmount);
        if (!mainChainStorage.isCrossChainFeeSponsered()) {
            uint256 finalAmount = _inputAmount + feeAmount + crossChainFee;
            require(msg.value == finalAmount, "lower than required amount");
            (bool success,) = mainChainStorage.coreSender().call{value: crossChainFee}("");
            require(success, "Cross chain fee transfer failed");
        } else {
            uint256 finalAmount = _inputAmount + feeAmount;
            require(msg.value == finalAmount, "lower than required amount");
        }
        //transfer fee to the owner
        weth.deposit{value: _inputAmount + feeAmount}();
        // Transfer fee to the fee receiver and check the result
        require(weth.transfer(address(owner()), feeAmount), "Fee transfer failed");

        //set mappings
        mainChainStorage.increaseIssuanceNonce();
        mainChainStorage.setIssuanceData(
            mainChainStorage.issuanceNonce(), msg.sender, address(weth), _inputAmount, bytes32(0)
        );
        //run issuance
        _issuance(_indexToken, address(weth), _inputAmount);
    }

    /**
     * @dev Internal function to handle issuance.
     * @param _indexToken The address of the index token.
     * @param _tokenIn The address of the input token.
     * @param _inputAmount The amount of input token.
     */
    function _issuance(address _indexToken, address _tokenIn, uint256 _inputAmount) internal {
        uint256 wethAmount = _inputAmount;
        mainChainStorage.increasePendingIssuanceInputByNonce(mainChainStorage.issuanceNonce(), wethAmount);
        // swap to underlying assets on all chain
        uint256 totalChains = functionsOracle.currentChainSelectorsCount(_indexToken);
        uint256 latestCount = functionsOracle.currentFilledCount(_indexToken);
        (,, uint64[] memory chainSelectors) = functionsOracle.getCurrentData(_indexToken, latestCount);
        for (uint256 i = 0; i < totalChains; i++) {
            uint64 chainSelector = chainSelectors[i];
            uint256 chainSelectorTokensCount =
                functionsOracle.currentChainSelectorTokensCount(_indexToken, chainSelector);
            if (chainSelector == currentChainSelector) {
                _issuanceSwapsCurrentChain(
                    _indexToken,
                    wethAmount,
                    mainChainStorage.issuanceNonce(),
                    chainSelectorTokensCount,
                    chainSelector,
                    latestCount
                );
            } else {
                _issuanceSwapsOtherChains(
                    _indexToken, wethAmount, mainChainStorage.issuanceNonce(), chainSelector, latestCount
                );
            }
        }
        emit RequestIssuance(
            mainChainStorage.getIssuanceMessageId(mainChainStorage.issuanceNonce()),
            mainChainStorage.issuanceNonce(),
            msg.sender,
            _tokenIn,
            mainChainStorage.getIssuanceInputAmount(mainChainStorage.issuanceNonce()),
            0,
            block.timestamp
        );
    }

    /**
     * @dev Handles issuance swaps on the current chain.
     * @param _indexToken The address of the index token.
     * @param _wethAmount The amount of WETH.
     * @param _issuanceNonce The issuance nonce.
     * @param _chainSelectorTokensCount The number of tokens in the chain selector.
     * @param _chainSelector The chain selector.
     * @param _latestCount The latest count.
     */
    function _issuanceSwapsCurrentChain(
        address _indexToken,
        uint256 _wethAmount,
        uint256 _issuanceNonce,
        uint256 _chainSelectorTokensCount,
        uint64 _chainSelector,
        uint256 _latestCount
    ) internal {
        address[] memory tokens = functionsOracle.allCurrentChainSelectorTokens(_indexToken, _chainSelector);
        for (uint256 i = 0; i < _chainSelectorTokensCount; i++) {
            address tokenAddress = tokens[i];
            (address[] memory fromETHPath, uint24[] memory fromETHFees) =
                functionsOracle.getFromETHPathData(tokenAddress);

            mainChainStorage.setIssuanceOldTokenValue(
                _issuanceNonce, tokenAddress, mainChainStorage.getCurrentTokenValue(tokenAddress)
            );

            uint256 tokenMarketShare = functionsOracle.tokenCurrentMarketShare(_indexToken, tokenAddress);
            uint256 swapAmount = (_wethAmount * tokenMarketShare) / 100e18;
            if (tokenAddress != address(weth)) {
                swap(fromETHPath, fromETHFees, swapAmount, address(mainChainStorage.vault()));
            } else {
                weth.transfer(address(mainChainStorage.vault()), swapAmount);
            }

            mainChainStorage.setIssuanceNewTokenValue(
                _issuanceNonce, tokenAddress, mainChainStorage.getCurrentTokenValue(tokenAddress)
            );
            mainChainStorage.issuanceIncreaseCompletedTokensCount(_issuanceNonce);
            // call the order manager here
            // orderManager.completeIssuance(
            //     _issuanceNonce, 
            //     _indexToken, 
            //     tokenAddress, 
            //     mainChainStorage.getIssuanceOldTokenValue(_issuanceNonce, tokenAddress),
            //     mainChainStorage.getIssuanceNewTokenValue(_issuanceNonce, tokenAddress)
            // );
        }
    }

    function _issuanceSwapsOtherChains(
        address _indexToken,
        uint256 _wethAmount,
        uint256 _issuanceNonce,
        uint64 _chainSelector,
        uint256 _latestCount
    ) internal {
        uint256 totalShares =
            functionsOracle.getCurrentChainSelectorTotalShares(_indexToken, _latestCount, _chainSelector);
        uint256 chainWethAmount = (_wethAmount * totalShares) / 100e18;

        weth.approve(address(coreSender), chainWethAmount);
        coreSender.sendIssuanceRequest(chainWethAmount, _issuanceNonce, _chainSelector, _latestCount);
    }

    /**
     * @dev Redeems tokens.
     * @param _indexToken The address of the index token.
     * @param _burnPercent The burn percentage.
     * @param _tokenOut The address of the output token.
     */
    function redemption(
        address _indexToken,
        uint256 _burnPercent,
        address _tokenOut,
        address[] memory _tokenOutPath,
        uint24[] memory _tokenOutFees
    ) public payable whenNotPaused {
        // Validate input parameters
        // require(amountIn > 0, "Amount must be greater than zero");
        require(_tokenOut != address(0), "Invalid output token address");
        require(_tokenOutPath[0] == address(weth), "Invalid token path");
        if (!mainChainStorage.isCrossChainFeeSponsered()) {
            // require(getRedemptionFee(_indexToken, amountIn) >= msg.value, "Insufficient ETH sent for cross chain fee");
            (bool success,) = mainChainStorage.coreSender().call{value: msg.value}("");
            require(success, "Cross chain fee transfer failed");
        }
        // uint256 burnPercent = (amountIn * 1e18) / indexToken.totalSupply();
        mainChainStorage.increaseRedemptionNonce();
        // mainChainStorage.increasePendingRedemptionInputByNonce(mainChainStorage.redemptionNonce(), amountIn);
        // mainChainStorage.setRedemptionData(
        //     mainChainStorage.redemptionNonce(), msg.sender, _tokenOut, amountIn, _tokenOutPath, _tokenOutFees, bytes32(0)
        // );

        // indexToken.burn(msg.sender, amountIn);

        //swap
        uint256 totalChains = functionsOracle.currentChainSelectorsCount(_indexToken);
        uint256 latestCount = functionsOracle.currentFilledCount(_indexToken);
        (,, uint64[] memory chainSelectors) = functionsOracle.getCurrentData(_indexToken, latestCount);
        for (uint256 i = 0; i < totalChains; i++) {
            uint64 chainSelector = chainSelectors[i];
            uint256 chainSelectorTokensCount =
                functionsOracle.currentChainSelectorTokensCount(_indexToken, chainSelector);
            if (chainSelector == currentChainSelector) {
                _redemptionSwapsCurrentChain(
                    _indexToken,
                    _burnPercent,
                    // redemptionNonce,
                    mainChainStorage.redemptionNonce(),
                    chainSelectorTokensCount
                );
            } else {
                _redemptionSwapsOtherChains(_burnPercent, mainChainStorage.redemptionNonce(), chainSelector);
            }
        }
        emit RequestRedemption(
            mainChainStorage.getRedemptionMessageId(mainChainStorage.redemptionNonce()),
            mainChainStorage.redemptionNonce(),
            msg.sender,
            _tokenOut,
            0,
            0,
            block.timestamp
        );
    }

    /**
     * @dev Handles redemption swaps on the current chain.
     * @param _indexToken The address of the index token.
     * @param _burnPercent The burn percentage.
     * @param _redemptionNonce The redemption nonce.
     * @param _chainSelectorTokensCount The number of tokens in the chain selector.
     */
    function _redemptionSwapsCurrentChain(
        address _indexToken,
        uint256 _burnPercent,
        uint256 _redemptionNonce,
        uint256 _chainSelectorTokensCount
    ) internal {
        address[] memory tokens = functionsOracle.allCurrentChainSelectorTokens(_indexToken, currentChainSelector);
        Vault vault = mainChainStorage.vault();
        for (uint256 i = 0; i < _chainSelectorTokensCount; i++) {
            address tokenAddress = tokens[i];
            (address[] memory toETHPath, uint24[] memory toETHFees) = functionsOracle.getToETHPathData(tokenAddress);
            uint256 swapAmount = (_burnPercent * IERC20(tokenAddress).balanceOf(address(mainChainStorage.vault()))) / 1e18;
            vault.withdrawFunds(tokenAddress, address(this), swapAmount);
            uint256 swapAmountOut =
                tokenAddress == address(weth) ? swapAmount : swap(toETHPath, toETHFees, swapAmount, address(coreSender));
            if (tokenAddress == address(weth)) {
                weth.transfer(address(coreSender), swapAmount);
            }
            mainChainStorage.increasePendingRedemptionHoldValueByNonce(_redemptionNonce, swapAmountOut);
            mainChainStorage.increaseRedemptionTotalValue(_redemptionNonce, swapAmountOut);
            mainChainStorage.increaseRedemptionTotalPortfolioValues(
                _redemptionNonce,
                tokenAddress == address(weth)
                    ? IERC20(tokenAddress).balanceOf(address(mainChainStorage.vault()))
                    : mainChainStorage.getAmountOut(
                        toETHPath, toETHFees, IERC20(tokenAddress).balanceOf(address(mainChainStorage.vault()))
                    )
            );
            mainChainStorage.increaseRedemptionCompletedTokensCount(_redemptionNonce, 1);
            // call the order manager here
            // ....
        }
    }

    function _redemptionSwapsOtherChains(uint256 _burnPercent, uint256 _redemptionNonce, uint64 _chainSelector)
        internal
    {
        coreSender.sendRedemptionRequest(_burnPercent, _redemptionNonce, _chainSelector);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "../utils/proposable/ProposableOwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./MainChainStorage.sol";
import "../oracle/FunctionsOracle.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "../libraries/SwapHelpers.sol";
import "../interfaces/IWETH.sol";
import "./BalancerSender.sol";
import "./MainChainFactory.sol";
import "../factory/IndexFactoryBalancer.sol";
import "../factory/IndexFactoryStorage.sol";

/// @title Index Token
/// @author NEX Labs Protocol
/// @notice The main token contract for Index Token (NEX Labs Protocol)
/// @dev This contract uses an upgradeable pattern
/// @custom:oz-upgrades-from MainChainBalancerV2
contract MainChainBalancerV3 is Initializable, ProposableOwnableUpgradeable, PausableUpgradeable {
    MainChainStorage public mainChainStorage;
    FunctionsOracle public functionsOracle;
    BalancerSender public balancerSender;
    IndexFactoryBalancer public indexFactoryBalancer;
    IndexFactoryStorage public indexFactoryStorage;
    uint64 public currentChainSelector;
    uint256 public reweightCalled;

    uint256 public targetPortfolioValue;

    IWETH public weth;
    address public usdcAddress;

    struct LowSwapVariables {
        address tokenAddress;
        uint256 tokenMarketShare;
        uint256 chainValue;
        uint256 swapWethAmount;
        uint256 wethAmount;
    }

    struct ExtraSwapVariables {
        address tokenAddress;
        uint256 tokenMarketShare;
        uint256 chainValue;
        uint256 swapWethAmount;
    }

    event RequestedAskValues(address indexToken, uint256 time);
    event RequestedFirstReweightAction(address indexToken, uint256 time);
    event RequestedSecondReweightAction(address indexToken, uint256 time);

    /**
     * @dev Pauses the contract.
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev Unpauses the contract.
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    modifier onlyOwnerOrOperator() {
        require(msg.sender == owner() || functionsOracle.isOperator(msg.sender), "Caller is not the owner or operator");
        _;
    }

    /**
     * @dev Initializes the contract with the given parameters.
     * @param _currentChainSelector The current chain selector.
     * @param _mainChainStorage The address of the MainChainStorage contract.
     * @param _functionsOracle The address of the FunctionsOracle contract.
     * @param _balancerSender The address of the BalancerSender contract.
     * @param _weth The address of the WETH token.
     */
    function initialize(
        uint64 _currentChainSelector,
        address _mainChainStorage,
        address _functionsOracle,
        address payable _balancerSender,
        //addresses
        address _weth,
        address _usdcAddress
    ) external initializer {
        // Validate input parameters
        require(_currentChainSelector > 0, "Invalid chain selector");
        require(_mainChainStorage != address(0), "Invalid factory storage address");
        require(_weth != address(0), "Invalid WETH address");
        __Ownable_init(msg.sender);
        //set chain selector
        currentChainSelector = _currentChainSelector;
        mainChainStorage = MainChainStorage(_mainChainStorage);
        functionsOracle = FunctionsOracle(_functionsOracle);
        balancerSender = BalancerSender(_balancerSender);
        //set addresses
        weth = IWETH(_weth);
        usdcAddress = _usdcAddress;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Sets the MainChainStorage contract address.
     * @param _mainChainStorage The address of the MainChainStorage contract.
     */
    function setMainChainStorage(address _mainChainStorage) public onlyOwner {
        mainChainStorage = MainChainStorage(_mainChainStorage);
    }

    function setIndexFactoryBalancer(address _indexFactoryBalancer) public onlyOwner {
        indexFactoryBalancer = IndexFactoryBalancer(_indexFactoryBalancer);
    }

    /**
     * @dev Sets the FunctionsOracle contract address.
     * @param _functionsOracle The address of the FunctionsOracle contract.
     */
    function setFunctionsOracle(address _functionsOracle) public onlyOwner {
        functionsOracle = FunctionsOracle(_functionsOracle);
    }

    function setBalancerSender(address payable _balancerSender) public onlyOwner {
        balancerSender = BalancerSender(_balancerSender);
    }

    function setIndexFactoryStorage(address _indexFactoryStorage) public onlyOwner {
        indexFactoryStorage = IndexFactoryStorage(_indexFactoryStorage);
    }

    // set WETH address
    function setWethAddress(address _weth) public onlyOwner {
        require(_weth != address(0), "Invalid WETH address");
        weth = IWETH(_weth);
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
        // uint256 amountOutMinimum = mainChainStorage.getMinAmountOut(path, fees, amountIn);
        // outputAmount = SwapHelpers.swap(swapRouterV3, swapRouterV2, path, fees, amountIn, amountOutMinimum, _recipient);
    }

    function getUpdatePortfolioNonce() public view returns (uint256) {
        return mainChainStorage.updatePortfolioNonce();
    }

    function requestRebalance(
        address _indexToken,
        uint256 _nonce,
        uint256 _targetPortfolioValue,
        address _usdcAddress,
        uint256 _dedicatedUSDCAmount
    ) public whenNotPaused onlyOwnerOrOperator {
        uint256 portfolioValue = mainChainStorage.portfolioTotalValueByNonce(_nonce);
        targetPortfolioValue = _targetPortfolioValue;
        if (_dedicatedUSDCAmount > 0) {
            IERC20(_usdcAddress).transferFrom(msg.sender, address(this), _dedicatedUSDCAmount);
            (address[] memory toETHPath, uint24[] memory toETHFees) = functionsOracle.getToETHPathData(_usdcAddress);
            uint256 wethAmount = swap(toETHPath, toETHFees, _dedicatedUSDCAmount, address(this));
            uint256 reweightExtraPercentage =
                ((_targetPortfolioValue - portfolioValue) * 100e18) / _targetPortfolioValue;
            mainChainStorage.increaseExtraWethByNonce(_nonce, wethAmount);
            mainChainStorage.increasePendingExtraWethByNonce(_nonce, wethAmount);
            mainChainStorage.increaseReweightExtraPercentage(_nonce, reweightExtraPercentage);
        }
        firstReweightAction(_indexToken, _nonce, _targetPortfolioValue);
    }

    function _firstReweightSwaps(
        uint256 i,
        address _indexToken,
        uint256 _targetPortfolioValue,
        uint64 _chainSelector,
        uint256 _latestOracleCount
    ) internal returns (bool isCrossChain) {
        uint256 _oracleChainSelectorTotalShares = functionsOracle.getOracleChainSelectorTotalShares(
            _indexToken, _latestOracleCount, _chainSelector
        );
        uint256 nonce = mainChainStorage.updatePortfolioNonce();
        uint256 portfolioValue = mainChainStorage.portfolioTotalValueByNonce(nonce);
        uint256 chainValue = mainChainStorage.chainValueByNonce(nonce, _chainSelector);

        if (
            (chainValue * 100e18) / indexFactoryBalancer.getGlobalPortfolioValueByProviderNonce(1, nonce)
                >= _oracleChainSelectorTotalShares
        ) {
            mainChainStorage.increaseReweightTotalExtraPendingChains(nonce, 1);
            if (_chainSelector == currentChainSelector) {
                _swapExtraValueCurrentChain(
                    i,
                    _indexToken,
                    nonce,
                    portfolioValue,
                    _targetPortfolioValue,
                    _chainSelector,
                    _latestOracleCount,
                    _oracleChainSelectorTotalShares
                );
                mainChainStorage.increaseReweightTotalExtraCompletedChains(nonce, 1);
            } else {
                isCrossChain = true;
                _sendExtraValueOtherChains(
                    _indexToken,
                    nonce,
                    indexFactoryBalancer.getGlobalPortfolioValueByProviderNonce(1, nonce),
                    _targetPortfolioValue,
                    _chainSelector,
                    _oracleChainSelectorTotalShares,
                    chainValue
                );
            }
        }
    }

    function completeSecondReweightAction(address _indexToken, uint256 nonce) public onlyOwnerOrOperator {
        if (
            // mainChainStorage.totalReweightLowerPendingChains(nonce) > 0 &&
            mainChainStorage.totalReweightLowerPendingChains(nonce)
                == mainChainStorage.totalReweightLowerCompletedChains(nonce)
        ) {
            balancerSender.emitSecondReweightActionCompleted(_indexToken, nonce);
            uint256 remainedExtraWeth =
                mainChainStorage.extraWethByNonce(nonce) - mainChainStorage.consumedExtraWethByNonce(nonce);
            reweightCalled = remainedExtraWeth;
            uint256 outputAmount;
            if (remainedExtraWeth > 1000) {
                (address[] memory toTokenPath, uint24[] memory toTokenFees) =
                    functionsOracle.getFromETHPathData(usdcAddress);
                outputAmount = swap(toTokenPath, toTokenFees, remainedExtraWeth, address(this));
                // approve to order manager
                IERC20(usdcAddress).approve(address(indexFactoryBalancer), outputAmount);
            }
            indexFactoryBalancer.completeReweightAction(_indexToken, 1, nonce, outputAmount);
        }
    }

    /**
     * @dev Performs the first reweight action.
     */
    function firstReweightAction(address _indexToken, uint256 nonce, uint256 _targetPortfolioValue)
        public
        whenNotPaused
        onlyOwnerOrOperator
    {
        // check ask values completed
        require(
            mainChainStorage.rebalanceStatusByNonce(nonce) == MainChainStorage.RebalanceStatus.AskValuesCompleted,
            "Values not asked"
        );
        uint256 portfolioValue = mainChainStorage.portfolioTotalValueByNonce(nonce);

        uint256 latestCurrentCount = functionsOracle.currentFilledCount(_indexToken);
        uint256 latestOracleCount = functionsOracle.oracleFilledCount(_indexToken);

        (,, uint64[] memory chainSelectors) = functionsOracle.getCurrentData(_indexToken, latestCurrentCount);
        bool isCrossChain = false;
        for (uint256 i = 0; i < functionsOracle.currentChainSelectorsCount(_indexToken); i++) {
            uint64 chainSelector = chainSelectors[i];

            bool _isCrossChain =
                _firstReweightSwaps(i, _indexToken, _targetPortfolioValue, chainSelector, latestOracleCount);
            if (_isCrossChain) {
                isCrossChain = true;
            }
        }

        emit RequestedFirstReweightAction(_indexToken, block.timestamp);
        if (!isCrossChain) {
            balancerSender.emitFirstReweightActionCompleted(_indexToken, nonce);
        }
    }

    function _internalSwapTokensToWETHFirstRebalance(
        address _indexToken,
        uint256,
        /*_nonce*/
        uint64 chainSelector,
        uint256,
        /*portfolioValue*/
        uint256 /*_targetPortfolioValue*/
    ) internal returns (uint256 swapWethAmount) {
        uint256 initialWethBalance = weth.balanceOf(address(indexFactoryStorage.indexTokenToVault(_indexToken)));
        // uint256 chainValue = mainChainStorage.chainValueByNonce(_nonce, chainSelector);
        address[] memory currentTokens = functionsOracle.allCurrentChainSelectorTokens(_indexToken, chainSelector);
        for (uint256 j = 0; j < currentTokens.length; j++) {
            ExtraSwapVariables memory swapVars;
            Vault vault = Vault(indexFactoryStorage.indexTokenToVault(_indexToken));
            swapVars.tokenAddress = currentTokens[j];
            (address[] memory toETHPath, uint24[] memory toETHFees) =
                functionsOracle.getToETHPathData(swapVars.tokenAddress);
            uint256 wethAmount;
            if (swapVars.tokenAddress == address(weth)) {
                vault.withdrawFunds(swapVars.tokenAddress, address(this), initialWethBalance);
                wethAmount = initialWethBalance;
            } else {
                uint256 tokenAmount = IERC20(swapVars.tokenAddress).balanceOf(address(vault));
                vault.withdrawFunds(swapVars.tokenAddress, address(this), tokenAmount);
                wethAmount = swap(toETHPath, toETHFees, tokenAmount, address(this));
            }
            swapWethAmount += wethAmount;
        }
    }

    function _swapTokensToWETHFirstRebalance(
        address _indexToken,
        uint256 _nonce,
        uint64 chainSelector,
        uint256 portfolioValue,
        uint256 _targetPortfolioValue
    ) internal returns (uint256 chainCurrentRealShare, uint256 wethAmountToSwap, uint256 extraWethAmount) {
        uint256 swapWethAmount = _internalSwapTokensToWETHFirstRebalance(
            _indexToken, _nonce, chainSelector, portfolioValue, _targetPortfolioValue
        );

        // uint256 latestOracleCount = functionsOracle.oracleFilledCount(_indexToken);
        uint256 oracleChainSelectorTotalShares = functionsOracle.getOracleChainSelectorTotalShares(
            _indexToken, functionsOracle.oracleFilledCount(_indexToken), chainSelector
        );
        chainCurrentRealShare = (mainChainStorage.chainValueByNonce(_nonce, chainSelector) * 100e18)
            / indexFactoryBalancer.getGlobalPortfolioValueByProviderNonce(1, _nonce);
        wethAmountToSwap = (swapWethAmount * oracleChainSelectorTotalShares) / chainCurrentRealShare;
        extraWethAmount = swapWethAmount - wethAmountToSwap;
    }

    function _internalSwapsWETHToTokensForFirstRebalance(
        address _indexToken,
        address _newTokenAddress,
        uint256 _wethAmountToSwap,
        uint256 _newTokenMarketShare,
        uint256 _oracleChainSelectorTotalShares
    ) internal returns (uint256) {
        uint256 wethAmount;
        if (_newTokenAddress == address(weth)) {
            wethAmount = (_wethAmountToSwap * _newTokenMarketShare) / _oracleChainSelectorTotalShares;
            weth.transfer(address(indexFactoryStorage.indexTokenToVault(_indexToken)), wethAmount);
        } else {
            (address[] memory fromETHPath, uint24[] memory fromETHFees) =
                functionsOracle.getFromETHPathData(_newTokenAddress);
            wethAmount = swap(
                fromETHPath,
                fromETHFees,
                (_wethAmountToSwap * _newTokenMarketShare) / _oracleChainSelectorTotalShares,
                address(indexFactoryStorage.indexTokenToVault(_indexToken))
            );
        }
        return wethAmount;
    }

    function _swapWETHToTokensForFirstRebalance(address _indexToken, uint64 chainSelector, uint256 wethAmountToSwap)
        internal
    {
        uint256 _latestOracleCount = functionsOracle.oracleFilledCount(_indexToken);
        uint256 oracleChainSelectorTotalShares =
            functionsOracle.getOracleChainSelectorTotalShares(_indexToken, _latestOracleCount, chainSelector);
        address[] memory oracleTokens = functionsOracle.allOracleChainSelectorTokens(_indexToken, chainSelector);
        uint256[] memory oracleMarketShares =
            functionsOracle.allOracleChainSelectorTokenShares(_indexToken, chainSelector);
        for (uint256 k = 0; k < oracleTokens.length; k++) {
            address newTokenAddress = oracleTokens[k];

            uint256 newTokenMarketShare = oracleMarketShares[k];

            _internalSwapsWETHToTokensForFirstRebalance(
                _indexToken, newTokenAddress, wethAmountToSwap, newTokenMarketShare, oracleChainSelectorTotalShares
            );
        }
    }

    function _updateExtraValuesMapping(
        uint256 nonce,
        uint256,
        /*portfolioValue*/
        uint256 _targetPortfolioValue,
        uint64 chainSelector,
        uint256 oracleChainSelectorTotalShares,
        uint256 extraWethAmount
    ) internal {
        uint256 chainValue = mainChainStorage.chainValueByNonce(nonce, chainSelector);
        uint256 targetChainValue =
            (indexFactoryBalancer.getGlobalPortfolioValueByProviderNonce(1, nonce) * oracleChainSelectorTotalShares)
                / 100e18;
        uint256 reweightExtraPercentage = ((chainValue - targetChainValue) * 100e18)
            / indexFactoryBalancer.getGlobalPortfolioValueByProviderNonce(1, nonce);
        mainChainStorage.increaseExtraWethByNonce(nonce, extraWethAmount);
        mainChainStorage.increasePendingExtraWethByNonce(nonce, extraWethAmount);
        mainChainStorage.increaseReweightExtraPercentage(nonce, reweightExtraPercentage);
    }

    function _swapExtraValueCurrentChain(
        uint256,
        /*i*/
        address _indexToken,
        uint256 nonce,
        uint256 portfolioValue,
        uint256 _targetPortfolioValue,
        uint64 chainSelector,
        uint256,
        /*_latestOracleCount*/
        uint256 oracleChainSelectorTotalShares
    ) internal {
        (uint256 unusedChainCurrentRealShare, uint256 wethAmountToSwap, uint256 extraWethAmount) =
            _swapTokensToWETHFirstRebalance(_indexToken, nonce, chainSelector, portfolioValue, _targetPortfolioValue);

        _swapWETHToTokensForFirstRebalance(_indexToken, chainSelector, wethAmountToSwap);

        _updateExtraValuesMapping(
            nonce, portfolioValue, _targetPortfolioValue, chainSelector, oracleChainSelectorTotalShares, extraWethAmount
        );
    }

    function _sendExtraValueOtherChains(
        address _indexToken,
        uint256 nonce,
        uint256 portfolioValue,
        uint256 _targetPortfolioValue,
        uint64 chainSelector,
        uint256 oracleChainSelectorTotalShares,
        uint256 chainValue
    ) internal {
        uint256[] memory oracleTokenShares =
            functionsOracle.allOracleChainSelectorTokenShares(_indexToken, chainSelector);
        balancerSender.sendFirstReweightAction(
            _indexToken,
            nonce,
            portfolioValue,
            _targetPortfolioValue,
            chainSelector,
            oracleChainSelectorTotalShares,
            chainValue,
            oracleTokenShares
        );
    }

    /**
     * @dev Performs the second reweight action.
     */
    function secondReweightAction(address _indexToken, uint256 nonce) public whenNotPaused onlyOwnerOrOperator {
        // check previous reweight completed
        require(
            mainChainStorage.rebalanceStatusByNonce(nonce) == MainChainStorage.RebalanceStatus.FirstRebalanceCompleted,
            "First reweight not completed"
        );
        uint256 _targetPortfolioValue = targetPortfolioValue;
        // uint256 portfolioValue = mainChainStorage.portfolioTotalValueByNonce(nonce);

        // uint256 totalChains = functionsOracle.oracleChainSelectorsCount(_indexToken);
        uint256 latestOracleCount = functionsOracle.oracleFilledCount(_indexToken);

        (,, uint64[] memory chainSelectors) = functionsOracle.getOracleData(_indexToken, latestOracleCount);
        bool isOnlyOnCurrentChain = true;
        for (uint256 i = 0; i < chainSelectors.length; i++) {
            uint64 chainSelector = chainSelectors[i];

            // uint256 chainSelectorCurrentTokensCount = functionsOracle.currentChainSelectorTokensCount(_indexToken, chainSelector);
            uint256 chainSelectorOracleTokensCount =
                functionsOracle.oracleChainSelectorTokensCount(_indexToken, chainSelector);
            uint256 oracleChainSelectorTotalShares =
                functionsOracle.getOracleChainSelectorTotalShares(_indexToken, latestOracleCount, chainSelector);
            uint256 chainValue = mainChainStorage.chainValueByNonce(nonce, chainSelector);
            uint256[] memory oracleTokenShares =
                functionsOracle.allOracleChainSelectorTokenShares(_indexToken, chainSelector);

            if (
                (chainValue * 100e18) / indexFactoryBalancer.getGlobalPortfolioValueByProviderNonce(1, nonce)
                    < oracleChainSelectorTotalShares
            ) {
                mainChainStorage.increaseReweightTotalLowerPendingChains(nonce, 1);
                // if (chainValue < oracleChainSelectorTotalShares * _targetPortfolioValue / 100e18) {
                if (chainSelector == currentChainSelector) {
                    _swapLowerValueCurrentChain(
                        i, _indexToken, nonce, _targetPortfolioValue, chainSelector, oracleChainSelectorTotalShares
                    );
                    mainChainStorage.increaseReweightTotalLowerCompletedChains(nonce, 1);
                } else {
                    isOnlyOnCurrentChain = false;
                    _sendLowerValueOtherChain(
                        _indexToken,
                        nonce,
                        _targetPortfolioValue,
                        chainSelector,
                        oracleChainSelectorTotalShares,
                        chainValue,
                        oracleTokenShares
                    );
                }
            }
        }
        mainChainStorage.decreasePendingExtraWethByNonce(nonce);
        emit RequestedSecondReweightAction(_indexToken, block.timestamp);
        if (isOnlyOnCurrentChain) {
            completeSecondReweightAction(_indexToken, nonce);
            // unpauseMainChainFactory();
        }
    }

    function _swapLowerValueCurrentChainToWETH(
        address _indexToken,
        uint64 chainSelector,
        uint256 chainSelectorTokensCount,
        uint256 portfolioValue,
        uint256 chainValue
    ) internal returns (uint256 swapWethAmount) {
        LowSwapVariables memory swapVars;
        Vault vault = Vault(indexFactoryStorage.indexTokenToVault(_indexToken));
        uint256 initialWethBalance = weth.balanceOf(address(vault));
        address[] memory currentTokens = functionsOracle.allCurrentChainSelectorTokens(_indexToken, chainSelector);
        for (uint256 j = 0; j < currentTokens.length; j++) {
            swapVars.tokenAddress = currentTokens[j];
            (address[] memory toETHPath, uint24[] memory toETHFees) =
                functionsOracle.getToETHPathData(swapVars.tokenAddress);

            if (swapVars.tokenAddress == address(weth)) {
                Vault(indexFactoryStorage.indexTokenToVault(_indexToken))
                    .withdrawFunds(swapVars.tokenAddress, address(this), initialWethBalance);
                swapVars.wethAmount = initialWethBalance;
            } else {
                uint256 tokenAmount = IERC20(swapVars.tokenAddress).balanceOf(address(vault));
                vault.withdrawFunds(swapVars.tokenAddress, address(this), tokenAmount);
                swapVars.wethAmount = swap(toETHPath, toETHFees, tokenAmount, address(this));
            }
            swapVars.swapWethAmount += swapVars.wethAmount;
        }
        swapWethAmount = swapVars.swapWethAmount;
    }

    function _swapLowerValueCurrentChainFromWETH(
        address _indexToken,
        uint64 chainSelector,
        uint256 swapWethAmount,
        uint256 oracleChainSelectorTotalShares
    ) internal {
        LowSwapVariables memory swapVars;
        swapVars.swapWethAmount = swapWethAmount;
        Vault vault = Vault(indexFactoryStorage.indexTokenToVault(_indexToken));
        address[] memory oracleTokens = functionsOracle.allOracleChainSelectorTokens(_indexToken, chainSelector);
        uint256[] memory oracleMarketShares =
            functionsOracle.allOracleChainSelectorTokenShares(_indexToken, chainSelector);
        for (uint256 k = 0; k < oracleTokens.length; k++) {
            address newTokenAddress = oracleTokens[k];
            (address[] memory fromETHPath, uint24[] memory fromETHFees) =
                functionsOracle.getFromETHPathData(newTokenAddress);

            uint256 newTokenMarketShare = oracleMarketShares[k];
            if (newTokenAddress == address(weth)) {
                swapVars.wethAmount = (swapVars.swapWethAmount * newTokenMarketShare) / oracleChainSelectorTotalShares;
                weth.transfer(address(vault), swapVars.wethAmount);
            } else {
                swapVars.wethAmount = swap(
                    fromETHPath,
                    fromETHFees,
                    (swapVars.swapWethAmount * newTokenMarketShare) / oracleChainSelectorTotalShares,
                    address(vault)
                );
            }
        }
    }

    function _swapLowerValueCurrentChain(
        uint256,
        /*i*/
        address _indexToken,
        uint256 nonce,
        uint256 _targetPortfolioValue,
        uint64 chainSelector,
        uint256 oracleChainSelectorTotalShares
    ) internal {
        LowSwapVariables memory swapVars;
        swapVars.chainValue = mainChainStorage.chainValueByNonce(nonce, chainSelector);
        uint256 chainSelectorCurrentTokensCount =
            functionsOracle.currentChainSelectorTokensCount(_indexToken, chainSelector);
        // uint256 portfolioValue = mainChainStorage.portfolioTotalValueByNonce(nonce);
        uint256 portfolioValue = indexFactoryBalancer.getGlobalPortfolioValueByProviderNonce(1, nonce);
        swapVars.swapWethAmount = _swapLowerValueCurrentChainToWETH(
            _indexToken, chainSelector, chainSelectorCurrentTokensCount, portfolioValue, swapVars.chainValue
        );

        uint256 targetChainValue =
            (indexFactoryBalancer.getGlobalPortfolioValueByProviderNonce(1, nonce) * oracleChainSelectorTotalShares)
                / 100e18;
        // uint256 negativePercentage = targetChainValue > portfolioValue ? ((targetChainValue - portfolioValue) * 100e18) / portfolioValue : 0;
        uint256 negativePercentage = ((targetChainValue - swapVars.chainValue) * 100e18)
            / indexFactoryBalancer.getGlobalPortfolioValueByProviderNonce(1, nonce);
        uint256 extraWethAmount = (mainChainStorage.extraWethByNonce(nonce) * negativePercentage)
            / mainChainStorage.reweightExtraPercentage(nonce);
        mainChainStorage.increaseConsumedExtraWethByNonce(
            nonce,
            extraWethAmount
            // mainChainStorage.extraWethByNonce(nonce) - extraWethAmount
        );
        swapVars.swapWethAmount += extraWethAmount;
        _swapLowerValueCurrentChainFromWETH(
            _indexToken, chainSelector, swapVars.swapWethAmount, oracleChainSelectorTotalShares
        );
    }

    struct SendLowerValueOtherChainVars {
        address[] currentTokenAddresses;
        address[] newTokenAddresses;
        uint256[] extraData;
    }

    function _calculateExtraAmountForLowerValue(
        uint256 _nonce,
        uint256 _portfolioValue,
        uint256 _targetPortfolioValue,
        uint256 _chainValue,
        uint256 _oracleChainSelectorTotalShares
    ) internal returns (uint256) {
        // uint256 chainCurrentRealShare = (_chainValue * 100e18) / _portfolioValue;
        uint256 targetChainValue =
            (indexFactoryBalancer.getGlobalPortfolioValueByProviderNonce(1, _nonce) * _oracleChainSelectorTotalShares)
                / 100e18;
        // uint256 negativePercentage = _oracleChainSelectorTotalShares - chainCurrentRealShare;
        uint256 negativePercentage = ((targetChainValue - _chainValue) * 100e18)
            / indexFactoryBalancer.getGlobalPortfolioValueByProviderNonce(1, _nonce);
        uint256 extraWethAmount = (mainChainStorage.extraWethByNonce(_nonce) * negativePercentage)
            / mainChainStorage.reweightExtraPercentage(_nonce);
        mainChainStorage.increaseConsumedExtraWethByNonce(
            _nonce,
            extraWethAmount
            // mainChainStorage.extraWethByNonce(_nonce) - extraWethAmount
        );
        return extraWethAmount;
    }

    function _sendLowerValueOtherChain(
        address _indexToken,
        uint256 nonce,
        uint256 targetPortfolioValue_,
        uint64 chainSelector,
        uint256 oracleChainSelectorTotalShares,
        uint256 chainValue,
        uint256[] memory oracleTokenShares
    ) internal {
        // uint256 portfolioValue = mainChainStorage.portfolioTotalValueByNonce(nonce);
        uint256 portfolioValue = indexFactoryBalancer.getGlobalPortfolioValueByProviderNonce(1, nonce);
        uint256 extraWethAmount = _calculateExtraAmountForLowerValue(
            nonce, portfolioValue, targetPortfolioValue_, chainValue, oracleChainSelectorTotalShares
        );
        weth.approve(address(balancerSender), extraWethAmount);
        balancerSender.sendSecondReweightAction(
            _indexToken,
            nonce,
            portfolioValue,
            chainSelector,
            oracleChainSelectorTotalShares,
            oracleTokenShares,
            extraWethAmount
        );
    }
}

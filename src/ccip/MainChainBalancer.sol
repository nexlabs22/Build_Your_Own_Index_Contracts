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

/// @title Index Token
/// @author NEX Labs Protocol
/// @notice The main token contract for Index Token (NEX Labs Protocol)
/// @dev This contract uses an upgradeable pattern
contract MainChainBalancer is Initializable, ProposableOwnableUpgradeable, PausableUpgradeable {
    MainChainStorage public mainChainStorage;
    FunctionsOracle public functionsOracle;
    BalancerSender public balancerSender;
    IndexFactoryBalancer public indexFactoryBalancer;
    uint64 public currentChainSelector;

    IWETH public weth;

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

    event RequestedAskValues(uint256 time);
    event RequestedFirstReweightAction(uint256 time);
    event RequestedSecondReweightAction(uint256 time);

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
        address _weth
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

    // set WETH address
    function setWethAddress(address _weth) public onlyOwner {
        require(_weth != address(0), "Invalid WETH address");
        weth = IWETH(_weth);
    }

    /**
     * @dev Sets the current chain selector.
     * @param _currentChainSelector The current chain selector.
     */
    function setCurrentChainSelector(uint64 _currentChainSelector) public onlyOwner {
        require(_currentChainSelector > 0, "Invalid chain selector");
        currentChainSelector = _currentChainSelector;
    }

    // pause main chain factory when rebalance happens
    function pauseMainChainFactory() public onlyOwnerOrOperator {
        address mainChainFactoryAddress = mainChainStorage.mainChainFactory();
        MainChainFactory mainChainFactory = MainChainFactory(payable(mainChainFactoryAddress));
        if (!mainChainFactory.paused()) {
            mainChainFactory.pause();
        }
    }

    // unpause main chain factory when rebalance is done
    function unpauseMainChainFactory() public onlyOwnerOrOperator {
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

    function _checkValuesCurrentChain(address _indexToken, uint64 chainSelector, uint256 chainSelectorTokensCount) internal {
        address[] memory tokens = functionsOracle.allCurrentChainSelectorTokens(_indexToken, chainSelector);
        Vault vault = mainChainStorage.vault();
        for (uint256 j = 0; j < chainSelectorTokensCount; j++) {
            address tokenAddress = tokens[j];
            (address[] memory toETHPath, uint24[] memory toETHFees) = functionsOracle.getToETHPathData(tokenAddress);
            uint256 value;
            if (tokenAddress == address(weth)) {
                value = IERC20(tokenAddress).balanceOf(address(vault));
            } else {
                value =
                    mainChainStorage.getAmountOut(toETHPath, toETHFees, IERC20(tokenAddress).balanceOf(address(vault)));
            }

            mainChainStorage.increasePortfolioTotalValueByNonce(
                mainChainStorage.updatePortfolioNonce(), mainChainStorage.convertEthToUsd(value)
            );
            mainChainStorage.increaseTokenValueByNonce(
                mainChainStorage.updatePortfolioNonce(), tokenAddress, mainChainStorage.convertEthToUsd(value)
            );
            mainChainStorage.increaseUpdatedTokensValueCount(mainChainStorage.updatePortfolioNonce());
            mainChainStorage.increaseChainValueByNonce(
                mainChainStorage.updatePortfolioNonce(), currentChainSelector, mainChainStorage.convertEthToUsd(value)
            );
            // inform factory about the value
            // indexFactoryBalancer.completeAskValueCCIP(
            //     mainChainStorage.updatePortfolioNonce(),
            //     mainChainStorage.convertEthToUsd(value)
            // );
        }
    }

    function _checkValuesOtherChains(address _indexToken, uint64 chainSelector) internal {
        balancerSender.sendAskValues(_indexToken, chainSelector);
    }

    /**
     * @dev Requests values for the portfolio.
     */
    function askValues(address _indexToken) public whenNotPaused returns(uint256) {
        // pauseMainChainFactory();
        mainChainStorage.increaseUpdatePortfolioNonce();

        uint256 totalChains = functionsOracle.currentChainSelectorsCount(_indexToken);
        uint256 latestCount = functionsOracle.currentFilledCount(_indexToken);

        for (uint256 i = 0; i < totalChains; i++) {
            (,, uint64[] memory chainSelectors) = functionsOracle.getCurrentData(_indexToken, latestCount);
            uint64 chainSelector = chainSelectors[i];
            uint256 chainSelectorTokensCount = functionsOracle.currentChainSelectorTokensCount(_indexToken, chainSelector);
            if (chainSelector == currentChainSelector) {
                _checkValuesCurrentChain(_indexToken, chainSelector, chainSelectorTokensCount);
            } else {
                // _checkValuesOtherChains(_indexToken, chainSelector);
            }
        }

        emit RequestedAskValues(block.timestamp);

        return mainChainStorage.updatePortfolioNonce();
    }

    function requestOverWeightedRebalance(address _indexToken, uint256 _targetPortfolioValue, address _usdcAddress, uint256 _dedicatedUSDCAmount) public whenNotPaused onlyOwnerOrOperator {
        uint256 nonce = mainChainStorage.updatePortfolioNonce();
        uint256 portfolioValue = mainChainStorage.portfolioTotalValueByNonce(nonce);
        if(_dedicatedUSDCAmount > 0) {
            (address[] memory toETHPath, uint24[] memory toETHFees) =
                functionsOracle.getToETHPathData(_usdcAddress);
            uint256 wethAmount = swap(toETHPath, toETHFees, _dedicatedUSDCAmount, address(this));
            uint256 reweightExtraPercentage = (_targetPortfolioValue * 100e18) / portfolioValue;
            mainChainStorage.increaseExtraWethByNonce(nonce, wethAmount);
            mainChainStorage.increasePendingExtraWethByNonce(nonce, wethAmount);
            mainChainStorage.increaseReweightExtraPercentage(nonce, reweightExtraPercentage);
        }
        firstReweightAction(_indexToken, _targetPortfolioValue);
    }

    function _firstReweightSwaps(
        uint256 i,
        // uint256 _chainValue,
        address _indexToken,
        // uint256 _nonce,
        // uint256 _portfolioValue,
        uint256 _targetPortfolioValue,
        uint64 _chainSelector,
        uint256 _latestOracleCount
    ) internal returns (bool isCrossChain) {
        uint256 _oracleChainSelectorTotalShares = functionsOracle.getOracleChainSelectorTotalShares(_indexToken, _latestOracleCount, _chainSelector);
        uint256 nonce = mainChainStorage.updatePortfolioNonce();
        uint256 portfolioValue = mainChainStorage.portfolioTotalValueByNonce(nonce);
        uint256 chainValue = mainChainStorage.chainValueByNonce(nonce, _chainSelector);

        if ((chainValue > (_oracleChainSelectorTotalShares * _targetPortfolioValue) / 100e18)) {
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
                } else {
                    isCrossChain = true;
                    _sendExtraValueOtherChains(
                        _indexToken,
                        nonce,
                        portfolioValue,
                        _targetPortfolioValue,
                        _chainSelector,
                        _oracleChainSelectorTotalShares,
                        chainValue
                    );
                }
            }
    }

    /**
     * @dev Performs the first reweight action.
     */
    function firstReweightAction(address _indexToken, uint256 _targetPortfolioValue) public whenNotPaused onlyOwnerOrOperator {
        uint256 nonce = mainChainStorage.updatePortfolioNonce();
        uint256 portfolioValue = mainChainStorage.portfolioTotalValueByNonce(nonce);

        uint256 latestCurrentCount = functionsOracle.currentFilledCount(_indexToken);
        uint256 latestOracleCount = functionsOracle.oracleFilledCount(_indexToken);

        (,, uint64[] memory chainSelectors) = functionsOracle.getCurrentData(_indexToken, latestCurrentCount);
        bool isCrossChain = false;
        for (uint256 i = 0; i < functionsOracle.currentChainSelectorsCount(_indexToken); i++) {
            uint64 chainSelector = chainSelectors[i];

            // uint256 chainSelectorCurrentTokensCount = functionsOracle.currentChainSelectorTokensCount(_indexToken, chainSelector);
            // uint256 chainSelectorOracleTokensCount = functionsOracle.oracleChainSelectorTokensCount(_indexToken, chainSelector);
            // uint256 currentChainSelectorTotalShares =
            //     functionsOracle.getCurrentChainSelectorTotalShares(_indexToken, latestOracleCount, chainSelector);
            uint256 oracleChainSelectorTotalShares =
                functionsOracle.getOracleChainSelectorTotalShares(_indexToken, latestOracleCount, chainSelector);
            // uint256 chainValue = mainChainStorage.chainValueByNonce(nonce, chainSelector);
            // uint256[] memory oracleTokenShares = functionsOracle.allOracleChainSelectorTokenShares(_indexToken, chainSelector);
            bool _isCrossChain = _firstReweightSwaps(
                i,
                _indexToken,
                _targetPortfolioValue,
                chainSelector,
                latestOracleCount
            );
            if (_isCrossChain) {
                isCrossChain = true;
            }
        }

        emit RequestedFirstReweightAction(block.timestamp);
        if (!isCrossChain) {
            balancerSender.emitFirstReweightActionCompleted();
        }
    }

    function _internalSwapTokensToWETHFirstRebalance(
        address _indexToken,
        uint256 _nonce,
        uint64 chainSelector,
        uint256 portfolioValue,
        uint256 _targetPortfolioValue
    ) internal returns(uint256 swapWethAmount) {
        // Vault vault = mainChainStorage.vault();
        uint256 initialWethBalance = weth.balanceOf(address(mainChainStorage.vault()));
        // uint256 chainValue = mainChainStorage.chainValueByNonce(_nonce, chainSelector);
        address[] memory currentTokens = functionsOracle.allCurrentChainSelectorTokens(_indexToken, chainSelector);
        for (uint256 j = 0; j < currentTokens.length; j++) {
            ExtraSwapVariables memory swapVars;
            swapVars.tokenAddress = currentTokens[j];
            (address[] memory toETHPath, uint24[] memory toETHFees) =
                functionsOracle.getToETHPathData(swapVars.tokenAddress);
            uint256 wethAmount;
            if (swapVars.tokenAddress == address(weth)) {
                mainChainStorage.vault().withdrawFunds(swapVars.tokenAddress, address(this), initialWethBalance);
                wethAmount = initialWethBalance;
            } else {
                uint256 tokenAmount = IERC20(swapVars.tokenAddress).balanceOf(address(mainChainStorage.vault()));
                mainChainStorage.vault().withdrawFunds(swapVars.tokenAddress, address(this), tokenAmount);
                wethAmount = swap(toETHPath, toETHFees, tokenAmount, address(this));
            }
            swapWethAmount += wethAmount;
        }
    }

    function _swapTokensToWETHFirstRebalance(
        address _indexToken,
        uint256 _nonce,
        uint64 chainSelector,
        // address[] memory currentTokens,
        uint256 portfolioValue,
        uint256 _targetPortfolioValue
        // uint256 oracleChainSelectorTotalShares,
        // uint256 chainValue
    ) internal returns (uint256 chainCurrentRealShare, uint256 wethAmountToSwap, uint256 extraWethAmount) {
        // uint256 swapWethAmount;
        // // Vault vault = mainChainStorage.vault();
        // uint256 initialWethBalance = weth.balanceOf(address(mainChainStorage.vault()));
        // // uint256 chainValue = mainChainStorage.chainValueByNonce(_nonce, chainSelector);
        // address[] memory currentTokens = functionsOracle.allCurrentChainSelectorTokens(_indexToken, chainSelector);
        // for (uint256 j = 0; j < currentTokens.length; j++) {
        //     ExtraSwapVariables memory swapVars;
        //     swapVars.tokenAddress = currentTokens[j];
        //     (address[] memory toETHPath, uint24[] memory toETHFees) =
        //         functionsOracle.getToETHPathData(swapVars.tokenAddress);
        //     uint256 wethAmount;
        //     if (swapVars.tokenAddress == address(weth)) {
        //         mainChainStorage.vault().withdrawFunds(swapVars.tokenAddress, address(this), initialWethBalance);
        //         wethAmount = initialWethBalance;
        //     } else {
        //         uint256 tokenAmount = IERC20(swapVars.tokenAddress).balanceOf(address(mainChainStorage.vault()));
        //         mainChainStorage.vault().withdrawFunds(swapVars.tokenAddress, address(this), tokenAmount);
        //         wethAmount = swap(toETHPath, toETHFees, tokenAmount, address(this));
        //     }
        //     swapWethAmount += wethAmount;
        // }

        uint256 swapWethAmount = _internalSwapTokensToWETHFirstRebalance(
            _indexToken,
            _nonce,
            chainSelector,
            portfolioValue,
            _targetPortfolioValue
        );

        // uint256 latestOracleCount = functionsOracle.oracleFilledCount(_indexToken);
        uint256 oracleChainSelectorTotalShares = functionsOracle.getOracleChainSelectorTotalShares(_indexToken, functionsOracle.oracleFilledCount(_indexToken), chainSelector);
        chainCurrentRealShare = (mainChainStorage.chainValueByNonce(_nonce, chainSelector) * 100e18) / portfolioValue;
        wethAmountToSwap += (swapWethAmount * ((oracleChainSelectorTotalShares * _targetPortfolioValue) / 100e18)) / mainChainStorage.chainValueByNonce(_nonce, chainSelector);
        extraWethAmount = swapWethAmount - wethAmountToSwap;
        // uint256 latestOracleCount = functionsOracle.oracleFilledCount(_indexToken);
        // uint256 oracleChainSelectorTotalShares = functionsOracle.getOracleChainSelectorTotalShares(_indexToken, latestOracleCount, chainSelector);
        // chainCurrentRealShare = (chainValue * 100e18) / portfolioValue;
        // wethAmountToSwap += (swapWethAmount * ((oracleChainSelectorTotalShares * _targetPortfolioValue) / 100e18)) / chainValue;
        // // wethAmountToSwap = (swapWethAmount * oracleChainSelectorTotalShares) / chainCurrentRealShare;
        // extraWethAmount = swapWethAmount - wethAmountToSwap;
        // // extraWethAmount = swapWethAmount - wethAmountToSwap;
    }

    function _internalSwapsWETHToTokensForFirstRebalance(
        address _newTokenAddress,
        uint256 _wethAmountToSwap,
        uint256 _newTokenMarketShare,
        uint256 _oracleChainSelectorTotalShares,
        Vault _vault
    ) internal returns (uint256) {
        uint256 wethAmount;
        if (_newTokenAddress == address(weth)) {
            wethAmount = (_wethAmountToSwap * _newTokenMarketShare) / _oracleChainSelectorTotalShares;
            weth.transfer(address(_vault), wethAmount);
        } else {
            (address[] memory fromETHPath, uint24[] memory fromETHFees) =
                functionsOracle.getFromETHPathData(_newTokenAddress);
            wethAmount = swap(
                fromETHPath,
                fromETHFees,
                (_wethAmountToSwap * _newTokenMarketShare) / _oracleChainSelectorTotalShares,
                address(_vault)
            );
        }
        return wethAmount;
    }

    function _swapWETHToTokensForFirstRebalance(
        address _indexToken,
        uint64 chainSelector,
        uint256 wethAmountToSwap
    ) internal {
        Vault vault = mainChainStorage.vault();
        uint256 _latestOracleCount = functionsOracle.oracleFilledCount(_indexToken);
        uint256 oracleChainSelectorTotalShares = functionsOracle.getCurrentChainSelectorTotalShares(_indexToken, _latestOracleCount, chainSelector);
        address[] memory oracleTokens = functionsOracle.allOracleChainSelectorTokens(_indexToken, chainSelector);
        for (uint256 k = 0; k < oracleTokens.length; k++) {
            address newTokenAddress = oracleTokens[k];

            uint256 newTokenMarketShare = functionsOracle.tokenOracleMarketShare(_indexToken, newTokenAddress);

            uint256 wethAmount = _internalSwapsWETHToTokensForFirstRebalance(
                newTokenAddress, wethAmountToSwap, newTokenMarketShare, oracleChainSelectorTotalShares, vault
            );
        }
    }

    function _updateExtraValuesMapping(
        uint256 nonce,
        uint256 portfolioValue,
        uint256 _targetPortfolioValue,
        uint64 chainSelector,
        uint256 oracleChainSelectorTotalShares,
        uint256 extraWethAmount
    ) internal {
        uint chainValue = mainChainStorage.chainValueByNonce(nonce, chainSelector);
        uint256 targetChainValue = (_targetPortfolioValue * oracleChainSelectorTotalShares) / 100e18;
        uint256 reweightExtraPercentage = ((chainValue - targetChainValue) * 100e18) / portfolioValue;
        mainChainStorage.increaseExtraWethByNonce(nonce, extraWethAmount);
        mainChainStorage.increasePendingExtraWethByNonce(nonce, extraWethAmount);
        mainChainStorage.increaseReweightExtraPercentage(nonce, reweightExtraPercentage);
    }

    
    function _swapExtraValueCurrentChain(
        uint256 i,
        address _indexToken,
        uint256 nonce,
        uint256 portfolioValue,
        uint256 _targetPortfolioValue,
        uint64 chainSelector,
        uint256 _latestOracleCount,
        uint256 oracleChainSelectorTotalShares
    ) internal {
        ExtraSwapVariables memory swapVars;
        // Vault vault = mainChainStorage.vault();
        // swapVars.chainValue = mainChainStorage.chainValueByNonce(nonce, chainSelector);
        // uint256 initialWethBalance = weth.balanceOf(address(vault));
        (uint256 chainCurrentRealShare, uint256 wethAmountToSwap, uint256 extraWethAmount) =
        _swapTokensToWETHFirstRebalance(
            _indexToken,
            nonce,
            chainSelector,
            // functionsOracle.allCurrentChainSelectorTokens(_indexToken, chainSelector),
            portfolioValue,
            _targetPortfolioValue
            // functionsOracle.getOracleChainSelectorTotalShares(_indexToken, _latestOracleCount, chainSelector),
            // mainChainStorage.chainValueByNonce(nonce, chainSelector)
        );

        _swapWETHToTokensForFirstRebalance(
            _indexToken,
            chainSelector,
            wethAmountToSwap
            // functionsOracle.getCurrentChainSelectorTotalShares(_indexToken, _latestOracleCount, chainSelector)
        );

        _updateExtraValuesMapping(nonce, portfolioValue, _targetPortfolioValue, chainSelector, oracleChainSelectorTotalShares, extraWethAmount);
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
        uint256[] memory oracleTokenShares = functionsOracle.allOracleChainSelectorTokenShares(_indexToken, chainSelector);
        balancerSender.sendFirstReweightAction(
            _indexToken, nonce, portfolioValue, _targetPortfolioValue, chainSelector, oracleChainSelectorTotalShares, chainValue, oracleTokenShares
        );
    }

    /**
     * @dev Performs the second reweight action.
     */
    function secondReweightAction(address _indexToken, uint256 _targetPortfolioValue) public whenNotPaused onlyOwnerOrOperator {
        uint256 nonce = mainChainStorage.updatePortfolioNonce();
        // uint256 portfolioValue = mainChainStorage.portfolioTotalValueByNonce(nonce);

        // uint256 totalChains = functionsOracle.oracleChainSelectorsCount(_indexToken);
        uint256 latestOracleCount = functionsOracle.oracleFilledCount(_indexToken);

        (,, uint64[] memory chainSelectors) = functionsOracle.getOracleData(_indexToken, latestOracleCount);
        bool isOnlyOnCurrentChain = true;
        for (uint256 i = 0; i < chainSelectors.length; i++) {
            uint64 chainSelector = chainSelectors[i];

            // uint256 chainSelectorCurrentTokensCount = functionsOracle.currentChainSelectorTokensCount(_indexToken, chainSelector);
            uint256 chainSelectorOracleTokensCount = functionsOracle.oracleChainSelectorTokensCount(_indexToken, chainSelector);
            uint256 oracleChainSelectorTotalShares =
                functionsOracle.getOracleChainSelectorTotalShares(_indexToken, latestOracleCount, chainSelector);
            uint256 chainValue = mainChainStorage.chainValueByNonce(nonce, chainSelector);
            uint256[] memory oracleTokenShares = functionsOracle.allOracleChainSelectorTokenShares(_indexToken, chainSelector);

            // if ((chainValue * 100e18) / portfolioValue < oracleChainSelectorTotalShares) {
            if (chainValue < (oracleChainSelectorTotalShares * _targetPortfolioValue) / 100e18) {
                if (chainSelector == currentChainSelector) {
                    _swapLowerValueCurrentChain(
                        i,
                        _indexToken,
                        nonce,
                        _targetPortfolioValue,
                        chainSelector,
                        oracleChainSelectorTotalShares
                    );
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
                if (isOnlyOnCurrentChain) {
                    functionsOracle.updateCurrentList(_indexToken);
                }
            }
        }
        mainChainStorage.decreasePendingExtraWethByNonce(nonce);
        emit RequestedSecondReweightAction(block.timestamp);
        if (isOnlyOnCurrentChain) {
            balancerSender.emitSecondReweightActionCompleted();
            unpauseMainChainFactory();
        }
    }

    function _swapLowerValueCurrentChainToWETH(
        address _indexToken,
        Vault vault,
        uint64 chainSelector,
        uint256 chainSelectorTokensCount,
        uint256 portfolioValue,
        uint256 chainValue
    ) internal returns (uint256 swapWethAmount) {
        LowSwapVariables memory swapVars;
        Vault vault = mainChainStorage.vault();
        uint256 initialWethBalance = weth.balanceOf(address(vault));
        address[] memory currentTokens = functionsOracle.allCurrentChainSelectorTokens(_indexToken, chainSelector);
        for (uint256 j = 0; j < currentTokens.length; j++) {
            swapVars.tokenAddress = currentTokens[j];
            (address[] memory toETHPath, uint24[] memory toETHFees) =
                functionsOracle.getToETHPathData(swapVars.tokenAddress);

            if (swapVars.tokenAddress == address(weth)) {
                vault.withdrawFunds(swapVars.tokenAddress, address(this), initialWethBalance);
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
        Vault vault,
        uint64 chainSelector,
        uint256 swapWethAmount,
        uint256 oracleChainSelectorTotalShares
    ) internal {
        LowSwapVariables memory swapVars;
        swapVars.swapWethAmount = swapWethAmount;
        address[] memory oracleTokens = functionsOracle.allOracleChainSelectorTokens(_indexToken, chainSelector);
        for (uint256 k = 0; k < oracleTokens.length; k++) {
            address newTokenAddress = oracleTokens[k];
            (address[] memory fromETHPath, uint24[] memory fromETHFees) =
                functionsOracle.getFromETHPathData(newTokenAddress);

            uint256 newTokenMarketShare = functionsOracle.tokenOracleMarketShare(_indexToken, newTokenAddress);
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
        uint256 i,
        address _indexToken,
        uint256 nonce,
        uint256 _targetPortfolioValue,
        uint64 chainSelector,
        uint256 oracleChainSelectorTotalShares
    ) internal {
        Vault vault = mainChainStorage.vault();
        LowSwapVariables memory swapVars;
        swapVars.chainValue = mainChainStorage.chainValueByNonce(nonce, chainSelector);
        uint256 chainSelectorCurrentTokensCount = functionsOracle.currentChainSelectorTokensCount(_indexToken, chainSelector);
        uint256 portfolioValue = mainChainStorage.portfolioTotalValueByNonce(nonce);
        swapVars.swapWethAmount = _swapLowerValueCurrentChainToWETH(
            _indexToken, vault, chainSelector, chainSelectorCurrentTokensCount, portfolioValue, swapVars.chainValue
        );
        // uint256 chainCurrentRealShare = (swapVars.chainValue * 100e18) / portfolioValue;
        uint256 targetChainValue = (_targetPortfolioValue * oracleChainSelectorTotalShares) / 100e18;
        // uint256 negativePercentage = oracleChainSelectorTotalShares - chainCurrentRealShare;
        uint256 negativePercentage = ((targetChainValue - portfolioValue) * 100e18) / portfolioValue;
        uint256 extraWethAmount = (mainChainStorage.extraWethByNonce(nonce) * negativePercentage)
            / mainChainStorage.reweightExtraPercentage(nonce);
        swapVars.swapWethAmount += extraWethAmount;

        _swapLowerValueCurrentChainFromWETH(
            _indexToken, vault, chainSelector, swapVars.swapWethAmount, oracleChainSelectorTotalShares
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
    ) internal view returns (uint256) {
        // uint256 chainCurrentRealShare = (_chainValue * 100e18) / _portfolioValue;
        uint256 targetChainValue = (_targetPortfolioValue * _oracleChainSelectorTotalShares) / 100e18;
        // uint256 negativePercentage = _oracleChainSelectorTotalShares - chainCurrentRealShare;
        uint256 negativePercentage = ((targetChainValue - _portfolioValue) * 100e18) / _portfolioValue;
        uint256 extraWethAmount = (mainChainStorage.extraWethByNonce(_nonce) * negativePercentage)
            / mainChainStorage.reweightExtraPercentage(_nonce);

        return extraWethAmount;
    }

    function _sendLowerValueOtherChain(
        address _indexToken,
        uint256 nonce,
        uint256 targetPortfolioValue,
        uint64 chainSelector,
        uint256 oracleChainSelectorTotalShares,
        uint256 chainValue,
        uint256[] memory oracleTokenShares
    ) internal {
        uint256 portfolioValue = mainChainStorage.portfolioTotalValueByNonce(nonce);
        uint256 extraWethAmount =
            _calculateExtraAmountForLowerValue(nonce, portfolioValue, targetPortfolioValue, chainValue, oracleChainSelectorTotalShares);

        weth.approve(address(balancerSender), extraWethAmount);
        balancerSender.sendSecondReweightAction(
            _indexToken, nonce, portfolioValue, chainSelector, oracleChainSelectorTotalShares, oracleTokenShares, extraWethAmount
        );
    }
}

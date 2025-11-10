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
/// @custom:oz-upgrades-from MainChainBalancer2V2
contract MainChainBalancer2V3 is Initializable, ProposableOwnableUpgradeable, PausableUpgradeable {
    MainChainStorage public mainChainStorage;
    FunctionsOracle public functionsOracle;
    BalancerSender public balancerSender;
    IndexFactoryBalancer public indexFactoryBalancer;
    IndexFactoryStorage public indexFactoryStorage;
    uint64 public currentChainSelector;
    uint256 public reweightCalled;

    IWETH public weth;
    address public usdcAddress;

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

    function getUpdatePortfolioNonce() public view returns (uint256) {
        return mainChainStorage.updatePortfolioNonce();
    }

    function _updateCheckValuesCurrentChainMappings(address _indexToken, uint256 value, address tokenAddress) internal {
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
        (, address[] memory underlyingAssets,) =
            functionsOracle.getCurrentProviderIndexData(_indexToken, functionsOracle.currentFilledCount(_indexToken), 1);
        if (
            mainChainStorage.updatedTokensValueCount(mainChainStorage.updatePortfolioNonce()) == underlyingAssets.length
        ) {
            mainChainStorage.setRebalanceStatusByNonce(
                mainChainStorage.updatePortfolioNonce(), MainChainStorage.RebalanceStatus.AskValuesCompleted
            );
            // inform factory about the value
            indexFactoryBalancer.completeAskValueCCIP(
                _indexToken,
                mainChainStorage.updatePortfolioNonce(),
                mainChainStorage.portfolioTotalValueByNonce(mainChainStorage.updatePortfolioNonce())
            );
        }
    }

    function _checkValueCurrentChainValues(address _indexToken, address tokenAddress)
        internal
        view
        returns (uint256 value)
    {
        (address[] memory toETHPath, uint24[] memory toETHFees) = functionsOracle.getToETHPathData(tokenAddress);
        if (tokenAddress == address(weth)) {
            value = IERC20(tokenAddress).balanceOf(address(indexFactoryStorage.indexTokenToVault(_indexToken)));
        } else {
            value = mainChainStorage.getAmountOut(
                toETHPath,
                toETHFees,
                IERC20(tokenAddress).balanceOf(address(indexFactoryStorage.indexTokenToVault(_indexToken)))
            );
        }
    }

    function _checkValuesCurrentChain(address _indexToken, uint64 chainSelector, uint256 chainSelectorTokensCount)
        internal
    {
        address[] memory tokens = functionsOracle.allCurrentChainSelectorTokens(_indexToken, chainSelector);
        for (uint256 j = 0; j < chainSelectorTokensCount; j++) {
            address tokenAddress = tokens[j];
            uint256 value = _checkValueCurrentChainValues(_indexToken, tokenAddress);
            _updateCheckValuesCurrentChainMappings(_indexToken, value, tokenAddress);
        }
    }

    function _checkValuesOtherChains(address _indexToken, uint64 chainSelector) internal {
        balancerSender.sendAskValues(_indexToken, chainSelector);
    }

    /**
     * @dev Requests values for the portfolio.
     */
    function askValues(address _indexToken) public whenNotPaused returns (uint256) {
        // pauseMainChainFactory();
        mainChainStorage.increaseUpdatePortfolioNonce();

        uint256 totalChains = functionsOracle.currentChainSelectorsCount(_indexToken);
        uint256 latestCount = functionsOracle.currentFilledCount(_indexToken);

        if (totalChains == 0) {
            mainChainStorage.setRebalanceStatusByNonce(
                mainChainStorage.updatePortfolioNonce(), MainChainStorage.RebalanceStatus.AskValuesCompleted
            );
        }

        for (uint256 i = 0; i < totalChains; i++) {
            (,, uint64[] memory chainSelectors) = functionsOracle.getCurrentData(_indexToken, latestCount);
            uint64 chainSelector = chainSelectors[i];
            uint256 chainSelectorTokensCount =
                functionsOracle.currentChainSelectorTokensCount(_indexToken, chainSelector);
            if (chainSelector == currentChainSelector) {
                _checkValuesCurrentChain(_indexToken, chainSelector, chainSelectorTokensCount);
            } else {
                _checkValuesOtherChains(_indexToken, chainSelector);
            }
        }

        emit RequestedAskValues(block.timestamp);

        return mainChainStorage.updatePortfolioNonce();
    }
}

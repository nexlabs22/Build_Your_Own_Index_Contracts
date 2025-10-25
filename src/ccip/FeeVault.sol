// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "../token/IndexToken.sol";
import "../utils/proposable/ProposableOwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./MainChainStorage.sol";
import "../oracle/FunctionsOracle.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "../libraries/FeeCalculation.sol";
import "../libraries/MessageSender.sol";
import "../libraries/SwapHelpers.sol";
import "../interfaces/IUniswapV2Router02.sol";
import "../interfaces/IWETH.sol";
/// @title Fee Vault Contract
/// @author NEX Labs Protocol
/// @notice The main contract for managing fees and withdrawals
/// @dev This contract uses an upgradeable pattern

contract FeeVault is Initializable, ProposableOwnableUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
    using SafeERC20 for IERC20;

    MainChainStorage public mainChainStorage;
    FunctionsOracle public functionsOracle;
    IWETH public weth;
    address public usdcAddress;

    mapping(address => bool) public isOperator;

    event FundsWithdrawn(address token, address to, uint256 amount);

    modifier onlyOperator() {
        require(isOperator[msg.sender], "FeeVault: caller is not an operator");
        _;
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
        address _weth,
        address _usdc
    ) external initializer {
        // Validate input parameters
        require(_weth != address(0), "Invalid WETH address");

        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();
        __ReentrancyGuard_init_unchained();
        //set chain selector
        mainChainStorage = MainChainStorage(_mainChainStorage);
        functionsOracle = FunctionsOracle(_functionsOracle);

        //set addresses
        weth = IWETH(_weth);
        usdcAddress = _usdc;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function setOperator(address _operator, bool _status) external onlyOwner {
        isOperator[_operator] = _status;
    }

    // set WETH address
    function setWethAddress(address _weth) public onlyOwner {
        require(_weth != address(0), "Invalid WETH address");
        weth = IWETH(_weth);
    }

    /**
     * @dev Sets the USDC address.
     * @param _usdc The address of the USDC token.
     */
    function setUsdcAddress(address _usdc) public onlyOwner {
        require(_usdc != address(0), "Invalid USDC address");
        usdcAddress = _usdc;
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

    function depositFunds() external payable {
        require(msg.value > 0, "NexVault: amount must be greater than 0");
        weth.deposit{value: msg.value}();
    }

    /**
     * @dev Withdraws funds from the vault.
     * @param _token The address of the token to withdraw (address(0) for ETH).
     * @param _to The address to send the withdrawn funds to.
     * @param _amount The amount of funds to withdraw.
     */
    function withdrawFunds(address _token, address _to, uint256 _amount) external onlyOperator {
        require(_to != address(0), "NexVault: invalid address");
        require(_amount > 0, "NexVault: amount must be greater than 0");
        if (_token == address(0)) {
            // Swap and withdraw ETH
            require(address(this).balance >= _amount, "NexVault: insufficient ETH balance");
            (address[] memory toETHPath, uint24[] memory toETHFees) = functionsOracle.getToETHPathData(usdcAddress);
            uint256 wethAmount = swap(toETHPath, toETHFees, _amount, address(this));
            weth.withdraw(wethAmount);
            (bool success,) = _to.call{value: wethAmount}("");
            require(success, "NexVault: ETH transfer failed");
            emit FundsWithdrawn(address(0), _to, wethAmount);
        } else {
            // Withdraw ERC20 tokens
            IERC20(_token).safeTransfer(_to, _amount);
            emit FundsWithdrawn(_token, _to, _amount);
        }
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "../utils/proposable/ProposableOwnableUpgradeable.sol";

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

import "./MainChainStorage.sol";
import "../oracle/FunctionsOracle.sol";
import "../../src/factory/IndexFactoryStorage.sol";

import "../libraries/SwapHelpers.sol";
import "../interfaces/IUniswapV2Router02.sol";
import "../interfaces/IWETH.sol";

/// @title FeeVault
/// @notice Tracks USDC in two buckets: user deposits and protocol rewards.
/// @dev Upgradeable. Uses explicit deposit entrypoints to distinguish inflow sources.
contract FeeVault is Initializable, ProposableOwnableUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
    using SafeERC20 for IERC20;

    MainChainStorage public mainChainStorage;
    FunctionsOracle public functionsOracle;
    IndexFactoryStorage public factoryStorage;

    IWETH public weth;
    address public usdcAddress;

    /// @notice USDC credited as rewards (inflow from whitelisted reward source contracts)
    uint256 public rewardAmount;

    /// @notice USDC credited as user deposits (inflow from users)
    uint256 public depositAmount;

    mapping(address => bool) public isOperator;
    mapping(address => bool) public isRewardSource; // contracts allowed to call depositRewardUsdc()

    event OperatorUpdated(address indexed operator, bool status);
    event RewardSourceUpdated(address indexed source, bool status);

    event UsdcUserDeposited(address indexed from, uint256 requestedAmount, uint256 receivedAmount);
    event UsdcRewardDeposited(address indexed source, uint256 requestedAmount, uint256 receivedAmount);

    event FundsWithdrawn(address indexed token, address indexed to, uint256 amount);
    event UsdcBucketsConsumed(uint256 fromRewards, uint256 fromDeposits, uint256 total);

    modifier onlyOperator() {
        require(isOperator[msg.sender], "FeeVault: caller is not an operator");
        _;
    }

    modifier onlyRewardSource() {
        require(isRewardSource[msg.sender], "FeeVault: caller is not reward source");
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _mainChainStorage,
        address _functionsOracle,
        address _weth,
        address _usdc,
        address _factoryStorage
    ) external initializer {
        require(_mainChainStorage != address(0), "FeeVault: mainChainStorage=0");
        require(_functionsOracle != address(0), "FeeVault: functionsOracle=0");
        require(_weth != address(0), "FeeVault: weth=0");
        require(_usdc != address(0), "FeeVault: usdc=0");
        require(_factoryStorage != address(0), "FeeVault: factoryStorage=0");

        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();
        __Pausable_init();

        mainChainStorage = MainChainStorage(_mainChainStorage);
        functionsOracle = FunctionsOracle(_functionsOracle);
        factoryStorage = IndexFactoryStorage(_factoryStorage);

        weth = IWETH(_weth);
        usdcAddress = _usdc;
    }

    function setOperator(address _operator, bool _status) external onlyOwner {
        require(_operator != address(0), "FeeVault: operator=0");
        isOperator[_operator] = _status;
        emit OperatorUpdated(_operator, _status);
    }

    function setRewardSource(address _source, bool _status) external onlyOwner {
        require(_source != address(0), "FeeVault: source=0");
        isRewardSource[_source] = _status;
        emit RewardSourceUpdated(_source, _status);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function setWethAddress(address _weth) external onlyOwner {
        require(_weth != address(0), "FeeVault: weth=0");
        weth = IWETH(_weth);
    }

    function setUsdcAddress(address _usdc) external onlyOwner {
        require(_usdc != address(0), "FeeVault: usdc=0");
        usdcAddress = _usdc;
    }

    function setMainChainStorage(address _mainChainStorage) external onlyOwner {
        require(_mainChainStorage != address(0), "FeeVault: mainChainStorage=0");
        mainChainStorage = MainChainStorage(_mainChainStorage);
    }

    function setFunctionsOracle(address _functionsOracle) external onlyOwner {
        require(_functionsOracle != address(0), "FeeVault: functionsOracle=0");
        functionsOracle = FunctionsOracle(_functionsOracle);
    }

    function totalTrackedUsdc() public view returns (uint256) {
        return rewardAmount + depositAmount;
    }

    function usdcBalance() public view returns (uint256) {
        return IERC20(usdcAddress).balanceOf(address(this));
    }

    receive() external payable {}

    /// @notice Wrap incoming ETH into WETH (not part of USDC buckets)
    function depositFunds() external payable nonReentrant whenNotPaused {
        require(msg.value > 0, "FeeVault: amount=0");
        weth.deposit{value: msg.value}();
    }

    /// @notice User deposits USDC => credited to depositAmount bucket
    function depositUsdc(uint256 _amount) external nonReentrant whenNotPaused {
        require(_amount > 0, "FeeVault: amount=0");

        IERC20 usdc = IERC20(usdcAddress);
        uint256 beforeBal = usdc.balanceOf(address(this));
        usdc.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 afterBal = usdc.balanceOf(address(this));

        uint256 received = afterBal - beforeBal; // handles fee-on-transfer tokens safely
        require(received > 0, "FeeVault: received=0");

        depositAmount += received;
        emit UsdcUserDeposited(msg.sender, _amount, received);
    }

    /// @notice Reward source deposits USDC => credited to rewardAmount bucket
    /// @dev Reward source must approve this vault for USDC.
    function depositRewardUsdc(uint256 _amount) external onlyRewardSource nonReentrant whenNotPaused {
        require(_amount > 0, "FeeVault: amount=0");

        IERC20 usdc = IERC20(usdcAddress);
        uint256 beforeBal = usdc.balanceOf(address(this));
        usdc.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 afterBal = usdc.balanceOf(address(this));

        uint256 received = afterBal - beforeBal;
        require(received > 0, "FeeVault: received=0");

        rewardAmount += received;
        emit UsdcRewardDeposited(msg.sender, _amount, received);
    }

    /// @notice If someone transfers USDC directly to the vault (bypassing deposit functions),
    /// this credits the untracked amount into rewards (conservative default).
    function sweepUntrackedUsdcToRewards() external onlyOwner {
        uint256 bal = usdcBalance();
        uint256 tracked = totalTrackedUsdc();
        require(bal > tracked, "FeeVault: nothing untracked");
        uint256 untracked = bal - tracked;
        rewardAmount += untracked;
    }

    /// @notice Withdraw all rewards USDC to operator
    function withdrawAllRewards(address _to) external onlyOperator nonReentrant whenNotPaused {
        require(_to != address(0), "FeeVault: to=0");
        uint256 amt = rewardAmount;
        require(amt > 0, "FeeVault: no rewards");
        rewardAmount = 0;
        IERC20(usdcAddress).safeTransfer(_to, amt);
        emit FundsWithdrawn(usdcAddress, _to, amt);
        emit UsdcBucketsConsumed(amt, 0, amt);
    }

    /// @notice Withdraw USDC specifying the bucket explicitly (reverts if bucket insufficient)
    function withdrawUsdcFromRewards(address _to, uint256 _amount) external onlyOperator nonReentrant whenNotPaused {
        require(_to != address(0), "FeeVault: to=0");
        require(_amount > 0, "FeeVault: amount=0");
        require(rewardAmount >= _amount, "FeeVault: rewards insufficient");
        rewardAmount -= _amount;
        IERC20(usdcAddress).safeTransfer(_to, _amount);
        emit FundsWithdrawn(usdcAddress, _to, _amount);
        emit UsdcBucketsConsumed(_amount, 0, _amount);
    }

    function withdrawUsdcFromDeposits(address _to, uint256 _amount) external onlyOperator nonReentrant whenNotPaused {
        require(_to != address(0), "FeeVault: to=0");
        require(_amount > 0, "FeeVault: amount=0");
        require(depositAmount >= _amount, "FeeVault: deposits insufficient");
        depositAmount -= _amount;
        IERC20(usdcAddress).safeTransfer(_to, _amount);
        emit FundsWithdrawn(usdcAddress, _to, _amount);
        emit UsdcBucketsConsumed(0, _amount, _amount);
    }

    /// @notice Backward-compatible USDC withdraw (consumes rewards first, then deposits)
    function withdrawFunds(address _to, uint256 _amount) external onlyOperator nonReentrant whenNotPaused {
        require(_to != address(0), "FeeVault: to=0");
        require(_amount > 0, "FeeVault: amount=0");

        (uint256 fromRewards, uint256 fromDeposits) = _consumeUsdcBuckets(_amount);

        IERC20(usdcAddress).safeTransfer(_to, _amount);
        emit FundsWithdrawn(usdcAddress, _to, _amount);
        emit UsdcBucketsConsumed(fromRewards, fromDeposits, _amount);
    }

    /**
     * @notice Withdraw tokens. If _token == address(0), swaps USDC->WETH and sends ETH.
     * @dev For _token == address(0), `_amount` is interpreted as USDC amount to swap into ETH.
     *      Consumes rewards first, then deposits (same as withdrawFunds USDC).
     */
    function withdrawFunds(address _token, address _to, uint256 _amount)
        external
        onlyOperator
        nonReentrant
        whenNotPaused
    {
        require(_to != address(0), "FeeVault: to=0");
        require(_amount > 0, "FeeVault: amount=0");

        if (_token == address(0)) {
            // Consume USDC buckets because USDC is leaving as swap input
            (uint256 fromRewards, uint256 fromDeposits) = _consumeUsdcBuckets(_amount);

            (address[] memory toETHPath, uint24[] memory toETHFees) = functionsOracle.getToETHPathData(usdcAddress);

            uint256 wethOut = _swap(toETHPath, toETHFees, _amount, address(this), usdcAddress);

            weth.withdraw(wethOut);
            (bool success,) = _to.call{value: wethOut}("");
            require(success, "FeeVault: ETH transfer failed");

            emit FundsWithdrawn(address(0), _to, wethOut);
            emit UsdcBucketsConsumed(fromRewards, fromDeposits, _amount);
        } else {
            // If withdrawing USDC via this overload, update buckets too.
            if (_token == usdcAddress) {
                (uint256 fromRewards, uint256 fromDeposits) = _consumeUsdcBuckets(_amount);
                IERC20(_token).safeTransfer(_to, _amount);
                emit FundsWithdrawn(_token, _to, _amount);
                emit UsdcBucketsConsumed(fromRewards, fromDeposits, _amount);
                return;
            }

            // Other ERC20 tokens are not bucketed here
            IERC20(_token).safeTransfer(_to, _amount);
            emit FundsWithdrawn(_token, _to, _amount);
        }
    }

    /// @dev Consumes USDC from rewardAmount first, then depositAmount.
    function _consumeUsdcBuckets(uint256 amount) internal returns (uint256 fromRewards, uint256 fromDeposits) {
        require(totalTrackedUsdc() >= amount, "FeeVault: tracked USDC insufficient");

        uint256 r = rewardAmount;
        if (r >= amount) {
            rewardAmount = r - amount;
            return (amount, 0);
        }

        // consume all rewards, remainder from deposits
        rewardAmount = 0;
        uint256 rem = amount - r;
        require(depositAmount >= rem, "FeeVault: deposits insufficient");
        depositAmount -= rem;

        return (r, rem);
    }

    function _swap(address[] memory path, uint24[] memory fees, uint256 amountIn, address recipient, address tokenKey)
        internal
        returns (uint256 outputAmount)
    {
        ISwapRouter swapRouterV3 = mainChainStorage.getSwapRouterV3(tokenKey);
        IUniswapV2Router02 swapRouterV2 = mainChainStorage.swapRouterV2();
        uint256 amountOutMinimum = mainChainStorage.getMinAmountOut(path, fees, amountIn, tokenKey);

        outputAmount = SwapHelpers.swap(swapRouterV3, swapRouterV2, path, fees, amountIn, amountOutMinimum, recipient);
    }

    uint256[48] private __gap;
}

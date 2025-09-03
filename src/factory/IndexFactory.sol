// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../orderManager/OrderManager.sol";

error ZeroAmount();
error ZeroAddress();
error WrongETHAmount();

contract IndexFactory is Initializable, OwnableUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    OrderManager public orderManager;
    uint256 public issuanceNonce;
    uint256 public redemptionNonce;

    mapping(address => bool) public supportedIndexTokens;

    event SupportedIndexTokenUpdated(address indexed token, bool isSupported);

    function initialize(address _orderManager) external initializer {
        require(_orderManager != address(0), "Invalid address for _orderManager");
        orderManager = OrderManager(_orderManager);

        __Ownable_init(msg.sender);
        __Pausable_init();
        __ReentrancyGuard_init();
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function issuanceIndexTokens(address indexToken, uint256 amount)
        public
        payable
        whenNotPaused
        nonReentrant
        returns (uint256 orderNonce)
    {
        if (amount == 0) revert ZeroAmount();
        if (indexToken == address(0)) revert ZeroAddress();
        require(supportedIndexTokens[indexToken], "IndexFactory: unsupported index token");

        address usdc = orderManager.usdcAddress();
        IERC20(usdc).safeTransferFrom(msg.sender, address(this), amount);

        IERC20(usdc).approve(address(orderManager), 0);
        OrderManager.CreateOrderConfig memory cfg = OrderManager.CreateOrderConfig({
            inputTokenAddress: usdc,
            outputTokenAddress: indexToken,
            assetType: uint64(1), // 1 = ERC20
            inputTokenAmount: amount, // USDC sent in
            outputTokenAmount: 0, // unknown at creation time
            isBuyOrder: true
        });

        orderNonce = orderManager.createOrder(cfg);

        // @notice Should manage this nonce for each index token
        issuanceNonce += 1;

        return orderNonce;
    }

    function redemption(address indexToken, uint256 amount)
        external
        payable
        whenNotPaused
        nonReentrant
        returns (uint256 nonce)
    {
        if (amount == 0) revert ZeroAmount();
        if (indexToken == address(0)) revert ZeroAddress();
        require(supportedIndexTokens[indexToken], "IndexFactory: unsupported index token");

        IERC20(indexToken).safeTransferFrom(msg.sender, address(this), amount);

        IERC20(indexToken).approve(address(orderManager), 0);

        OrderManager.CreateOrderConfig memory cfg = OrderManager.CreateOrderConfig({
            inputTokenAddress: indexToken, // we're selling the index token
            outputTokenAddress: address(0), // unknown for now
            assetType: uint64(1), // 1 = ERC20
            inputTokenAmount: amount, // amount of index token to sell
            outputTokenAmount: 0, // unknown at creation
            isBuyOrder: false // SELL order
        });

        // Create order in OrderManager (this contract must be an operator)
        uint256 orderNonce = orderManager.createOrder(cfg);

        redemptionNonce += 1;

        return orderNonce;
    }

    function setSupportedIndexToken(address token, bool status) external onlyOwner {
        if (token == address(0)) revert ZeroAddress();
        supportedIndexTokens[token] = status;
        emit SupportedIndexTokenUpdated(token, status);
    }

    // /**
    //  * @dev Pauses the contract.
    //  */
    // function pause() external onlyOwnerOrOperator {
    //     _pause();
    // }

    // /**
    //  * @dev Unpauses the contract.
    //  */
    // function unpause() external onlyOwnerOrOperator {
    //     _unpause();
    // }
}

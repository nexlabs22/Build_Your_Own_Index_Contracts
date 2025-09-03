// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

error ZeroAmount();
error WrongETHAmount();
error OrderAlreadyCancelled();

contract IndexFactory is Initializable, OwnableUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    uint256 public issuanceNonce;
    uint256 public redemptionNonce;

    function initialize() external initializer {
        __Ownable_init(msg.sender);
        __Pausable_init();
        __ReentrancyGuard_init();
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function issuanceIndexTokens() public payable whenNotPaused nonReentrant returns (uint256) {}

    function redemption() external payable whenNotPaused nonReentrant returns (uint256 nonce) {}

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

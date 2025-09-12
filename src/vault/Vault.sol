// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol"; // Corrected import style
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol"; // Corrected import style

contract NexVault is Initializable, OwnableUpgradeable {
    using SafeERC20 for IERC20;

    address public operator;
    mapping(address => bool) public isOperator;

    event FundsWithdrawn(address token, address to, uint256 amount);

    modifier onlyOperator() {
        require(isOperator[msg.sender], "NexVault: caller is not an operator");
        _;
    }

    function initialize(address _operator) external initializer {
        __Ownable_init(msg.sender);
        setOperator(_operator, true);
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function setOperator(address _operator, bool _status) public onlyOwner {
        require(_operator != address(0), "NexVault: invalid operator address");
        isOperator[_operator] = _status;
    }

    function withdrawFunds(address token, address to, uint256 amount) external onlyOperator {
        require(token != address(0), "NexVault: invalid token address");
        require(to != address(0), "NexVault: invalid address");
        require(amount > 0, "NexVault: amount must be greater than 0");

        IERC20(token).safeTransfer(to, amount);
        emit FundsWithdrawn(token, to, amount);
    }
}

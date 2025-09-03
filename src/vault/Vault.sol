// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract NexVault is Initializable, OwnableUpgradeable {
    using SafeERC20 for IERC20;

    mapping(address => bool) public isOperator;

    event FundsWithdrawn(address token, address to, uint256 amount);

    modifier onlyOperator() {
        require(isOperator[msg.sender], "NexVault: caller is not an operator");
        _;
    }

    function initialize(address _operator) external initializer {
        __Ownable_init(msg.sender);
        isOperator[_operator] = true;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function setOperator(address _operator, bool _status) external onlyOwner {
        isOperator[_operator] = _status;
    }

    function withdrawFunds(address _token, address _to, uint256 _amount) external onlyOperator {
        require(_token != address(0), "NexVault: invalid token address");
        require(_to != address(0), "NexVault: invalid address");
        require(_amount > 0, "NexVault: amount must be greater than 0");

        emit FundsWithdrawn(_token, _to, _amount);
        IERC20(_token).safeTransfer(_to, _amount);
    }
}

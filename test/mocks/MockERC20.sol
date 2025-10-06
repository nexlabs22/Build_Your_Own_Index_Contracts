// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title MockERC20
/// @author NexLabs
/// @notice Lightweight ERC20 implementation for testing token interactions
contract MockERC20 is ERC20 {
    /// @notice Deploys the mock token with a configurable name and symbol
    /// @param name Token display name
    /// @param symbol Token ticker symbol
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    /// @notice Mints tokens to a recipient for scenario setup
    /// @param to Recipient address receiving minted tokens
    /// @param amount Number of tokens to mint
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.25;

// solhint-disable gas-indexed-events

/// @title TestERC20
/// @author NexLabs
/// @notice Minimal ERC20-like token used solely within the test suite
contract TestERC20 {
    /// @notice Readable token name surfaced to consumers
    string public name;

    /// @notice Token ticker symbol surfaced to consumers
    string public symbol;

    /// @notice Fixed number of decimals exposed by the token
    uint8 public immutable decimals = 18; // solhint-disable-line immutable-vars-naming

    /// @notice Aggregate supply tracked for bookkeeping in tests
    uint256 public totalSupply;

    /// @notice Tracks balances associated with each token holder
    mapping(address => uint256) public balanceOf;

    /// @notice Tracks allowances granted to spenders per owner
    mapping(address => mapping(address => uint256)) public allowance;

    /// @notice Emitted whenever tokens move between accounts
    /// @param from Address sending the tokens
    /// @param to Address receiving the tokens
    /// @param value Amount of tokens transferred
    event Transfer(address indexed from, address indexed to, uint256 value);

    /// @notice Emitted whenever an allowance is updated
    /// @param owner Token owner granting the allowance
    /// @param spender Address permitted to spend the tokens
    /// @param value Amount of tokens approved for spending
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /// @notice Error thrown when an account lacks sufficient balance
    error InsufficientBalance();

    /// @notice Error thrown when an allowance is not large enough
    error InsufficientAllowance();

    /// @notice Creates the mock token with the provided metadata
    /// @param n Token name
    /// @param s Token symbol
    constructor(string memory n, string memory s) {
        name = n;
        symbol = s;
    }

    /// @notice Mints tokens to the designated recipient
    /// @param to Recipient address receiving the minted supply
    /// @param amount Number of tokens to mint
    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }

    /// @notice Approves a spender to transfer tokens on behalf of the caller
    /// @param spender Address approved to spend tokens
    /// @param amount Amount of tokens approved for spending
    /// @return success True when the approval succeeds
    function approve(address spender, uint256 amount) external returns (bool success) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        success = true;
    }

    /// @notice Transfers tokens from the caller to a recipient
    /// @param to Recipient address to receive the tokens
    /// @param amount Amount of tokens to transfer
    /// @return success True when the transfer succeeds
    function transfer(address to, uint256 amount) external returns (bool success) {
        if (balanceOf[msg.sender] < amount) revert InsufficientBalance();
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        success = true;
    }

    /// @notice Transfers tokens from an owner using an approved allowance
    /// @param from Address from which the tokens are drawn
    /// @param to Recipient address to receive the tokens
    /// @param amount Amount of tokens to transfer
    /// @return success True when the transfer succeeds
    function transferFrom(address from, address to, uint256 amount) external returns (bool success) {
        if (balanceOf[from] < amount) revert InsufficientBalance();
        uint256 a = allowance[from][msg.sender];
        if (a < amount) revert InsufficientAllowance();
        if (a != type(uint256).max) {
            allowance[from][msg.sender] = a - amount;
        }
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        success = true;
    }
}

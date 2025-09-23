// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract ContractOwnedAccount {
    address public owner;

    constructor(address _owner) {
        owner = _owner;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Not authorized");
        _;
    }

    function sendToken(address token, address to, uint256 value) external onlyOwner {
        require(IERC20(token).transfer(to, value), "Transfer failed");
    }

    function setOwner(address newOwner) external onlyOwner {
        owner = newOwner;
    }
}

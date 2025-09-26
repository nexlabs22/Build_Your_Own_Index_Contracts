// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    uint8 tokenDecimals;

    constructor(string memory name, string memory symbol, uint8 _decimals) ERC20(name, symbol) {
        tokenDecimals = _decimals;
    }

    function decimals() public view override returns (uint8) {
        return tokenDecimals;
    }

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }
}

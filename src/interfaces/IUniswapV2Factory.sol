// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

interface IUniswapV2Factory {
    function getPair(address token0, address token1) external returns (address);
}
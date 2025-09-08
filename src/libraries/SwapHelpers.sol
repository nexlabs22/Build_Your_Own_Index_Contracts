// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IUniswapV2Router02} from "../interfaces/IUniswapV2Router02.sol";

library SwapHelpers {
    
    function encodePath(address[] memory tokens, uint24[] memory fees)
        public
        pure
        returns (bytes memory path)
    {
        require(tokens.length == fees.length + 1, "Invalid input arrays");

        for (uint256 i = 0; i < fees.length; i++) {
            // Concatenate token address and fee tier
            path = abi.encodePacked(path, tokens[i], fees[i]);
        }

        // Append the final token address
        path = abi.encodePacked(path, tokens[tokens.length - 1]);
    }


    function swapVersion3(
        ISwapRouter uniswapRouter,
        address[] memory path,
        uint24[] memory fees,
        uint256 amountIn,
        uint256 amountOutMinimum,
        address recipient
    ) internal returns (uint256 amountOut) {
        IERC20(path[0]).approve(address(uniswapRouter), amountIn);
        ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
            path: encodePath(path, fees),
            recipient: recipient,
            deadline: block.timestamp + 300,
            amountIn:  amountIn,
            amountOutMinimum: amountOutMinimum
        });

        amountOut = uniswapRouter.exactInput(params);
    }

    function swapTokensV2(
        IUniswapV2Router02 uniswapRouter,
        address[] memory path,
        uint256 amountIn,
        uint256 amountOutMin,
        address recipient
    ) internal returns (uint amountOut) {
        uint[] memory v2AmountOut = uniswapRouter.getAmountsOut(amountIn, path);
        IERC20(path[0]).approve(address(uniswapRouter), amountIn);
        uniswapRouter.swapExactTokensForTokens(
            amountIn, //amountIn
            amountOutMin, //amountOutMin
            path, //path
            recipient, //to
            block.timestamp //deadline
        );
        amountOut = v2AmountOut[v2AmountOut.length - 1];
    }

    function swap(
        ISwapRouter uniswapRouter,
        IUniswapV2Router02 uniswapRouterV2,
        address[] memory path,
        uint24[] memory fees,
        uint256 amountIn,
        uint256 amountOutMinimum,
        address recipient
    ) internal returns (uint256 amountOut) {
        require(amountIn > 0, "Amount must be greater than zero");
        if (fees.length > 0) {
            amountOut = swapVersion3(uniswapRouter, path, fees, amountIn, amountOutMinimum, recipient);
        } else {
            amountOut = swapTokensV2(uniswapRouterV2, path, amountIn, amountOutMinimum, recipient);
        }
    }

}
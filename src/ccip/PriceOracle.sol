// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0 <0.8.0;


import "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";

/// @title PriceOracle
/// @author NEX Labs Protocol
/// @notice The main token contract forPriceOracle (NEX Labs Protocol)
contract PriceOracle
{

    /**
     * @dev Estimates the amount out for a token swap using Uniswap V3.
     * @param tokenIn The address of the input token.
     * @param tokenOut The address of the output token.
     * @param amountIn The amount of input token.
     * @return amountOut The estimated amount of output token.
     */
    function estimateAmountOut(
        address factoryAddress,
        address tokenIn,
        address tokenOut,
        uint128 amountIn,
        uint24 fee
    ) public view returns (uint amountOut) {
        address _pool = IUniswapV3Factory(factoryAddress).getPool(tokenIn, tokenOut, fee);

        (, int24 tick , , , , , ) = IUniswapV3Pool(_pool).slot0();
        amountOut = OracleLibrary.getQuoteAtTick(
            tick,
            amountIn,
            tokenIn,
            tokenOut
        );
    }
 
}

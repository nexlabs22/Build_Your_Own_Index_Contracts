// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library FeeCalculation {
    /**
     * @dev Calculates the fee based on the given amount and fee rate.
     * @param amount The amount to calculate the fee on.
     * @param feeRate The fee rate to apply.
     * @return The calculated fee.
     */
    function calculateFee(uint256 amount, uint8 feeRate) internal pure returns (uint256) {
        return (amount * feeRate) / 10000;
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol"; // Corrected import style
import {VaultTest} from "../unit/Vault.t.sol"; // Corrected import style

contract VaultFuzzTest is VaultTest {
    // Fuzz tests for NexVault
    function testFuzzWithdrawFunds(address token, address to, uint256 amount) public {
        vm.assume(token != address(0));
        vm.assume(to != address(0));
        vm.assume(amount > 0);
        vm.assume(mockToken.balanceOf(address(vault)) >= amount);

        // Ensure operator is set
        vm.prank(owner);
        vault.setOperator(operator, true);

        vm.prank(operator);
        vault.withdrawFunds(token, to, amount);

        assertEq(mockToken.balanceOf(to), amount);
        assertEq(mockToken.balanceOf(address(vault)), 10000 * 1e18 - amount);
    }

    function testFuzzSetOperator(address newOperator, bool status) public {
        vm.assume(newOperator != address(0));

        vm.prank(owner);
        vault.setOperator(newOperator, status);

        assertEq(vault.isOperator(newOperator), status);
    }

    function testFuzzWithdrawInsufficientBalance(address token, address to, uint256 amount) public {
        vm.assume(token != address(0));
        vm.assume(to != address(0));
        vm.assume(amount > mockToken.balanceOf(address(vault)));
        vm.assume(amount > 0);

        vm.prank(owner);
        vault.setOperator(operator, true);

        vm.prank(operator);
        vm.expectRevert(); // Expect revert due to insufficient balance
        vault.withdrawFunds(token, to, amount);
    }

    function testFuzzWithdrawZeroAmount(address token, address to) public {
        vm.assume(token != address(0));
        vm.assume(to != address(0));

        vm.prank(owner);
        vault.setOperator(operator, true);

        vm.prank(operator);
        vm.expectRevert("NexVault: amount must be greater than 0");
        vault.withdrawFunds(token, to, 0);
    }
}
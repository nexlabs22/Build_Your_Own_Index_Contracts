// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../../src/vault/Vault.sol";
import "../mocks/MockERC20.sol";

contract VaultTest is Test {
    NexVault vault;
    MockERC20 token;
    address operator = address(0x1);

    function setUp() external {
        vault = new NexVault();
        vault.initialize(operator);
        token = new MockERC20("Test", "TST");
        token.mint(address(this), 10000e18);
    }

    function test_withdrawFunds_FailWhenCallerIsNotOperator() public {
        vault.setOperator(operator, true);

        address token = address(0x2);
        address to = address(0x3);
        uint256 amount = 1 ether;

        vm.startPrank(address(0x4));
        vm.expectRevert("NexVault: caller is not an operator");
        vault.withdrawFunds(token, to, amount);
        vm.stopPrank();
    }

    // function test_withdrawFunds_FailWhenTokenAddressIsZero() public {
    //     vault.setOperator(operator, true);

    //     address token = address(0);
    //     address to = address(0x3);
    //     uint256 amount = 1 ether;

    //     vm.startPrank(operator);
    //     vm.expectRevert("NexVault: token address is zero");
    //     vault.withdrawFunds(token, to, amount);
    //     vm.stopPrank();
    // }

    // function test_failesWithdrawFunds_FailWhenRecipientAddressIsZero() public {
    //     vault.setOperator(operator, true);

    //     address token = address(0x2);
    //     address to = address(0);
    //     uint256 amount = 1 ether;

    //     vm.startPrank(operator);
    //     vm.expectRevert("NexVault: recipient address is zero");
    //     vault.withdrawFunds(token, to, amount);
    //     vm.stopPrank();
    // }

    // function test_failesWithdrawFunds_FailWhenAmountIsZero() public {
    //     vault.setOperator(operator, true);

    //     address token = address(0x2);
    //     address to = address(0x3);
    //     uint256 amount = 0;

    //     vm.startPrank(operator);
    //     vm.expectRevert("NexVault: amount is zero");
    //     vault.withdrawFunds(token, to, amount);
    //     vm.stopPrank();
    // }

    function testWithdrawFundsSuccessfully() public {
        uint256 initialAmount = 1000e18;
        // address token = address(0x2);
        address to = address(0x3);
        uint256 amount = initialAmount;

        deal(address(token), address(vault), initialAmount);

        vault.setOperator(operator, true);

        uint256 userBalanceBeforeWithdraw = IERC20(token).balanceOf(to);

        vm.startPrank(operator);
        vault.withdrawFunds(address(token), to, amount);
        vm.stopPrank();

        uint256 userBalanceAfterWithdraw = IERC20(token).balanceOf(to);

        assertGt(userBalanceAfterWithdraw, userBalanceBeforeWithdraw);
    }
}

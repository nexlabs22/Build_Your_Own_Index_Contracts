// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "../../src/vault/Vault.sol";
import "../mocks/MockERC20.sol";

contract VaultTest is Test {
    Vault vault;
    MockERC20 token;
    address operator = address(0x1);

    function setUp() public {
        Vault vaultImlp = new Vault();
        vault = Vault(address(new ERC1967Proxy(address(vaultImlp), abi.encodeCall(Vault.initialize, (operator)))));
        token = new MockERC20("Test", "TST");
        token.mint(address(this), 10000e18);
    }

    function test_withdrawFunds_FailWhenCallerIsNotOperator() public {
        vault.setOperator(operator, true);

        address token1 = address(0x2);
        address to = address(0x3);
        uint256 amount = 1 ether;

        vm.startPrank(address(0x4));
        vm.expectRevert("NexVault: caller is not an operator");
        vault.withdrawFunds(token1, to, amount);
        vm.stopPrank();
    }

    function testWithdrawFundsSuccessfully() public {
        uint256 initialAmount = 1000e18;
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

    function test_withdrawFunds_RevertOnZeroTokenAddress() public {
        vault.setOperator(operator, true);
        address to = address(0x3);
        uint256 amount = 1 ether;
        vm.startPrank(operator);
        vm.expectRevert("NexVault: invalid token address");
        vault.withdrawFunds(address(0), to, amount);
        vm.stopPrank();
    }

    function test_withdrawFunds_RevertOnZeroToAddress() public {
        vault.setOperator(operator, true);
        address to = address(0);
        uint256 amount = 1 ether;
        vm.startPrank(operator);
        vm.expectRevert("NexVault: invalid address");
        vault.withdrawFunds(address(token), to, amount);
        vm.stopPrank();
    }

    function test_withdrawFunds_RevertOnZeroAmount() public {
        vault.setOperator(operator, true);
        address to = address(0x3);
        uint256 amount = 0;
        vm.startPrank(operator);
        vm.expectRevert("NexVault: amount must be greater than 0");
        vault.withdrawFunds(address(token), to, amount);
        vm.stopPrank();
    }
}

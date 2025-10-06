// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Vault} from "../../src/vault/Vault.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {OlympixUnitTest} from "../OlympixUnitTest.sol";

/// @title VaultTest
/// @author NexLabs
/// @notice Exercises operator withdrawal flows for the upgradeable Vault contract
contract VaultTest is OlympixUnitTest("Vault") {
    /// @notice Proxy instance of the vault under test
    Vault private vault;

    /// @notice Mock ERC20 token used to seed vault balances during tests
    MockERC20 private token;

    /// @notice Operator account granted withdrawal permissions
    address private operator = address(0x1);

    /// @notice Deploys the Vault proxy and mints mock liquidity for scenarios
    function setUp() public {
        Vault vaultImpl = new Vault();
        vault = Vault(address(new ERC1967Proxy(address(vaultImpl), abi.encodeCall(Vault.initialize, (operator)))));
        token = new MockERC20("Test", "TST");
        token.mint(address(this), 10000e18);
    }

    /// @notice Reverts when an unauthorised caller attempts to withdraw funds
    function testWithdrawFundsFailWhenCallerIsNotOperator() public {
        vault.setOperator(operator, true);

        address token1 = address(0x2);
        address to = address(0x3);
        uint256 amount = 1 ether;

        vm.startPrank(address(0x4));
        vm.expectRevert("NexVault: caller is not an operator");
        vault.withdrawFunds(token1, to, amount);
        vm.stopPrank();
    }

    /// @notice Allows an authorised operator to withdraw ERC20 funds successfully
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

    /// @notice Reverts when attempting to withdraw using the zero token address
    function testWithdrawFundsRevertOnZeroTokenAddress() public {
        vault.setOperator(operator, true);
        address to = address(0x3);
        uint256 amount = 1 ether;
        vm.startPrank(operator);
        vm.expectRevert("NexVault: invalid token address");
        vault.withdrawFunds(address(0), to, amount);
        vm.stopPrank();
    }

    /// @notice Reverts when attempting to withdraw to the zero address
    function testWithdrawFundsRevertOnZeroToAddress() public {
        vault.setOperator(operator, true);
        address to = address(0);
        uint256 amount = 1 ether;
        vm.startPrank(operator);
        vm.expectRevert("NexVault: invalid address");
        vault.withdrawFunds(address(token), to, amount);
        vm.stopPrank();
    }

    /// @notice Reverts when attempting to withdraw a zero amount
    function testWithdrawFundsRevertOnZeroAmount() public {
        vault.setOperator(operator, true);
        address to = address(0x3);
        uint256 amount = 0;
        vm.startPrank(operator);
        vm.expectRevert("NexVault: amount must be greater than 0");
        vault.withdrawFunds(address(token), to, amount);
        vm.stopPrank();
    }
}

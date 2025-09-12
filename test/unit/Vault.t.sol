// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol"; // Corrected import style
import {console} from "forge-std/console.sol"; // Corrected import style
import {NexVault} from "../../src/vault/Vault.sol"; // Corrected import style
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol"; // Corrected import style
import {MockERC20} from "../utils/MockContracts.sol"; // Corrected import style
import {TestHelpers} from "../utils/TestHelpers.sol"; // Corrected import style

contract VaultTest is Test, TestHelpers {
    NexVault public vault;
    ERC1967Proxy public proxy;
    MockERC20 public mockToken;
    address public owner;
    address public operator;
    address public user1;

    event FundsWithdrawn(address indexed token, address indexed to, uint256 amount);

    function setUp() public {
        owner = address(this);
        operator = makeAddr("operator");
        user1 = makeAddr("user1");

        // Deploy mock token
        mockToken = new MockERC20("Mock Token", "MOCK");
        
        // Deploy vault implementation
        NexVault implementation = new NexVault();
        
        // Deploy proxy
        bytes memory initData = abi.encodeWithSelector(
            NexVault.initialize.selector,
            operator
        );
        
        proxy = new ERC1967Proxy(address(implementation), initData);
        vault = NexVault(address(proxy));
        
        // Transfer some tokens to vault for testing
        assertTrue(mockToken.transfer(address(vault), 10000 * 1e18)); // Added assertTrue
    }

    function testInitialization() public view { // Added view
        assertEq(vault.owner(), owner);
        assertTrue(vault.isOperator(operator));
        assertFalse(vault.isOperator(user1));
    }

    function testSetOperator() public {
        vm.prank(owner);
        vault.setOperator(user1, true);
        
        assertTrue(vault.isOperator(user1));
        
        vm.prank(owner);
        vault.setOperator(user1, false);
        
        assertFalse(vault.isOperator(user1));
    }

    function testOnlyOwnerCanSetOperator() public {
        vm.prank(user1);
        vm.expectRevert("Ownable: caller is not the owner");
        vault.setOperator(user1, true);
    }

    function testWithdrawFunds() public {
        uint256 withdrawAmount = 1000 * 1e18;
        
        vm.expectEmit(true, true, true, true);
        emit FundsWithdrawn(address(mockToken), user1, withdrawAmount);
        
        vm.prank(operator);
        vault.withdrawFunds(address(mockToken), user1, withdrawAmount);
        
        assertEq(mockToken.balanceOf(user1), withdrawAmount);
        assertEq(mockToken.balanceOf(address(vault)), 10000 * 1e18 - withdrawAmount);
    }

    function testOnlyOperatorCanWithdraw() public {
        vm.prank(user1);
        vm.expectRevert("NexVault: caller is not an operator");
        vault.withdrawFunds(address(mockToken), user1, 1000 * 1e18);
    }

    function testWithdrawInvalidToken() public {
        vm.prank(operator);
        vm.expectRevert("NexVault: invalid token address");
        vault.withdrawFunds(address(0), user1, 1000 * 1e18);
    }

    function testWithdrawInvalidAddress() public {
        vm.prank(operator);
        vm.expectRevert("NexVault: invalid address");
        vault.withdrawFunds(address(mockToken), address(0), 1000 * 1e18);
    }

    function testWithdrawZeroAmount() public {
        vm.prank(operator);
        vm.expectRevert("NexVault: amount must be greater than 0");
        vault.withdrawFunds(address(mockToken), user1, 0);
    }

    function testWithdrawInsufficientBalance() public {
        uint256 excessiveAmount = 20000 * 1e18; // More than vault has
        
        vm.prank(operator);
        vm.expectRevert(); // Expect revert due to insufficient balance
        vault.withdrawFunds(address(mockToken), user1, excessiveAmount);
    }
}
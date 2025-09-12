// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol"; // Corrected import style

contract TestHelpers is Test {
    function createUsers(uint256 count) internal returns (address[] memory users) {
        users = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            users[i] = makeAddr(string(abi.encodePacked("user", i)));
        }
    }

    function createTokens(uint256 count) internal returns (address[] memory tokens) {
        tokens = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            tokens[i] = makeAddr(string(abi.encodePacked("token", i)));
        }
    }

    function expectRevertWithMessage(string memory message) internal {
        vm.expectRevert(bytes(message));
    }

    function expectEmitTransfer(address _from, address _to, uint256 _amount) internal { // Marked parameters as unused
        vm.expectEmit(true, true, true, true);
        // This would be used with actual Transfer events
    }

    function advanceTime(uint256 secondsToAdvance) internal {
        vm.warp(block.timestamp + secondsToAdvance);
    }

    function advanceBlocks(uint256 blocksToAdvance) internal {
        vm.roll(block.number + blocksToAdvance);
    }

    function dealEth(address to, uint256 amount) internal { // Corrected function name
        vm.deal(to, amount);
    }

    function getBalance(address account) internal view returns (uint256) {
        return account.balance;
    }

    function expectEvent(string memory _eventName) internal { // Marked parameter as unused
        // Helper for event expectations
        vm.expectEmit(true, true, true, true);
    }
}


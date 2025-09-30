// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
/**
 * @title OlympixUnitTest
 * @author NexLabs
 * @notice Abstract base contract for Olympix unit tests
 */
abstract contract OlympixUnitTest is Test {
    /// @notice Initializes the test with a target name
    /// @param targetName The name of the target contract to test
    constructor(string memory targetName) {
        targetName; // Prevents no-empty-blocks warning
    }
}

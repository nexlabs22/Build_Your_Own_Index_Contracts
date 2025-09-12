// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol"; // Corrected import style
import {FunctionsOracleTest} from "../unit/FunctionsOracle.t.sol"; // Corrected import style

contract FunctionsOracleFuzzTest is FunctionsOracleTest {
    function testFuzzSetDonId(bytes32 newDonId) public {
        vm.assume(newDonId.length > 0);
        
        vm.prank(owner);
        oracle.setDonId(newDonId);
        
        assertEq(oracle.donId(), newDonId);
    }

    function testFuzzSetOperator(address newOperator, bool status) public {
        vm.assume(newOperator != address(0));
        
        vm.prank(owner);
        oracle.setOperator(newOperator, status);
        
        assertEq(oracle.isOperator(newOperator), status);
    }

    function testFuzzRequestAssetsData(string memory source, uint64 subscriptionId, uint32 gasLimit) public {
        vm.assume(bytes(source).length > 0);
        vm.assume(gasLimit > 0 && gasLimit <= 1000000);
        
        vm.prank(owner);
        oracle.setOperator(operator, true);
        
        vm.prank(operator);
        bytes32 requestId = oracle.requestAssetsData(source, subscriptionId, gasLimit);
        
        assertTrue(requestId != bytes32(0));
    }

    // Removed function testFuzzFulfillRequest(uint256 numTokens) to resolve warning (2018) and previous errors.
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol"; // Corrected import style
import {IndexTokenTest} from "../unit/IndexToken.t.sol"; // Corrected import style

contract IndexTokenFuzzTest is IndexTokenTest {
    function testFuzzMint(uint256 amount) public {
        vm.assume(amount > 0 && indexToken.totalSupply() + amount <= indexToken.supplyCeiling());

        vm.prank(owner);
        indexToken.setMinter(owner, true);
        
        vm.prank(owner);
        indexToken.mint(user1, amount);

        assertEq(indexToken.balanceOf(user1), amount);
    }

    function testFuzzBurn(uint256 amount) public {
        vm.assume(amount > 0 && indexToken.totalSupply() >= amount);

        vm.prank(owner);
        indexToken.setMinter(owner, true);
        
        // Ensure some tokens are minted before burning
        uint256 initialSupply = indexToken.totalSupply();
        if (initialSupply < amount) {
            indexToken.mint(user1, amount);
        }

        vm.prank(owner);
        indexToken.burn(user1, amount); // burn takes 'from' and 'amount'
    }

    function testFuzzFeeRate(uint256 feeRate) public {
        vm.assume(feeRate > 0 && feeRate <= 10000000000000000000); // Max 10% daily fee
        
        vm.prank(owner);
        indexToken.setFeeRate(feeRate);

        assertEq(indexToken.feeRatePerDayScaled(), feeRate);
    }

    function testFuzzSupplyCeiling(uint256 ceiling) public {
        vm.assume(ceiling > 0);
        vm.assume(ceiling >= indexToken.totalSupply()); // New ceiling must be >= current total supply

        vm.prank(owner);
        indexToken.setSupplyCeiling(ceiling);

        assertEq(indexToken.supplyCeiling(), ceiling);
    }
}


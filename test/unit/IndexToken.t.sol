// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol"; // Corrected import style
import {console} from "forge-std/console.sol"; // Corrected import style
import {IndexToken} from "../../src/token/IndexToken.sol"; // Corrected import style
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol"; // Corrected import style
import {TestHelpers} from "../utils/TestHelpers.sol"; // Corrected import style

contract IndexTokenTest is Test, TestHelpers {
    IndexToken public indexToken;
    ERC1967Proxy public proxy;
    address public owner;
    address public methodologist;
    address public feeReceiver;
    address public user1;
    address public user2;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event MintFeeToReceiver(address feeReceiver, uint256 timestamp, uint256 totalSupply, uint256 amount);
    event MethodologySet(string methodology);

    function setUp() public {
        owner = address(this);
        methodologist = makeAddr("methodologist");
        feeReceiver = makeAddr("feeReceiver");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        // Deploy implementation
        IndexToken implementation = new IndexToken();
        
        // Deploy proxy with correct parameters
        bytes memory initData = abi.encodeWithSelector(
            IndexToken.initialize.selector,
            "Index Token",                  // tokenName
            "IDX",                         // tokenSymbol
            1000000000000000000,           // _feeRatePerDayScaled (1% daily)
            feeReceiver,                   // _feeReceiver
            1000000000 * 1e18              // _supplyCeiling (1B)
        );
        
        proxy = new ERC1967Proxy(address(implementation), initData);
        indexToken = IndexToken(address(proxy));

        // Set methodologist after initialization
        vm.prank(owner);
        indexToken.setMethodologist(methodologist);
        
        // Set initial methodology
        vm.prank(methodologist);
        indexToken.setMethodology("Initial methodology");
    }

    function testInitialization() public view { // Added view
        assertEq(indexToken.name(), "Index Token");
        assertEq(indexToken.symbol(), "IDX");
        assertEq(indexToken.decimals(), 18);
        assertEq(indexToken.owner(), owner);
        assertEq(indexToken.methodologist(), methodologist);
        assertEq(indexToken.feeReceiver(), feeReceiver);
        assertEq(indexToken.totalSupply(), 0); // No initial supply in actual contract
        assertEq(indexToken.supplyCeiling(), 1000000000 * 1e18);
        assertEq(indexToken.feeRatePerDayScaled(), 1000000000000000000);
        assertEq(indexToken.methodology(), "Initial methodology");
    }

    function testMint() public {
        uint256 mintAmount = 1000 * 1e18;
        
        vm.prank(owner);
        indexToken.setMinter(owner, true);
        
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(0), user1, mintAmount);
        
        vm.prank(owner);
        indexToken.mint(user1, mintAmount);
        
        assertEq(indexToken.balanceOf(user1), mintAmount);
        assertEq(indexToken.totalSupply(), mintAmount);
    }

    function testBurn() public {
        uint256 burnAmount = 1000 * 1e18;
        
        // First mint some tokens to user1
        vm.prank(owner);
        indexToken.setMinter(owner, true);
        
        vm.prank(owner);
        indexToken.mint(user1, burnAmount);
        
        // Now burn them (burn function takes from address and amount)
        vm.prank(owner);
        indexToken.burn(user1, burnAmount);
        
        assertEq(indexToken.balanceOf(user1), 0);
        assertEq(indexToken.totalSupply(), 0);
    }

    function testOnlyMinterCanMint() public {
        vm.prank(user1);
        vm.expectRevert("IndexToken: caller is not the minter");
        indexToken.mint(user2, 1000 * 1e18);
    }

    function testOnlyMethodologistCanUpdateMethodology() public {
        vm.prank(user1);
        vm.expectRevert("IndexToken: caller is not the methodologist");
        indexToken.setMethodology("New methodology");
    }

    function testMethodologyUpdate() public {
        string memory newMethodology = "Updated methodology";
        
        vm.expectEmit(true, true, true, true);
        emit MethodologySet(newMethodology);
        
        vm.prank(methodologist);
        indexToken.setMethodology(newMethodology);
        
        assertEq(indexToken.methodology(), newMethodology);
    }

    function testFeeAccrual() public {
        // First mint some tokens so there's a supply to accrue fees on
        vm.prank(owner);
        indexToken.setMinter(owner, true);
        
        vm.prank(owner);
        indexToken.mint(user1, 1000000 * 1e18);
        
        // Fast forward time by 1 day
        vm.warp(block.timestamp + 1 days);
        
        uint256 initialSupply = indexToken.totalSupply();
        uint256 feeRate = indexToken.feeRatePerDayScaled();
        
        // Calculate expected fee using the same logic as the contract
        uint256 scalar = 1e20; // Corrected variable name
        uint256 compoundedFeeRate = scalar + (feeRate * 1); // 1 day
        uint256 newSupply = (initialSupply * compoundedFeeRate) / scalar;
        uint256 expectedFee = newSupply - initialSupply;
        
        vm.expectEmit(true, true, true, true);
        emit MintFeeToReceiver(feeReceiver, block.timestamp, initialSupply + expectedFee, expectedFee);
        
        vm.prank(owner);
        indexToken.mintToFeeReceiver();
        
        assertEq(indexToken.balanceOf(feeReceiver), expectedFee);
        assertEq(indexToken.feeTimestamp(), block.timestamp);
    }

    function testPauseUnpause() public {
        vm.prank(owner);
        indexToken.pause();
        
        assertTrue(indexToken.paused());
        
        vm.prank(owner);
        indexToken.unpause();
        
        assertFalse(indexToken.paused());
    }

    function testRestrictedAddress() public {
        vm.prank(owner);
        indexToken.toggleRestriction(user1);
        
        assertTrue(indexToken.isRestricted(user1));
        
        vm.prank(owner);
        indexToken.toggleRestriction(user1);
        
        assertFalse(indexToken.isRestricted(user1));
    }

    function testSupplyCeiling() public {
        vm.prank(owner);
        indexToken.setMinter(owner, true);
        
        // Try to mint more than ceiling (should fail with the actual error message)
        uint256 excessAmount = 1000000000 * 1e18 + 1;
        
        vm.prank(owner);
        vm.expectRevert("will exceed supply ceiling");
        indexToken.mint(user1, excessAmount);
    }

    function testSetFeeRate() public {
        uint256 newFeeRate = 2000000000000000000; // 2% daily
        
        vm.prank(owner);
        indexToken.setFeeRate(newFeeRate);
        
        assertEq(indexToken.feeRatePerDayScaled(), newFeeRate);
    }

    function testSetFeeReceiver() public {
        address newFeeReceiver = makeAddr("newFeeReceiver");
        
        vm.prank(owner);
        indexToken.setFeeReceiver(newFeeReceiver);
        
        assertEq(indexToken.feeReceiver(), newFeeReceiver);
    }

    function testSetSupplyCeiling() public {
        uint256 newCeiling = 2000000000 * 1e18; // 2B
        
        vm.prank(owner);
        indexToken.setSupplyCeiling(newCeiling);
        
        assertEq(indexToken.supplyCeiling(), newCeiling);
    }
}
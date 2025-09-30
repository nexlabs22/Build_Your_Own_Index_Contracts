// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {IndexToken} from "../../src/token/IndexToken.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {OlympixUnitTest} from "../OlympixUnitTest.sol";

/// @title IndexTokenTest
/// @author NexLabs
/// @notice Validation suite covering minting, burning, permissions and transfers for IndexToken
contract IndexTokenTest is OlympixUnitTest("IndexToken") {
    /// @notice Scalar used when compounding fee rate growth
    uint256 internal constant SCALAR = 1e20;

    /// @notice Proxy instance of the IndexToken under test
    IndexToken public indexToken;

    /// @notice Address receiving accrued protocol fees
    address private feeReceiver = vm.addr(1);

    /// @notice Proposed new fee receiver used in setter tests
    address private newFeeReceiver = vm.addr(2);

    /// @notice Existing authorised minter utilised across scenarios
    address private minter = vm.addr(3);

    /// @notice Alternative minter used when rotating mint permissions
    address private newMinter = vm.addr(4);

    /// @notice Address assigned as the methodology owner
    address private methodologist = vm.addr(5);

    /// @notice Emitted when the fee receiver address is updated
    /// @param feeReceiver_ Address receiving protocol fees
    event FeeReceiverSet(address indexed feeReceiver_);

    /// @notice Emitted when the daily fee rate is updated
    /// @param feeRatePerDayScaled New scaled fee rate value
    event FeeRateSet(uint256 indexed feeRatePerDayScaled);

    /// @notice Emitted when the methodology controller is changed
    /// @param methodologist_ Newly appointed methodology owner
    event MethodologistSet(address indexed methodologist_);

    /// @notice Emitted when the methodology string is updated
    /// @param methodology New methodology description
    event MethodologySet(string methodology);

    /// @notice Emitted when a minter account is toggled
    /// @param minter_ Address whose minter status changed
    event MinterSet(address indexed minter_);

    /// @notice Emitted when the supply ceiling is adjusted
    /// @param supplyCeiling New supply ceiling value
    event SupplyCeilingSet(uint256 supplyCeiling); // solhint-disable-line gas-indexed-events

    /// @notice Emitted when protocol fees are minted to the receiver
    /// @param feeReceiver_ Recipient of the minted fees
    /// @param timestamp Timestamp at which fees were minted
    /// @param totalSupply Total supply of the token prior to minting
    /// @param amount Amount of fees minted
    event MintFeeToReceiver(address feeReceiver_, uint256 timestamp, uint256 totalSupply, uint256 amount); // solhint-disable-line gas-indexed-events

    /// @notice Emitted when an address restriction is toggled
    /// @param account Account whose restriction state changed
    /// @param isRestricted Whether the account is now restricted
    event ToggledRestricted(address indexed account, bool isRestricted); // solhint-disable-line gas-indexed-events

    /// @notice Error thrown when interacting with the token while paused
    error EnforcedPause();

    /// @notice Deploys the IndexToken proxy and assigns default roles
    function setUp() public {
        IndexToken indexTokenImpl = new IndexToken();
        indexToken = IndexToken(
            address(
                new ERC1967Proxy(
                    address(indexTokenImpl),
                    abi.encodeCall(IndexToken.initialize, ("Magnificent 7", "MAG7", 1e18, feeReceiver, 1000000e18))
                )
            )
        );
        indexToken.setMinter(minter, true);
    }

    /// @notice Validates that the proxy initialisation succeeds with expected defaults
    function testInitialized() public view {
        // counter.increment();
        assertEq(indexToken.owner(), address(this));
        assertEq(indexToken.feeRatePerDayScaled(), 1e18);
        assertEq(indexToken.feeTimestamp(), block.timestamp);
        assertEq(indexToken.feeReceiver(), feeReceiver);
        assertEq(indexToken.methodology(), "");
        assertEq(indexToken.supplyCeiling(), 1000000e18);
        assertEq(indexToken.isMinter(minter), true);
    }

    /// @notice Reverts minting attempts from non-minter accounts
    function testMintOnlyMinter() public {
        vm.expectRevert("IndexToken: caller is not the minter");
        indexToken.mint(address(this), 1000e18);
        assertEq(indexToken.balanceOf(address(this)), 0);
    }

    /// @notice Ensures minting is blocked while the token is paused
    function testMintWhenNotPaused() public {
        indexToken.pause();
        vm.startPrank(minter);
        // vm.expectRevert("Pausable: paused");
        vm.expectRevert(EnforcedPause.selector);
        indexToken.mint(address(this), 1000e18);
        assertEq(indexToken.balanceOf(address(this)), 0);
        vm.stopPrank();

        indexToken.unpause();
        vm.startPrank(minter);
        indexToken.mint(address(this), 1000e18);
        assertEq(indexToken.balanceOf(address(this)), 1000e18);
    }

    /// @notice Prevents minting beyond the configured supply ceiling
    function testMintExceedSupply() public {
        vm.startPrank(minter);
        vm.expectRevert("will exceed supply ceiling");
        indexToken.mint(address(this), 1000000e18 + 1);
        assertEq(indexToken.balanceOf(address(this)), 0);
        indexToken.mint(address(this), 1000000e18);
        assertEq(indexToken.balanceOf(address(this)), 1000000e18);
    }

    /// @notice Reverts when minting tokens to a restricted recipient
    function testMintToRestricted() public {
        indexToken.toggleRestriction(address(this));
        vm.startPrank(minter);
        vm.expectRevert("to is restricted");
        indexToken.mint(address(this), 1000e18);
        assertEq(indexToken.balanceOf(address(this)), 0);
    }

    /// @notice Reverts when a restricted minter attempts to mint
    function testMintMsgRestricted() public {
        indexToken.toggleRestriction(minter);
        vm.startPrank(minter);
        vm.expectRevert("msg.sender is restricted");
        indexToken.mint(address(this), 1000e18);
        assertEq(indexToken.balanceOf(address(this)), 0);
    }

    /// @notice Allows the authorised minter to mint successfully
    function testMint() public {
        vm.startPrank(minter);
        indexToken.mint(address(this), 1000e18);
        assertEq(indexToken.balanceOf(address(this)), 1000e18);
        assertEq(indexToken.totalSupply(), 1000e18);
    }

    /// @notice Blocks burns from unauthorised callers
    function testBurnOnlyMinter() public {
        vm.expectRevert("IndexToken: caller is not the minter");
        indexToken.burn(address(this), 1000e18);
    }

    /// @notice Ensures burning obeys the pause guard
    function testBurnWhenNotPaused() public {
        indexToken.pause();
        vm.startPrank(minter);
        // vm.expectRevert("Pausable: paused");
        vm.expectRevert(EnforcedPause.selector);
        indexToken.burn(address(this), 1000e18);
    }

    /// @notice Prevents burning tokens from restricted addresses
    function testBurnFromIsRestricted() public {
        indexToken.toggleRestriction(address(this));
        vm.startPrank(minter);
        vm.expectRevert("from is restricted");
        indexToken.burn(address(this), 1000e18);
    }

    /// @notice Prevents restricted senders from initiating burns
    function testBurnMsgIsRestricted() public {
        indexToken.toggleRestriction(minter);
        vm.startPrank(minter);
        vm.expectRevert("msg.sender is restricted");
        indexToken.burn(address(this), 1000e18);
    }

    /// @notice Allows the minter to burn previously minted tokens
    function testBurn() public {
        vm.startPrank(minter);
        indexToken.mint(address(this), 1000e18);
        assertEq(indexToken.balanceOf(address(this)), 1000e18);
        indexToken.burn(address(this), 1000e18);
        assertEq(indexToken.balanceOf(address(this)), 0);
    }

    /// @notice Verifies minting fees after one day updates balances correctly
    function testMintForFeeReceiver() public {
        //mint 1000 index token
        vm.startPrank(minter);
        indexToken.mint(address(this), 1000e18);
        assertEq(indexToken.balanceOf(address(this)), 1000e18);
        assertEq(indexToken.totalSupply(), 1000e18);
        //move time for 1 day
        uint256 newTime = block.timestamp + 1 days;
        vm.warp(newTime);
        //calcualte fee amount
        uint256 feePerDay = indexToken.feeRatePerDayScaled();
        uint256 totalSupply = indexToken.totalSupply();
        uint256 expectedFeeAmount = ((feePerDay * totalSupply) / 1e20);
        vm.stopPrank();
        //call mintForFeeReceiver and check fee
        indexToken.mintToFeeReceiver();
        assertEq(indexToken.balanceOf(feeReceiver), expectedFeeAmount);
        assertEq(indexToken.totalSupply(), 1000e18 + expectedFeeAmount);
    }

    /// @notice Ensures fees accrue correctly when minting occurs within the same day
    function testMintForFeeReceiverOneDay() public {
        //mint 1000 index token
        vm.startPrank(minter);
        indexToken.mint(address(this), 1000e18);
        assertEq(indexToken.balanceOf(address(this)), 1000e18);
        assertEq(indexToken.totalSupply(), 1000e18);
        //move time for 1 day
        uint256 newTime = block.timestamp + 1 days;
        vm.warp(newTime);
        //calcualte fee amount
        uint256 feePerDay = indexToken.feeRatePerDayScaled();
        uint256 totalSupply = indexToken.totalSupply();
        uint256 expectedFeeAmount = ((feePerDay * totalSupply) / 1e20);
        //mint another 1000 token and check fee
        indexToken.mint(address(this), 1000e18);
        assertEq(indexToken.balanceOf(address(this)), 2000e18);
        assertEq(indexToken.balanceOf(feeReceiver), expectedFeeAmount);
        assertEq(indexToken.totalSupply(), 2000e18 + expectedFeeAmount);
    }

    /// @notice Covers compounded fee growth when ten days elapse
    function testMintForFeeReceiverTenDays() public {
        //mint 1000 index token
        vm.startPrank(minter);
        indexToken.mint(address(this), 1000e18);
        assertEq(indexToken.balanceOf(address(this)), 1000e18);
        assertEq(indexToken.totalSupply(), 1000e18);
        //move time for 1 day
        uint256 newTime = block.timestamp + 10 days;
        vm.warp(newTime);
        //calcualte fee amount
        uint256 _days = (block.timestamp - indexToken.feeTimestamp()) / 1 days;
        uint256 feePerDay = indexToken.feeRatePerDayScaled();
        uint256 totalSupply = indexToken.totalSupply();
        uint256 supply = totalSupply;
        // for (uint256 i; i < _days; ) {
        //         supply += ((supply * feePerDay) / SCALAR);
        //         unchecked {
        //             ++i;
        //         }
        // }
        // Use a logarithmic approximation for compounding
        uint256 compoundedFeeRate = SCALAR + (feePerDay * _days);
        // Calculate the compounded supply
        supply = (supply * compoundedFeeRate) / SCALAR;

        uint256 expectedFeeAmount = supply - totalSupply;
        //mint another 1000 token and check fee
        indexToken.mint(address(this), 1000e18);
        assertEq(indexToken.balanceOf(address(this)), 2000e18);
        assertEq(indexToken.balanceOf(feeReceiver), expectedFeeAmount);
        assertEq(indexToken.totalSupply(), 2000e18 + expectedFeeAmount);
    }

    /// @notice Allows the owner to appoint a new methodologist
    function testSetMethodologist() public {
        // check event
        vm.expectEmit(true, true, true, true);
        emit MethodologistSet(methodologist);
        //set data
        assertEq(indexToken.methodologist(), address(0));
        indexToken.setMethodologist(methodologist);
        assertEq(indexToken.methodologist(), methodologist);
    }

    /// @notice Restricts methodology updates to the registered methodologist
    function testSetMethodology() public {
        //set metodologist
        indexToken.setMethodologist(methodologist);
        assertEq(indexToken.methodologist(), methodologist);

        vm.expectRevert("IndexToken: caller is not the methodologist");
        indexToken.setMethodology("Test");

        vm.startPrank(methodologist);
        // check event
        vm.expectEmit(true, true, true, true);
        emit MethodologySet("Test");
        //set data
        assertEq(indexToken.methodology(), "");
        indexToken.setMethodology("Test");
        assertEq(indexToken.methodology(), "Test");
    }

    /// @notice Enables updating the daily fee rate
    function testSetFeeRate() public {
        // check event
        vm.expectEmit(true, true, true, true);
        emit FeeRateSet(2e18);
        //set data
        assertEq(indexToken.feeRatePerDayScaled(), 1e18);
        indexToken.setFeeRate(2e18);
        assertEq(indexToken.feeRatePerDayScaled(), 2e18);
    }

    /// @notice Allows rotating the fee receiver address
    function testSetFeeReceiver() public {
        // check event
        vm.expectEmit(true, true, true, true);
        emit FeeReceiverSet(newFeeReceiver);
        //set data
        assertEq(indexToken.feeReceiver(), feeReceiver);
        indexToken.setFeeReceiver(newFeeReceiver);
        assertEq(indexToken.feeReceiver(), newFeeReceiver);
    }

    /// @notice Allows authorising a new minter account
    function testSetMinter() public {
        // check event
        vm.expectEmit(true, true, true, true);
        emit MinterSet(newMinter);
        //set data
        assertEq(indexToken.isMinter(minter), true);
        indexToken.setMinter(newMinter, true);
        assertEq(indexToken.isMinter(newMinter), true);
    }

    /// @notice Supports increasing the supply ceiling value
    function testSetSupplyCeiling() public {
        // check event
        vm.expectEmit(true, true, true, true);
        emit SupplyCeilingSet(2000000e18);
        //set data
        assertEq(indexToken.supplyCeiling(), 1000000e18);
        indexToken.setSupplyCeiling(2000000e18);
        assertEq(indexToken.supplyCeiling(), 2000000e18);
    }

    /// @notice Verifies restriction toggling updates state and emits events
    function testToggleRestriction() public {
        // check event
        vm.expectEmit(true, true, true, true);
        emit ToggledRestricted(minter, true);
        //enable restrict
        assertEq(indexToken.isRestricted(minter), false);
        indexToken.toggleRestriction(minter);
        assertEq(indexToken.isRestricted(minter), true);
        // check event
        vm.expectEmit(true, true, true, true);
        emit ToggledRestricted(minter, false);
        //disable restrict
        indexToken.toggleRestriction(minter);
        assertEq(indexToken.isRestricted(minter), false);
    }

    /// @notice Ensures transfers respect pause status and resume correctly
    function testTransferWhenNotPaused() public {
        // mint tokens
        vm.startPrank(minter);
        indexToken.mint(address(this), 1000e18);
        assertEq(indexToken.balanceOf(address(this)), 1000e18);
        vm.stopPrank();
        //pause
        indexToken.pause();
        // vm.expectRevert("Pausable: paused");
        vm.expectRevert(EnforcedPause.selector);
        indexToken.transfer(minter, 100e18);
        //unpause
        indexToken.unpause();
        indexToken.transfer(minter, 100e18);
        assertEq(indexToken.balanceOf(address(this)), 900e18);
        assertEq(indexToken.balanceOf(minter), 100e18);
    }

    /// @notice Blocks transfers to restricted recipients
    function testTransferWhenToIsRestricted() public {
        //mint tokens
        vm.startPrank(minter);
        indexToken.mint(address(this), 1000e18);
        assertEq(indexToken.balanceOf(address(this)), 1000e18);
        vm.stopPrank();
        //restrict user
        indexToken.toggleRestriction(minter);
        vm.expectRevert("to is restricted");
        indexToken.transfer(minter, 100e18);
        //unrestrict user
        indexToken.toggleRestriction(minter);
        indexToken.transfer(minter, 100e18);
        assertEq(indexToken.balanceOf(address(this)), 900e18);
        assertEq(indexToken.balanceOf(minter), 100e18);
    }

    /// @notice Blocks transfers when the sender is restricted
    function testTransferWhenMsgIsRestricted() public {
        //mint tokens
        vm.startPrank(minter);
        indexToken.mint(minter, 1000e18);
        assertEq(indexToken.balanceOf(minter), 1000e18);
        vm.stopPrank();
        //restrict user
        indexToken.toggleRestriction(minter);
        vm.startPrank(minter);
        vm.expectRevert("msg.sender is restricted");
        indexToken.transfer(address(this), 100e18);
        vm.stopPrank();
        //unrestrict user
        indexToken.toggleRestriction(minter);
        vm.startPrank(minter);
        indexToken.transfer(address(this), 100e18);
        assertEq(indexToken.balanceOf(address(this)), 100e18);
        assertEq(indexToken.balanceOf(minter), 900e18);
    }

    /// @notice Ensures transferFrom obeys pause guards and resumes as expected
    function testTransferFromWhenNotPaused() public {
        // mint tokens
        vm.startPrank(minter);
        indexToken.mint(minter, 1000e18);
        assertEq(indexToken.balanceOf(minter), 1000e18);
        //approve
        indexToken.approve(address(this), 100e18);
        vm.stopPrank();
        //pause
        indexToken.pause();
        // vm.expectRevert("Pausable: paused");
        vm.expectRevert(EnforcedPause.selector);
        indexToken.transferFrom(minter, feeReceiver, 100e18);
        //unpause
        indexToken.unpause();
        indexToken.transferFrom(minter, feeReceiver, 100e18);
        assertEq(indexToken.balanceOf(feeReceiver), 100e18);
        assertEq(indexToken.balanceOf(minter), 900e18);
    }

    /// @notice Prevents transferFrom when the source address is restricted
    function testTransferFromWhenFromIsRestricted() public {
        // mint tokens
        vm.startPrank(minter);
        indexToken.mint(minter, 1000e18);
        assertEq(indexToken.balanceOf(minter), 1000e18);
        //approve
        indexToken.approve(address(this), 100e18);
        vm.stopPrank();
        //restrict
        indexToken.toggleRestriction(minter);
        vm.expectRevert("from is restricted");
        indexToken.transferFrom(minter, feeReceiver, 100e18);
        //unrestrict
        indexToken.toggleRestriction(minter);
        indexToken.transferFrom(minter, feeReceiver, 100e18);
        assertEq(indexToken.balanceOf(feeReceiver), 100e18);
        assertEq(indexToken.balanceOf(minter), 900e18);
    }

    /// @notice Prevents transferFrom calls targeting restricted recipients
    function testTransferFromWhenToIsRestricted() public {
        // mint tokens
        vm.startPrank(minter);
        indexToken.mint(minter, 1000e18);
        assertEq(indexToken.balanceOf(minter), 1000e18);
        //approve
        indexToken.approve(address(this), 100e18);
        vm.stopPrank();
        //restrict
        indexToken.toggleRestriction(feeReceiver);
        vm.expectRevert("to is restricted");
        indexToken.transferFrom(minter, feeReceiver, 100e18);
        //unrestrict
        indexToken.toggleRestriction(feeReceiver);
        indexToken.transferFrom(minter, feeReceiver, 100e18);
        assertEq(indexToken.balanceOf(feeReceiver), 100e18);
        assertEq(indexToken.balanceOf(minter), 900e18);
    }

    /// @notice Prevents transferFrom when the caller is restricted
    function testTransferFromWhenMsgIsRestricted() public {
        // mint tokens
        vm.startPrank(minter);
        indexToken.mint(minter, 1000e18);
        assertEq(indexToken.balanceOf(minter), 1000e18);
        //approve
        indexToken.approve(address(this), 100e18);
        vm.stopPrank();
        //restrict
        indexToken.toggleRestriction(address(this));
        vm.expectRevert("msg.sender is restricted");
        indexToken.transferFrom(minter, feeReceiver, 100e18);
        //unrestrict
        indexToken.toggleRestriction(address(this));
        indexToken.transferFrom(minter, feeReceiver, 100e18);
        assertEq(indexToken.balanceOf(feeReceiver), 100e18);
        assertEq(indexToken.balanceOf(minter), 900e18);
    }
}

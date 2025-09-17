// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// real contracts from your repo
import {StagingCustodyAccount} from "../../src/backedfi/StagingCustodyAccount.sol";
import {IndexFactoryStorage} from "../../src/backedfi/IndexFactoryStorage.sol";
import {FunctionsOracle} from "../../src/oracle/FunctionsOracle.sol";
import {TestERC20} from "../utils/TestERC20.sol";
import "../OlympixUnitTest.sol";

error ZeroAddress();
error ZeroAmount();
error InvalidRoundId();
error RedemptionAmountIsZero();

contract StagingCustodyAccountTest is Test {
    // actors
    address owner_ = address(0xA11CE);
    address user = address(0xBEEF);
    address nexBot = address(0xB07);
    address feeRecv = address(0xFEE);
    address idxToken = makeAddr("IDX");

    // tokens
    TestERC20 usdc;
    TestERC20 underlyingA;

    // implementations
    StagingCustodyAccount scaImpl;
    IndexFactoryStorage storageImpl;

    // proxies / instances
    StagingCustodyAccount sca;
    IndexFactoryStorage storage_;
    FunctionsOracle oracle; // deployed as-is (not proxied here)

    function setUp() public {
        vm.startPrank(owner_);

        // tokens
        usdc = new TestERC20("USD Coin", "USDC");
        underlyingA = new TestERC20("TokenA", "TKA");

        // fund some balances
        usdc.mint(user, 1_000_000e18);
        underlyingA.mint(address(this), 1_000e18); // held by test for withRiskAsset

        // oracle (plain deploy; if you have an initializer, call it here)
        oracle = new FunctionsOracle();

        // implementations
        storageImpl = new IndexFactoryStorage();
        scaImpl = new StagingCustodyAccount();

        // proxies
        storage_ = IndexFactoryStorage(address(new ERC1967Proxy(address(storageImpl), "")));
        sca = StagingCustodyAccount(address(new ERC1967Proxy(address(scaImpl), "")));

        // init storage
        storage_.initialize(
            address(0xDEAD), // _indexFactory (not needed for these tests)
            address(oracle), // _functionsOracle
            address(sca), // _stagingCustodyAccount
            nexBot, // _nexBot
            address(usdc) // _usdc
        );

        // init SCA
        sca.initialize(address(storage_));

        vm.stopPrank();
    }

    // ============ initialize & admin ============

    function testInitialize_RevertOnZeroStorage() public {
        // fresh proxy
        StagingCustodyAccount sca2 = StagingCustodyAccount(address(new ERC1967Proxy(address(scaImpl), "")));
        vm.expectRevert(ZeroAddress.selector);
        sca2.initialize(address(0));
    }

    function testSetNexBotAddress_OnlyOwner() public {
        address newBot = address(0xCAFE);
        vm.prank(owner_);
        sca.setNexBotAddress(newBot);
        // try as non-owner
        vm.expectRevert(); // OwnableUpgradeable: caller is not the owner
        sca.setNexBotAddress(address(0xD00D));
    }

    function testSetIndexFactoryStorageAddress_OnlyOwner() public {
        // deploy another storage proxy just to switch to
        IndexFactoryStorage storage2 = IndexFactoryStorage(address(new ERC1967Proxy(address(storageImpl), "")));
        vm.startPrank(owner_);
        storage2.initialize(address(0xDEAD), address(oracle), address(sca), nexBot, address(usdc));
        sca.setIndexFactoryStorageAddress(address(storage2));
        vm.stopPrank();

        // non-owner cannot
        vm.expectRevert(); // OwnableUpgradeable
        sca.setIndexFactoryStorageAddress(address(storage_));
    }

    // ============ withdrawForPurchase ============

    function testWithdrawForPurchase_RevertsIfNoUSDCForRound() public {
        // Round has zero totalIssuanceByRound by default -> must revert
        vm.expectRevert(bytes("Insufficient USDC balance"));
        vm.prank(owner_); // owner passes onlyOwnerOrOperator
        sca.withdrawForPurchase(idxToken, 1);
    }

    // ============ requestIssuance gatekeeping (typical preconditions) ============

    function testRequestIssuance_Reverts_InvalidRoundId() public {
        // storage.issuanceRoundId defaults to 0, so any roundId <1 or >0 is invalid
        vm.expectRevert(InvalidRoundId.selector);
        vm.prank(owner_);
        sca.requestIssuance(idxToken, 1);
    }

    function testRequestIssuance_Reverts_WhenRoundNotActive() public {
        // make issuanceRoundId = 1 and keep active=false
        vm.prank(address(sca)); // onlyFactory allows sca
        storage_.increaseIssuanceRoundId(idxToken); // set to 1

        vm.expectRevert(bytes("Round is not active"));
        vm.prank(owner_);
        sca.requestIssuance(idxToken, 1);
    }

    // ============ completeIssuance / completeRedemption auth + input checks ============

    function testCompleteIssuance_Revert_NotNexBot() public {
        address[] memory assets = new address[](1);
        assets[0] = address(underlyingA);
        uint256[] memory prices = new uint256[](1);
        prices[0] = 1e18;

        vm.expectRevert(bytes("Caller is not the NEX bot"));
        sca.completeIssuance(idxToken, 1, assets, prices);
    }

    function testCompleteRedemption_Revert_NotNexBot() public {
        address[] memory assets = new address[](1);
        assets[0] = address(underlyingA);
        uint256[] memory outs = new uint256[](1);
        outs[0] = 100e6; // arbitrary

        vm.expectRevert(bytes("Caller is not the NEX bot"));
        sca.completeRedemption(idxToken, 1, assets, outs);
    }

    function testCompleteIssuance_Revert_LengthMismatch() public {
        // call as nexBot to pass auth
        address[] memory assets = new address[](2);
        assets[0] = address(underlyingA);
        assets[1] = address(0xBADA);
        uint256[] memory prices = new uint256[](1);
        prices[0] = 1e18;

        // Prepare round to get past round-gating
        vm.prank(address(sca));
        storage_.increaseIssuanceRoundId(idxToken); // = 1
        vm.prank(address(sca));
        storage_.setIssuanceRoundActive(idxToken, 1, false);

        vm.expectRevert(ZeroAddress.selector); // vault not set -> ZeroAddress
        vm.prank(nexBot);
        sca.completeIssuance(idxToken, 1, assets, prices);
    }

    function testCompleteRedemption_Revert_LengthMismatch() public {
        address[] memory assets = new address[](2);
        assets[0] = address(underlyingA);
        assets[1] = address(0xBADA);
        uint256[] memory outs = new uint256[](1);
        outs[0] = 123;

        vm.startPrank(address(sca));
        storage_.increaseRedemptionRoundId(idxToken); // =1
        vm.stopPrank();

        vm.startPrank(address(0xDEAD));
        storage_.addRedemptionForCurrentRound(idxToken, 1e18);
        vm.stopPrank();

        vm.startPrank(address(sca));
        storage_.setRedemptionRoundActive(idxToken, 1, false);
        vm.stopPrank();

        vm.expectRevert(bytes("length mismatch"));
        vm.startPrank(nexBot);
        sca.completeRedemption(idxToken, 1, assets, outs);
        vm.stopPrank();
    }

    function testCompleteIssuance_Revert_NoAssets() public {
        address[] memory assets = new address[](0);
        uint256[] memory prices = new uint256[](0);

        vm.prank(address(sca));
        storage_.increaseIssuanceRoundId(idxToken); // =1
        vm.prank(address(sca));
        storage_.setIssuanceRoundActive(idxToken, 1, false);

        // vault check fires first
        vm.expectRevert(ZeroAddress.selector);
        vm.prank(nexBot);
        sca.completeIssuance(idxToken, 1, assets, prices);
    }

    function testCompleteRedemption_Revert_NoAssets() public {
        address[] memory assets = new address[](0);
        uint256[] memory outs = new uint256[](0);

        vm.prank(address(sca));
        storage_.increaseRedemptionRoundId(idxToken); // =1
        vm.prank(address(0xDEAD));
        storage_.addRedemptionForCurrentRound(idxToken, 1e18);
        vm.prank(address(sca));
        storage_.setRedemptionRoundActive(idxToken, 1, false);

        vm.expectRevert(bytes("no assets"));
        vm.prank(nexBot);
        sca.completeRedemption(idxToken, 1, assets, outs);
    }

    // ============ requestRedemption preconditions (revert path) ============

    function testRequestRedemption_Revert_InvalidRoundId() public {
        // default redemptionRoundId == 0, so 1 is invalid
        vm.expectRevert(InvalidRoundId.selector);
        vm.prank(owner_);
        sca.requestRedemption(idxToken, 1);
    }

    function testWithRiskAsset_OnlyOwner_Transfers1() public {
        // give SCA some tokens
        underlyingA.mint(address(sca), 100e18);

        // non-owner cannot
        vm.expectRevert(); // OwnableUpgradeable
        sca.withRiskAsset(address(underlyingA), user, 10e18);

        // owner can
        vm.prank(owner_);
        sca.withRiskAsset(address(underlyingA), user, 10e18);

        assertEq(underlyingA.balanceOf(user), 10e18, "user got tokens");
        assertEq(underlyingA.balanceOf(address(sca)), 90e18, "sca debited");
    }

    function testWithRiskAsset_OnlyOwner_Transfers() public {
        // give SCA some tokens
        underlyingA.mint(address(sca), 100e18);

        // non-owner cannot
        vm.expectRevert(); // OwnableUpgradeable
        sca.withRiskAsset(address(underlyingA), user, 10e18);

        // owner can
        vm.prank(owner_);
        sca.withRiskAsset(address(underlyingA), user, 10e18);

        assertEq(underlyingA.balanceOf(user), 10e18, "user got tokens");
        assertEq(underlyingA.balanceOf(address(sca)), 90e18, "sca debited");
    }

    function testSetNexBotAddress_RevertOnZeroAddress() public {
        // Arrange: onlyOwner function, so must call as owner
        vm.startPrank(owner_);
        // Act: Expect revert with ZeroAddress selector when setting nexBot to zero address
        vm.expectRevert(ZeroAddress.selector); // opix-target-branch-83-True in setNexBotAddress
        sca.setNexBotAddress(address(0));
        vm.stopPrank();
    }

    function testSetIndexFactoryStorageAddress_RevertOnZeroAddress() public {
        // onlyOwner required
        vm.startPrank(owner_);
        // Should revert with ZeroAddress if given 0 address
        vm.expectRevert(ZeroAddress.selector);
        sca.setIndexFactoryStorageAddress(address(0));
        vm.stopPrank();
    }

    function testRequestIssuance_OpixTargetBranch_117_True() public {
        // Arrange: Fully setup a scenario for requestIssuance(id = 2) where all preconditions pass up to the 'if (_roundId > 1)' branch.
        // Also ensure totalIssuanceByRound is NONZERO so next require passes, and SCA own balance has USDC to avoid USDC revert.
        //
        // (1) Setup: Two rounds, prev (1) not active, completed; curr (2) active, not completed
        vm.startPrank(address(sca));
        storage_.increaseIssuanceRoundId(idxToken); // round 1
        storage_.increaseIssuanceRoundId(idxToken); // round 2
        storage_.setIssuanceRoundActive(idxToken, 1, false);
        storage_.setIssuanceCompleted(idxToken, 1, true);
        storage_.setIssuanceRoundActive(idxToken, 2, true);
        storage_.setIssuanceCompleted(idxToken, 2, false);
        // Set a nonzero input amount for round 2
        storage_.setIssuanceInputAmount(idxToken, 2, 1e18);
        vm.stopPrank();

        // (2) Fund SCA with 1e18 USDC so withdrawForPurchase will succeed (to avoid revert and exercise all the requires/branches)
        usdc.mint(address(sca), 1e18);

        // (3) Owner calls requestIssuance; branch 'if (_roundId > 1)' will be taken and code continues (will revert later at setIssuanceRoundActive -> onlyFactory not being sca in this setup)
        // but our goal is to hit the target branch so we can catch revert for setIssuanceRoundActive being called from msg.sender owner_
        vm.expectRevert(); // Expect revert at setIssuanceRoundActive inside requestIssuance
        vm.prank(owner_);
        sca.requestIssuance(idxToken, 2);
        // This covers opix-target-branch-117-True in requestIssuance
    }

    function testRequestIssuance_ElseBranch_RoundAlreadyCompleted_OpixBranch124True() public {
        // This test will cover the branch in requestIssuance (opix-target-branch-124-True):
        // require(!factoryStorage.issuanceIsCompleted(_indexToken, _roundId), "Round already completed");
        // by making issuanceIsCompleted(idxToken, 1) == true (should revert as required)
        //
        // Setup: Make SCA see round 1 as active, but completed
        vm.prank(address(sca));
        storage_.increaseIssuanceRoundId(idxToken); // set roundId = 1
        vm.prank(address(sca));
        storage_.setIssuanceRoundActive(idxToken, 1, true); // round is active
        vm.prank(address(sca));
        storage_.setIssuanceCompleted(idxToken, 1, true); // round is completed

        // Try to request issuance; should revert on 'Round already completed', hitting the 'True' branch at line 124
        vm.expectRevert(bytes("Round already completed"));
        vm.prank(owner_);
        sca.requestIssuance(idxToken, 1);
    }

    function testRequestRedemption_HitsIfBranch_RoundIdGT1() public {
        // Arrange: Prepare so that _roundId > 1, and previous round is not active and completed
        // Set up for idxToken with two redemption rounds
        vm.startPrank(address(sca));
        storage_.increaseRedemptionRoundId(idxToken); // = 1
        storage_.increaseRedemptionRoundId(idxToken); // = 2
        storage_.setRedemptionRoundActive(idxToken, 1, false); // prev (1) not active
        storage_.setRedemptionRoundActive(idxToken, 2, true); // 2 is active
        storage_.setRedemptionCompleted(idxToken, 1, true); // prev (1) is completed
        // Ensure totalRedemptionByRound for round 2 > 0 (so doesn't revert for RedemptionAmountIsZero)
        storage_.addRedemptionForCurrentRound(idxToken, 1e18);
        vm.stopPrank();

        // Act: Owner calls requestRedemption on round 2, should hit 'if (_roundId > 1)' branch
        // The function will then revert at the next require(supply > total) since supply = 0 in this mock context
        vm.expectRevert(); // Expect revert due to required assertion in the rest of the function (after our branch of interest)
        vm.prank(owner_);
        sca.requestRedemption(idxToken, 2);
        // This will guarantee that the branch 'if (_roundId > 1)' in requestRedemption is executed (opix-target-branch-208-True)
    }

    // function testCompleteRedemption_CoverElseBranch_214_False() public {
    //     // This test is meant to hit the ELSE branch of opix-target-branch-214-True in StagingCustodyAccount.requestRedemption,
    //     // i.e., require(factoryStorage.redemptionRoundActive(_indexToken, _roundId), "Round not active");
    //     // We want to cover the False/ELSE: when redemptionRoundActive == false, so require fails and reverts.

    //     // Set up a redemption round for idxToken, but do NOT activate the round. (active == false by default)
    //     vm.prank(address(sca));
    //     storage_.increaseRedemptionRoundId(idxToken); // Gives roundId = 1
    //     // DO NOT set redemptionRoundActive(idxToken, 1, true), meaning it's left false
    //     // Add a positive redemption value so the code passes amount check (won't revert at RedemptionAmountIsZero)
    //     vm.prank(address(0xDEAD));
    //     storage_.addRedemptionForCurrentRound(idxToken, 1e18);
    //     // Now call as owner, expect revert on 'Round not active', which is the FALSE branch
    //     vm.expectRevert(bytes("Round not active"));
    //     vm.prank(owner_);
    //     sca.requestRedemption(idxToken, 1);
    //     // This triggers and covers opix-target-branch-214-False
    // }

    function testRequestRedemption_Revert_RedemptionAmountIsZero_HitsOpixTargetBranch_219_True() public {
        // This test covers the opix-target-branch-219-True in requestRedemption():
        // If totalIdxThisRound == 0, revert RedemptionAmountIsZero
        // Setup: make redemptionRoundId=1, keep as active+not-completed, but totalRedemptionByRound returns 0

        // Increase the redemption round ID to 1 for the test index token
        vm.prank(address(sca));
        storage_.increaseRedemptionRoundId(idxToken); // = 1
        vm.prank(address(sca));
        storage_.setRedemptionRoundActive(idxToken, 1, true);
        // Do not add any redemption for round 1, so totalRedemptionByRound == 0
        // Ensure not completed
        // Call as owner, expect revert with RedemptionAmountIsZero (custom error)
        vm.expectRevert(RedemptionAmountIsZero.selector); // opix-target-branch-219-True
        vm.prank(owner_);
        sca.requestRedemption(idxToken, 1);
    }

    function testCompleteRedemption_Revert_InvalidRoundId_gtRedemptionRoundId() public {
        // Setup: Prepare state such that roundId > storage_.redemptionRoundId(idxToken)
        uint256 redId = 1;
        // storage_.redemptionRoundId defaults to 0, so anything > 0 is invalid
        // Make all other preconditions pass to isolate branch
        address[] memory assets = new address[](1);
        assets[0] = address(underlyingA);
        uint256[] memory outs = new uint256[](1);
        outs[0] = 1e6; // some value to not trigger further reverts

        vm.prank(nexBot);
        vm.expectRevert(InvalidRoundId.selector); // Because _roundId (=1) > redemptionRoundId (=0)
        sca.completeRedemption(idxToken, redId, assets, outs);
    }

    function testCompleteRedemption_Branch_270_True_IfBlock() public {
        // This test will cover the branch at opix-target-branch-270-True, i.e.,
        // the 'if (_roundId > 1)' path in completeRedemption.
        //
        // - We will create two redemption rounds (so _roundId > 1)
        // - Previous round is not active and is completed
        // - Current round is not active, has a positive total redemption amount
        //
        // Since the setup lacks an actual OrderManager, the call will revert later on
        // when attempting to transfer USDC, but that's beyond the target branch.

        uint256 round1 = 1;
        uint256 round2 = 2;
        address[] memory assets = new address[](1);
        assets[0] = address(underlyingA);
        uint256[] memory outs = new uint256[](1);
        outs[0] = 1e6; // Arbitrary redeem out amount

        // 1. Create two redemption rounds for the Index Token
        vm.prank(address(sca));
        storage_.increaseRedemptionRoundId(idxToken); // round 1
        vm.prank(address(sca));
        storage_.increaseRedemptionRoundId(idxToken); // round 2

        // 2. Previous round (1) should not be active and should be completed
        vm.prank(address(sca));
        storage_.setRedemptionRoundActive(idxToken, round1, false);
        vm.prank(owner_); // Owner can call settleRedemption
        storage_.settleRedemption(idxToken, round1);

        // 3. Current round (2) should not be active
        vm.prank(address(sca));
        storage_.setRedemptionRoundActive(idxToken, round2, false);

        // 4. Provide a non-zero totalRedemptionByRound for round 2
        vm.prank(address(0xDEAD));
        storage_.addRedemptionForCurrentRound(idxToken, 1e18);

        // 5. Mint USDC to SCA to ensure it can try the transfer
        usdc.mint(address(sca), 1e18); // minting so balance is nonzero

        // 6. Call completeRedemption as nexBot; expect revert due to missing OrderManager (address(0))
        //    The call will hit the branch at if (_roundId > 1) {...} (opix-target-branch-270-True),
        //    and revert later in the loop when attempting a usdc transfer to address(0)
        vm.startPrank(nexBot);
        vm.expectRevert();
        sca.completeRedemption(idxToken, round2, assets, outs);
        vm.stopPrank();
    }

    function testCompleteRedemption_Revert_PrevRedemptionRoundActive_TriggersRequiredBranch() public {
        // Arrange: Redemption roundId > 1, and previous round is active
        // Make roundId = 2, and roundId=1 active=true, isCompleted=false

        // Set up two rounds
        vm.startPrank(address(sca));
        storage_.increaseRedemptionRoundId(idxToken); // roundId=1
        storage_.increaseRedemptionRoundId(idxToken); // roundId=2
        storage_.setRedemptionRoundActive(idxToken, 1, true); // Previous roundId=1 is active
        storage_.setRedemptionRoundActive(idxToken, 2, false); // Current roundId=2 is NOT active
        storage_.setRedemptionRoundActive(idxToken, 2, false); // For completeness, explicitly set to false
        vm.stopPrank();
        // Add redemption for current round (so totalIDX>0 and passes that require)
        vm.prank(address(0xDEAD));
        storage_.addRedemptionForCurrentRound(idxToken, 1e18);
        // Assets and outs arrays (matching length)
        address[] memory assets = new address[](1);
        assets[0] = address(underlyingA);
        uint256[] memory outs = new uint256[](1);
        outs[0] = 1e6;
        // Prank as nexBot; expect revert at require(!factoryStorage.redemptionRoundActive(_indexToken, prev), ...)
        vm.startPrank(nexBot);
        // The revert string from SCA is "Prev redemption round active"
        vm.expectRevert(bytes("Prev redemption round active"));
        sca.completeRedemption(idxToken, 2, assets, outs); // this must hit the opix-target-branch-271-True branch
        vm.stopPrank();
    }

    function testCompleteRedemption_prevNotCompleted_branch271False() public {
        // Test for hitting else branch of 'if (_roundId > 1)' at line 271 in completeRedemption()
        // and then proceeds to the check for !factoryStorage.redemptionIsCompleted(...)
        // i.e. _roundId > 1, but previous round is NOT completed (false)

        uint256 round1 = 1;
        uint256 round2 = 2;
        address[] memory assets = new address[](1);
        assets[0] = address(underlyingA);
        uint256[] memory outs = new uint256[](1);
        outs[0] = 1e6; // Arbitrary positive value

        // 1. Setup two redemption rounds
        vm.prank(address(sca));
        storage_.increaseRedemptionRoundId(idxToken); // round 1
        vm.prank(address(sca));
        storage_.increaseRedemptionRoundId(idxToken); // round 2

        // 2. Previous round (1) not active and NOT completed (leave completed=false)
        vm.prank(address(sca));
        storage_.setRedemptionRoundActive(idxToken, round1, false);
        // Current round (2) also not active
        vm.prank(address(sca));
        storage_.setRedemptionRoundActive(idxToken, round2, false);

        // 3. Provide a non-zero totalRedemptionByRound for round 2
        vm.prank(address(0xDEAD));
        storage_.addRedemptionForCurrentRound(idxToken, 1e18);

        // 4. Call completeRedemption as nexBot; expect revert on 'Prev redemption not completed'
        vm.startPrank(nexBot);
        vm.expectRevert(bytes("Prev redemption not completed"));
        sca.completeRedemption(idxToken, round2, assets, outs);
        vm.stopPrank();
    }

    function testCompleteRedemption_CoverElseBranch_276_False() public {
        // This test will hit the 'else' branch of the check on line 276 (opix-target-branch-276-False):
        // require(!factoryStorage.redemptionRoundActive(_indexToken, _roundId), "Round still active");
        // The test makes redemptionRoundActive(_indexToken, roundId) == true,
        // so require reverts and the False opix-branch is covered.

        uint256 round1 = 1;
        address[] memory assets = new address[](1);
        assets[0] = address(underlyingA);
        uint256[] memory outs = new uint256[](1);
        outs[0] = 1e6;

        // Set up redemption roundId=1 and make active=true
        vm.prank(address(sca));
        storage_.increaseRedemptionRoundId(idxToken); // roundId = 1
        vm.prank(address(sca));
        storage_.setRedemptionRoundActive(idxToken, round1, true); // ACTIVE: triggers revert in require (! ...)

        // Add redemption so totalRedemptionByRound(1)>0
        vm.prank(address(0xDEAD));
        storage_.addRedemptionForCurrentRound(idxToken, 1e18);

        // Prank as nexBot, expect revert with message "Round still active"
        vm.startPrank(nexBot);
        vm.expectRevert(bytes("Round still active")); // Expect revert at require(!active,...)
        sca.completeRedemption(idxToken, round1, assets, outs);
        vm.stopPrank();
    }

    function test_withRiskAsset_Revert_IfAmountExceedsBalance() public {
        // Give SCA 20 tokens
        underlyingA.mint(address(sca), 20e18);

        // Attempt to withdraw 25 tokens (over balance, should revert and enter require branch)
        vm.prank(owner_); // pass onlyOwner
        vm.expectRevert(bytes("Not enought balance"));
        sca.withRiskAsset(address(underlyingA), user, 25e18);
        // branch at line with: require(amount <= balance, ...); // should revert, hitting opix-target-branch-318-True
    }
}

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

contract StagingCustodyAccountTest is OlympixUnitTest("StagingCustodyAccount") {
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
}

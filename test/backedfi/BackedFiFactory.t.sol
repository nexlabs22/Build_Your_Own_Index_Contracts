// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {BackedFiFactory} from "../../src/backedfi/BackedFiFactory.sol";
import {IndexFactoryStorage} from "../../src/backedfi/IndexFactoryStorage.sol";
import {StagingCustodyAccount} from "../../src/backedfi/StagingCustodyAccount.sol";
import {FunctionsOracle} from "../../src/oracle/FunctionsOracle.sol";
import {TestERC20} from "../utils/TestERC20.sol";
import "../OlympixUnitTest.sol";

error ZeroAmount();

contract BackedFiFactoryTest is OlympixUnitTest("BackedFiFactory") {
    address owner_ = address(0xA11CE);
    address user = address(0xBEEF);
    address feeVault = address(0xFEE);
    address nexBot = address(0xB07);

    TestERC20 usdc;
    TestERC20 indexToken;

    BackedFiFactory backedFiImpl;
    IndexFactoryStorage storageImpl;
    StagingCustodyAccount scaImpl;

    BackedFiFactory backedFi;
    IndexFactoryStorage storage_;
    StagingCustodyAccount sca;

    FunctionsOracle oracle;

    function setUp() public {
        vm.startPrank(owner_);

        usdc = new TestERC20("USD Coin", "USDC");
        indexToken = new TestERC20("Index", "IDX");

        usdc.mint(user, 1_000_000e18);
        indexToken.mint(user, 100_000e18);

        oracle = new FunctionsOracle();

        storageImpl = new IndexFactoryStorage();
        scaImpl = new StagingCustodyAccount();
        backedFiImpl = new BackedFiFactory();

        storage_ = IndexFactoryStorage(address(new ERC1967Proxy(address(storageImpl), "")));
        sca = StagingCustodyAccount(address(new ERC1967Proxy(address(scaImpl), "")));
        backedFi = BackedFiFactory(address(new ERC1967Proxy(address(backedFiImpl), "")));

        storage_.initialize(address(0xDEAD), address(oracle), address(sca), nexBot, address(usdc));

        sca.initialize(address(storage_));

        backedFi.initialize(address(storage_), feeVault);

        storage_.setIndexFactory(address(backedFi));

        vm.stopPrank();
    }

    function testInitialize_RevertsOnZeroArgs() public {
        vm.startPrank(owner_);
        BackedFiFactory impl = new BackedFiFactory();
        BackedFiFactory proxy = BackedFiFactory(address(new ERC1967Proxy(address(impl), "")));

        vm.expectRevert(bytes("Invalid Address"));
        proxy.initialize(address(0), feeVault);

        vm.expectRevert(bytes("Invalid FeeVault"));
        proxy.initialize(address(storage_), address(0));
        vm.stopPrank();
    }

    function testIssuance_Success_TransfersUSDC_Emits_IncrementsNonce() public {
        uint256 amount = 5_000e18;

        vm.startPrank(user);
        usdc.approve(address(backedFi), type(uint256).max);

        vm.expectEmit(true, true, true, true);
        emit BackedFiFactory.RequestIssuance(
            address(indexToken),
            storage_.issuanceRoundId(address(indexToken)),
            1,
            user,
            address(usdc),
            amount,
            block.timestamp
        );

        uint256 nonce = backedFi.issuanceIndexTokens(address(indexToken), amount);
        vm.stopPrank();

        assertEq(nonce, 1, "issuance nonce mismatch");

        assertEq(usdc.balanceOf(user), 1_000_000e18 - amount, "user USDC debited");
        assertEq(usdc.balanceOf(address(sca)), amount, "SCA credited USDC");
    }

    function testIssuance_RevertsOnZeroAmount() public {
        vm.startPrank(user);
        vm.expectRevert(ZeroAmount.selector);
        backedFi.issuanceIndexTokens(address(indexToken), 0);
        vm.stopPrank();
    }

    function testRedemption_Success_TransfersIDX_Emits_IncrementsNonce() public {
        uint256 amount = 2_500e18;
        uint256 burnPct = 123_456_789_000_000_000;

        vm.startPrank(user);
        indexToken.approve(address(backedFi), type(uint256).max);

        vm.expectEmit(true, true, true, true);
        emit BackedFiFactory.RequestRedemption(
            address(indexToken),
            storage_.redemptionRoundId(address(indexToken)),
            1,
            user,
            address(usdc),
            amount,
            block.timestamp
        );

        uint256 nonce = backedFi.redemption(address(indexToken), amount, burnPct);
        vm.stopPrank();

        assertEq(nonce, 1, "redemption nonce mismatch");

        assertEq(indexToken.balanceOf(user), 100_000e18 - amount, "user IDX debited");
        assertEq(indexToken.balanceOf(address(sca)), amount, "SCA credited IDX");
    }

    function testRedemption_RevertsOnZeroAmount() public {
        vm.startPrank(user);
        vm.expectRevert(ZeroAmount.selector);
        backedFi.redemption(address(indexToken), 0, 0);
        vm.stopPrank();
    }
}

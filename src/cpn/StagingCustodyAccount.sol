// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {IndexFactory} from "../factory/IndexFactory.sol";
import {IndexToken} from "../token/IndexToken.sol";
import {IndexFactoryStorage} from "./IndexFactoryStorage.sol";
import {FunctionsOracle} from "../oracle/FunctionsOracle.sol";
import {FeeCalculation} from "../libraries/FeeCalculation.sol";
import {Vault} from "../vault/Vault.sol";
import {OrderManager} from "../orderManager/OrderManager.sol";

error ZeroAmount();
error ZeroAddress();
error InvalidRoundId();
error WrongETHAmount();
error RedemptionAmountIsZero();

contract StagingCustodyAccount is Initializable, ReentrancyGuardUpgradeable, OwnableUpgradeable {
    using SafeERC20 for IERC20;

    IndexFactoryStorage factoryStorage;
    FunctionsOracle functionsOracle;
    OrderManager orderManager;
    IndexFactory indexFactory;

    address public nexBot;

    event WithdrawnForPurchase(uint256 indexed roundId, uint256 indexed amount, uint256 indexed timestamp);
    event Refunded(uint256 indexed roundId, address indexed to, uint256 indexed amount, uint256 timestamp);
    event RedemptionSettled(uint256 indexed roundId, uint256 indexed amount, uint256 timestamp);
    event IssuanceSettled(uint256 indexed roundId, uint256 indexed usdcAmount, uint256 timestamp);
    event RedemptionRequested(uint256 indexed totalIdx, uint256 indexed totalBond, uint256 timestamp);
    event IssuanceRequested(uint256 indexed usdcForBond, uint256 timestamp);
    event IssuanceCompleted(address indexed user, uint256 indexed amount, uint256 timestamp);
    event RedemptionCompleted(address indexed user, uint256 indexed amount, uint256 timestamp);

    modifier onlyOwnerOrOperator() {
        require(
            msg.sender == owner() || functionsOracle.isOperator(msg.sender) || msg.sender == nexBot,
            "Caller is not the owner or operator"
        );
        _;
    }

    modifier onlyNexBot() {
        require(msg.sender == nexBot, "Caller is not the NEX bot");
        _;
    }

    function initialize(address _indexFactoryStorageAddress) external initializer {
        if (_indexFactoryStorageAddress == address(0)) revert ZeroAddress();

        factoryStorage = IndexFactoryStorage(_indexFactoryStorageAddress);
        nexBot = factoryStorage.nexBot();

        __ReentrancyGuard_init();
        __Ownable_init(msg.sender);
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function setNexBotAddress(address _newNexBotAddress) external onlyOwner {
        if (_newNexBotAddress == address(0)) revert ZeroAddress();
        nexBot = _newNexBotAddress;
    }

    function setIndexFactoryStorageAddress(address _newIndexFactoryStorageAddress) external onlyOwner {
        if (_newIndexFactoryStorageAddress == address(0)) revert ZeroAddress();
        factoryStorage = IndexFactoryStorage(_newIndexFactoryStorageAddress);
    }

    /// @notice Withdraw USDC for bond purchase; only active, unsettled rounds
    function withdrawForPurchase(uint256 roundId, uint256 amount) public onlyOwnerOrOperator nonReentrant {
        if (amount == 0) revert ZeroAmount();
        uint256 balance = IERC20(factoryStorage.usdc()).balanceOf(address(this));
        require(balance >= amount, "Insufficient USDC balance");
        IERC20(factoryStorage.usdc()).safeTransfer(nexBot, amount);
        emit WithdrawnForPurchase(roundId, amount, block.timestamp);
    }

    function requestIssuance(address indexToken, uint256 roundId) public payable onlyOwnerOrOperator {
        if (roundId < 1 || roundId > factoryStorage.issuanceRoundId(indexToken)) revert InvalidRoundId();
        uint256 prev = roundId - 1;
        if (roundId > 1) {
            require(!factoryStorage.issuanceRoundActive(indexToken, prev), "Prev round still active");
            require(factoryStorage.issuanceIsCompleted(indexToken, prev), "Prev round not completed");
        }
        require(factoryStorage.issuanceRoundActive(indexToken, roundId), "Round is not active");
        require(!factoryStorage.issuanceIsCompleted(indexToken, roundId), "Round already completed");

        uint256 balance = factoryStorage.totalIssuanceByRound(indexToken, roundId);
        require(balance > 0, "Total issuance in this round is Zero!");

        if (balance > 0) {
            withdrawForPurchase(roundId, balance);
        }

        factoryStorage.setIssuanceRoundActive(indexToken, roundId, false);
        factoryStorage.increaseIssuanceRoundId(indexToken);

        emit IssuanceRequested(balance, block.timestamp);
    }

    function completeIssuance(
        address indexToken,
        uint256 roundId,
        address[] memory underlyingAssets,
        uint256[] memory prices
    ) external onlyNexBot {
        uint256[] memory nonces = factoryStorage.getIssuanceRoundIdToNonces(indexToken, roundId);
        require(nonces.length > 0, "No issuance requests");
        address vault = factoryStorage.indexTokenToVault(indexToken);

        if (roundId > factoryStorage.issuanceRoundId(indexToken)) revert InvalidRoundId();
        if (roundId < 1 || roundId > factoryStorage.issuanceRoundId(indexToken)) revert InvalidRoundId();
        uint256 prev = roundId - 1;
        if (roundId > 1) {
            require(!factoryStorage.issuanceRoundActive(indexToken, prev), "Prev round still active");
            require(factoryStorage.issuanceIsCompleted(indexToken, prev), "Prev round not completed");
        }
        require(!factoryStorage.issuanceRoundActive(indexToken, roundId), "Round is active");
        require(!factoryStorage.issuanceIsCompleted(indexToken, roundId), "Round already completed");

        // address[] memory currentList = factoryStorage.functionsOracle().currentList();
        uint256 oldValue = factoryStorage.getPortfolioValue(indexToken, underlyingAssets, prices);
        for (uint256 i; i < factoryStorage.functionsOracle().totalCurrentList(indexToken); i++) {
            address tokenAddress = factoryStorage.functionsOracle().currentList(indexToken, i);
            uint256 balance = IERC20(tokenAddress).balanceOf(address(this));
            IERC20(tokenAddress).safeTransfer(address(vault), balance);
        }
        uint256 newValue = factoryStorage.getPortfolioValue(indexToken, underlyingAssets, prices);

        uint256 total = factoryStorage.totalIssuanceByRound(indexToken, roundId);
        require(total > 0, "Nothing to distribute");

        orderManager.completeIssuance(indexFactory.issuanceNonce(), indexToken, underlyingAssets, oldValue, newValue);

        factoryStorage.settleIssuance(indexToken, roundId);
        emit IssuanceSettled(roundId, total, block.timestamp);
    }

    function requestRedemption(address indexToken, uint256 roundId, uint256 burnPercent)
        external
        payable
        nonReentrant
        onlyOwnerOrOperator
    {
        if (roundId < 1 || roundId > factoryStorage.redemptionRoundId(indexToken)) revert InvalidRoundId();
        uint256 prev = roundId - 1;
        if (roundId > 1) {
            require(!factoryStorage.redemptionRoundActive(indexToken, prev), "Prev redemption round active");
            require(factoryStorage.redemptionIsCompleted(indexToken, prev), "Prev redemption not completed");
        }
        require(factoryStorage.redemptionRoundActive(indexToken, roundId), "Round not active");
        require(!factoryStorage.redemptionIsCompleted(indexToken, roundId), "Round already completed");

        // uint256 totalIdxThisRound = factoryStorage.totalRedemptionByIndexTokenRound(indexToken, roundId);
        uint256 totalIdxThisRound = factoryStorage.totalRedemptionByRound(indexToken, roundId);
        if (totalIdxThisRound == 0) revert RedemptionAmountIsZero();
        if (!factoryStorage.redemptionRoundActive(indexToken, roundId)) {
            revert("batch not started");
        }
        factoryStorage.setRedemptionRoundActive(indexToken, roundId, false);

        uint256 supplyBefore = IERC20(indexToken).totalSupply();
        require(supplyBefore > totalIdxThisRound, "IDX supply is zero");
        // uint256 pct1e18 = (totalIdxThisRound * 1e18) / supplyBefore;

        uint256 currentList = functionsOracle.totalCurrentList(indexToken);
        uint256 bondSliceTotal;
        for (uint256 i = 0; i < currentList; ++i) {
            address token = factoryStorage.functionsOracle().currentList(indexToken, i);
            uint256 slice = IERC20(token).balanceOf(address(factoryStorage.vault())) * burnPercent / 1e18;

            if (slice == 0) continue;

            factoryStorage.vault().withdrawFunds(token, address(this), slice);
            IERC20(token).safeTransfer(nexBot, slice);

            // bondSliceTotal += slice;
        }

        // if (bondSliceTotal > 0) {
        //     IERC20(bond).safeTransfer(nexBot, bondSliceTotal);
        // }

        factoryStorage.increaseRedemptionRoundId(indexToken);
        factoryStorage.setRedemptionRoundActive(indexToken, factoryStorage.redemptionRoundId(indexToken), false);

        emit RedemptionRequested(totalIdxThisRound, bondSliceTotal, block.timestamp);
    }

    function completeRedemption(address indexToken, uint256 roundId, uint256 usdcFromBond) external onlyNexBot {
        uint256[] memory nonces = factoryStorage.getRedemptionRoundIdToNonces(indexToken, roundId);
        require(nonces.length > 0, "No redemption requests");

        if (roundId < 1 || roundId > factoryStorage.redemptionRoundId(indexToken)) revert InvalidRoundId();
        uint256 prev = roundId - 1;
        if (roundId > 1) {
            require(!factoryStorage.redemptionRoundActive(indexToken, prev), "Prev redemption round active");
            require(factoryStorage.redemptionIsCompleted(indexToken, prev), "Prev redemption not completed");
        }
        require(!factoryStorage.redemptionRoundActive(indexToken, roundId), "Round still active");
        require(!factoryStorage.redemptionIsCompleted(indexToken, roundId), "Round already completed");

        uint256 totalIDX = factoryStorage.totalRedemptionByRound(indexToken, roundId);
        require(totalIDX > 0, "No tokens to redeem");

        // if (usdcFromBond > 0) {
        //     factoryStorage.usdc().safeTransferFrom(msg.sender, address(this), usdcFromBond);
        // }

        uint256 totalUSDC = usdcFromBond;
        require(totalUSDC > 0, "zero USDC received");

        uint256 feeAmount = FeeCalculation.calculateFee(totalUSDC, factoryStorage.feeRate());
        uint256 usdcForDistribute = totalUSDC - feeAmount;

        address[] memory users = factoryStorage.addressesInRedemptionRound(roundId);
        uint256 paid;

        for (uint256 i; i < users.length; ++i) {
            address user = users[i];
            uint256 idxShare = factoryStorage.redemptionAmountByRoundUser(roundId, user);
            uint256 owed = usdcForDistribute * idxShare / totalIDX;

            if (owed > 0) {
                factoryStorage.usdc().safeTransfer(user, owed);
                paid += owed;
            }

            emit RedemptionCompleted(user, owed, block.timestamp);
        }

        uint256 dust = usdcForDistribute - paid;
        if (dust > 0) factoryStorage.usdc().safeTransfer(factoryStorage.feeReceiver(), dust);
        factoryStorage.usdc().safeTransfer(factoryStorage.feeReceiver(), feeAmount);

        factoryStorage.settleRedemption(indexToken, roundId);
        emit RedemptionSettled(roundId, usdcForDistribute, block.timestamp);
    }

    function _distributeIssuance(uint256 roundId, uint256 mintAmt, uint256 totalUsdc)
        internal
        returns (uint256 distributed)
    {
        address[] memory users = factoryStorage.addressesInIssuanceRound(roundId);
        for (uint256 i; i < users.length; ++i) {
            address user = users[i];
            uint256 userAmt = factoryStorage.issuanceAmountByRoundUser(roundId, user);
            uint256 owed = (mintAmt * userAmt) / totalUsdc;
            if (owed > 0) {
                factoryStorage.indexToken().transfer(user, owed);
                distributed += owed;
            }
            emit IssuanceCompleted(user, userAmt, block.timestamp);
        }
    }

    function withRiskAsset(address token, address to, uint256 amount) public onlyOwner {
        uint256 balance = IERC20(token).balanceOf(address(this));
        require(amount <= balance, "Not enought balance");
        IERC20(token).safeTransfer(to, amount);
    }
}

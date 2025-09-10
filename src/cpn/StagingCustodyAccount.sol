// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {IRiskAssetFactory} from "./interfaces/IRiskAssetFactory.sol";
import {IndexFactory} from "../factory/IndexFactory.sol";
import {IndexToken} from "../token/IndexToken.sol";
import {IndexFactoryStorage} from "./IndexFactoryStorage.sol";
import {FunctionsOracle} from "./FunctionsOracle.sol";
import {FeeCalculation} from "../libraries/FeeCalculation.sol";
import {Vault} from "../vault/Vault.sol";

error ZeroAmount();
error ZeroAddress();
error InvalidRoundId();
error WrongETHAmount();
error RedemptionAmountIsZero();

contract StagingCustodyAccount is Initializable, ReentrancyGuardUpgradeable, OwnableUpgradeable {
    using SafeERC20 for IERC20;

    IndexFactoryStorage factoryStorage;
    FunctionsOracle functionsOracle;

    address public riskAssetFactoryAddress;
    address public nexBot;
    address public bond;

    event Rescue(address indexed token, address indexed to, uint256 amount, uint256 indexed timestamp);
    event WithdrawnForPurchase(uint256 indexed roundId, uint256 indexed amount, uint256 indexed timestamp);
    event Refunded(uint256 indexed roundId, address indexed to, uint256 indexed amount, uint256 timestamp);
    event IssuanceRiskAsset(uint256 indexed amount, uint256 timestamp);
    event RedemptionRiskAsset(uint256 indexed amount, uint256 timestamp);
    event RedemptionSettled(uint256 indexed roundId, uint256 indexed amount, uint256 timestamp);
    event IssuanceSettled(
        uint256 indexed roundId,
        uint256 indexed indexTokenAmount,
        uint256 indexTokenDistributed,
        uint256 indexed usdcAmount,
        uint256 timestamp
    );
    event RedemptionRequested(
        uint256 indexed totalIdx, uint256 indexed totalBond, uint256 indexed totalRiskAsset, uint256 timestamp
    );
    event IssuanceRequested(uint256 indexed usdcForBond, uint256 indexed usdcForRiskAsset, uint256 timestamp);
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
        // require(_indexFactoryStorageAddress != address(0), "Invalid address for _indexFactoryStorageAddress");
        if (_indexFactoryStorageAddress == address(0)) revert ZeroAddress();

        factoryStorage = IndexFactoryStorage(_indexFactoryStorageAddress);
        nexBot = factoryStorage.nexBot();
        riskAssetFactoryAddress = factoryStorage.riskAssetFactoryAddress();
        bond = factoryStorage.bond();

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

    function setRiskAssetFactoryAddress(address _newRiskAssetFactoryAddress) external onlyOwner {
        if (_newRiskAssetFactoryAddress == address(0)) revert ZeroAddress();
        riskAssetFactoryAddress = _newRiskAssetFactoryAddress;
    }

    function setBondAddress(address _newsetBondAddress) external onlyOwner {
        if (_newsetBondAddress == address(0)) revert ZeroAddress();
        bond = _newsetBondAddress;
    }

    function setIndexFactoryStorageAddress(address _newIndexFactoryStorageAddress) external onlyOwner {
        if (_newIndexFactoryStorageAddress == address(0)) revert ZeroAddress();
        factoryStorage = IndexFactoryStorage(_newIndexFactoryStorageAddress);
    }

    /// @notice Withdraw USDC for bond purchase; only active, unsettled rounds
    function withdrawForPurchase(uint256 roundId, uint256 amount) public onlyOwnerOrOperator nonReentrant {
        require(
            factoryStorage.issuanceRoundActive(roundId) && !factoryStorage.issuanceIsCompleted(roundId),
            "Round not open"
        );
        require(factoryStorage.totalIssuanceByRound(roundId) > 0, "Nothing to withdraw");
        if (amount == 0) revert ZeroAmount();
        uint256 balance = IERC20(factoryStorage.usdc()).balanceOf(address(this));
        require(balance >= amount, "Insufficient USDC balance");
        IERC20(factoryStorage.usdc()).safeTransfer(nexBot, amount);
        emit WithdrawnForPurchase(roundId, amount, block.timestamp);
    }

    function rescue(address token, address to, uint256 amount) external onlyOwnerOrOperator {
        if (token == address(0) || to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        IERC20(token).safeTransfer(to, amount);
        emit Rescue(token, to, amount, block.timestamp);
    }

    function refund(uint256 roundId, address to, uint256 amount) external onlyOwnerOrOperator {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        IERC20(factoryStorage.usdc()).safeTransfer(to, amount);
        emit Refunded(roundId, to, amount, block.timestamp);
    }

    function issuanceRiskAsset(uint256 usdcAmount, address[] calldata _tokenInPath, uint24[] calldata _tokenInFees)
        public
        payable
        onlyOwnerOrOperator
    {
        uint256 expected =
            factoryStorage.getIssuanceFee(address(factoryStorage.usdc()), _tokenInPath, _tokenInFees, usdcAmount);
        if (msg.value < expected) revert WrongETHAmount();
        uint256 usdcFee = FeeCalculation.calculateFee(usdcAmount, factoryStorage.feeRate());

        factoryStorage.usdc().approve(riskAssetFactoryAddress, usdcAmount + usdcFee);
        IRiskAssetFactory(riskAssetFactoryAddress).issuanceIndexTokens{value: msg.value}(
            address(factoryStorage.usdc()), _tokenInPath, _tokenInFees, usdcAmount
        );
        // IRiskAssetFactory(riskAssetFactoryAddress).issuanceIndexTokens{value: msg.value}(
        //     address(factoryStorage.usdc()), _tokenInPath, _tokenInFees, usdcAmount
        // );
        emit IssuanceRiskAsset(usdcAmount, block.timestamp);
    }

    function redemptionRiskAsset(
        uint256 amountIn,
        address _tokenOut,
        address[] memory _tokenOutPath,
        uint24[] memory _tokenOutFees
    ) public payable onlyOwnerOrOperator {
        uint256 expected = factoryStorage.getRedemptionFee(amountIn);
        if (msg.value < expected) revert WrongETHAmount();
        factoryStorage.usdc().approve(riskAssetFactoryAddress, amountIn);
        IRiskAssetFactory(riskAssetFactoryAddress).redemption{value: msg.value}(
            amountIn, _tokenOut, _tokenOutPath, _tokenOutFees
        );
        emit RedemptionRiskAsset(amountIn, block.timestamp);
    }

    function requestIssuance(uint256 roundId, address[] calldata _tokenInPath, uint24[] calldata _tokenInFees)
        public
        payable
        onlyOwnerOrOperator
    {
        if (roundId < 1 || roundId > factoryStorage.issuanceRoundId()) revert InvalidRoundId();
        uint256 prev = roundId - 1;
        if (roundId > 1) {
            require(!factoryStorage.issuanceRoundActive(prev), "Prev round still active");
            require(factoryStorage.issuanceIsCompleted(prev), "Prev round not completed");
        }
        require(factoryStorage.issuanceRoundActive(roundId), "Round is not active");
        require(!factoryStorage.issuanceIsCompleted(roundId), "Round already completed");

        // uint256 balance = factoryStorage.usdc().balanceOf(address(this));
        // require(balance > 0, "USDC Balance is Zero!");

        uint256 balance = factoryStorage.totalIssuanceByRound(roundId);
        require(balance > 0, "Total issuance in this round is Zero!");

        uint256 usdcAmountForBond;
        uint256 usdcAmountForRiskAsset;

        for (uint256 i; i < factoryStorage.functionsOracle().totalCurrentList(); ++i) {
            address token = factoryStorage.functionsOracle().currentList(i);
            uint256 share = factoryStorage.functionsOracle().tokenCurrentMarketShare(token);
            uint256 slice = (balance * share) / 100e18;

            if (factoryStorage.functionsOracle().tokenAssetType(token) == 1) {
                usdcAmountForRiskAsset += slice;
            } else {
                usdcAmountForBond += slice;
            }
        }

        // uint256 dust = balance - usdcAmountForRiskAsset - usdcAmountForBond;
        // if (dust > 0) usdcAmountForBond += dust;

        if (usdcAmountForRiskAsset > 0) {
            uint256 fee = factoryStorage.getIssuanceFee(
                address(factoryStorage.usdc()), _tokenInPath, _tokenInFees, usdcAmountForRiskAsset
            );
            if (msg.value < fee) revert WrongETHAmount();
            uint256 usdcFee = FeeCalculation.calculateFee(usdcAmountForRiskAsset, factoryStorage.feeRate());
            issuanceRiskAsset(usdcAmountForRiskAsset - usdcFee, _tokenInPath, _tokenInFees);
        } else {
            require(msg.value == 0, "SCA: unexpected ETH");
        }

        if (usdcAmountForBond > 0) {
            withdrawForPurchase(roundId, usdcAmountForBond);
        }

        factoryStorage.setIssuanceRoundActive(roundId, false);
        factoryStorage.increaseIssuanceRoundId();

        emit IssuanceRequested(usdcAmountForBond, usdcAmountForRiskAsset, block.timestamp);
    }

    function completeIssuance(uint256 roundId, uint256 bondPrice, uint256 riskAssetPrice) external onlyNexBot {
        uint256[] memory nonces = factoryStorage.getIssuanceRoundIdToNonces(roundId);
        require(nonces.length > 0, "No issuance requests");

        if (roundId > factoryStorage.issuanceRoundId()) revert InvalidRoundId();
        if (roundId < 1 || roundId > factoryStorage.issuanceRoundId()) revert InvalidRoundId();
        uint256 prev = roundId - 1;
        if (roundId > 1) {
            require(!factoryStorage.issuanceRoundActive(prev), "Prev round still active");
            require(factoryStorage.issuanceIsCompleted(prev), "Prev round not completed");
        }
        require(!factoryStorage.issuanceRoundActive(roundId), "Round is active");
        require(!factoryStorage.issuanceIsCompleted(roundId), "Round already completed");

        uint256 oldValue = factoryStorage.getPortfolioValue(bondPrice, riskAssetPrice);
        for (uint256 i; i < factoryStorage.functionsOracle().totalCurrentList(); i++) {
            address tokenAddress = factoryStorage.functionsOracle().currentList(i);
            uint256 balance = IERC20(tokenAddress).balanceOf(address(this));
            IERC20(tokenAddress).safeTransfer(address(factoryStorage.vault()), balance);
        }

        uint256 newValue = factoryStorage.getPortfolioValue(bondPrice, riskAssetPrice);
        uint256 mintAmount = factoryStorage.calculateMintAmount(oldValue, newValue);
        if (mintAmount > 0) factoryStorage.indexToken().mint(address(this), mintAmount);

        uint256 total = factoryStorage.totalIssuanceByRound(roundId);
        require(total > 0, "Nothing to distribute");

        uint256 distributed = _distributeIssuance(roundId, mintAmount, total);

        uint256 remainder = mintAmount - distributed;
        if (remainder > 0) {
            factoryStorage.indexToken().transfer(factoryStorage.feeReceiver(), remainder);
        }

        factoryStorage.settleIssuance(roundId);
        emit IssuanceSettled(roundId, mintAmount, distributed, total, block.timestamp);
    }

    function requestRedemption(uint256 roundId, address[] calldata tokenOutPath, uint24[] calldata tokenOutFees)
        external
        payable
        nonReentrant
        onlyOwnerOrOperator
    {
        if (roundId < 1 || roundId > factoryStorage.redemptionRoundId()) revert InvalidRoundId();
        uint256 prev = roundId - 1;
        if (roundId > 1) {
            require(!factoryStorage.redemptionRoundActive(prev), "Prev redemption round active");
            require(factoryStorage.redemptionIsCompleted(prev), "Prev redemption not completed");
        }
        require(factoryStorage.redemptionRoundActive(roundId), "Round not active");
        require(!factoryStorage.redemptionIsCompleted(roundId), "Round already completed");

        uint256 totalIdxThisRound = factoryStorage.totalRedemptionByRound(roundId);
        if (totalIdxThisRound == 0) revert RedemptionAmountIsZero();
        if (!factoryStorage.redemptionRoundActive(roundId)) {
            revert("batch not started");
        }
        factoryStorage.setRedemptionRoundActive(roundId, false);

        uint256 supplyBefore = factoryStorage.indexToken().totalSupply();
        require(supplyBefore > totalIdxThisRound, "IDX supply is zero");
        uint256 pct1e18 = (totalIdxThisRound * 1e18) / supplyBefore;

        uint256 bondSliceTotal;
        uint256 riskSliceTotal;
        uint256 currentList = factoryStorage.functionsOracle().totalCurrentList();
        for (uint256 i = 0; i < currentList; ++i) {
            address token = factoryStorage.functionsOracle().currentList(i);
            uint8 aType = factoryStorage.functionsOracle().tokenAssetType(token);
            uint256 slice = IERC20(token).balanceOf(address(factoryStorage.vault())) * pct1e18 / 1e18;

            if (slice == 0) continue;

            factoryStorage.vault().withdrawFunds(token, address(this), slice);
            // factoryStorage.vault().withdrawFunds(token, factoryStorage.nexBot(), slice);

            if (aType == 1) {
                riskSliceTotal += slice;
            } else {
                bondSliceTotal += slice;
            }
        }

        if (riskSliceTotal > 0) {
            uint256 fee = factoryStorage.getRedemptionFee(riskSliceTotal);
            if (msg.value < fee) revert WrongETHAmount();
            redemptionRiskAsset(riskSliceTotal, address(factoryStorage.usdc()), tokenOutPath, tokenOutFees);
        }

        if (bondSliceTotal > 0) {
            IERC20(bond).safeTransfer(nexBot, bondSliceTotal);
        }

        factoryStorage.indexToken().burn(address(this), totalIdxThisRound);
        factoryStorage.increaseRedemptionRoundId();
        factoryStorage.setRedemptionRoundActive(factoryStorage.redemptionRoundId(), false);

        emit RedemptionRequested(totalIdxThisRound, bondSliceTotal, riskSliceTotal, block.timestamp);
    }

    function completeRedemption(uint256 roundId, uint256 usdcFromBond, uint256 usdcFromRiskAsset) external onlyNexBot {
        uint256[] memory nonces = factoryStorage.getRedemptionRoundIdToNonces(roundId);
        require(nonces.length > 0, "No redemption requests");

        if (roundId < 1 || roundId > factoryStorage.redemptionRoundId()) revert InvalidRoundId();
        uint256 prev = roundId - 1;
        if (roundId > 1) {
            require(!factoryStorage.redemptionRoundActive(prev), "Prev redemption round active");
            require(factoryStorage.redemptionIsCompleted(prev), "Prev redemption not completed");
        }
        require(!factoryStorage.redemptionRoundActive(roundId), "Round still active");
        require(!factoryStorage.redemptionIsCompleted(roundId), "Round already completed");

        uint256 totalIDX = factoryStorage.totalRedemptionByRound(roundId);
        require(totalIDX > 0, "No tokens to redeem");

        if (usdcFromBond > 0) {
            factoryStorage.usdc().safeTransferFrom(msg.sender, address(this), usdcFromBond);
        }

        uint256 totalUSDC = usdcFromBond + usdcFromRiskAsset;
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

        factoryStorage.settleRedemption(roundId);
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

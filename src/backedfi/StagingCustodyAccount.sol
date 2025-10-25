// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {IndexFactory} from "../factory/IndexFactory.sol";
import {IndexToken} from "../token/IndexToken.sol";
// import {IndexFactoryStorage} from "./IndexFactoryStorage.sol";
import {BackedFiStorage} from "./BackedFiStorage.sol";
import {FunctionsOracle} from "../oracle/FunctionsOracle.sol";
import {FeeCalculation} from "../libraries/FeeCalculation.sol";
import {Vault} from "../vault/Vault.sol";
import {OrderManager} from "../orderManager/OrderManager.sol";

error ZeroAmount();
error ZeroAddress();
error InvalidRoundId();
error WrongETHAmount();
error RedemptionAmountIsZero();
error UnauthorizedCaller();
error NotNexBot();
error InsufficientRoundBalance();
error PreviousRoundActive();
error PreviousRoundNotCompleted();
error RoundInactive();
error RoundAlreadyCompleted();
error NoIssuanceBalance();
error NoAssetsProvided();
error LengthMismatch();
error NothingToDistribute();
error RoundStillActive();
error IndexSupplyTooLow();
error NoTokensToRedeem();
error InsufficientTokenBalance();
error BatchNotStarted();

contract StagingCustodyAccount is Initializable, ReentrancyGuardUpgradeable, OwnableUpgradeable {
    using SafeERC20 for IERC20;

    // IndexFactoryStorage factoryStorage;
    BackedFiStorage backedFiStorage;
    FunctionsOracle functionsOracle;
    OrderManager orderManager;
    IndexFactory indexFactory;

    address public nexBot;

    event WithdrawnForPurchase(
        address indexed indexToken, uint256 indexed roundId, uint256 indexed amount, uint256 timestamp
    );
    event RedemptionSettled(
        address indexed indexToken, uint256 indexed roundId, uint256 indexed amount, uint256 timestamp
    );
    event IssuanceSettled(
        address indexed indexToken, uint256 indexed roundId, uint256 indexed usdcAmount, uint256 timestamp
    );
    event RedemptionRequested(
        address indexed indexToken, uint256 indexed totalIdx, uint256 indexed totalBond, uint256 timestamp
    );
    event IssuanceRequested(address indexed indexToken, uint256 indexed usdcForBond, uint256 timestamp);
    event IssuanceCompleted(
        address indexed indexToken, address indexed user, uint256 indexed amount, uint256 timestamp
    );
    event RedemptionCompleted(
        address indexed indexToken, address indexed user, uint256 indexed amount, uint256 timestamp
    );

    modifier onlyOwnerOrOperator() {
        // require(
        //     msg.sender == owner() || functionsOracle.isOperator(msg.sender) || msg.sender == nexBot,
        //     "Caller is not the owner or operator"
        // );
        if (msg.sender != owner() && !functionsOracle.isOperator(msg.sender) && msg.sender != nexBot) {
            revert UnauthorizedCaller();
        }
        _;
    }

    modifier onlyNexBot() {
        // require(msg.sender == nexBot, "Caller is not the NEX bot");
        if (msg.sender != nexBot) revert NotNexBot();
        _;
    }

    function initialize(address _backedFiStorageAddress) external initializer {
        if (_backedFiStorageAddress == address(0)) revert ZeroAddress();

        backedFiStorage = BackedFiStorage(_backedFiStorageAddress);
        nexBot = backedFiStorage.nexBot();

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

    function setBackedFiStorageAddress(address _newBackedFiStorageAddress) external onlyOwner {
        if (_newBackedFiStorageAddress == address(0)) revert ZeroAddress();
        backedFiStorage = BackedFiStorage(_newBackedFiStorageAddress);
    }

    /// @notice Withdraw USDC for bond purchase; only active, unsettled rounds
    function withdrawForPurchase(address _indexToken, uint256 _roundId) public onlyOwnerOrOperator nonReentrant {
        uint256 roundIdBalance = backedFiStorage.totalIssuanceByRound(_indexToken, _roundId);
        // require(roundIdBalance > 0, "Insufficient USDC balance");
        if (roundIdBalance == 0) revert InsufficientRoundBalance();
        IERC20(backedFiStorage.usdc()).safeTransfer(nexBot, roundIdBalance);
        emit WithdrawnForPurchase(_indexToken, _roundId, roundIdBalance, block.timestamp);
    }

    function requestIssuance(address _indexToken, uint256 _roundId) public payable onlyOwnerOrOperator {
        if (_roundId < 1 || _roundId > backedFiStorage.issuanceRoundId(_indexToken)) revert InvalidRoundId();
        uint256 prev = _roundId - 1;
        if (_roundId > 1) {
            // require(!backedFiStorage.issuanceRoundActive(_indexToken, prev), "Prev round still active");
            if (backedFiStorage.issuanceRoundActive(_indexToken, prev)) revert PreviousRoundActive();
            // require(backedFiStorage.issuanceIsCompleted(_indexToken, prev), "Prev round not completed");
            if (!backedFiStorage.issuanceIsCompleted(_indexToken, prev)) revert PreviousRoundNotCompleted();
        }
        // require(backedFiStorage.issuanceRoundActive(_indexToken, _roundId), "Round is not active");
        if (!backedFiStorage.issuanceRoundActive(_indexToken, _roundId)) revert RoundInactive();
        // require(!backedFiStorage.issuanceIsCompleted(_indexToken, _roundId), "Round already completed");
        if (backedFiStorage.issuanceIsCompleted(_indexToken, _roundId)) revert RoundAlreadyCompleted();

        uint256 roundIdBalance = backedFiStorage.totalIssuanceByRound(_indexToken, _roundId);
        // require(roundIdBalance > 0, "Total issuance in this round is Zero!");
        if (roundIdBalance == 0) revert NoIssuanceBalance();

        if (roundIdBalance > 0) {
            withdrawForPurchase(_indexToken, _roundId);
        }

        backedFiStorage.setIssuanceRoundActive(_indexToken, _roundId, false);
        backedFiStorage.increaseIssuanceRoundId(_indexToken);

        emit IssuanceRequested(_indexToken, roundIdBalance, block.timestamp);
    }

    function completeIssuance(
        address _indexToken,
        uint256 _roundId,
        address[] memory _underlyingAssets,
        uint256[] memory _prices
    ) external onlyNexBot {
        address vault = backedFiStorage.indexTokenToVault(_indexToken);
        if (vault == address(0)) revert ZeroAddress();

        if (_roundId > backedFiStorage.issuanceRoundId(_indexToken)) revert InvalidRoundId();
        if (_roundId < 1 || _roundId > backedFiStorage.issuanceRoundId(_indexToken)) revert InvalidRoundId();
        uint256 prev = _roundId - 1;
        if (_roundId > 1) {
            // require(!backedFiStorage.issuanceRoundActive(_indexToken, prev), "Prev round still active");
            if (backedFiStorage.issuanceRoundActive(_indexToken, prev)) revert PreviousRoundActive();
            // require(backedFiStorage.issuanceIsCompleted(_indexToken, prev), "Prev round not completed");
            if (!backedFiStorage.issuanceIsCompleted(_indexToken, prev)) revert PreviousRoundNotCompleted();
        }
        // require(!backedFiStorage.issuanceRoundActive(_indexToken, _roundId), "Round is active");
        if (backedFiStorage.issuanceRoundActive(_indexToken, _roundId)) revert RoundStillActive();
        // require(!backedFiStorage.issuanceIsCompleted(_indexToken, _roundId), "Round already completed");
        if (backedFiStorage.issuanceIsCompleted(_indexToken, _roundId)) revert RoundAlreadyCompleted();

        uint256 assetsCount = _underlyingAssets.length;
        // require(assetsCount > 0, "no assets");
        if (assetsCount == 0) revert NoAssetsProvided();
        // require(_prices.length == assetsCount, "length mismatch");
        if (_prices.length != assetsCount) revert LengthMismatch();

        for (uint256 i = 0; i < assetsCount;) {
            address tokenAddress = _underlyingAssets[i];
            uint256 price = _prices[i];

            uint256 oldValue = backedFiStorage.getTokenValue(_indexToken, tokenAddress, price);
            uint256 balance = IERC20(tokenAddress).balanceOf(address(this));
            if (balance != 0) {
                IERC20(tokenAddress).safeTransfer(vault, balance);
            }
            uint256 newValue = backedFiStorage.getTokenValue(_indexToken, tokenAddress, price);
            backedFiStorage.indexFactory()
                .handleCompleteIssuance(
                    backedFiStorage.indexFactory().issuanceNonce(), _indexToken, tokenAddress, oldValue, newValue
                );

            unchecked {
                ++i;
            }
        }

        uint256 total = backedFiStorage.totalIssuanceByRound(_indexToken, _roundId);
        // require(total > 0, "Nothing to distribute");
        if (total == 0) revert NothingToDistribute();

        backedFiStorage.settleIssuance(_indexToken, _roundId);
        emit IssuanceSettled(_indexToken, _roundId, total, block.timestamp);
    }

    function requestRedemption(address _indexToken, uint256 _roundId)
        external
        payable
        nonReentrant
        onlyOwnerOrOperator
    {
        if (_roundId < 1 || _roundId > backedFiStorage.redemptionRoundId(_indexToken)) {
            revert InvalidRoundId();
        }
        uint256 prev = _roundId - 1;
        if (_roundId > 1) {
            // require(!backedFiStorage.redemptionRoundActive(_indexToken, prev), "Prev redemption round active");
            if (backedFiStorage.redemptionRoundActive(_indexToken, prev)) revert PreviousRoundActive();
            // require(backedFiStorage.redemptionIsCompleted(_indexToken, prev), "Prev redemption not completed");
            if (!backedFiStorage.redemptionIsCompleted(_indexToken, prev)) revert PreviousRoundNotCompleted();
        }
        // require(backedFiStorage.redemptionRoundActive(_indexToken, _roundId), "Round not active");
        if (!backedFiStorage.redemptionRoundActive(_indexToken, _roundId)) revert RoundInactive();
        // require(!backedFiStorage.redemptionIsCompleted(_indexToken, _roundId), "Round already completed");
        if (backedFiStorage.redemptionIsCompleted(_indexToken, _roundId)) revert RoundAlreadyCompleted();

        address vault = backedFiStorage.indexTokenToVault(_indexToken);

        // uint256 totalIdxThisRound = backedFiStorage.totalRedemptionByIndexTokenRound(indexToken, roundId);
        uint256 totalIdxThisRound = backedFiStorage.totalRedemptionByRound(_indexToken, _roundId);
        if (totalIdxThisRound == 0) revert RedemptionAmountIsZero();
        if (!backedFiStorage.redemptionRoundActive(_indexToken, _roundId)) {
            revert BatchNotStarted();
        }
        backedFiStorage.setRedemptionRoundActive(_indexToken, _roundId, false);

        uint256 supplyBefore = IERC20(_indexToken).totalSupply();
        // require(supplyBefore > totalIdxThisRound, "IDX supply is zero");
        if (supplyBefore <= totalIdxThisRound) revert IndexSupplyTooLow();

        uint256 burnPercent = backedFiStorage.ordersBurnPercent(_indexToken, _roundId);

        (, address[] memory underlyingAssets,) = functionsOracle.getCurrentProviderIndexData(
            _indexToken, functionsOracle.currentFilledCount(_indexToken), backedFiStorage.providerIndex()
        );
        uint256 currentList = underlyingAssets.length;
        uint256 bondSliceTotal;
        for (uint256 i = 0; i < currentList; ++i) {
            address token = underlyingAssets[i];
            uint256 slice = IERC20(token).balanceOf(vault) * burnPercent / 1e18;

            if (slice == 0) continue;

            Vault(vault).withdrawFunds(token, address(this), slice);
            IERC20(token).safeTransfer(nexBot, slice);
        }

        backedFiStorage.increaseRedemptionRoundId(_indexToken);
        backedFiStorage.setRedemptionRoundActive(_indexToken, backedFiStorage.redemptionRoundId(_indexToken), false);

        emit RedemptionRequested(_indexToken, totalIdxThisRound, bondSliceTotal, block.timestamp);
    }

    function completeRedemption(
        address _indexToken,
        uint256 _roundId,
        address[] memory _underlyingAssets,
        uint256[] memory _usdcOutputs
    ) external onlyNexBot {
        // if (_roundId < 1 || _roundId > backedFiStorage.redemptionRoundId(_indexToken)) revert InvalidRoundId();
        if (_roundId > backedFiStorage.redemptionRoundId(_indexToken)) revert InvalidRoundId();
        uint256 prev = _roundId - 1;
        if (_roundId > 1) {
            // require(!backedFiStorage.redemptionRoundActive(_indexToken, prev), "Prev redemption round active");
            if (backedFiStorage.redemptionRoundActive(_indexToken, prev)) revert PreviousRoundActive();
            // require(backedFiStorage.redemptionIsCompleted(_indexToken, prev), "Prev redemption not completed");
            if (!backedFiStorage.redemptionIsCompleted(_indexToken, prev)) revert PreviousRoundNotCompleted();
        }
        // require(!backedFiStorage.redemptionRoundActive(_indexToken, _roundId), "Round still active");
        if (backedFiStorage.redemptionRoundActive(_indexToken, _roundId)) revert RoundStillActive();
        // require(!backedFiStorage.redemptionIsCompleted(_indexToken, _roundId), "Round already completed");
        if (backedFiStorage.redemptionIsCompleted(_indexToken, _roundId)) revert RoundAlreadyCompleted();

        uint256 totalIDX = backedFiStorage.totalRedemptionByRound(_indexToken, _roundId);
        // require(totalIDX > 0, "No tokens to redeem");
        if (totalIDX == 0) revert NoTokensToRedeem();

        // if (usdcFromBond > 0) {
        //     backedFiStorage.usdc().safeTransferFrom(msg.sender, address(this), usdcFromBond);
        // }

        uint256 assetsCount = _underlyingAssets.length;
        // require(assetsCount > 0, "no assets");
        if (assetsCount == 0) revert NoAssetsProvided();
        // require(_usdcOutputs.length == assetsCount, "length mismatch");
        if (_usdcOutputs.length != assetsCount) revert LengthMismatch();

        uint256 totalUSDC = 0;
        IERC20 usdc = IERC20(backedFiStorage.usdc());

        for (uint256 i = 0; i < assetsCount;) {
            address asset = _underlyingAssets[i];
            uint256 usdcOut = _usdcOutputs[i];

            totalUSDC += usdcOut;

            if (usdcOut != 0) {
                usdc.safeTransfer(address(orderManager), usdcOut);

                backedFiStorage.indexFactory()
                    .handleCompleteRedemption(
                        backedFiStorage.indexFactory().redemptionNonce(), _indexToken, asset, usdcOut
                    );
            }

            unchecked {
                ++i;
            }
        }

        backedFiStorage.settleRedemption(_indexToken, _roundId);
        emit RedemptionSettled(_indexToken, _roundId, totalUSDC, block.timestamp);
    }

    function withRiskAsset(address token, address to, uint256 amount) public onlyOwner {
        uint256 balance = IERC20(token).balanceOf(address(this));
        // require(amount <= balance, "Not enought balance");
        if (amount > balance) revert InsufficientTokenBalance();
        IERC20(token).safeTransfer(to, amount);
    }
}

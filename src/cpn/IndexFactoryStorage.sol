// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IndexFactory} from "../factory/IndexFactory.sol";
// import {FunctionsOracle} from "./FunctionsOracle.sol";
import {FunctionsOracle} from "../oracle/FunctionsOracle.sol";
import {IndexToken} from "../token/IndexToken.sol";
import {Vault} from "../vault/Vault.sol";
import {StagingCustodyAccount} from "./StagingCustodyAccount.sol";
import {IRiskAssetFactory} from "./interfaces/IRiskAssetFactory.sol";
// import {IndexFactoryBalancer} from "./IndexFactoryBalancer.sol";

error InvalidAddress();
error ZeroAmount();
error UnsettledRound(uint256 previousRoundId);

contract IndexFactoryStorage is Initializable, OwnableUpgradeable {
    IndexToken public indexToken;
    Vault public vault;
    IndexFactory public indexFactory;
    FunctionsOracle public functionsOracle;
    StagingCustodyAccount public sca;
    IERC20 public usdc;

    address public feeReceiver;
    uint8 public feeRate;
    uint256 public issuanceRoundId;
    uint256 public redemptionRoundId;
    address public nexBot;
    uint256 public latestFeeUpdate;

    // BYOI
    mapping(address => mapping(uint256 => bool)) public issuanceIsCompletedByIndexToken;
    mapping(address => mapping(uint256 => bool)) public redemptionIsCompletedByIndexToken;

    mapping(uint256 => bool) public issuanceIsCompleted; // no need
    mapping(uint256 => bool) public redemptionIsCompleted; // no need
    // mapping(uint256 => address) public issuanceRequesterByNonce; // no need
    // mapping(uint256 => address) public redemptionRequesterByNonce; // no need
    mapping(address => mapping(uint256 => uint256)) public issuanceInputAmountByIndexToken;
    mapping(address => mapping(uint256 => uint256)) public redemptionInputAmountByIndexToken;
    mapping(uint256 => address[]) public issuanceRoundIdToAddresses; // no need
    mapping(uint256 => address[]) public redemptionRoundIdToAddresses; // no need
    mapping(uint256 => mapping(address => uint256)) public issuanceAmountByRoundUser; // no need
    mapping(uint256 => mapping(address => uint256)) public redemptionAmountByRoundUser; // no need
    mapping(address => mapping(uint256 => uint256)) public totalIssuanceByRoundByIndexToken;
    mapping(address => mapping(uint256 => uint256)) public totalRedemptionByRoundByIndexToken;
    mapping(uint256 => uint256) public totalIssuanceByRound;
    mapping(uint256 => uint256) public totalRedemptionByRound;
    mapping(uint256 => bool) public issuanceRoundActive;
    mapping(uint256 => bool) public redemptionRoundActive;
    mapping(address => mapping(uint256 => uint256[])) public issuanceRoundIdToNoncesByIndexToken;
    mapping(address => mapping(uint256 => uint256[])) public redemptionRoundIdToNoncesByIndexToken;
    mapping(address => mapping(uint256 => uint256)) public nonceToIssuanceRoundByIndexToken;
    mapping(address => mapping(uint256 => uint256)) public nonceToRedemptionRoundByIndexToken;
    //   mapping(uint256 => uint256) public issuanceFeeByNonce; // no need
    // mapping(uint256 => uint256) public redemptionFeeByNonce; // no need
    //     mapping(uint256 => bool) public issuanceRequestCancelled; // no need
    // mapping(uint256 => bool) public redemptionRequestCancelled; // no need
    mapping(uint256 => uint256) public nonceToIssuanceRound; // no need
    mapping(uint256 => uint256) public nonceToRedemptionRound; // no need
    mapping(uint256 => uint256[]) public issuanceRoundIdToNonces; // no need
    mapping(uint256 => uint256[]) public redemptionRoundIdToNonces; // no need

    mapping(address => uint256) public tokenPendingRebalanceAmount;
    mapping(address => mapping(uint256 => uint256)) public tokenPendingRebalanceAmountByNonce;

    event IssuanceSettled(uint256 indexed roundId);
    event RedemptionSettled(uint256 indexed roundId);
    event IssuanceNonceRecorded(uint256 indexed roundId, uint256 indexed nonce);
    event RedemptionNonceRecorded(uint256 indexed roundId, uint256 indexed nonce);

    modifier onlyFactory() {
        require(
            msg.sender == address(indexFactory) || msg.sender == nexBot || msg.sender == address(sca),
            // || msg.sender == address(factoryBalancer),
            "Caller is not a factory contract"
        );
        _;
    }

    modifier onlyOwnerOrOperator() {
        require(
            msg.sender == owner() || functionsOracle.isOperator(msg.sender) || msg.sender == nexBot,
            // || msg.sender == address(factoryBalancer),
            "Caller is not the owner or operator"
        );
        _;
    }

    function initialize(
        address _indexToken,
        address _indexFactory,
        address _functionsOracle,
        address _stagingCustodyAccount,
        address _vault,
        address _nexBot,
        // address _riskAssetFactoryAddress,
        address _usdc,
        // address _bond,
        address _feeVault,
        address _indexFactoryBalancer
    ) external initializer {
        require(_nexBot != address(0), "Invalid _nexBot address");
        // require(_riskAssetFactoryAddress != address(0), "Invalid _riskAssetFactoryAddress address");
        require(_usdc != address(0), "Invalid _usdc address");
        // require(_bond != address(0), "Invalid _bond address");

        __Ownable_init(msg.sender);

        indexToken = IndexToken(_indexToken);
        indexFactory = IndexFactory(_indexFactory);
        functionsOracle = FunctionsOracle(_functionsOracle);
        sca = StagingCustodyAccount(_stagingCustodyAccount);
        vault = Vault(_vault);
        // feeVault = FeeVault(_feeVault);
        usdc = IERC20(_usdc);
        // bond = _bond;

        // factoryBalancer = IndexFactoryBalancer(_indexFactoryBalancer);

        // riskAssetFactoryAddress = _riskAssetFactoryAddress;
        nexBot = _nexBot;
        // isMainnet = _isMainnet;
        issuanceRoundId = 1;
        redemptionRoundId = 1;
        feeRate = 10;
        feeReceiver = msg.sender;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function setFeeRate(uint8 _newFee) public onlyOwner {
        uint256 distance = block.timestamp - latestFeeUpdate;
        require(distance / 60 / 60 >= 12, "You should wait at least 12 hours after the latest update");
        require(_newFee <= 10000 && _newFee >= 1, "The newFee should be between 1 and 100 (0.01% - 1%)");
        feeRate = _newFee;
        latestFeeUpdate = block.timestamp;
    }

    function setNexBotAddress(address _newNexBotAddress) public onlyOwner {
        if (_newNexBotAddress == address(0)) revert InvalidAddress();
        nexBot = _newNexBotAddress;
    }

    function setSCA(address _sca) external onlyOwner {
        if (_sca == address(0)) revert InvalidAddress();
        sca = StagingCustodyAccount(_sca);
    }

    function setFunctionsOracle(address _functionsOracle) external onlyOwner {
        if (_functionsOracle == address(0)) revert InvalidAddress();
        functionsOracle = FunctionsOracle(_functionsOracle);
    }

    function setIndexFactory(address _indexFactory) external onlyOwner {
        if (_indexFactory == address(0)) revert InvalidAddress();
        indexFactory = IndexFactory(_indexFactory);
    }

    function setFeeReceiver(address _feeReceiver) public onlyOwner {
        if (_feeReceiver == address(0)) revert InvalidAddress();
        feeReceiver = _feeReceiver;
    }

    function setIssuanceInputAmount(address _indexToken, uint256 _issuanceNonce, uint256 _amount)
        external
        onlyFactory
    {
        if (_amount == 0) revert ZeroAmount();
        issuanceInputAmountByIndexToken[_indexToken][_issuanceNonce] = _amount;
    }

    function setRedemptionInputAmount(address _indexToken, uint256 _redemptionNonce, uint256 _amount)
        external
        onlyFactory
    {
        if (_amount == 0) revert ZeroAmount();
        redemptionInputAmountByIndexToken[_indexToken][_redemptionNonce] = _amount;
    }

    function addressesInRedemptionRound(uint256 roundId) external view returns (address[] memory) {
        return redemptionRoundIdToAddresses[roundId];
    }

    function addressesInIssuanceRound(uint256 roundId) external view returns (address[] memory) {
        return issuanceRoundIdToAddresses[roundId];
    }

    // function setIssuanceFeeByNonce(uint256 nonce, uint256 fee) external onlyFactory {
    //     issuanceFeeByNonce[nonce] = fee;
    // }

    // function setRedemptionFeeByNonce(uint256 nonce, uint256 fee) external onlyFactory {
    //     redemptionFeeByNonce[nonce] = fee;
    // }

    // function setIssuanceRoundIdToAddresses(uint256 _roundId, address[] memory addresses) external onlyFactory {
    //     require(_roundId > 0, "Invalid roundId amount");
    //     issuanceRoundIdToAddresses[_roundId] = addresses;
    // }

    function setIssuanceCompleted(uint256 nonce, bool flag) external onlyFactory {
        issuanceIsCompleted[nonce] = flag;
    }

    function setRedemptionCompleted(uint256 nonce, bool flag) external onlyFactory {
        redemptionIsCompleted[nonce] = flag;
    }

    function increaseIssuanceRoundId() external onlyFactory {
        issuanceRoundId++;
    }

    function increaseRedemptionRoundId() external onlyFactory {
        redemptionRoundId++;
    }

    function setRedemptionRoundActive(uint256 roundId, bool flag) external onlyFactory {
        redemptionRoundActive[roundId] = flag;
    }

    function setIssuanceRoundActive(uint256 roundId, bool flag) external onlyFactory {
        issuanceRoundActive[roundId] = flag;
    }

    function setIssuanceRoundToNonce(uint256 nonce, uint256 roundId) external onlyFactory {
        nonceToIssuanceRound[nonce] = roundId;
    }

    function setRedemptionRoundToNonce(uint256 nonce, uint256 roundId) external onlyFactory {
        nonceToRedemptionRound[nonce] = roundId;
    }

    function addNonceToIssuanceRound(uint256 roundId, uint256 nonce) external onlyFactory {
        issuanceRoundIdToNonces[roundId].push(nonce);
    }

    function addNonceToRedemptionRound(uint256 roundId, uint256 nonce) external onlyFactory {
        redemptionRoundIdToNonces[roundId].push(nonce);
    }

    function addIssuanceForCurrentRound(address indexToken, uint256 amount) external onlyFactory {
        if (!issuanceRoundActive[issuanceRoundId]) {
            issuanceRoundActive[issuanceRoundId] = true;
        }

        // if (issuanceAmountByRoundUser[issuanceRoundId][account] == 0) {
        //     issuanceRoundIdToAddresses[issuanceRoundId].push(account);
        // }
        // issuanceAmountByRoundUser[issuanceRoundId][account] += amount;
        totalIssuanceByRoundByIndexToken[indexToken][issuanceRoundId] += amount;
    }

    function addRedemptionForCurrentRound(address indexToken, uint256 amount) external onlyFactory {
        uint256 roundId = redemptionRoundId;

        if (!redemptionRoundActive[roundId]) redemptionRoundActive[roundId] = true;

        // if (redemptionAmountByRoundUser[roundId][user] == 0) {
        //     redemptionRoundIdToAddresses[roundId].push(user);
        // }

        // redemptionAmountByRoundUser[roundId][user] += amount;
        totalRedemptionByRoundByIndexToken[indexToken][roundId] += amount;
    }

    // function addressesInRedemptionRound(uint256 roundId) external view returns (address[] memory) {
    //     return redemptionRoundIdToAddresses[roundId];
    // }

    // function addressesInIssuanceRound(uint256 roundId) external view returns (address[] memory) {
    //     return issuanceRoundIdToAddresses[roundId];
    // }

    function getRedemptionRoundActive(uint256 roundId) external view returns (bool) {
        return redemptionRoundActive[roundId];
    }

    function getIssuanceRoundIdToNonces(uint256 roundId) external view returns (uint256[] memory) {
        return issuanceRoundIdToNonces[roundId];
    }

    function getRedemptionRoundIdToNonces(uint256 roundId) external view returns (uint256[] memory) {
        return redemptionRoundIdToNonces[roundId];
    }

    // function setIssuanceRequesterByNonce(uint256 nonce, address requester) external onlyFactory {
    //     issuanceRequesterByNonce[nonce] = requester;
    // }

    // function setRedemptionRequesterByNonce(uint256 nonce, address requester) external onlyFactory {
    //     redemptionRequesterByNonce[nonce] = requester;
    // }

    function recordIssuanceNonce(uint256 roundId, uint256 nonce) external onlyFactory {
        issuanceRoundIdToNonces[roundId].push(nonce);
        nonceToIssuanceRound[nonce] = roundId;
        emit IssuanceNonceRecorded(roundId, nonce);
    }

    function recordRedemptionNonce(uint256 roundId, uint256 nonce) external onlyFactory {
        redemptionRoundIdToNonces[roundId].push(nonce);
        nonceToRedemptionRound[nonce] = roundId;
        emit RedemptionNonceRecorded(roundId, nonce);
    }

    function settleIssuance(uint256 roundId) external onlyOwnerOrOperator {
        issuanceIsCompleted[roundId] = true;
        issuanceRoundActive[roundId] = false;

        emit IssuanceSettled(roundId);
    }

    function settleRedemption(uint256 roundId) external onlyOwnerOrOperator {
        redemptionIsCompleted[roundId] = true;
        redemptionRoundActive[roundId] = false;

        emit RedemptionSettled(roundId);
    }

    function _pruneAddress(uint256 round, address user) internal {
        address[] storage arr = issuanceRoundIdToAddresses[round];
        for (uint256 i; i < arr.length; ++i) {
            if (arr[i] == user) {
                arr[i] = arr[arr.length - 1];
                arr.pop();
                break;
            }
        }
        if (arr.length == 0) issuanceRoundActive[round] = false;
    }

    function nextProcessableRoundIdForIssuance() external view returns (uint256) {
        uint256 id = issuanceRoundId;
        for (uint256 i = 1; i < id; ++i) {
            if (issuanceRoundActive[i]) {
                revert UnsettledRound(i);
            }
        }
        return id;
    }

    function nextProcessableRoundIdForRedemption() external view returns (uint256) {
        uint256 id = redemptionRoundId;
        for (uint256 i = 1; i < id; ++i) {
            if (redemptionRoundActive[i]) {
                revert UnsettledRound(i);
            }
        }
        return id;
    }

    function currentIssuanceRoundWithStatus() external view returns (bool allSettled, uint256 roundId) {
        for (uint256 i = 1; i < issuanceRoundId; ++i) {
            if (issuanceRoundActive[i]) {
                return (false, i);
            }
        }
        return (true, issuanceRoundId);
    }

    function currentRedemptionRoundWithStatus() external view returns (bool allSettled, uint256 roundId) {
        for (uint256 i = 1; i < redemptionRoundId; ++i) {
            if (redemptionRoundActive[i]) {
                return (false, i);
            }
        }
        return (true, redemptionRoundId);
    }

    function getCurrentIssuanceRoundActivationStatus() external view returns (bool isActive, uint256 roundId) {
        return (issuanceRoundActive[issuanceRoundId], issuanceRoundId);
    }

    function getCurrentRedemptionRoundActivationStatus() external view returns (bool isActive, uint256 roundId) {
        return (redemptionRoundActive[redemptionRoundId], redemptionRoundId);
    }

    /**
     * @dev First issuance round that can call `issuanceAndWithdrawForPurchase`.
     */
    function nextIssuanceRoundForRequestIssuance() external view returns (uint256 roundId) {
        uint256 last = issuanceRoundId;
        for (uint256 id = 1; id <= last; ++id) {
            bool ok = issuanceRoundActive[id] && !issuanceIsCompleted[id];
            if (ok && _prevIssuanceSettled(id)) return id;
        }
        return 0;
    }

    /**
     * @dev First issuance round that can call `completeIssuance`.
     */
    function nextIssuanceRoundForCompleteIssuance() external view returns (uint256 roundId) {
        uint256 last = issuanceRoundId;
        for (uint256 id = 1; id <= last; ++id) {
            bool ok = !issuanceRoundActive[id] && !issuanceIsCompleted[id];
            if (ok && _prevIssuanceSettled(id)) return id;
        }
        return 0;
    }

    /**
     * @dev First redemption round that can call `initiateRedemptionBatch`.
     */
    function nextRedemptionRoundForRequestRedemption() external view returns (uint256 roundId) {
        uint256 last = redemptionRoundId;
        for (uint256 id = 1; id <= last; ++id) {
            bool ok = redemptionRoundActive[id] && !redemptionIsCompleted[id];
            if (ok && _prevRedemptionSettled(id)) return id;
        }
        return 0;
    }

    /**
     * @dev First redemption round that can call `completeRedemption`.
     */
    function nextRedemptionRoundForCompleteRedemption() external view returns (uint256 roundId) {
        uint256 last = redemptionRoundId;
        for (uint256 id = 1; id <= last; ++id) {
            bool ok = !redemptionRoundActive[id] && !redemptionIsCompleted[id];
            if (ok && _prevRedemptionSettled(id)) return id;
        }
        return 0;
    }

    function _prevIssuanceSettled(uint256 id) internal view returns (bool) {
        if (id == 1) return true;
        uint256 prev = id - 1;
        return !issuanceRoundActive[prev] && issuanceIsCompleted[prev];
    }

    function _prevRedemptionSettled(uint256 id) internal view returns (bool) {
        if (id == 1) return true;
        uint256 prev = id - 1;
        return !redemptionRoundActive[prev] && redemptionIsCompleted[prev];
    }

    function getPortfolioValue(
        address indexTokenAddress,
        address[] memory underlyingAssets, /* underlyingAssets */
        uint256[] memory prices
    ) public view returns (uint256 totalValue) {
        uint256 tokens = functionsOracle.totalCurrentList(indexTokenAddress);
        require(prices.length >= tokens, "prices length too small");

        for (uint256 i = 0; i < tokens; ++i) {
            address token = functionsOracle.currentList(indexTokenAddress, i);
            uint256 price = prices[i]; // price expected in 1e18
            uint256 balance = IERC20(token).balanceOf(address(vault));
            if (balance == 0 || price == 0) continue;

            // balance is in token decimals (assumed 18), price in 1e18 -> value in 1e18:
            totalValue += (balance * price) / 1e18;
        }
    }

    function calculateMintAmount(uint256 oldValue, uint256 newValue) public view returns (uint256 mintAmount) {
        require(newValue > oldValue, "no NAV increase");

        uint256 supply = indexToken.totalSupply();

        if (supply == 0 || oldValue == 0) {
            return newValue / 100;
        }

        mintAmount = supply * (newValue - oldValue) / oldValue;
    }

    // function getIssuanceAmountByRound(uint256 roundId) public view returns (uint256) {
    //     return totalIssuanceByRound[roundId];
    // }

    // function getRedemptionAmountByRound(uint256 roundId) public view returns (uint256) {
    //     return totalRedemptionByRound[roundId];
    // }

    uint256[50] private __gap;
}

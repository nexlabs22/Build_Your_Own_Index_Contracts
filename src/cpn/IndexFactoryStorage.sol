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
    address public nexBot;
    uint256 public latestFeeUpdate;

    // BYOI
    mapping(address => uint256) public issuanceRoundId;
    mapping(address => uint256) public redemptionRoundId;
    mapping(address => mapping(uint256 => bool)) public issuanceIsCompletedByIndexToken;
    mapping(address => mapping(uint256 => bool)) public redemptionIsCompletedByIndexToken;
    mapping(address => mapping(uint256 => bool)) public issuanceIsCompleted;
    mapping(address => mapping(uint256 => bool)) public redemptionIsCompleted;
    mapping(address => mapping(uint256 => uint256)) public issuanceInputAmountByIndexToken;
    mapping(address => mapping(uint256 => uint256)) public redemptionInputAmountByIndexToken;
    mapping(uint256 => address[]) public issuanceRoundIdToAddresses;
    mapping(uint256 => address[]) public redemptionRoundIdToAddresses;
    mapping(uint256 => mapping(address => uint256)) public issuanceAmountByRoundUser;
    mapping(uint256 => mapping(address => uint256)) public redemptionAmountByRoundUser;
    mapping(address => mapping(uint256 => uint256)) public totalIssuanceByRoundByIndexToken;
    mapping(address => mapping(uint256 => uint256)) public totalRedemptionByRoundByIndexToken;
    mapping(address => mapping(uint256 => uint256)) public totalIssuanceByRound;
    mapping(address => mapping(uint256 => uint256)) public totalRedemptionByRound;
    mapping(address => mapping(uint256 => bool)) public issuanceRoundActive;
    mapping(address => mapping(uint256 => bool)) public redemptionRoundActive;
    mapping(address => mapping(uint256 => uint256[])) public issuanceRoundIdToNoncesByIndexToken;
    mapping(address => mapping(uint256 => uint256[])) public redemptionRoundIdToNoncesByIndexToken;
    mapping(address => mapping(uint256 => uint256)) public nonceToIssuanceRoundByIndexToken;
    mapping(address => mapping(uint256 => uint256)) public nonceToRedemptionRoundByIndexToken;
    mapping(address => mapping(uint256 => uint256)) public nonceToIssuanceRound;
    mapping(address => mapping(uint256 => uint256)) public nonceToRedemptionRound;
    mapping(address => mapping(uint256 => uint256[])) public issuanceRoundIdToNonces;
    mapping(address => mapping(uint256 => uint256[])) public redemptionRoundIdToNonces;
    mapping(address => address) public indexTokenToVault;

    //   mapping(uint256 => uint256) public issuanceFeeByNonce; // no need
    // mapping(uint256 => uint256) public redemptionFeeByNonce; // no need
    //     mapping(uint256 => bool) public issuanceRequestCancelled; // no need
    // mapping(uint256 => bool) public redemptionRequestCancelled; // no need
    // mapping(uint256 => uint256) public nonceToIssuanceRound; // no need
    // mapping(uint256 => uint256) public nonceToRedemptionRound; // no need
    // mapping(uint256 => uint256[]) public issuanceRoundIdToNonces; // no need
    // mapping(uint256 => uint256[]) public redemptionRoundIdToNonces; // no need
    // mapping(uint256 => address) public issuanceRequesterByNonce; // no need
    // mapping(uint256 => address) public redemptionRequesterByNonce; // no need
    // mapping(uint256 => bool) public issuanceIsCompleted; // no need
    // mapping(uint256 => bool) public redemptionIsCompleted; // no need
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
        address _indexFactory,
        address _functionsOracle,
        address _stagingCustodyAccount,
        address _nexBot,
        address _usdc
    ) external initializer {
        require(_indexFactory != address(0), "Invalid _indexFactory address");
        require(_functionsOracle != address(0), "Invalid _functionsOracle address");
        require(_stagingCustodyAccount != address(0), "Invalid _stagingCustodyAccount address");
        require(_nexBot != address(0), "Invalid _nexBot address");
        require(_usdc != address(0), "Invalid _usdc address");

        __Ownable_init(msg.sender);

        indexFactory = IndexFactory(_indexFactory);
        functionsOracle = FunctionsOracle(_functionsOracle);
        sca = StagingCustodyAccount(_stagingCustodyAccount);
        usdc = IERC20(_usdc);

        nexBot = _nexBot;
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

    function setIssuanceCompleted(address _indexToken, uint256 _nonce, bool _flag) external onlyFactory {
        issuanceIsCompleted[_indexToken][_nonce] = _flag;
    }

    function setRedemptionCompleted(address _indexToken, uint256 _nonce, bool _flag) external onlyFactory {
        redemptionIsCompleted[_indexToken][_nonce] = _flag;
    }

    function increaseIssuanceRoundId(address _indexToken) external onlyFactory {
        issuanceRoundId[_indexToken]++;
    }

    function increaseRedemptionRoundId(address _indexToken) external onlyFactory {
        redemptionRoundId[_indexToken]++;
    }

    function setRedemptionRoundActive(address _indexToken, uint256 _roundId, bool _flag) external onlyFactory {
        redemptionRoundActive[_indexToken][_roundId] = _flag;
    }

    function setIssuanceRoundActive(address _indexToken, uint256 _roundId, bool _flag) external onlyFactory {
        issuanceRoundActive[_indexToken][_roundId] = _flag;
    }

    function setIssuanceRoundToNonce(address _indexToken, uint256 _nonce, uint256 _roundId) external onlyFactory {
        nonceToIssuanceRound[_indexToken][_nonce] = _roundId;
    }

    function setRedemptionRoundToNonce(address _indexToken, uint256 _nonce, uint256 _roundId) external onlyFactory {
        nonceToRedemptionRound[_indexToken][_nonce] = _roundId;
    }

    function addNonceToIssuanceRound(address _indexToken, uint256 _roundId, uint256 _nonce) external onlyFactory {
        issuanceRoundIdToNonces[_indexToken][_roundId].push(_nonce);
    }

    function addNonceToRedemptionRound(address _indexToken, uint256 _roundId, uint256 _nonce) external onlyFactory {
        redemptionRoundIdToNonces[_indexToken][_roundId].push(_nonce);
    }

    function addIssuanceForCurrentRound(address _indexToken, uint256 _amount) external onlyFactory {
        if (!issuanceRoundActive[_indexToken][issuanceRoundId[_indexToken]]) {
            issuanceRoundActive[_indexToken][issuanceRoundId[_indexToken]] = true;
        }

        totalIssuanceByRoundByIndexToken[_indexToken][issuanceRoundId[_indexToken]] += _amount;
    }

    function addRedemptionForCurrentRound(address _indexToken, uint256 _amount) external onlyFactory {
        uint256 roundId = redemptionRoundId[_indexToken];

        if (!redemptionRoundActive[_indexToken][roundId]) redemptionRoundActive[_indexToken][roundId] = true;

        totalRedemptionByRoundByIndexToken[_indexToken][roundId] += _amount;
    }

    // function addressesInRedemptionRound(uint256 roundId) external view returns (address[] memory) {
    //     return redemptionRoundIdToAddresses[roundId];
    // }

    // function addressesInIssuanceRound(uint256 roundId) external view returns (address[] memory) {
    //     return issuanceRoundIdToAddresses[roundId];
    // }

    function getRedemptionRoundActive(address _indexToken, uint256 _roundId) external view returns (bool) {
        return redemptionRoundActive[_indexToken][_roundId];
    }

    function getIssuanceRoundIdToNonces(address _indexToken, uint256 _roundId)
        external
        view
        returns (uint256[] memory)
    {
        return issuanceRoundIdToNonces[_indexToken][_roundId];
    }

    function getRedemptionRoundIdToNonces(address _indexToken, uint256 _roundId)
        external
        view
        returns (uint256[] memory)
    {
        return redemptionRoundIdToNonces[_indexToken][_roundId];
    }

    // function setIssuanceRequesterByNonce(uint256 nonce, address requester) external onlyFactory {
    //     issuanceRequesterByNonce[nonce] = requester;
    // }

    // function setRedemptionRequesterByNonce(uint256 nonce, address requester) external onlyFactory {
    //     redemptionRequesterByNonce[nonce] = requester;
    // }

    function recordIssuanceNonce(address _indexToken, uint256 _roundId, uint256 _nonce) external onlyFactory {
        issuanceRoundIdToNonces[_indexToken][_roundId].push(_nonce);
        nonceToIssuanceRound[_indexToken][_nonce] = _roundId;
        emit IssuanceNonceRecorded(_roundId, _nonce);
    }

    function recordRedemptionNonce(address _indexToken, uint256 _roundId, uint256 _nonce) external onlyFactory {
        redemptionRoundIdToNonces[_indexToken][_roundId].push(_nonce);
        nonceToRedemptionRound[_indexToken][_nonce] = _roundId;
        emit RedemptionNonceRecorded(_roundId, _nonce);
    }

    function settleIssuance(address _indexToken, uint256 _roundId) external onlyOwnerOrOperator {
        issuanceIsCompleted[_indexToken][_roundId] = true;
        issuanceRoundActive[_indexToken][_roundId] = false;

        emit IssuanceSettled(_roundId);
    }

    function settleRedemption(address _indexToken, uint256 _roundId) external onlyOwnerOrOperator {
        redemptionIsCompleted[_indexToken][_roundId] = true;
        redemptionRoundActive[_indexToken][_roundId] = false;

        emit RedemptionSettled(_roundId);
    }

    function _pruneAddress(address _indexToken, uint256 _round, address _user) internal {
        address[] storage arr = issuanceRoundIdToAddresses[_round];
        for (uint256 i; i < arr.length; ++i) {
            if (arr[i] == _user) {
                arr[i] = arr[arr.length - 1];
                arr.pop();
                break;
            }
        }
        if (arr.length == 0) issuanceRoundActive[_indexToken][_round] = false;
    }

    function nextProcessableRoundIdForIssuance(address _indexToken) external view returns (uint256) {
        uint256 id = issuanceRoundId[_indexToken];
        for (uint256 i = 1; i < id; ++i) {
            if (issuanceRoundActive[_indexToken][i]) {
                revert UnsettledRound(i);
            }
        }
        return id;
    }

    function nextProcessableRoundIdForRedemption(address _indexToken) external view returns (uint256) {
        uint256 id = redemptionRoundId[_indexToken];
        for (uint256 i = 1; i < id; ++i) {
            if (redemptionRoundActive[_indexToken][i]) {
                revert UnsettledRound(i);
            }
        }
        return id;
    }

    function currentIssuanceRoundWithStatus(address _indexToken)
        external
        view
        returns (bool allSettled, uint256 roundId)
    {
        for (uint256 i = 1; i < issuanceRoundId[_indexToken]; ++i) {
            if (issuanceRoundActive[_indexToken][i]) {
                return (false, i);
            }
        }
        return (true, issuanceRoundId[_indexToken]);
    }

    function currentRedemptionRoundWithStatus(address _indexToken)
        external
        view
        returns (bool allSettled, uint256 roundId)
    {
        for (uint256 i = 1; i < redemptionRoundId[_indexToken]; ++i) {
            if (redemptionRoundActive[_indexToken][i]) {
                return (false, i);
            }
        }
        return (true, redemptionRoundId[_indexToken]);
    }

    function getCurrentIssuanceRoundActivationStatus(address _indexToken)
        external
        view
        returns (bool isActive, uint256 roundId)
    {
        return (issuanceRoundActive[_indexToken][issuanceRoundId[_indexToken]], issuanceRoundId[_indexToken]);
    }

    function getCurrentRedemptionRoundActivationStatus(address _indexToken)
        external
        view
        returns (bool isActive, uint256 roundId)
    {
        return (redemptionRoundActive[_indexToken][redemptionRoundId[_indexToken]], redemptionRoundId[_indexToken]);
    }

    /**
     * @dev First issuance round that can call `issuanceAndWithdrawForPurchase`.
     */
    function nextIssuanceRoundForRequestIssuance(address _indexToken) external view returns (uint256 roundId) {
        uint256 last = issuanceRoundId[_indexToken];
        for (uint256 id = 1; id <= last; ++id) {
            bool ok = issuanceRoundActive[_indexToken][id] && !issuanceIsCompleted[_indexToken][id];
            if (ok && _prevIssuanceSettled(_indexToken, id)) return id;
        }
        return 0;
    }

    /**
     * @dev First issuance round that can call `completeIssuance`.
     */
    function nextIssuanceRoundForCompleteIssuance(address _indexToken) external view returns (uint256 roundId) {
        uint256 last = issuanceRoundId[_indexToken];
        for (uint256 id = 1; id <= last; ++id) {
            bool ok = !issuanceRoundActive[_indexToken][id] && !issuanceIsCompleted[_indexToken][id];
            if (ok && _prevIssuanceSettled(_indexToken, id)) return id;
        }
        return 0;
    }

    /**
     * @dev First redemption round that can call `initiateRedemptionBatch`.
     */
    function nextRedemptionRoundForRequestRedemption(address _indexToken) external view returns (uint256 roundId) {
        uint256 last = redemptionRoundId[_indexToken];
        for (uint256 id = 1; id <= last; ++id) {
            bool ok = redemptionRoundActive[_indexToken][id] && !redemptionIsCompleted[_indexToken][id];
            if (ok && _prevRedemptionSettled(_indexToken, id)) return id;
        }
        return 0;
    }

    /**
     * @dev First redemption round that can call `completeRedemption`.
     */
    function nextRedemptionRoundForCompleteRedemption(address _indexToken) external view returns (uint256 roundId) {
        uint256 last = redemptionRoundId[_indexToken];
        for (uint256 id = 1; id <= last; ++id) {
            bool ok = !redemptionRoundActive[_indexToken][id] && !redemptionIsCompleted[_indexToken][id];
            if (ok && _prevRedemptionSettled(_indexToken, id)) return id;
        }
        return 0;
    }

    function _prevIssuanceSettled(address _indexToken, uint256 id) internal view returns (bool) {
        if (id == 1) return true;
        uint256 prev = id - 1;
        return !issuanceRoundActive[_indexToken][prev] && issuanceIsCompleted[_indexToken][prev];
    }

    function _prevRedemptionSettled(address _indexToken, uint256 id) internal view returns (bool) {
        if (id == 1) return true;
        uint256 prev = id - 1;
        return !redemptionRoundActive[_indexToken][prev] && redemptionIsCompleted[_indexToken][prev];
    }

    function getPortfolioValue(
        address indexTokenAddress,
        address[] memory, /* underlyingAssets */
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

    // function getIssuanceAmountByRound(uint256 roundId) public view returns (uint256) {
    //     return totalIssuanceByRound[roundId];
    // }

    // function getRedemptionAmountByRound(uint256 roundId) public view returns (uint256) {
    //     return totalRedemptionByRound[roundId];
    // }

    uint256[50] private __gap;
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {StagingCustodyAccount} from "./StagingCustodyAccount.sol";
// import {IndexFactoryStorage} from "./IndexFactoryStorage.sol";
import {BackedFiStorage} from "./BackedFiStorage.sol";
import {FunctionsOracle} from "./FunctionsOracle.sol";
import {IndexToken} from "../token/IndexToken.sol";
import {FeeCalculation} from "../libraries/FeeCalculation.sol";

error ZeroAmount();
error WrongETHAmount();
error UnauthorizedCaller();
error ZeroBackedFiStorageAddress();

contract BackedFiFactory is Initializable, OwnableUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    BackedFiStorage backedFiStorage;
    FunctionsOracle functionsOracle;

    uint256 public issuanceNonce;
    uint256 public redemptionNonce;

    event RequestIssuance(
        address indexed indexToken,
        uint256 indexed roundId,
        uint256 indexed nonce,
        address user,
        address inputToken,
        uint256 inputAmount,
        uint256 time
    );

    event RequestRedemption(
        address indexed indexToken,
        uint256 indexed roundId,
        uint256 indexed nonce,
        address user,
        address outputToken,
        uint256 inputAmount,
        uint256 time
    );

    modifier onlyOwnerOrOperator() {
        // require(
        //     msg.sender == owner() || functionsOracle.isOperator(msg.sender),
        //     // || msg.sender == address(factoryStorage.factoryBalancer()),
        //     "Caller is not the owner or operator"
        // );
        if (msg.sender != owner() && !functionsOracle.isOperator(msg.sender)) revert UnauthorizedCaller();
        _;
    }

    function initialize(address _backedFiStorage) external initializer {
        // require(_backedFiStorage != address(0), "Invalid _backedFiStorage Address");
        if (_backedFiStorage == address(0)) revert ZeroBackedFiStorageAddress();

        backedFiStorage = BackedFiStorage(_backedFiStorage);

        __Ownable_init(msg.sender);
        __Pausable_init();
        __ReentrancyGuard_init();
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function issuanceIndexTokens(address _indexToken, uint256 _inputAmount)
        public
        payable
        whenNotPaused
        nonReentrant
        returns (uint256)
    {
        if (_inputAmount == 0) revert ZeroAmount();

        IERC20(backedFiStorage.usdc()).safeTransferFrom(msg.sender, address(backedFiStorage.sca()), _inputAmount);

        uint256 nonce = ++issuanceNonce;
        backedFiStorage.setIssuanceInputAmount(_indexToken, nonce, _inputAmount);
        backedFiStorage.addIssuanceForCurrentRound(msg.sender, _inputAmount);
        backedFiStorage.setIssuanceRoundToNonce(_indexToken, nonce, backedFiStorage.issuanceRoundId(_indexToken));

        uint256 currentRound = backedFiStorage.issuanceRoundId(_indexToken);
        backedFiStorage.recordIssuanceNonce(_indexToken, currentRound, nonce);

        emit RequestIssuance(
            _indexToken,
            backedFiStorage.issuanceRoundId(_indexToken),
            nonce,
            msg.sender,
            address(backedFiStorage.usdc()),
            _inputAmount,
            block.timestamp
        );
        return nonce;
    }

    function redemption(address _indexToken, uint256 _amount, uint256 _burnPercent)
        external
        payable
        whenNotPaused
        nonReentrant
        returns (uint256 nonce)
    {
        if (_amount == 0) revert ZeroAmount();

        IERC20(_indexToken).safeTransferFrom(msg.sender, address(backedFiStorage.sca()), _amount);

        nonce = ++redemptionNonce;

        backedFiStorage.setRedemptionInputAmount(_indexToken, nonce, _amount);
        backedFiStorage.addRedemptionForCurrentRound(msg.sender, _amount);
        backedFiStorage.setRedemptionRoundToNonce(_indexToken, nonce, backedFiStorage.redemptionRoundId(_indexToken));
        backedFiStorage.setOrdersBurnPercent(_indexToken, backedFiStorage.redemptionRoundId(_indexToken), _burnPercent);

        uint256 currentRedemRound = backedFiStorage.redemptionRoundId(_indexToken);
        backedFiStorage.recordRedemptionNonce(_indexToken, currentRedemRound, nonce);

        emit RequestRedemption(
            _indexToken,
            backedFiStorage.redemptionRoundId(_indexToken),
            nonce,
            msg.sender,
            address(backedFiStorage.usdc()),
            _amount,
            block.timestamp
        );
        return nonce;
    }

    /**
     * @dev Pauses the contract.
     */
    function pause() external onlyOwnerOrOperator {
        _pause();
    }

    /**
     * @dev Unpauses the contract.
     */
    function unpause() external onlyOwnerOrOperator {
        _unpause();
    }
}

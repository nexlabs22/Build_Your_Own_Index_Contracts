// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {StagingCustodyAccount} from "./StagingCustodyAccount.sol";
import {IndexFactoryStorage} from "./IndexFactoryStorage.sol";
import {FunctionsOracle} from "./FunctionsOracle.sol";
import {IndexToken} from "../token/IndexToken.sol";
import {FeeCalculation} from "../libraries/FeeCalculation.sol";
import {IRiskAssetFactory} from "./interfaces/IRiskAssetFactory.sol";
// import {FeeVault} from "../vault/FeeVault.sol";

error ZeroAmount();
error WrongETHAmount();

contract CPNFactory is Initializable, OwnableUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    IndexFactoryStorage factoryStorage;
    FunctionsOracle functionsOracle;
    // FeeVault feeVault;

    uint256 public issuanceNonce;
    uint256 public redemptionNonce;

    event RequestIssuance(
        uint256 indexed roundId,
        uint256 indexed nonce,
        address indexed user,
        address inputToken,
        uint256 inputAmount,
        uint256 feeAmount,
        uint256 time
    );

    event RequestRedemption(
        uint256 indexed roundId,
        uint256 indexed nonce,
        address indexed user,
        address outputToken,
        uint256 inputAmount,
        uint256 time
    );

    modifier onlyOwnerOrOperator() {
        require(
            msg.sender == owner() || functionsOracle.isOperator(msg.sender),
            // || msg.sender == address(factoryStorage.factoryBalancer()),
            "Caller is not the owner or operator"
        );
        _;
    }

    function initialize(address _indexFactoryStorage, address _feeVault) external initializer {
        require(_indexFactoryStorage != address(0), "Invalid Address");
        require(_feeVault != address(0), "Invalid FeeVault");

        factoryStorage = IndexFactoryStorage(_indexFactoryStorage);
        // feeVault = FeeVault(_feeVault);

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

        uint256 usdcFee = FeeCalculation.calculateFee(_inputAmount, factoryStorage.feeRate());
        IERC20(factoryStorage.usdc()).safeTransferFrom(msg.sender, address(factoryStorage.sca()), _inputAmount);
        IERC20(factoryStorage.usdc()).safeTransferFrom(msg.sender, address(factoryStorage.feeReceiver()), usdcFee);

        uint256 nonce = ++issuanceNonce;
        factoryStorage.setIssuanceInputAmount(_indexToken, nonce, _inputAmount);
        factoryStorage.addIssuanceForCurrentRound(msg.sender, _inputAmount);
        factoryStorage.setIssuanceRoundToNonce(nonce, factoryStorage.issuanceRoundId());

        uint256 currentRound = factoryStorage.issuanceRoundId();
        factoryStorage.recordIssuanceNonce(currentRound, nonce);

        emit RequestIssuance(
            factoryStorage.issuanceRoundId(),
            nonce,
            msg.sender,
            address(factoryStorage.usdc()),
            _inputAmount,
            usdcFee,
            block.timestamp
        );
        return nonce;
    }

    function redemption(address _indexToken, uint256 _amount)
        external
        payable
        whenNotPaused
        nonReentrant
        returns (uint256 nonce)
    {
        if (_amount == 0) revert ZeroAmount();

        IERC20(_indexToken).safeTransferFrom(msg.sender, address(factoryStorage.sca()), _amount);

        nonce = ++redemptionNonce;

        factoryStorage.setRedemptionInputAmount(_indexToken, nonce, _amount);
        factoryStorage.addRedemptionForCurrentRound(msg.sender, _amount);
        factoryStorage.setRedemptionRoundToNonce(nonce, factoryStorage.redemptionRoundId());

        uint256 currentRedemRound = factoryStorage.redemptionRoundId();
        factoryStorage.recordRedemptionNonce(currentRedemRound, nonce);

        emit RequestRedemption(
            factoryStorage.redemptionRoundId(),
            nonce,
            msg.sender,
            address(factoryStorage.usdc()),
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

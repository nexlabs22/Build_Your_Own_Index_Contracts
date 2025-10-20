// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "../token/IndexToken.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import {IOrderProcessor} from "./dinari/interfaces/IOrderProcessor.sol";
import {FeeLib} from "./dinari/common/FeeLib.sol";
import {Vault} from "../vault/Vault.sol";
import {WrappedDShare} from "./dinari/WrappedDShare.sol";
import {DinariStorage} from "./DinariStorage.sol";
import {DinariOrderManager} from "./DinariOrderManager.sol";
import {FunctionsOracle} from "../oracle/FunctionsOracle.sol";
import {IndexFactoryStorage} from "../factory/IndexFactoryStorage.sol";
import "../orderManager/OrderManager.sol";

error ZeroIndexFactoryStorageAddress();
error ZeroDinariStorageAddress();
error ZeroFunctionsOracleAddress();
error ZeroOrderManagerAddress();
error ZeroFactoryStorageAddress();
error IssuanceOrdersIncomplete();
error IssuanceAlreadyCompleted();
error RedemptionOrdersIncomplete();
error RedemptionAlreadyCompleted();

/// @title Index Token Factory
/// @author NEX Labs Protocol
/// @notice Allows User to initiate burn/mint requests and allows issuers to approve or deny them
contract DinariFactoryProcessor is
    Initializable,
    OwnableUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    DinariStorage public dinariStorage;
    IndexFactoryStorage public factoryStorage;
    FunctionsOracle public functionsOracle;
    OrderManager public orderManager;

    event Issuanced(
        address indexed indexToken,
        uint256 indexed nonce,
        address indexed user,
        address inputToken,
        uint256 inputAmount,
        uint256 time
    );

    event Redemption(
        address indexed indexToken,
        uint256 indexed nonce,
        address indexed user,
        address outputToken,
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 time
    );

    function initialize(
        address _indexFactoryStorage,
        address _dinariStorage,
        address _functionsOracle,
        address _orderManager
    ) external initializer {
        // require(_indexFactoryStorage != address(0), "invalid _indexFactoryStorage address");
        if (_indexFactoryStorage == address(0)) revert ZeroIndexFactoryStorageAddress();
        // require(_dinariStorage != address(0), "invalid _dinariStorage address");
        if (_dinariStorage == address(0)) revert ZeroDinariStorageAddress();
        // require(_functionsOracle != address(0), "invalid _functionsOracle address");
        if (_functionsOracle == address(0)) revert ZeroFunctionsOracleAddress();
        // require(_orderManager != address(0), "invalid _orderManager address");
        if (_orderManager == address(0)) revert ZeroOrderManagerAddress();
        factoryStorage = IndexFactoryStorage(_indexFactoryStorage);
        dinariStorage = DinariStorage(_dinariStorage);
        functionsOracle = FunctionsOracle(_functionsOracle);
        orderManager = OrderManager(_orderManager);

        __Ownable_init(msg.sender);
        __Pausable_init();
        __ReentrancyGuard_init();
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function setFunctionsOracle(address _functionsOracle) external onlyOwner returns (bool) {
        // require(_functionsOracle != address(0), "invalid functions oracle address");
        if (_functionsOracle == address(0)) revert ZeroFunctionsOracleAddress();
        functionsOracle = FunctionsOracle(_functionsOracle);
        return true;
    }

    function setIndexFactoryStorage(address _factoryStorage) external onlyOwner returns (bool) {
        // require(_factoryStorage != address(0), "invalid factory storage address");
        if (_factoryStorage == address(0)) revert ZeroFactoryStorageAddress();
        dinariStorage = DinariStorage(_factoryStorage);
        return true;
    }

    function completeIssuance(address _indexToken, uint256 _issuanceNonce) public nonReentrant whenNotPaused {
        // require(dinariStorage.checkIssuanceOrdersStatus(_indexToken, _issuanceNonce), "Orders are not completed");
        if (!dinariStorage.checkIssuanceOrdersStatus(_indexToken, _issuanceNonce)) {
            revert IssuanceOrdersIncomplete();
        }
        // require(!dinariStorage.issuanceIsCompleted(_indexToken, _issuanceNonce), "Issuance is completed");
        if (dinariStorage.issuanceIsCompleted(_indexToken, _issuanceNonce)) revert IssuanceAlreadyCompleted();
        address requester = dinariStorage.issuanceRequesterByNonce(_indexToken, _issuanceNonce);
        // IOrderProcessor issuer = dinariStorage.issuer();
        uint256 primaryPortfolioValue;
        uint256 secondaryPortfolioValue;

        (, address[] memory underlyingAssets,) = functionsOracle.getCurrentProviderIndexData(
            _indexToken, functionsOracle.currentFilledCount(_indexToken), dinariStorage.providerIndex()
        );

        for (uint256 i; i < underlyingAssets.length; i++) {
            address tokenAddress = underlyingAssets[i];
            (uint256 primaryValue, uint256 secondaryValue, uint256 balance) =
                getCompleteIssuanceValues(tokenAddress, _indexToken, _issuanceNonce);
            primaryPortfolioValue += primaryValue;
            secondaryPortfolioValue += secondaryValue;
            DinariOrderManager dinariOrderManager = dinariStorage.dinariOrderManager();
            dinariOrderManager.withdrawFunds(tokenAddress, address(this), balance);
            orderManager.completeIssuance(
                dinariStorage.providerIndex(), _issuanceNonce, _indexToken, tokenAddress, primaryValue, secondaryValue
            );
            _setCompleteIssuanceData(tokenAddress, balance, _indexToken);
        }
        dinariStorage.issuanceIndexTokenPrimaryTotalSupply(_indexToken, _issuanceNonce);

        dinariStorage.setIssuanceIsCompleted(_indexToken, _issuanceNonce, true);

        emit Issuanced(
            _indexToken,
            _issuanceNonce,
            requester,
            dinariStorage.usdc(),
            dinariStorage.issuanceInputAmount(_indexToken, _issuanceNonce),
            block.timestamp
        );
    }

    function getCompleteIssuanceValues(address _tokenAddress, address _indexToken, uint256 _issuanceNonce)
        internal
        view
        returns (uint256 primaryValue, uint256 secondaryValue, uint256 balance)
    {
        IOrderProcessor issuer = dinariStorage.issuer();

        uint256 tokenRequestId = dinariStorage.issuanceRequestId(_indexToken, _issuanceNonce, _tokenAddress);
        uint256 price = dinariStorage.priceInWei(_tokenAddress);
        balance = issuer.getReceivedAmount(tokenRequestId);
        uint256 receivedValue = balance * price / 1e18;
        uint256 primaryBalance = dinariStorage.issuanceTokenPrimaryBalance(_indexToken, _issuanceNonce, _tokenAddress);
        primaryValue = primaryBalance * price / 1e18;
        secondaryValue = primaryValue + receivedValue;
    }

    function _setCompleteIssuanceData(address _tokenAddress, uint256 _balance, address _indexToken) internal {
        IERC20(_tokenAddress).approve(dinariStorage.wrappedDshareAddress(_tokenAddress), _balance);
        WrappedDShare(dinariStorage.wrappedDshareAddress(_tokenAddress)).deposit(
            _balance, address(factoryStorage.indexTokenToVault(_indexToken))
        );
    }

    function completeRedemption(address _indexToken, uint256 _redemptionNonce) public nonReentrant whenNotPaused {
        // require(
        //     dinariStorage.checkRedemptionOrdersStatus(_indexToken, _redemptionNonce),
        //     "Redemption orders are not completed"
        // );
        if (!dinariStorage.checkRedemptionOrdersStatus(_indexToken, _redemptionNonce)) {
            revert RedemptionOrdersIncomplete();
        }
        // require(!dinariStorage.redemptionIsCompleted(_indexToken, _redemptionNonce), "Redemption is completed");
        if (dinariStorage.redemptionIsCompleted(_indexToken, _redemptionNonce)) revert RedemptionAlreadyCompleted();
        address requester = dinariStorage.redemptionRequesterByNonce(_indexToken, _redemptionNonce);
        IOrderProcessor issuer = dinariStorage.issuer();
        uint256 totalBalance;

        (, address[] memory underlyingAssets,) = functionsOracle.getCurrentProviderIndexData(
            _indexToken, functionsOracle.currentFilledCount(_indexToken), dinariStorage.providerIndex()
        );

        DinariOrderManager dinariOrderManager = dinariStorage.dinariOrderManager();
        for (uint256 i; i < underlyingAssets.length; i++) {
            address tokenAddress = underlyingAssets[i];
            uint256 tokenRequestId = dinariStorage.redemptionRequestId(_indexToken, _redemptionNonce, tokenAddress);
            uint256 balance = issuer.getReceivedAmount(tokenRequestId);
            uint256 feeTaken = issuer.getFeesTaken(tokenRequestId);
            dinariOrderManager.withdrawFunds(dinariStorage.usdc(), requester, totalBalance);
            orderManager.completeRedemption(_redemptionNonce, _indexToken, tokenAddress, balance - feeTaken);
            totalBalance += balance - feeTaken;
        }
        dinariStorage.setRedemptionIsCompleted(_indexToken, _redemptionNonce, true);
        emit Redemption(
            _indexToken,
            _redemptionNonce,
            requester,
            dinariStorage.usdc(),
            dinariStorage.redemptionInputAmount(_indexToken, _redemptionNonce),
            totalBalance,
            block.timestamp
        );
    }

    function checkMultical(address _indexToken, uint256 _reqeustId) public view returns (bool) {
        DinariStorage.ActionInfo memory actionInfo = dinariStorage.getActionInfoById(_indexToken, _reqeustId);
        if (actionInfo.actionType == 1) {
            return dinariStorage.checkIssuanceOrdersStatus(_indexToken, actionInfo.nonce);
        } else if (actionInfo.actionType == 2) {
            return dinariStorage.checkRedemptionOrdersStatus(_indexToken, actionInfo.nonce);
        }
        return false;
    }

    function multical(address _indexToken, uint256 _requestId) public {
        DinariStorage.ActionInfo memory actionInfo = dinariStorage.getActionInfoById(_indexToken, _requestId);
        if (actionInfo.actionType == 1) {
            completeIssuance(_indexToken, actionInfo.nonce);
        } else if (actionInfo.actionType == 2) {
            completeRedemption(_indexToken, actionInfo.nonce);
        }
    }
}

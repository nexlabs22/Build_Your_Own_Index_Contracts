// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "../token/IndexToken.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import "./dinari/interfaces/IOrderProcessor.sol";
import {FeeLib} from "./dinari/common/FeeLib.sol";
import "./NexVault.sol";
import "./dinari/WrappedDShare.sol";
import "./IndexFactoryStorage.sol";
import "./OrderManager.sol";
import "../oracle/FunctionsOracle.sol";

/// @title Index Token Factory
/// @author NEX Labs Protocol
/// @notice Allows User to initiate burn/mint requests and allows issuers to approve or deny them
contract IndexFactoryProcessor is Initializable, OwnableUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable {
    IndexFactoryStorage public factoryStorage;
    FunctionsOracle public functionsOracle;

    event Issuanced(
        uint256 indexed nonce,
        address indexed user,
        address inputToken,
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 price,
        uint256 time
    );

    event IssuanceCancelled(
        uint256 indexed nonce,
        address indexed user,
        address inputToken,
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 time
    );

    event Redemption(
        uint256 indexed nonce,
        address indexed user,
        address outputToken,
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 time
    );

    event RedemptionCancelled(
        uint256 indexed nonce,
        address indexed user,
        address outputToken,
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 time
    );

    function initialize(address _factoryStorage, address _functionsOracle) external initializer {
        require(_factoryStorage != address(0), "invalid factory storage address");
        require(_functionsOracle != address(0), "invalid functions oracle address");
        factoryStorage = IndexFactoryStorage(_factoryStorage);
        functionsOracle = FunctionsOracle(_functionsOracle);

        __Ownable_init(msg.sender);
        __Pausable_init();
        __ReentrancyGuard_init();
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function setFunctionsOracle(address _functionsOracle) external onlyOwner returns (bool) {
        require(_functionsOracle != address(0), "invalid functions oracle address");
        functionsOracle = FunctionsOracle(_functionsOracle);
        return true;
    }

    function setIndexFactoryStorage(address _factoryStorage) external onlyOwner returns (bool) {
        require(_factoryStorage != address(0), "invalid factory storage address");
        factoryStorage = IndexFactoryStorage(_factoryStorage);
        return true;
    }

    function completeIssuance(address _indexToken, uint256 _issuanceNonce) public nonReentrant whenNotPaused {
        require(factoryStorage.checkIssuanceOrdersStatus(_indexToken, _issuanceNonce), "Orders are not completed");
        require(!factoryStorage.issuanceIsCompleted(_indexToken, _issuanceNonce), "Issuance is completed");
        address requester = factoryStorage.issuanceRequesterByNonce(_indexToken, _issuanceNonce);
        IOrderProcessor issuer = factoryStorage.issuer();
        uint256 primaryPortfolioValue;
        uint256 secondaryPortfolioValue;
        for (uint256 i; i < functionsOracle.totalCurrentList(_indexToken); i++) {
            address tokenAddress = functionsOracle.currentList(_indexToken, i);
            uint256 tokenRequestId = factoryStorage.issuanceRequestId(_indexToken, _issuanceNonce, tokenAddress);
            uint256 price = factoryStorage.priceInWei(tokenAddress);
            uint256 balance = issuer.getReceivedAmount(tokenRequestId);
            uint256 receivedValue = balance * price / 1e18;
            uint256 primaryBalance =
                factoryStorage.issuanceTokenPrimaryBalance(_indexToken, _issuanceNonce, tokenAddress);
            uint256 primaryValue = primaryBalance * price / 1e18;
            uint256 secondaryValue = primaryValue + receivedValue;
            primaryPortfolioValue += primaryValue;
            secondaryPortfolioValue += secondaryValue;
            OrderManager orderManager = factoryStorage.orderManager();
            orderManager.withdrawFunds(tokenAddress, address(this), balance);
            IERC20(tokenAddress).approve(factoryStorage.wrappedDshareAddress(tokenAddress), balance);
            WrappedDShare(factoryStorage.wrappedDshareAddress(tokenAddress)).deposit(
                balance, address(factoryStorage.vault())
            );
        }
        uint256 primaryTotalSupply = factoryStorage.issuanceIndexTokenPrimaryTotalSupply(_indexToken, _issuanceNonce);
        // if (primaryTotalSupply == 0 || primaryPortfolioValue == 0) {
        //     uint256 mintAmount = secondaryPortfolioValue / 100;
        //     IndexToken token = factoryStorage.token();
        //     token.mint(requester, mintAmount);
        //     emit Issuanced(
        //         _issuanceNonce,
        //         requester,
        //         factoryStorage.usdc(),
        //         factoryStorage.issuanceInputAmount(_issuanceNonce),
        //         mintAmount,
        //         factoryStorage.getIndexTokenPrice(),
        //         block.timestamp
        //     );
        // } else {
        //     uint256 secondaryTotalSupply = primaryTotalSupply * secondaryPortfolioValue / primaryPortfolioValue;
        //     uint256 mintAmount = secondaryTotalSupply - primaryTotalSupply;
        //     IndexToken token = factoryStorage.token();
        //     token.mint(requester, mintAmount);
        //     emit Issuanced(
        //         _issuanceNonce,
        //         requester,
        //         factoryStorage.usdc(),
        //         factoryStorage.issuanceInputAmount(_issuanceNonce),
        //         mintAmount,
        //         factoryStorage.getIndexTokenPrice(),
        //         block.timestamp
        //     );
        // }
        factoryStorage.setIssuanceIsCompleted(_indexToken, _issuanceNonce, true);
    }

    function completeRedemption(address _indexToken, uint256 _redemptionNonce) public nonReentrant whenNotPaused {
        require(
            factoryStorage.checkRedemptionOrdersStatus(_indexToken, _redemptionNonce),
            "Redemption orders are not completed"
        );
        require(!factoryStorage.redemptionIsCompleted(_indexToken, _redemptionNonce), "Redemption is completed");
        address requester = factoryStorage.redemptionRequesterByNonce(_indexToken, _redemptionNonce);
        IOrderProcessor issuer = factoryStorage.issuer();
        uint256 totalBalance;
        for (uint256 i; i < functionsOracle.totalCurrentList(_indexToken); i++) {
            address tokenAddress = functionsOracle.currentList(_indexToken, i);
            uint256 tokenRequestId = factoryStorage.redemptionRequestId(_indexToken, _redemptionNonce, tokenAddress);
            uint256 balance = issuer.getReceivedAmount(tokenRequestId);
            uint256 feeTaken = issuer.getFeesTaken(tokenRequestId);
            totalBalance += balance - feeTaken;
        }
        // uint256 fee = (totalBalance * factoryStorage.feeRate()) / 10000;
        OrderManager orderManager = factoryStorage.orderManager();
        // orderManager.withdrawFunds(factoryStorage.usdc(), factoryStorage.feeReceiver(), fee);
        // orderManager.withdrawFunds(factoryStorage.usdc(), requester, totalBalance - fee);
        factoryStorage.setRedemptionIsCompleted(_indexToken, _redemptionNonce, true);
        emit Redemption(
            _redemptionNonce,
            requester,
            factoryStorage.usdc(),
            factoryStorage.redemptionInputAmount(_indexToken, _redemptionNonce),
            totalBalance,
            block.timestamp
        );
    }

    function checkMultical(address _indexToken, uint256 _reqeustId) public view returns (bool) {
        IndexFactoryStorage.ActionInfo memory actionInfo = factoryStorage.getActionInfoById(_indexToken, _reqeustId);
        if (actionInfo.actionType == 1) {
            return factoryStorage.checkIssuanceOrdersStatus(_indexToken, actionInfo.nonce);
        } else if (actionInfo.actionType == 2) {
            return factoryStorage.checkRedemptionOrdersStatus(_indexToken, actionInfo.nonce);
        }
        return false;
    }

    function multical(address _indexToken, uint256 _requestId) public {
        IndexFactoryStorage.ActionInfo memory actionInfo = factoryStorage.getActionInfoById(_indexToken, _requestId);
        if (actionInfo.actionType == 1) {
            completeIssuance(_indexToken, actionInfo.nonce);
        } else if (actionInfo.actionType == 2) {
            completeRedemption(_indexToken, actionInfo.nonce);
        }
    }
}

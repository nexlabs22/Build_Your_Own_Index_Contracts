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
import "./StockStorage.sol";
import "./OrderManager.sol";
import "../oracle/FunctionsOracle.sol";

/// @title Index Token Factory
/// @author NEX Labs Protocol
/// @notice Allows User to initiate burn/mint requests and allows issuers to approve or deny them
contract IndexFactoryProcessor is Initializable, OwnableUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable {
    StockStorage public stockStorage;
    IndexFactoryStorage public factoryStorage;
    FunctionsOracle public functionsOracle;

    event Issuanced(uint256 indexed nonce, address indexed user, address inputToken, uint256 inputAmount, uint256 time);

    event Redemption(
        uint256 indexed nonce,
        address indexed user,
        address outputToken,
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 time
    );

    function initialize(address _indexFactoryStorage, address _stockStorage, address _functionsOracle)
        external
        initializer
    {
        require(_indexFactoryStorage != address(0), "invalid _indexFactoryStorage address");
        require(_stockStorage != address(0), "invalid _stockStorage address");
        require(_functionsOracle != address(0), "invalid _functionsOracle address");
        factoryStorage = IndexFactoryStorage(_indexFactoryStorage);
        stockStorage = StockStorage(_stockStorage);
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
        stockStorage = StockStorage(_factoryStorage);
        return true;
    }

    function completeIssuance(address _indexToken, uint256 _issuanceNonce) public nonReentrant whenNotPaused {
        require(stockStorage.checkIssuanceOrdersStatus(_indexToken, _issuanceNonce), "Orders are not completed");
        require(!stockStorage.issuanceIsCompleted(_indexToken, _issuanceNonce), "Issuance is completed");
        address requester = stockStorage.issuanceRequesterByNonce(_indexToken, _issuanceNonce);
        IOrderProcessor issuer = stockStorage.issuer();
        uint256 primaryPortfolioValue;
        uint256 secondaryPortfolioValue;

        (, address[] memory underlyingAssets,) =
            functionsOracle.getCurrentProviderIndexData(_indexToken, functionsOracle.currentFilledCount(_indexToken), 3);

        for (uint256 i; i < underlyingAssets.length; i++) {
            address tokenAddress = underlyingAssets[i];
            (uint256 primaryValue, uint256 secondaryValue, uint256 balance) =
                getCompleteIssuanceValues(tokenAddress, _indexToken, _issuanceNonce);
            primaryPortfolioValue += primaryValue;
            secondaryPortfolioValue += secondaryValue;
            OrderManager orderManager = stockStorage.orderManager();
            orderManager.withdrawFunds(tokenAddress, address(this), balance);
            _setCompleteIssuanceData(tokenAddress, balance, _indexToken);
        }
        stockStorage.issuanceIndexTokenPrimaryTotalSupply(_indexToken, _issuanceNonce);

        stockStorage.setIssuanceIsCompleted(_indexToken, _issuanceNonce, true);

        emit Issuanced(
            _issuanceNonce,
            requester,
            stockStorage.usdc(),
            stockStorage.issuanceInputAmount(_indexToken, _issuanceNonce),
            block.timestamp
        );
    }

    function getCompleteIssuanceValues(address _tokenAddress, address _indexToken, uint256 _issuanceNonce)
        internal
        view
        returns (uint256 primaryValue, uint256 secondaryValue, uint256 balance)
    {
        IOrderProcessor issuer = stockStorage.issuer();

        uint256 tokenRequestId = stockStorage.issuanceRequestId(_indexToken, _issuanceNonce, _tokenAddress);
        uint256 price = stockStorage.priceInWei(_tokenAddress);
        balance = issuer.getReceivedAmount(tokenRequestId);
        uint256 receivedValue = balance * price / 1e18;
        uint256 primaryBalance = stockStorage.issuanceTokenPrimaryBalance(_indexToken, _issuanceNonce, _tokenAddress);
        primaryValue = primaryBalance * price / 1e18;
        secondaryValue = primaryValue + receivedValue;
    }

    function _setCompleteIssuanceData(address _tokenAddress, uint256 _balance, address _indexToken) internal {
        IERC20(_tokenAddress).approve(stockStorage.wrappedDshareAddress(_tokenAddress), _balance);
        WrappedDShare(stockStorage.wrappedDshareAddress(_tokenAddress)).deposit(
            _balance, address(factoryStorage.indexTokenToVault(_indexToken))
        );
    }

    function completeRedemption(address _indexToken, uint256 _redemptionNonce) public nonReentrant whenNotPaused {
        require(
            stockStorage.checkRedemptionOrdersStatus(_indexToken, _redemptionNonce),
            "Redemption orders are not completed"
        );
        require(!stockStorage.redemptionIsCompleted(_indexToken, _redemptionNonce), "Redemption is completed");
        address requester = stockStorage.redemptionRequesterByNonce(_indexToken, _redemptionNonce);
        IOrderProcessor issuer = stockStorage.issuer();
        uint256 totalBalance;

        (, address[] memory underlyingAssets,) =
            functionsOracle.getCurrentProviderIndexData(_indexToken, functionsOracle.currentFilledCount(_indexToken), 3);

        // for (uint256 i; i < functionsOracle.totalCurrentList(_indexToken); i++) {
        for (uint256 i; i < underlyingAssets.length; i++) {
            address tokenAddress = underlyingAssets[i];
            // address tokenAddress = functionsOracle.currentList(_indexToken, i);
            uint256 tokenRequestId = stockStorage.redemptionRequestId(_indexToken, _redemptionNonce, tokenAddress);
            uint256 balance = issuer.getReceivedAmount(tokenRequestId);
            uint256 feeTaken = issuer.getFeesTaken(tokenRequestId);
            totalBalance += balance - feeTaken;
        }
        // uint256 fee = (totalBalance * stockStorage.feeRate()) / 10000;
        OrderManager orderManager = stockStorage.orderManager();
        // orderManager.withdrawFunds(stockStorage.usdc(), stockStorage.feeReceiver(), fee);
        orderManager.withdrawFunds(stockStorage.usdc(), requester, totalBalance);
        stockStorage.setRedemptionIsCompleted(_indexToken, _redemptionNonce, true);
        emit Redemption(
            _redemptionNonce,
            requester,
            stockStorage.usdc(),
            stockStorage.redemptionInputAmount(_indexToken, _redemptionNonce),
            totalBalance,
            block.timestamp
        );
    }

    function checkMultical(address _indexToken, uint256 _reqeustId) public view returns (bool) {
        StockStorage.ActionInfo memory actionInfo = stockStorage.getActionInfoById(_indexToken, _reqeustId);
        if (actionInfo.actionType == 1) {
            return stockStorage.checkIssuanceOrdersStatus(_indexToken, actionInfo.nonce);
        } else if (actionInfo.actionType == 2) {
            return stockStorage.checkRedemptionOrdersStatus(_indexToken, actionInfo.nonce);
        }
        return false;
    }

    function multical(address _indexToken, uint256 _requestId) public {
        StockStorage.ActionInfo memory actionInfo = stockStorage.getActionInfoById(_indexToken, _requestId);
        if (actionInfo.actionType == 1) {
            completeIssuance(_indexToken, actionInfo.nonce);
        } else if (actionInfo.actionType == 2) {
            completeRedemption(_indexToken, actionInfo.nonce);
        }
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {OrderManager} from "../orderManager/OrderManager.sol";
import {FunctionsOracle} from "../oracle/FunctionsOracle.sol";
import {IndexFactoryStorage} from "./IndexFactoryStorage.sol";
import {IndexToken} from "../token/IndexToken.sol";

error ZeroAmount();
error ZeroAddress();
error WrongETHAmount();

contract IndexFactory is Initializable, OwnableUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    OrderManager public orderManager;
    FunctionsOracle public functionsOracle;
    IndexFactoryStorage public factoryStorage;
    uint256 public issuanceNonce;
    uint256 public redemptionNonce;

    mapping(address => bool) public supportedIndexTokens;
    mapping(address => uint64) public assetsTypes;

    event SupportedIndexTokenUpdated(address indexed token, bool isSupported);

    uint256 private constant SHARE_DENOMINATOR = 100e18;

    function initialize(address _orderManager, address _functionsOracle, address _factoryStorage) external initializer {
        require(_orderManager != address(0), "Invalid address for _orderManager");
        require(_functionsOracle != address(0), "Invalid address for _functionsOracle");
        orderManager = OrderManager(_orderManager);
        functionsOracle = FunctionsOracle(_functionsOracle);
        factoryStorage = IndexFactoryStorage(_factoryStorage);        

        __Ownable_init(msg.sender);
        __Pausable_init();
        __ReentrancyGuard_init();
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function issuanceIndexTokens(address indexToken, uint256 amount)
        public
        payable
        whenNotPaused
        nonReentrant
        returns (uint256 orderNonce)
    {
        if (amount == 0) revert ZeroAmount();
        if (indexToken == address(0)) revert ZeroAddress();
        require(supportedIndexTokens[indexToken], "IndexFactory: unsupported index token");

        address usdc = orderManager.usdcAddress();
        IERC20(usdc).safeTransferFrom(msg.sender, address(this), amount);

        uint256 underlyingAssets = functionsOracle.totalCurrentList(indexToken);
        require(underlyingAssets > 0, "IndexFactory: no underlyings");

        IERC20(usdc).approve(address(orderManager), 0);

        uint256 allocated; // keeps track of sum of per-order amounts to fix rounding dust

        for (uint256 i = 0; i < underlyingAssets; i++) {
            address underlying = functionsOracle.currentList(indexToken, i);
            require(underlying != address(0), "IndexFactory: invalid underlying");

            uint256 marketShare = functionsOracle.tokenCurrentMarketShare(indexToken, underlying);
            // Pro-rata USDC = amount * share / 100e18
            uint256 share = (amount * marketShare) / SHARE_DENOMINATOR;

            if (i == underlyingAssets - 1) {
                share = amount - allocated;
            } else {
                allocated += share;
            }

            if (share == 0) {
                // Skip zero-sized legs to avoid pointless orders
                continue;
            }

            OrderManager.CreateOrderConfig memory cfg = OrderManager.CreateOrderConfig({
                requestNonce: issuanceNonce,
                inputTokenAddress: usdc,
                outputTokenAddress: underlying, // buy the underlying directly
                assetType: assetsTypes[underlying], // ERC20
                inputTokenAmount: share,
                outputTokenAmount: 0, // unknown at creation time
                isBuyOrder: true,
                burnPercent: 0
            });

            orderNonce = orderManager.createOrder(cfg);

            // lastOrderNonce = orderManager.createOrder(cfg);
        }

        // @notice Should manage this nonce for each index token
        issuanceNonce += 1;

        return orderNonce;
    }


    // order manager calls this
    function handleCompleteIssuance(
        uint256 _issuanceNonce,
        address _indexToken,
        address _underlyingTokenAddress, 
        uint256 _oldTokenValue,
        uint256 _newTokenValue
    ) public {
        // storing data in the mapping
        factoryStorage.setOldTokenValue(msg.sender, _underlyingTokenAddress, _issuanceNonce, _oldTokenValue);
        factoryStorage.setNewTokenValue(msg.sender, _underlyingTokenAddress, _issuanceNonce, _newTokenValue);

        // incrementing issuance completed count
        factoryStorage.incrementIssuanceCompletedAssetsCount(_indexToken, _issuanceNonce);

        // calling complete issuance
        if(factoryStorage.issuanceCompletedAssetsCount(_indexToken, _issuanceNonce) == functionsOracle.totalCurrentList(_indexToken))
        completeIssuance(_issuanceNonce, _indexToken);
    }


    function completeIssuance(
        uint256 _issuanceNonce,
        address _indexToken
    ) public {
        uint256 totalOldValues;
        uint256 totalNewValues;

        for (uint256 i = 0; i <= _issuanceNonce; i++) {
            address _underlyingTokenAddress = functionsOracle.currentList(_indexToken, i);
            totalOldValues += factoryStorage.oldTokenValue(_indexToken, _underlyingTokenAddress, i);
            totalNewValues += factoryStorage.newTokenValue(_indexToken, _underlyingTokenAddress, i);
        }

        require(totalNewValues > totalOldValues, "IndexFactory: no new tokens to mint");

        // calculate the mint amount
        uint256 totalSupply = IERC20(_indexToken).totalSupply();
        uint256 newTotalSupply = (totalSupply * totalNewValues) / totalOldValues;
        uint256 mintAmount = newTotalSupply - totalSupply;

        // mint index token for requester
        address requester = factoryStorage.issuanceRequester(_indexToken, _issuanceNonce);
        require(requester != address(0), "IndexFactory: invalid requester");
        IndexToken(_indexToken).mint(requester, mintAmount);
    }

    function redemption(address indexToken, uint256 amount)
        external
        payable
        whenNotPaused
        nonReentrant
        returns (uint256 orderNonce)
    {
        if (amount == 0) revert ZeroAmount();
        if (indexToken == address(0)) revert ZeroAddress();
        require(supportedIndexTokens[indexToken], "IndexFactory: unsupported index token");

        IERC20(indexToken).safeTransferFrom(msg.sender, address(this), amount);

        uint256 underlyingAssets = functionsOracle.totalCurrentList(indexToken);
        require(underlyingAssets > 0, "IndexFactory: no underlyings");

        IERC20(indexToken).approve(address(orderManager), amount);

        uint256 allocated;

        for (uint256 i = 0; i < underlyingAssets; i++) {
            address underlying = functionsOracle.currentList(indexToken, i);
            require(underlying != address(0), "IndexFactory: invalid underlying");

            uint256 marketShare = functionsOracle.tokenCurrentMarketShare(indexToken, underlying);

            // Pro-rata index tokens to sell for this leg
            uint256 part = (amount * marketShare) / SHARE_DENOMINATOR;

            // Push rounding dust to the last leg
            if (i == underlyingAssets - 1) {
                part = amount - allocated;
            } else {
                allocated += part;
            }

            if (part == 0) {
                continue; // skip zero-sized legs
            }

            // SELL order: input = indexToken, output (hint) = underlying
            OrderManager.CreateOrderConfig memory cfg = OrderManager.CreateOrderConfig({
                requestNonce: redemptionNonce,
                inputTokenAddress: indexToken,
                outputTokenAddress: underlying, // informational; OrderManager stores input token for sells
                assetType: assetsTypes[indexToken], // selling the index token
                inputTokenAmount: part,
                outputTokenAmount: 0,
                isBuyOrder: false,
                burnPercent: 0
            });

            orderNonce = orderManager.createOrder(cfg);
        }

        redemptionNonce += 1;

        return orderNonce;
    }

    function handleCompleteRedemption(
        uint256 _redemptionNonce,
        address _indexToken,
        address _underlyingTokenAddress, 
        uint256 _outputValue
    ) public {
        // storing data in the mapping
        factoryStorage.setRedemptionOutputValuePerToken(_redemptionNonce, _indexToken, _underlyingTokenAddress, _outputValue);

        // incrementing redemption completed count
        factoryStorage.incrementRedemptionCompletedAssetsCount(_indexToken, _redemptionNonce);

        // calling complete redemption
        if(factoryStorage.redemptionCompletedAssetsCount(_indexToken, _redemptionNonce) == functionsOracle.totalCurrentList(_indexToken))
        completeRedemption(_redemptionNonce, _indexToken);
    }

    function completeRedemption(
        uint256 _redemptionNonce,
        address _indexToken
    ) public {
        uint256 totalOutputValue = factoryStorage.redemptionTotalOutputValue(_indexToken, _redemptionNonce);
        require(totalOutputValue > 0, "IndexFactory: no output value");
        address requester = factoryStorage.redemptionRequester(_indexToken, _redemptionNonce);
        require(requester != address(0), "IndexFactory: invalid requester");
        address usdc = orderManager.usdcAddress();
        IERC20(usdc).safeTransfer(requester, totalOutputValue);
    }

    function setSupportedIndexToken(address token, bool status) external onlyOwner {
        if (token == address(0)) revert ZeroAddress();
        supportedIndexTokens[token] = status;
        emit SupportedIndexTokenUpdated(token, status);
    }

    function setFunctionsOracle(address _oracle) external onlyOwner {
        if (_oracle == address(0)) revert ZeroAddress();
        functionsOracle = FunctionsOracle(_oracle);
    }

    function setAssetType(address token, uint64 assetType) external onlyOwner {
        if (token == address(0)) revert ZeroAddress();
        assetsTypes[token] = assetType;
    }

    function setAssetTypes(address[] calldata tokens, uint64[] calldata assetTypes) external onlyOwner {
        require(tokens.length == assetTypes.length, "length mismatch");
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == address(0)) revert ZeroAddress();
            assetsTypes[tokens[i]] = assetTypes[i];
        }
    }

    // /**
    //  * @dev Pauses the contract.
    //  */
    // function pause() external onlyOwnerOrOperator {
    //     _pause();
    // }

    // /**
    //  * @dev Unpauses the contract.
    //  */
    // function unpause() external onlyOwnerOrOperator {
    //     _unpause();
    // }
}

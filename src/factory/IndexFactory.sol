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
import {Vault} from "../vault/Vault.sol";
import {FeeCalculation} from "../libraries/FeeCalculation.sol";

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
    event Issuanced(
        uint256 indexed requestNonce,
        address indexed user,
        address indexed indexToken,
        address inputToken,
        address outputToken,
        uint256 amount
    );
    event Redemption(
        uint256 indexed requestNonce,
        address indexed user,
        address indexed indexToken,
        address inputToken,
        address outputToken,
        uint256 amount
    );

    uint256 private constant SHARE_DENOMINATOR = 100e18;

    function initialize(address _orderManager, address _functionsOracle, address _factoryStorage)
        external
        initializer
    {
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

    // =========================
    // === External Functions ==
    // =========================

    function issuanceIndexTokens(address indexToken, uint256 amount)
        public
        payable
        whenNotPaused
        nonReentrant
        returns (uint256 orderNonce)
    {
        _validateIssuanceInputs(indexToken, amount);

        address usdc = orderManager.usdcAddress();
        uint256 usdcFee = FeeCalculation.calculateFee(amount, factoryStorage.feeRate());

        _collectUsdcAndFee(usdc, amount, usdcFee);
        factoryStorage.setIssuanceRequester(indexToken, issuanceNonce, msg.sender);

        uint256 totalCurrentList = _requireUnderlyings(indexToken);
        _approveForOrderManager(usdc, amount);

        (address[] memory underlyings, uint256[] memory parts) = _calcProRataUSDC(indexToken, amount, totalCurrentList);

        for (uint256 i = 0; i < totalCurrentList; i++) {
            if (parts[i] == 0) continue;
            orderNonce = _createBuyOrder(issuanceNonce, usdc, underlyings[i], assetsTypes[underlyings[i]], parts[i]);
            emit Issuanced(issuanceNonce, msg.sender, indexToken, usdc, underlyings[i], parts[i]);
        }

        issuanceNonce += 1;
        return orderNonce;
    }

    function redemption(address indexToken, uint256 amount)
        external
        payable
        whenNotPaused
        nonReentrant
        returns (uint256 orderNonce)
    {
        _validateRedemptionInputs(indexToken, amount);

        // Pull and burn
        IERC20(indexToken).safeTransferFrom(msg.sender, address(this), amount);
        uint256 burnPercent = _computeBurnPercent(indexToken, amount);
        IndexToken(indexToken).burn(address(this), amount);

        uint256 totalCurrentList = _requireUnderlyings(indexToken);
        address vaultAddr = _getVault(indexToken);
        address usdc = orderManager.usdcAddress();

        for (uint256 i = 0; i < totalCurrentList; i++) {
            address underlying = functionsOracle.currentList(indexToken, i);
            require(underlying != address(0), "IndexFactory: invalid underlying");

            uint64 assetType = assetsTypes[underlying];
            uint256 withdrawn = 0;

            if (assetType != 2) {
                withdrawn = _withdrawProRataFromVault(vaultAddr, underlying, burnPercent);
                if (withdrawn > 0) {
                    _approveExactForOrderManager(underlying, withdrawn);
                }
            }

            orderNonce = _createSellOrder(
                redemptionNonce,
                underlying, // input for sells (or 0 amount for type 2)
                usdc, // output hint
                assetType,
                (assetType == 2) ? 0 : withdrawn,
                burnPercent
            );

            emit Redemption(redemptionNonce, msg.sender, indexToken, underlying, address(0), withdrawn);
        }

        factoryStorage.setRedemptionRequester(indexToken, redemptionNonce, msg.sender);
        redemptionNonce += 1;
        return orderNonce;
    }

    // =========================
    // ======= Callbacks =======
    // =========================

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
        if (
            factoryStorage.issuanceCompletedAssetsCount(_indexToken, _issuanceNonce)
                == functionsOracle.totalCurrentList(_indexToken)
        ) {
            completeIssuance(_issuanceNonce, _indexToken);
        }
    }

    function handleCompleteRedemption(
        uint256 _redemptionNonce,
        address _indexToken,
        address _underlyingTokenAddress,
        uint256 _outputValue
    ) public {
        // storing data in the mapping
        factoryStorage.setRedemptionOutputValuePerToken(
            _redemptionNonce, _indexToken, _underlyingTokenAddress, _outputValue
        );

        // incrementing redemption completed count
        factoryStorage.incrementRedemptionCompletedAssetsCount(_indexToken, _redemptionNonce);

        // calling complete redemption
        if (
            factoryStorage.redemptionCompletedAssetsCount(_indexToken, _redemptionNonce)
                == functionsOracle.totalCurrentList(_indexToken)
        ) {
            completeRedemption(_redemptionNonce, _indexToken);
        }
    }

    function completeIssuance(uint256 _issuanceNonce, address _indexToken) public {
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

    function completeRedemption(uint256 _redemptionNonce, address _indexToken) public {
        uint256 totalOutputValue = factoryStorage.redemptionTotalOutputValue(_indexToken, _redemptionNonce);
        require(totalOutputValue > 0, "IndexFactory: no output value");
        address requester = factoryStorage.redemptionRequester(_indexToken, _redemptionNonce);
        require(requester != address(0), "IndexFactory: invalid requester");
        address usdc = orderManager.usdcAddress();
        IERC20(usdc).safeTransfer(requester, totalOutputValue);
    }

    // =========================
    // ========= Admin =========
    // =========================
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

    // ===================================
    // =========== Internals =============
    // ===================================
    function _validateIssuanceInputs(address indexToken, uint256 amount) private view {
        if (amount == 0) revert ZeroAmount();
        if (indexToken == address(0)) revert ZeroAddress();
        require(supportedIndexTokens[indexToken], "IndexFactory: unsupported index token");
    }

    function _validateRedemptionInputs(address indexToken, uint256 amount) private view {
        if (amount == 0) revert ZeroAmount();
        if (indexToken == address(0)) revert ZeroAddress();
        require(supportedIndexTokens[indexToken], "IndexFactory: unsupported index token");
    }

    function _collectUsdcAndFee(address usdc, uint256 amount, uint256 usdcFee) private {
        IERC20(usdc).safeTransferFrom(msg.sender, address(this), amount);
        if (usdcFee > 0) {
            IERC20(usdc).safeTransferFrom(msg.sender, factoryStorage.feeReceiver(), usdcFee);
        }
    }

    function _requireUnderlyings(address indexToken) private view returns (uint256 totalCurrentList) {
        totalCurrentList = functionsOracle.totalCurrentList(indexToken);
        require(totalCurrentList > 0, "IndexFactory: no underlyings");
    }

    function _approveForOrderManager(address token, uint256 amount) private {
        IERC20(token).approve(address(orderManager), 0);
        IERC20(token).approve(address(orderManager), amount);
    }

    function _approveExactForOrderManager(address token, uint256 amount) private {
        IERC20(token).approve(address(orderManager), 0);
        IERC20(token).approve(address(orderManager), amount);
    }

    function _calcProRataUSDC(address indexToken, uint256 amount, uint256 totalList)
        private
        view
        returns (address[] memory underlyings, uint256[] memory parts)
    {
        underlyings = new address[](totalList);
        parts = new uint256[](totalList);

        uint256 allocated;
        for (uint256 i = 0; i < totalList; i++) {
            address underlying = functionsOracle.currentList(indexToken, i);
            require(underlying != address(0), "IndexFactory: invalid underlying");
            underlyings[i] = underlying;

            uint256 marketShares = functionsOracle.tokenCurrentMarketShare(indexToken, underlying);
            uint256 share = (amount * marketShares) / SHARE_DENOMINATOR;

            if (i == totalList - 1) {
                share = amount - allocated; // mop up dust
            } else {
                allocated += share;
            }
            parts[i] = share;
        }
    }

    function _computeBurnPercent(address indexToken, uint256 amount) private view returns (uint256 burnPercent) {
        uint256 totalSupply = IERC20(indexToken).totalSupply();
        require(totalSupply > 0, "IndexFactory: zero supply");
        burnPercent = (amount * 1e18) / totalSupply; // 1e18 scaled
    }

    function _getVault(address indexToken) private view returns (address vaultAddr) {
        vaultAddr = factoryStorage.indexTokenToVault(indexToken);
        require(vaultAddr != address(0), "IndexFactory: no vault");
    }

    function _withdrawProRataFromVault(address vaultAddr, address underlying, uint256 burnPercent)
        private
        returns (uint256 withdrawn)
    {
        uint256 balance = IERC20(underlying).balanceOf(vaultAddr);
        if (balance == 0) return 0;
        withdrawn = (balance * burnPercent) / 1e18;
        if (withdrawn == 0) return 0;

        Vault(vaultAddr).withdrawFunds(underlying, address(this), withdrawn);
    }

    function _createBuyOrder(uint256 requestNonce_, address usdc, address underlying, uint64 assetType_, uint256 share)
        private
        returns (uint256 orderNonce)
    {
        OrderManager.CreateOrderConfig memory cfg = OrderManager.CreateOrderConfig({
            requestNonce: requestNonce_,
            inputTokenAddress: usdc,
            outputTokenAddress: underlying,
            assetType: assetType_,
            inputTokenAmount: share,
            outputTokenAmount: 0,
            isBuyOrder: true,
            burnPercent: 0
        });
        orderNonce = orderManager.createOrder(cfg);
    }

    function _createSellOrder(
        uint256 requestNonce_,
        address inputToken, // underlying leg
        address outputTokenHint, // e.g., USDC
        uint64 assetType_,
        uint256 inputAmount, // 0 when assetType==2
        uint256 burnPercent_
    ) private returns (uint256 orderNonce) {
        OrderManager.CreateOrderConfig memory cfg = OrderManager.CreateOrderConfig({
            requestNonce: requestNonce_,
            inputTokenAddress: inputToken,
            outputTokenAddress: outputTokenHint,
            assetType: assetType_,
            inputTokenAmount: inputAmount,
            outputTokenAmount: 0,
            isBuyOrder: false,
            burnPercent: burnPercent_
        });
        orderNonce = orderManager.createOrder(cfg);
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

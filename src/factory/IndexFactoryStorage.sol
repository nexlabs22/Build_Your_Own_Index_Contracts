// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {OrderManager} from "../orderManager/OrderManager.sol";
import {FunctionsOracle} from "../oracle/FunctionsOracle.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "../utils/proposable/ProposableOwnableUpgradeable.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

// error ZeroAmount();
// error ZeroAddress();
// error WrongETHAmount();

contract IndexFactoryStorage is Initializable, ProposableOwnableUpgradeable {
    address public indexFactory;
    address public mainChainBalancer;
    address public orderManager;
    address public feeReceiver;
    address public usdcAddress;

    AggregatorV3Interface public toUsdPriceFeed;

    uint8 public feeRate;

    mapping(address => address) public indexTokenToVault;

    mapping(address => mapping(uint256 => address)) public issuanceRequester; // user => issuanceNonce => requester
    mapping(address => mapping(uint256 => address)) public redemptionRequester; // user => redemption
    mapping(address => mapping(address => mapping(uint256 => uint256))) public oldTokenValue; // user => token => issuanceNonce => value
    mapping(address => mapping(address => mapping(uint256 => uint256))) public newTokenValue; // user => token => issuanceNonce => value

    // redemption output values
    mapping(address => mapping(uint256 => mapping(address => uint256))) public redemptionOutputValuePerToken; // user => redemptionNonce => token => value
    mapping(address => mapping(uint256 => uint256)) public redemptionTotalOutputValue; // user => redemptionNonce => value

    // issuance completed count
    mapping(address => mapping(uint256 => uint256)) public issuanceCompletedAssetsCount; // issuanceNonce => count
    mapping(address => mapping(uint256 => uint256)) public redemptionCompletedAssetsCount; // redemptionNonce => count

    mapping(address => address) public vaultToIndexToken;
    mapping(address => address) public indexTokenToFeeVault;

    modifier onlyIndexFactory() {
        require(msg.sender == indexFactory, "IndexFactoryStorage: only index factory");
        _;
    }

    modifier onlyOrderManager() {
        require(msg.sender == orderManager, "IndexFactoryStorage: only order manager");
        _;
    }

    function initialize() external initializer {
        __Ownable_init(msg.sender);
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Converts ETH amount to USD.
     * @param _ethAmount The amount of ETH.
     * @return The equivalent amount in USD.
     */
    function convertEthToUsd(uint256 _ethAmount) public view returns (uint256) {
        return (_ethAmount * priceInWei()) / 1e18;
    }

    /**
     * @dev Returns the price in Wei.
     * @return The price in Wei.
     */
    function priceInWei() public view returns (uint256) {
        (uint80 roundId, int256 price,, uint256 _updatedAt,) = toUsdPriceFeed.latestRoundData();
        require(roundId != 0, "invalid round id");
        require(_updatedAt != 0 && _updatedAt <= block.timestamp, "invalid updated time");
        require(price > 0, "invalid price");
        require(block.timestamp - _updatedAt < 1 days, "invalid updated time");

        uint8 priceFeedDecimals = toUsdPriceFeed.decimals();
        price = _toWei(price, priceFeedDecimals, 18);
        return uint256(price);
    }

    /**
     * @dev Converts an amount to Wei.
     * @param _amount The amount to convert.
     * @param _amountDecimals The decimals of the amount.
     * @param _chainDecimals The decimals of the chain.
     * @return The amount in Wei.
     */
    function _toWei(int256 _amount, uint8 _amountDecimals, uint8 _chainDecimals) private pure returns (int256) {
        if (_chainDecimals > _amountDecimals) {
            return _amount * int256(10 ** (_chainDecimals - _amountDecimals));
        } else {
            return _amount * int256(10 ** (_amountDecimals - _chainDecimals));
        }
    }

    function setIndexFactory(address _indexFactory) external onlyOwner {
        // if (_indexFactory == address(0)) revert ZeroAddress();
        indexFactory = _indexFactory;
    }

    function setUsdcAddress(address _usdcAddress) external onlyOwner {
        // if (_usdcAddress == address(0)) revert ZeroAddress();
        usdcAddress = _usdcAddress;
    }

    function setToUsdPriceFeed(address _toUsdPriceFeed) external onlyOwner {
        // if (_toUsdPriceFeed == address(0)) revert ZeroAddress();
        toUsdPriceFeed = AggregatorV3Interface(_toUsdPriceFeed);
    }

    function setMainChainBalancer(address _mainChainBalancer) external onlyOwner {
        // if (_mainChainBalancer == address(0)) revert ZeroAddress();
        mainChainBalancer = _mainChainBalancer;
    }

    function setIndexTokenToVault(address _indexToken, address _vault) external onlyOwner {
        // if (_indexToken == address(0) || _vault == address(0)) revert ZeroAddress();
        indexTokenToVault[_indexToken] = _vault;
    }

    function setIndexTokenToFeeVault(address _indexToken, address _feeVault) external onlyOwner {
        // if (_indexToken == address(0) || _vault == address(0)) revert ZeroAddress();
        indexTokenToFeeVault[_indexToken] = _feeVault;
    }

    function setVaultToIndexToken(address _vault, address _indexToken) external onlyOwner {
        // if (_indexToken == address(0) || _vault == address(0)) revert ZeroAddress();
        vaultToIndexToken[_vault] = _indexToken;
    }

    function setOrderManager(address _orderManager) external onlyOwner {
        // if (_orderManager == address(0)) revert ZeroAddress();
        orderManager = _orderManager;
    }

    // update issuance requester mapping
    function setIssuanceRequester(address _indexToken, uint256 _issuanceNonce, address _requester)
        external
        onlyIndexFactory
    {
        issuanceRequester[_indexToken][_issuanceNonce] = _requester;
    }

    // update redemption requester mapping
    function setRedemptionRequester(address _indexToken, uint256 _redemptionNonce, address _requester)
        external
        onlyIndexFactory
    {
        redemptionRequester[_indexToken][_redemptionNonce] = _requester;
    }
    // update old token value mapping

    function setOldTokenValue(address _indexToken, address _token, uint256 _issuanceNonce, uint256 _value)
        external
        onlyIndexFactory
    {
        oldTokenValue[_indexToken][_token][_issuanceNonce] = _value;
    }

    // update new token value mapping
    function setNewTokenValue(address _indexToken, address _token, uint256 _issuanceNonce, uint256 _value)
        external
        onlyIndexFactory
    {
        newTokenValue[_indexToken][_token][_issuanceNonce] = _value;
    }

    // update issuance completed count
    function incrementIssuanceCompletedAssetsCount(address _indexToken, uint256 _user) external onlyIndexFactory {
        issuanceCompletedAssetsCount[_indexToken][_user]++;
    }

    // update redemption completed count
    function incrementRedemptionCompletedAssetsCount(address _indexToken, uint256 _user) external onlyIndexFactory {
        redemptionCompletedAssetsCount[_indexToken][_user]++;
    }

    // update redemption output value per token mapping
    function setRedemptionOutputValuePerToken(
        uint256 _redemptionNonce,
        address _indexToken,
        address _token,
        uint256 _value
    ) external onlyIndexFactory {
        redemptionOutputValuePerToken[_indexToken][_redemptionNonce][_token] = _value;
        redemptionTotalOutputValue[_indexToken][_redemptionNonce] += _value;
    }
}

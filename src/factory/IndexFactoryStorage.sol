// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {OrderManager} from "../orderManager/OrderManager.sol";
import {FunctionsOracle} from "../oracle/FunctionsOracle.sol";

// error ZeroAmount();
// error ZeroAddress();
// error WrongETHAmount();

contract IndexFactoryStorage {

    address public indexFactory;
    address public indexFactoryBalancer;
    address public orderManager;
    address public feeReceiver;

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


    function setIndexFactory(address _indexFactory) external {
        // if (_indexFactory == address(0)) revert ZeroAddress();
        indexFactory = _indexFactory;
    }

    function setIndexFactoryBalancer(address _indexFactoryBalancer) external {
        // if (_indexFactoryBalancer == address(0)) revert ZeroAddress();
        indexFactoryBalancer = _indexFactoryBalancer;
    }

    function setOrderManager(address _orderManager) external {
        // if (_orderManager == address(0)) revert ZeroAddress();
        orderManager = _orderManager;
    }


    // update issuance requester mapping
    function setIssuanceRequester(address _user, uint256 _issuanceNonce, address _requester) external {
        issuanceRequester[_user][_issuanceNonce] = _requester;
    }

    // update redemption requester mapping
    function setRedemptionRequester(address _user, uint256 _redemptionNonce, address _requester) external {
        redemptionRequester[_user][_redemptionNonce] = _requester;
    }
    // update old token value mapping

    function setOldTokenValue(address _user, address _token, uint256 _issuanceNonce, uint256 _value) external {
        oldTokenValue[_user][_token][_issuanceNonce] = _value;
    }

    // update new token value mapping
    function setNewTokenValue(address _user, address _token, uint256 _issuanceNonce, uint256 _value) external {
        newTokenValue[_user][_token][_issuanceNonce] = _value;
    }

    // update issuance completed count
    function incrementIssuanceCompletedAssetsCount(address _indexToken, uint256 _user) external {
        issuanceCompletedAssetsCount[_indexToken][_user]++;
    }

    // update redemption completed count
    function incrementRedemptionCompletedAssetsCount(address _indexToken, uint256 _user) external {
        redemptionCompletedAssetsCount[_indexToken][_user]++;
    }

    // update redemption output value per token mapping
    function setRedemptionOutputValuePerToken(
        uint256 _redemptionNonce,
        address _indexToken,
        address _token,
        uint256 _value
    ) external {
        redemptionOutputValuePerToken[_indexToken][_redemptionNonce][_token] = _value;
        redemptionTotalOutputValue[_indexToken][_redemptionNonce] += _value;
    }
}

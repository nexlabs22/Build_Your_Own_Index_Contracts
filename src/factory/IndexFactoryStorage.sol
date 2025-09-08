pragma solidity 0.8.25;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {OrderManager} from "../orderManager/OrderManager.sol";
import {FunctionsOracle} from "../oracle/FunctionsOracle.sol";

error ZeroAmount();
error ZeroAddress();
error WrongETHAmount();

contract IndexFactoryStorage {

    mapping (address => mapping(uint256 => address)) public issuanceRequester; // user => issuanceNonce => requester
    mapping (address => mapping(uint256 => address)) public redemptionRequester; // user => redemption
    mapping(address => mapping(address => mapping(uint256 => uint256))) public oldTokenValue; // user => token => issuanceNonce => value
    mapping(address => mapping(address => mapping(uint256 => uint256))) public newTokenValue; // user => token => issuanceNonce => value

    // redemption output values
    mapping(address => mapping(uint256 => mapping(address => uint256))) public redemptionOutputValuePerToken; // user => redemptionNonce => token => value
    mapping(address => mapping(uint256 => uint256)) public redemptionTotalOutputValue; // user => redemptionNonce => value

    // issuance completed count
    mapping(address => mapping(uint256 => uint256)) public issuanceCompletedAssetsCount; // issuanceNonce => count
    mapping(address => mapping(uint256 => uint256)) public redemptionCompletedAssetsCount; // redemptionNonce => count

    // update issuance requester mapping
    function setIssuanceRequester(
        address _user,
        uint256 _issuanceNonce,
        address _requester
    ) external {
        issuanceRequester[_user][_issuanceNonce] = _requester;
    }

    // update redemption requester mapping
    function setRedemptionRequester(
        address _user,
        uint256 _redemptionNonce,
        address _requester
    ) external {
        redemptionRequester[_user][_redemptionNonce] = _requester;
    }
    // update old token value mapping
    function setOldTokenValue(
        address _user,
        address _token,
        uint256 _issuanceNonce,
        uint256 _value
    ) external {
        oldTokenValue[_user][_token][_issuanceNonce] = _value;
    }

    // update new token value mapping
    function setNewTokenValue(
        address _user,
        address _token,
        uint256 _issuanceNonce,
        uint256 _value
    ) external {
        newTokenValue[_user][_token][_issuanceNonce] = _value;
    }

    // update issuance completed count
    function incrementIssuanceCompletedAssetsCount(
        address _indexToken,
        uint256 _user
    ) external {
        issuanceCompletedAssetsCount[_indexToken][_user]++;
    }

    // update redemption completed count
    function incrementRedemptionCompletedAssetsCount(
        address _indexToken,
        uint256 _user
    ) external {
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
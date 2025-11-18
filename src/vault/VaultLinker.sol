// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./Vault.sol";

contract VaultLinker is Initializable, OwnableUpgradeable {
    using SafeERC20 for IERC20;

    mapping(address => bool) public isOperator;

    address mainchainFactory;
    address mainchainBalancer;
    address dinariFactory;
    address dinariBalancer;

    modifier onlyOperator() {
        require(isOperator[msg.sender], "NexVault: caller is not an operator");
        _;
    }

    function initialize(
        address _operator,
        address _mainchainFactory,
        address _mainchainBalancer,
        address _dinariFactory,
        address _dinariBalancer
    ) external initializer {
        mainchainFactory = _mainchainFactory;
        mainchainBalancer = _mainchainBalancer;
        dinariFactory = _dinariFactory;
        dinariBalancer = _dinariBalancer;
        __Ownable_init(msg.sender);
        isOperator[_operator] = true;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function setOperators(address vault, address[] memory operators) public onlyOperator {
        for (uint256 i = 0; i <= operators.length; i++) {
            Vault(vault).setOperator(operators[i], true);
        }
    }

    function setOperator(address _operator, bool _status) external onlyOwner {
        isOperator[_operator] = _status;
    }
}

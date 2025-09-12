// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol"; // Corrected import style
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract ProposableOwnableUpgradeable is Initializable, OwnableUpgradeable {
    // No explicit __ProposableOwnableUpgradeable_init function is needed
    // as it solely relies on OwnableUpgradeable's __Ownable_init
    // and Initializable's __Initializable_init.
}

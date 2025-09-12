// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IOwnable} from "@chainlink/contracts/src/v0.8/shared/interfaces/IOwnable.sol";

/// @title The ConfirmedOwner contract
/// @notice A contract with helpers for basic contract ownership.
contract ConfirmedOwnerWithProposal is IOwnable {
    address private sOwner; // Corrected variable name
    address private sPendingOwner; // Corrected variable name

    event OwnershipTransferRequested(address indexed from, address indexed to);
    event OwnershipTransferred(address indexed from, address indexed to);

    function _ConfirmedOwnerWithProposal_init(address newOwner, address pendingOwner) internal { // Corrected function name
        // solhint-disable-next-line gas-custom-errors
        require(newOwner != address(0), "Cannot set owner to zero");

        sOwner = newOwner;
        if (pendingOwner != address(0)) {
            _transferOwnership(pendingOwner);
        }
    }

    /// @notice Allows an owner to begin transferring ownership to a new address.
    function transferOwnership(address to) public override onlyOwner {
        _transferOwnership(to);
    }

    /// @notice Allows an ownership transfer to be completed by the recipient.
    function acceptOwnership() external override {
        // solhint-disable-next-line gas-custom-errors
        require(msg.sender == sPendingOwner, "Must be proposed owner"); // Corrected variable name

        address oldOwner = sOwner; // Corrected variable name
        sOwner = msg.sender; // Corrected variable name
        sPendingOwner = address(0); // Corrected variable name

        emit OwnershipTransferred(oldOwner, msg.sender);
    }

    /// @notice Get the current owner
    function owner() public view override returns (address) {
        return sOwner; // Corrected variable name
    }

    /// @notice validate, transfer ownership, and emit relevant events
    function _transferOwnership(address to) private {
        // solhint-disable-next-line gas-custom-errors
        require(to != msg.sender, "Cannot transfer to self");

        sPendingOwner = to; // Corrected variable name

        emit OwnershipTransferRequested(sOwner, to); // Corrected variable name
    }

    /// @notice validate access
    function _validateOwnership() internal view {
        // solhint-disable-next-line gas-custom-errors
        require(msg.sender == sOwner, "Only callable by owner"); // Corrected variable name
    }

    /// @notice Reverts if called by anyone other than the contract owner.
    modifier onlyOwner() {
        _validateOwnership();
        _;
    }
}

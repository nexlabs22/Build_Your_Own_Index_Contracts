// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library PathHelpers {

    function getFromETHPathBytes(address[] memory _path, uint24[] memory _fees) public pure returns (bytes memory) {
        return abi.encode(_path, _fees);
    }

    function getZeroFromETHPathBytes() public pure returns (bytes memory) {
        return abi.encode(new address[](0), new uint24[](0));
    }

    function decodePathBytes(bytes memory _pathBytes) public pure returns (address[] memory, uint24[] memory) {
        return abi.decode(_pathBytes, (address[], uint24[]));
    }

    function reverseUint24Array(uint24[] memory input) public pure returns (uint24[] memory) {
        uint256 length = input.length;

        for (uint256 i = 0; i < length / 2; i++) {
            // Swap elements
            (input[i], input[length - 1 - i]) = (input[length - 1 - i], input[i]);
        }

        return input;
    }

    function reverseAddressArray(address[] memory input) public pure returns (address[] memory) {
        uint256 length = input.length;

        for (uint256 i = 0; i < length / 2; i++) {
            // Swap elements
            (input[i], input[length - 1 - i]) = (input[length - 1 - i], input[i]);
        }

        return input;
    }

    function encodePath(address[] memory tokens, uint24[] memory fees)
        public
        pure
        returns (bytes memory path)
    {
        require(tokens.length == fees.length + 1, "Invalid input arrays");

        for (uint256 i = 0; i < fees.length; i++) {
            // Concatenate token address and fee tier
            path = abi.encodePacked(path, tokens[i], fees[i]);
        }

        // Append the final token address
        path = abi.encodePacked(path, tokens[tokens.length - 1]);
    }
}
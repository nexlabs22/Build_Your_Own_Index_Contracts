// test/utils/MockContracts.sol
// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol"; // Corrected import style
// Removed unused import {Ownable}

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, 1000000 * 1e18);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}

contract MockUSDC is ERC20 {
    constructor() ERC20("USD Coin", "USDC") {
        _mint(msg.sender, 10000000 * 1e6); // 10M USDC with 6 decimals
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MockFunctionsRouter {
    function sendRequest(
        bytes32 donId,
        bytes memory data,
        uint64 subscriptionId,
        uint32 gasLimit,
        bytes32 jobId
    ) external pure returns (bytes32) { // Added pure
        return keccak256(abi.encodePacked(donId, data, subscriptionId, gasLimit, jobId));
    }
}

contract MockBalancerFactory {
    function createPool() external pure returns (address) {
        return address(0x1234567890123456789012345678901234567890);
    }
}


// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { SwapHelpers } from "../libraries/SwapHelpers.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";



contract CCIPFactory is Initializable, OwnableUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    

    function initialize() external initializer {
        __Ownable_init(msg.sender);
        __Pausable_init();
        __ReentrancyGuard_init();
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // /**
    //  * @dev Internal function to swap tokens.
    //  * @param path The path of the tokens to swap.
    //  * @param fees The fees of the tokens to swap.
    //  * @param amountIn The amount of input token.
    //  * @param _recipient The address of the recipient.
    //  * @return outputAmount The amount of output token.
    //  */
    // function swap(
    //     address[] memory path,
    //     uint24[] memory fees,
    //     uint256 amountIn,
    //     address _recipient
    // ) internal returns (uint256 outputAmount) {
    //     ISwapRouter swapRouterV3 = factoryStorage.swapRouterV3();
    //     IUniswapV2Router02 swapRouterV2 = factoryStorage.swapRouterV2();
    //     uint256 amountOutMinimum = factoryStorage.getMinAmountOut(path, fees, amountIn);
    //     outputAmount = SwapHelpers.swap(
    //         swapRouterV3,
    //         swapRouterV2,
    //         path,
    //         fees,
    //         amountIn,
    //         amountOutMinimum,
    //         _recipient
    //     );
    // }


    function issuanceDefi(address _indexToken, address _tokenIn, uint256 _amountIn)
        public
        payable
        whenNotPaused
        nonReentrant
        returns (uint256 orderNonce)
    {
        IERC20(_tokenIn).safeTransferFrom(
            msg.sender,
            address(this),
            _amountIn
        );

        // uint256 wethAmountBeforFee = swap(
        //     _tokenInPath,
        //     _tokenInFees,
        //     _amountIn + feeAmount,
        //     address(this)
        // );
    }
}

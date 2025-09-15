// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Client} from "contracts-ccip/contracts/libraries/Client.sol";
import {IRouterClient} from "contracts-ccip/contracts/interfaces/IRouterClient.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

library MessageSender {
    using Client for *;

    function sendToken(
        address i_router,
        address i_link,
        uint16 i_maxTokensLength,
        uint64 destinationChainSelector,
        bytes memory _data,
        address receiver,
        Client.EVMTokenAmount[] memory tokensToSendDetails,
        PayFeesIn payFeesIn,
        uint256 _gasLimit
    ) internal returns (bytes32) {
        uint256 length = tokensToSendDetails.length;
        require(length <= i_maxTokensLength, "Maximum 5 different tokens can be sent per CCIP Message");

        for (uint256 i = 0; i < length;) {
            if (tokensToSendDetails[i].token != i_link) {
                IERC20(tokensToSendDetails[i].token).approve(i_router, tokensToSendDetails[i].amount);
            }
            unchecked {
                ++i;
            }
        }

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(receiver),
            data: _data,
            tokenAmounts: tokensToSendDetails,
            extraArgs: Client._argsToBytes(
                // Client.EVMExtraArgsV1({gasLimit: 3_000_000})
                Client.EVMExtraArgsV1({gasLimit: _gasLimit})
            ),
            feeToken: payFeesIn == PayFeesIn.LINK ? i_link : address(0)
        });

        uint256 fee = IRouterClient(i_router).getFee(destinationChainSelector, message);

        bytes32 messageId;

        if (payFeesIn == PayFeesIn.LINK) {
            messageId = IRouterClient(i_router).ccipSend(destinationChainSelector, message);
        } else {
            messageId = IRouterClient(i_router).ccipSend{value: fee}(destinationChainSelector, message);
        }

        // emit IndexFactory.MessageSent(messageId);

        return messageId;
    }

    enum PayFeesIn {
        Native,
        LINK
    }

    function sendMessage(
        address i_router,
        address i_link,
        uint64 destinationChainSelector,
        address receiver,
        bytes memory _data,
        PayFeesIn payFeesIn,
        uint256 _gasLimit
    ) internal returns (bytes32) {
        require(i_router != address(0), "Invalid i_router address");
        require(i_link != address(0), "Invalid i_link address");
        require(destinationChainSelector != 0, "Invalid destinationChainSelector");
        require(receiver != address(0), "Invalid receiver address");
        require(_data.length > 0, "Invalid data");
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(receiver),
            data: _data,
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: Client._argsToBytes(
                // Client.EVMExtraArgsV1({gasLimit: 3_000_000})
                Client.EVMExtraArgsV1({gasLimit: _gasLimit})
            ),
            feeToken: payFeesIn == PayFeesIn.LINK ? i_link : address(0)
        });

        uint256 fee = IRouterClient(i_router).getFee(destinationChainSelector, message);

        bytes32 messageId;

        if (payFeesIn == PayFeesIn.LINK) {
            messageId = IRouterClient(i_router).ccipSend(destinationChainSelector, message);
        } else {
            messageId = IRouterClient(i_router).ccipSend{value: fee}(destinationChainSelector, message);
        }

        // emit IndexFactory.MessageSent(messageId);

        return messageId;
    }
}

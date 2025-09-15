// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
// pragma experimental ABIEncoderV2;
// import "chainlink/contracts/src/v0.8/libs/LinkTokenReceiver.sol";
// import "chainlink/contracts/src/v0.8/libs/SafeMathChainlink.sol";
// import "chainlink/contracts/src/v0.8/interfaces/ChainlinkRequestInterface.sol";
// import "chainlink/contracts/src/v0.8/interfaces/LinkTokenInterface.sol";

/**
 * @title The Chainlink Mock Oracle contract
 * @notice Chainlink smart contract developers can use this to test their contracts
 */
contract MockApiOracle {
  
  uint public counter;
  uint public counter2;
  bytes32 public preRequestId;
  function sendRequest(
    uint64 subscriptionId,
    bytes calldata data,
    uint16 dataVersion,
    uint32 callbackGasLimit,
    bytes32 donId
  ) external returns (bytes32) {
    // return getRandomBytes32();
    counter++;
    return keccak256(abi.encodePacked(block.timestamp, counter));
  }
  
  function fulfillRequest(address _requester, bytes32 _requestId, bytes memory _data)
    external
    returns (bool)
  {
    if(_requestId != preRequestId){
      preRequestId = _requestId;
      counter2++;
    }
    bytes memory err;
    (bool success, ) = _requester.call(
      // abi.encodeWithSelector(req.callbackFunctionId, _requestId, _data1, _data2, _data3, _data4, _data5)
      // abi.encodeWithSelector(req.callbackFunctionId, _requestId, convertUintToBytes32(price), convertIntToBytes32Array(fundingRate), convertStringToBytes32Array(strings))
      abi.encodeWithSelector(this.handleOracleFulfillment.selector, _requestId, _data, err)
    ); // solhint-disable-line avoid-low-level-calls
    require(success, "MockOracle: fulfilling request faild");
    return success;
  }

  function handleOracleFulfillment(bytes32 requestId, bytes memory response, bytes memory err) external {
    
  }

  function getRandomBytes32() public view returns (bytes32) {
        // Use block properties and msg.sender as entropy
        return keccak256(
            abi.encodePacked(
                block.timestamp,    // Current block timestamp
                block.difficulty,   // Current block difficulty
                msg.sender          // Address of the caller
            )
        );
    }
  
}
// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "../utils/chainlink/FunctionsClient.sol";
import "../utils/chainlink/ConfirmedOwner.sol";
import "@chainlink/contracts/src/v0.8/functions/v1_0_0/libraries/FunctionsRequest.sol";

error InvalidAddress();

/// @title FunctionsOracle
/// @notice Stores data and provides functions for managing index token issuance and redemption
contract FunctionsOracle is Initializable, FunctionsClient, ConfirmedOwner {
    using FunctionsRequest for FunctionsRequest.Request;

    // Addresses of factory contracts
    address public factoryBalancerAddress;

    bytes32 public donId; // DON ID for the Functions DON to which the requests are sent
    address public functionsRouterAddress;
    uint256 public lastUpdateTime;

    // Total number of oracles and current list3
    mapping(address => uint256) public totalOracleList;
    mapping(address => uint256) public totalCurrentList;
    // // Total number of oracles and current list3
    // uint256 public totalOracleList;
    // uint256 public totalCurrentList;

    // Mappings for oracle and current lists
    mapping(address => mapping(uint256 => address)) public oracleList;
    mapping(address => mapping(uint256 => address)) public currentList;

    // Mappings for token indices
    mapping(address => mapping(address => uint256)) public tokenOracleListIndex;
    mapping(address => mapping(address => uint256)) public tokenCurrentListIndex;

    // Mappings for token market shares
    mapping(address => mapping(address => uint256)) public tokenCurrentMarketShare;
    mapping(address => mapping(address => uint256)) public tokenOracleMarketShare;

    mapping(address => bool) public isOperator;

    event RequestFulFilled(bytes32 indexed requestId, uint256 time);

    modifier onlyOwnerOrOperator() {
        require(msg.sender == owner() || isOperator[msg.sender], "Caller is not the owner or operator.");
        _;
    }

    /// @notice Initializes the contract with the given parameters
    /// @param _functionsRouterAddress The address of the functions router
    /// @param _newDonId The don ID for the oracle
    function initialize(address _functionsRouterAddress, bytes32 _newDonId) external initializer {
        require(_functionsRouterAddress != address(0), "invalid functions router address");
        require(_newDonId.length > 0, "invalid don id");
        __FunctionsClient_init(_functionsRouterAddress);
        __ConfirmedOwner_init(msg.sender);
        donId = _newDonId;
        functionsRouterAddress = _functionsRouterAddress;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    //set operator
    function setOperator(address _operator, bool _status) external onlyOwner {
        isOperator[_operator] = _status;
    }

    /**
     * @notice Set the DON ID
     * @param newDonId New DON ID
     */
    function setDonId(bytes32 newDonId) external onlyOwner {
        donId = newDonId;
    }

    /**
     * @notice Set the Functions Router address
     * @param _functionsRouterAddress New Functions Router address
     */
    function setFunctionsRouterAddress(address _functionsRouterAddress) external onlyOwner {
        require(_functionsRouterAddress != address(0), "invalid functions router address");
        functionsRouterAddress = _functionsRouterAddress;
    }

    function setFactoryBalancer(address _factoryBalancerAddress) public onlyOwner {
        require(_factoryBalancerAddress != address(0), "invalid factory balancer address");
        factoryBalancerAddress = _factoryBalancerAddress;
    }

    function requestAssetsData(string calldata source, uint64 subscriptionId, uint32 callbackGasLimit)
        public
        onlyOwnerOrOperator
        returns (bytes32)
    {
        FunctionsRequest.Request memory req;
        req.initializeRequestForInlineJavaScript(source);
        return _sendRequest(req.encodeCBOR(), subscriptionId, callbackGasLimit, donId);
    }

    /**
     * @notice Store latest result/error
     * @param requestId The request ID, returned by sendRequest()
     * @param response Aggregated response from the user code
     * @param err Aggregated error from the user code or from the execution pipeline
     * Either response or error parameter will be set, but never both
     */
    function fulfillRequest(bytes32 requestId, bytes memory response, bytes memory err) internal override {
        // require(requestId != bytes32(0), "invalid request id");

        (address[] memory _indexTokens, address[] memory _tokens, uint256[] memory _marketShares) =
            abi.decode(response, (address[], address[], uint256[]));
        require(_indexTokens.length == _tokens.length, "length mismatch");
        require(_marketShares.length == _tokens.length, "length mismatch");
        require(_indexTokens.length > 0, "invalid index token addresses");
        require(requestId.length > 0, "invalid request id");
        require(_tokens.length > 0, "invalid tokens");
        require(_marketShares.length > 0, "invalid market shares");
        _initData(_indexTokens, _tokens, _marketShares);
    }

    function _initData(address[] memory _indexTokens, address[] memory _tokens, uint256[] memory _marketShares)
        private
    {
        address[] memory indexTokens = _indexTokens;
        address[] memory tokens0 = _tokens;
        uint256[] memory marketShares0 = _marketShares;

        // //save mappings
        for (uint256 i = 0; i < indexTokens.length; i++) {
            address indexToken = indexTokens[i];
            address token = tokens0[i];
            uint256 share = marketShares0[i];

            if (indexToken == address(0)) revert InvalidAddress();
            if (token == address(0)) revert InvalidAddress();

            oracleList[indexToken][i] = token;
            tokenOracleListIndex[indexToken][token] = i;
            tokenOracleMarketShare[indexToken][token] = share;

            if (totalCurrentList[indexToken] == 0) {
                currentList[indexToken][i] = token;
                tokenCurrentMarketShare[indexToken][token] = share;
                tokenCurrentListIndex[indexToken][token] = i;
            }

            // FIX: per-index totals must reflect the highest slot we touched for that index token,
            // not the global tokens array length.
            uint256 candidateLen = i + 1;
            if (totalOracleList[indexToken] < candidateLen) {
                totalOracleList[indexToken] = candidateLen;

                // if we're in bootstrap mode (first time), mirror oracle length into current length
                if (totalCurrentList[indexToken] == 0) {
                    totalCurrentList[indexToken] = candidateLen;
                }
            }
        }
        lastUpdateTime = block.timestamp;
    }

    function updateCurrentList(address _indexToken) external {
        // require(msg.sender == factoryBalancerAddress, "caller must be factory balancer");
        totalCurrentList[_indexToken] = totalOracleList[_indexToken];
        for (uint256 i = 0; i < totalOracleList[_indexToken]; i++) {
            address tokenAddress = oracleList[_indexToken][i];
            currentList[_indexToken][i] = tokenAddress;
            tokenCurrentMarketShare[_indexToken][tokenAddress] = tokenOracleMarketShare[_indexToken][tokenAddress];
            tokenCurrentListIndex[_indexToken][tokenAddress] = i;
        }
    }
}

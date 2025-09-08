// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "../utils/chainlink/FunctionsClient.sol";
import "../utils/chainlink/ConfirmedOwner.sol";
import "@chainlink/contracts/src/v0.8/functions/v1_0_0/libraries/FunctionsRequest.sol";
import "../libraries/PathHelpers.sol";

error InvalidAddress();
error ChainSelectorIsZero();
error AssetTypeIsZero();

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
    mapping(address => mapping(address => uint256))
        public tokenCurrentListIndex;

    // Mappings for token market shares
    mapping(address => mapping(address => uint256))
        public tokenCurrentMarketShare;
    mapping(address => mapping(address => uint256))
        public tokenOracleMarketShare;

    // mappings for tokens of each asset type
    mapping(address => mapping(address => uint256)) public tokenAssetType;

    // chain selector for each token
    mapping(address => uint64) public tokenChainSelector;

    // paths and fees for swapping to/from ETH
    mapping(address => address[]) public fromETHPath;
    mapping(address => address[]) public toETHPath;
    mapping(address => uint24[]) public fromETHFees;
    mapping(address => uint24[]) public toETHFees;

    uint public oracleFilledCount;
    uint public currentFilledCount;

    struct OracleData {
        address[] tokens;
        uint[] marketShares;
        uint64[] chainSelectors;
        uint256[] assetTypes;
        mapping(uint64 => bool) isOracleChainSelectorStored;
        mapping(uint64 => address[]) oracleChainSelectorTokens;
        mapping(uint64 => uint[]) oracleChainSelectorVersions;
        mapping(uint64 => uint[]) oracleChainSelectorTokenShares;
        mapping(uint64 => uint) oracleChainSelectorTotalShares;
        mapping(uint256 => bool) isOracleAssetTypeStored;
        mapping(uint256 => address[]) oracleAssetTypeTokens;
        mapping(uint256 => uint[]) oracleAssetTypeTokenShares;
        mapping(uint256 => uint) oracleAssetTypeTotalShares;
    }

    struct CurrentData {
        address[] tokens;
        uint[] marketShares;
        uint64[] chainSelectors;
        uint256[] assetTypes;
        mapping(uint64 => bool) isCurrentChainSelectorStored;
        mapping(uint64 => address[]) currentChainSelectorTokens;
        mapping(uint64 => uint[]) currentChainSelectorVersions;
        mapping(uint64 => uint[]) currentChainSelectorTokenShares;
        mapping(uint64 => uint) currentChainSelectorTotalShares;
        mapping(uint256 => bool) isCurrentAssetTypeStored;
        mapping(uint256 => address[]) currentAssetTypeTokens;
        mapping(uint256 => uint[]) currentAssetTypeTokenShares;
        mapping(uint256 => uint) currentAssetTypeTotalShares;
    }

    mapping(address => mapping(uint256 => OracleData)) internal oracleData;
    mapping(address => mapping(uint256 => CurrentData)) internal currentData;

    mapping(address => bool) public isOperator;

    event RequestFulFilled(bytes32 indexed requestId, uint256 time);

    modifier onlyOwnerOrOperator() {
        require(
            msg.sender == owner() || isOperator[msg.sender],
            "Caller is not the owner or operator."
        );
        _;
    }

    /// @notice Initializes the contract with the given parameters
    /// @param _functionsRouterAddress The address of the functions router
    /// @param _newDonId The don ID for the oracle
    function initialize(
        address _functionsRouterAddress,
        bytes32 _newDonId
    ) external initializer {
        require(
            _functionsRouterAddress != address(0),
            "invalid functions router address"
        );
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
    function setFunctionsRouterAddress(
        address _functionsRouterAddress
    ) external onlyOwner {
        require(
            _functionsRouterAddress != address(0),
            "invalid functions router address"
        );
        functionsRouterAddress = _functionsRouterAddress;
    }

    function setFactoryBalancer(
        address _factoryBalancerAddress
    ) public onlyOwner {
        require(
            _factoryBalancerAddress != address(0),
            "invalid factory balancer address"
        );
        factoryBalancerAddress = _factoryBalancerAddress;
    }

    function requestAssetsData(
        string calldata source,
        uint64 subscriptionId,
        uint32 callbackGasLimit
    ) public onlyOwnerOrOperator returns (bytes32) {
        FunctionsRequest.Request memory req;
        req.initializeRequestForInlineJavaScript(source);
        return
            _sendRequest(
                req.encodeCBOR(),
                subscriptionId,
                callbackGasLimit,
                donId
            );
    }

    /**
     * @notice Store latest result/error
     * @param requestId The request ID, returned by sendRequest()
     * @param response Aggregated response from the user code
     * @param err Aggregated error from the user code or from the execution pipeline
     * Either response or error parameter will be set, but never both
     */
    function fulfillRequest(
        bytes32 requestId,
        bytes memory response,
        bytes memory err
    ) internal override {
        // require(requestId != bytes32(0), "invalid request id");

        (
            address[] memory _indexTokens,
            address[] memory _tokens,
            uint256[] memory _marketShares
        ) = abi.decode(response, (address[], address[], uint256[]));
        require(_indexTokens.length == _tokens.length, "length mismatch");
        require(_marketShares.length == _tokens.length, "length mismatch");
        require(_indexTokens.length > 0, "invalid index token addresses");
        require(requestId.length > 0, "invalid request id");
        require(_tokens.length > 0, "invalid tokens");
        require(_marketShares.length > 0, "invalid market shares");
        _initData(_indexTokens, _tokens, _marketShares);
    }

    function _initChainSelectorsOracleData(
        address indexToken,
        uint64 chainSelector,
        address token,
        uint256 marketShares
    ) internal {
        if (
            !oracleData[indexToken][oracleFilledCount].isOracleChainSelectorStored[
                chainSelector
            ]
        ) {
            oracleData[indexToken][oracleFilledCount].chainSelectors.push(chainSelector);
            oracleData[indexToken][oracleFilledCount].isOracleChainSelectorStored[
                chainSelector
            ] = true;
        }
        oracleData[indexToken][oracleFilledCount]
            .oracleChainSelectorTokens[chainSelector]
            .push(token);
        oracleData[indexToken][oracleFilledCount].oracleChainSelectorTotalShares[
            chainSelector
        ] += marketShares;

        oracleData[indexToken][oracleFilledCount]
            .oracleChainSelectorTokenShares[chainSelector]
            .push(marketShares);
    }

    function _initChainSelectorsCurrentData(
        address indexToken,
        uint64 chainSelector,
        address token,
        uint256 marketShares
    ) internal {
        if (
            !currentData[indexToken][currentFilledCount].isCurrentChainSelectorStored[
                chainSelector
            ]
        ) {
            currentData[indexToken][currentFilledCount].isCurrentChainSelectorStored[
                chainSelector
            ] = true;
            currentData[indexToken][currentFilledCount].chainSelectors.push(
                chainSelector
            );
        }
        currentData[indexToken][currentFilledCount]
            .currentChainSelectorTokens[chainSelector]
            .push(token);
        currentData[indexToken][currentFilledCount].currentChainSelectorTotalShares[
            chainSelector
        ] += marketShares;
        currentData[indexToken][currentFilledCount]
            .currentChainSelectorTokenShares[chainSelector]
            .push(marketShares);
    }

    function _initAssetTypesOracleData(
        address indexToken,
        address token,
        uint256 assetType,
        uint256 marketShare
    ) internal {
        if(
            !oracleData[indexToken][oracleFilledCount].isOracleAssetTypeStored[assetType]
        ) {
            oracleData[indexToken][oracleFilledCount].isOracleAssetTypeStored[assetType] = true;
            oracleData[indexToken][oracleFilledCount].oracleAssetTypeTokens[assetType].push(token);
        }
        oracleData[indexToken][oracleFilledCount].oracleAssetTypeTotalShares[assetType] += marketShare;
        oracleData[indexToken][oracleFilledCount].oracleAssetTypeTokenShares[assetType].push(marketShare);
    }

    function _initAssetTypesCurrentData(
        address indexToken,
        address token,
        uint256 assetType,
        uint256 marketShare
    ) internal {
        if(
            !currentData[indexToken][currentFilledCount].isCurrentAssetTypeStored[assetType]
        ) {
            currentData[indexToken][currentFilledCount].isCurrentAssetTypeStored[assetType] = true;
            currentData[indexToken][currentFilledCount].currentAssetTypeTokens[assetType].push(token);
        }
        currentData[indexToken][currentFilledCount].currentAssetTypeTotalShares[assetType] += marketShare;
        currentData[indexToken][currentFilledCount].currentAssetTypeTokenShares[assetType].push(marketShare);
    }

    function _initData(
        address[] memory _indexTokens,
        address[] memory _tokens,
        uint256[] memory _marketShares
    ) private {
        address[] memory indexTokens = _indexTokens;
        address[] memory tokens0 = _tokens;
        uint256[] memory marketShares0 = _marketShares;

        oracleFilledCount += 1;
        if (totalCurrentList[indexTokens[0]] == 0) {
            currentFilledCount += 1;
        }
        // //save mappings
        for (uint256 i = 0; i < tokens0.length; i++) {
            address indexToken = indexTokens[0];
            address token = tokens0[i];
            uint256 share = marketShares0[i];

            if (indexToken == address(0)) revert InvalidAddress();
            if (token == address(0)) revert InvalidAddress();

            oracleList[indexToken][i] = token;
            tokenOracleListIndex[indexToken][token] = i;
            tokenOracleMarketShare[indexToken][token] = share;

            uint64 chainSelector = tokenChainSelector[token];
            uint256 assetType = tokenAssetType[indexToken][token];
            if (chainSelector == 0) revert ChainSelectorIsZero();
            if (assetType == 0) revert AssetTypeIsZero();
            // oracle asset type actions
            _initAssetTypesOracleData(
                indexToken,
                token, 
                assetType, 
                share);
            // oracle chain selector actions
            if (assetType == 2) {
                _initChainSelectorsOracleData(
                    indexToken,
                    chainSelector, 
                    token, 
                    share);
            }

            if (totalCurrentList[indexToken] == 0) {
                currentList[indexToken][i] = token;
                tokenCurrentMarketShare[indexToken][token] = share;
                tokenCurrentListIndex[indexToken][token] = i;
                // current asset type actions
                _initAssetTypesCurrentData(
                    indexToken,
                    token, 
                    assetType, 
                    share);
                // current chain selector actions
                if (assetType == 2) {
                    _initChainSelectorsCurrentData(
                        indexToken,
                        chainSelector,
                        token,
                        share
                    );
                }
            }
        }

        // update total oracle and current list lengths
        totalOracleList[indexTokens[0]] = tokens0.length;
        if (totalCurrentList[indexTokens[0]] == 0) {
            totalCurrentList[indexTokens[0]] = tokens0.length;
        }
        lastUpdateTime = block.timestamp;
    }

    function updateCurrentList(address _indexToken) external {
        // require(msg.sender == factoryBalancerAddress, "caller must be factory balancer");
        totalCurrentList[_indexToken] = totalOracleList[_indexToken];
        for (uint256 i = 0; i < totalOracleList[_indexToken]; i++) {
            address tokenAddress = oracleList[_indexToken][i];
            currentList[_indexToken][i] = tokenAddress;
            tokenCurrentMarketShare[_indexToken][
                tokenAddress
            ] = tokenOracleMarketShare[_indexToken][tokenAddress];
            tokenCurrentListIndex[_indexToken][tokenAddress] = i;
        }
    }

    function updatePathData(
        uint256[] memory assetTypes,
        uint64[] memory chainSelectors,
        bytes[] memory pathBytes
    ) public onlyOwnerOrOperator {
        require(
            chainSelectors.length == pathBytes.length,
            "The length of the chainSelectors and pathBytes arrays should be the same"
        );
        for (uint256 i = 0; i < chainSelectors.length; i++) {
            _initPathData(
                assetTypes[i],
                chainSelectors[i], 
                pathBytes[i]);
        }

        // emit PathDataUpdated(block.timestamp);
    }

    function _initPathData(
        uint256 _assetType,
        uint64 _chainSelector,
        bytes memory _pathBytes
    ) internal {
        // decode pathBytes to get fromETHPath and fromETHFees
        (address[] memory _fromETHPath, uint24[] memory _fromETHFees) = abi
            .decode(_pathBytes, (address[], uint24[]));
        require(
            _fromETHPath.length == _fromETHFees.length + 1,
            "Invalid input arrays"
        );
        address tokenAddress = _fromETHPath[_fromETHPath.length - 1];
        tokenAssetType[tokenAddress] = _assetType;
        tokenChainSelector[tokenAddress] = _chainSelector;
        fromETHPath[tokenAddress] = _fromETHPath;
        fromETHFees[tokenAddress] = _fromETHFees;
        // update toETHPath and toETHFees
        address[] memory _toETHPath = PathHelpers.reverseAddressArray(
            _fromETHPath
        );
        uint24[] memory _toETHFees = PathHelpers.reverseUint24Array(
            _fromETHFees
        );
        toETHPath[tokenAddress] = _toETHPath;
        toETHFees[tokenAddress] = _toETHFees;
    }
}

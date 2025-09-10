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

    uint64 public maxAssetTypes; // Maximum number of asset types supported

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
    mapping(address => uint64) public tokenAssetType;

    // chain selector for each token
    mapping(address => uint64) public tokenChainSelector;

    // paths and fees for swapping to/from ETH
    mapping(address => address[]) public fromETHPath;
    mapping(address => address[]) public toETHPath;
    mapping(address => uint24[]) public fromETHFees;
    mapping(address => uint24[]) public toETHFees;

    mapping(address => uint256) public oracleFilledCount;
    mapping(address => uint256) public currentFilledCount;

    struct OracleData {
        address[] tokens;
        uint[] marketShares;
        uint64[] chainSelectors;
        uint64[] assetTypes;
        mapping(uint64 => bool) isOracleChainSelectorStored;
        mapping(uint64 => address[]) oracleChainSelectorTokens;
        mapping(uint64 => uint[]) oracleChainSelectorVersions;
        mapping(uint64 => uint[]) oracleChainSelectorTokenShares;
        mapping(uint64 => uint) oracleChainSelectorTotalShares;
        mapping(uint64 => bool) isOracleAssetTypeStored;
        mapping(uint64 => address[]) oracleAssetTypeTokens;
        mapping(uint64 => uint[]) oracleAssetTypeTokenShares;
        mapping(uint64 => uint) oracleAssetTypeTotalShares;
    }

    struct CurrentData {
        address[] tokens;
        uint[] marketShares;
        uint64[] chainSelectors;
        uint64[] assetTypes;
        mapping(uint64 => bool) isCurrentChainSelectorStored;
        mapping(uint64 => address[]) currentChainSelectorTokens;
        mapping(uint64 => uint[]) currentChainSelectorVersions;
        mapping(uint64 => uint[]) currentChainSelectorTokenShares;
        mapping(uint64 => uint) currentChainSelectorTotalShares;
        mapping(uint64 => bool) isCurrentAssetTypeStored;
        mapping(uint64 => address[]) currentAssetTypeTokens;
        mapping(uint64 => uint[]) currentAssetTypeTokenShares;
        mapping(uint64 => uint) currentAssetTypeTotalShares;
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
        maxAssetTypes = 3;
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

    function setMaxAssetTypes(uint64 _maxAssetTypes) public onlyOwner {
        require(_maxAssetTypes > 0, "max asset types must be greater than zero");
        maxAssetTypes = _maxAssetTypes;
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
        uint256 oracleFilledCount0 = oracleFilledCount[indexToken];
        if (
            !oracleData[indexToken][oracleFilledCount0]
                .isOracleChainSelectorStored[chainSelector]
        ) {
            oracleData[indexToken][oracleFilledCount0].chainSelectors.push(
                chainSelector
            );
            oracleData[indexToken][oracleFilledCount0]
                .isOracleChainSelectorStored[chainSelector] = true;
        }
        oracleData[indexToken][oracleFilledCount0]
            .oracleChainSelectorTokens[chainSelector]
            .push(token);
        oracleData[indexToken][oracleFilledCount0]
            .oracleChainSelectorTotalShares[chainSelector] += marketShares;

        oracleData[indexToken][oracleFilledCount0]
            .oracleChainSelectorTokenShares[chainSelector]
            .push(marketShares);
    }

    function _initChainSelectorsCurrentData(
        address indexToken,
        uint64 chainSelector,
        address token,
        uint256 marketShares
    ) internal {
        uint256 currentFilledCount0 = currentFilledCount[indexToken];
        if (
            !currentData[indexToken][currentFilledCount0]
                .isCurrentChainSelectorStored[chainSelector]
        ) {
            currentData[indexToken][currentFilledCount0]
                .isCurrentChainSelectorStored[chainSelector] = true;
            currentData[indexToken][currentFilledCount0].chainSelectors.push(
                chainSelector
            );
        }
        currentData[indexToken][currentFilledCount0]
            .currentChainSelectorTokens[chainSelector]
            .push(token);
        currentData[indexToken][currentFilledCount0]
            .currentChainSelectorTotalShares[chainSelector] += marketShares;
        currentData[indexToken][currentFilledCount0]
            .currentChainSelectorTokenShares[chainSelector]
            .push(marketShares);
    }

    function _initAssetTypesOracleData(
        address indexToken,
        address token,
        uint64 assetType,
        uint256 marketShare
    ) internal {
        uint256 oracleFilledCount0 = oracleFilledCount[indexToken];
        if (
            !oracleData[indexToken][oracleFilledCount0].isOracleAssetTypeStored[
                assetType
            ]
        ) {
            oracleData[indexToken][oracleFilledCount0].isOracleAssetTypeStored[
                assetType
            ] = true;
            oracleData[indexToken][oracleFilledCount0]
                .oracleAssetTypeTokens[assetType]
                .push(token);
        }
        oracleData[indexToken][oracleFilledCount0].oracleAssetTypeTotalShares[
            assetType
        ] += marketShare;
        oracleData[indexToken][oracleFilledCount0]
            .oracleAssetTypeTokenShares[assetType]
            .push(marketShare);
    }

    function _initAssetTypesCurrentData(
        address indexToken,
        address token,
        uint64 assetType,
        uint256 marketShare
    ) internal {
        uint256 currentFilledCount0 = currentFilledCount[indexToken];
        if (
            !currentData[indexToken][currentFilledCount0]
                .isCurrentAssetTypeStored[assetType]
        ) {
            currentData[indexToken][currentFilledCount0]
                .isCurrentAssetTypeStored[assetType] = true;
            currentData[indexToken][currentFilledCount0]
                .currentAssetTypeTokens[assetType]
                .push(token);
        }
        currentData[indexToken][currentFilledCount0]
            .currentAssetTypeTotalShares[assetType] += marketShare;
        currentData[indexToken][currentFilledCount0]
            .currentAssetTypeTokenShares[assetType]
            .push(marketShare);
    }

    function _initData(
        address[] memory _indexTokens,
        address[] memory _tokens,
        uint256[] memory _marketShares
    ) private {
        address[] memory indexTokens = _indexTokens;
        address[] memory tokens0 = _tokens;
        uint256[] memory marketShares0 = _marketShares;

        oracleFilledCount[indexTokens[0]] += 1;
        if (totalCurrentList[indexTokens[0]] == 0) {
            currentFilledCount[indexTokens[0]] += 1;
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
            uint64 assetType = tokenAssetType[token];
            if (chainSelector == 0) revert ChainSelectorIsZero();
            if (assetType == 0) revert AssetTypeIsZero();
            // oracle asset type actions
            _initAssetTypesOracleData(indexToken, token, assetType, share);
            // oracle chain selector actions
            if (assetType == 2) {
                _initChainSelectorsOracleData(
                    indexToken,
                    chainSelector,
                    token,
                    share
                );
            }

            if (totalCurrentList[indexToken] == 0) {
                currentList[indexToken][i] = token;
                tokenCurrentMarketShare[indexToken][token] = share;
                tokenCurrentListIndex[indexToken][token] = i;
                // current asset type actions
                _initAssetTypesCurrentData(indexToken, token, assetType, share);
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


    function _updateCurrentList(address _indexToken) internal {
        currentFilledCount[_indexToken] += 1;
        for (uint i = 0; i < totalOracleList[_indexToken]; i++) {
            address tokenAddress = oracleList[_indexToken][i];
            currentList[_indexToken][i] = tokenAddress;
            tokenCurrentMarketShare[_indexToken][tokenAddress] = tokenOracleMarketShare[_indexToken][tokenAddress];
            tokenCurrentListIndex[_indexToken][tokenAddress] = i;
    

            // current chain selector actions
            uint64 chainSelector = tokenChainSelector[tokenAddress];
            uint64 tokenAssetType0 = tokenAssetType[tokenAddress];
            _initAssetTypesCurrentData(_indexToken, tokenAddress, tokenAssetType0, tokenOracleMarketShare[_indexToken][tokenAddress]);
            if (tokenAssetType0 == 2) {
                _initChainSelectorsCurrentData(_indexToken, chainSelector, tokenAddress, tokenOracleMarketShare[_indexToken][tokenAddress]);
            }
        }
        totalCurrentList[_indexToken] = totalOracleList[_indexToken];
    }

    function updatePathData(
        uint64[] memory assetTypes,
        uint64[] memory chainSelectors,
        bytes[] memory pathBytes
    ) public onlyOwnerOrOperator {
        require(
            chainSelectors.length == pathBytes.length,
            "The length of the chainSelectors and pathBytes arrays should be the same"
        );
        for (uint256 i = 0; i < chainSelectors.length; i++) {
            _initPathData(assetTypes[i], chainSelectors[i], pathBytes[i]);
        }

        // emit PathDataUpdated(block.timestamp);
    }

    function _initPathData(
        uint64 _assetType,
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


    function getFromETHPathData(
        address _tokenAddress
    ) public view returns (address[] memory, uint24[] memory) {
        return (fromETHPath[_tokenAddress], fromETHFees[_tokenAddress]);
    }

    function getToETHPathData(
        address _tokenAddress
    ) public view returns (address[] memory, uint24[] memory) {
        return (toETHPath[_tokenAddress], toETHFees[_tokenAddress]);
    }

    function getFromETHPathBytesForTokens(
        address[] memory _tokens
    ) public view returns (bytes[] memory) {
        bytes[] memory pathBytes = new bytes[](_tokens.length);
        for (uint i = 0; i < _tokens.length; i++) {
            pathBytes[i] = PathHelpers.getFromETHPathBytes(
                fromETHPath[_tokens[i]],
                fromETHFees[_tokens[i]]
            );
        }

        return pathBytes;
    }

    /**
     * @dev Returns all tokens in the oracle chain selector.
     * @param _chainSelector The chain selector.
     * @return tokens The addresses of the tokens.
     */
    function allOracleChainSelectorTokens(
        address _indexToken,
        uint64 _chainSelector
    ) public view returns (address[] memory tokens) {
        tokens = oracleData[_indexToken][oracleFilledCount[_indexToken]].oracleChainSelectorTokens[
            _chainSelector
        ];
    }

    /**
     * @dev Returns all tokens in the current chain selector.
     * @param _chainSelector The chain selector.
     * @return tokens The addresses of the tokens.
     */
    function allCurrentChainSelectorTokens(
        address _indexToken,
        uint64 _chainSelector
    ) public view returns (address[] memory tokens) {
        tokens = currentData[_indexToken][currentFilledCount[_indexToken]].currentChainSelectorTokens[
            _chainSelector
        ];
    }

    /**
     * @dev Returns all versions in the oracle chain selector.
     * @param _chainSelector The chain selector.
     * @return versions The versions of the tokens.
     */
    function allOracleChainSelectorVersions(
        address _indexToken,
        uint64 _chainSelector
    ) public view returns (uint[] memory versions) {
        versions = oracleData[_indexToken][oracleFilledCount[_indexToken]].oracleChainSelectorVersions[
            _chainSelector
        ];
    }

    /**
     * @dev Returns all versions in the current chain selector.
     * @param _chainSelector The chain selector.
     * @return versions The versions of the tokens.
     */
    function allCurrentChainSelectorVersions(
        address _indexToken,
        uint64 _chainSelector
    ) public view returns (uint[] memory versions) {
        versions = currentData[_indexToken][currentFilledCount[_indexToken]].currentChainSelectorVersions[
            _chainSelector
        ];
    }

    /**
     * @dev Returns all token shares in the oracle chain selector.
     * @param _chainSelector The chain selector.
     * @return The token shares.
     */
    function allOracleChainSelectorTokenShares(
        address _indexToken,
        uint64 _chainSelector
    ) public view returns (uint[] memory) {
        return
            oracleData[_indexToken][oracleFilledCount[_indexToken]].oracleChainSelectorTokenShares[
                _chainSelector
            ];
    }

    /**
     * @dev Returns all token shares in the current chain selector.
     * @param _chainSelector The chain selector.
     * @return The token shares.
     */
    function allCurrentChainSelectorTokenShares(
        address _indexToken,
        uint64 _chainSelector
    ) public view returns (uint[] memory) {
        return
            currentData[_indexToken][currentFilledCount[_indexToken]].currentChainSelectorTokenShares[
                _chainSelector
            ];
    }

    function getOracleData(
        address _indexToken,
        uint _oracleFilledCount
    )
        public
        view
        returns (
            address[] memory tokens,
            uint[] memory marketShares,
            uint64[] memory chainSelectors
        )
    {
        OracleData storage data = oracleData[_indexToken][_oracleFilledCount];
        return (data.tokens, data.marketShares, data.chainSelectors);
    }

    function getCurrentData(
        address indexToken,
        uint currentFilledCount
    )
        public
        view
        returns (
            address[] memory tokens,
            uint[] memory marketShares,
            uint64[] memory chainSelectors
        )
    {
        CurrentData storage data = currentData[indexToken][currentFilledCount];
        return (data.tokens, data.marketShares, data.chainSelectors);
    }

    function getCurrentAssetTypes(
        address indexToken,
        uint currentFilledCount
    ) public view returns (uint64[] memory) {
        return currentData[indexToken][currentFilledCount].assetTypes;
    }

    function getOracleAssetTypes(
        address indexToken,
        uint oracleFilledCount
    ) public view returns (uint64[] memory) {
        return oracleData[indexToken][oracleFilledCount].assetTypes;
    }

    function getCurrentChainSelectorTotalShares(
        address indexToken,
        uint currentFilledCount,
        uint64 chainSelector
    ) public view returns (uint) {
        return
            currentData[indexToken][currentFilledCount].currentChainSelectorTotalShares[chainSelector];
    }

    function getOracleChainSelectorTotalShares(
        address indexToken,
        uint oracleFilledCount,
        uint64 chainSelector
    ) public view returns (uint) {
        return oracleData[indexToken][oracleFilledCount].oracleChainSelectorTotalShares[chainSelector];
    }

    function getCurrentAssetTypeTotalShares(
        address indexToken,
        uint currentFilledCount,
        uint64 assetType
    ) public view returns (uint) {
        return
            currentData[indexToken][currentFilledCount].currentAssetTypeTotalShares[assetType];
    }

    function getCurrentAssetTypeData(
        address indexToken,
        uint currentFilledCount,
        uint64 assetType
    ) public view returns (uint, address[] memory, uint[] memory) {
        return (
            currentData[indexToken][currentFilledCount].currentAssetTypeTotalShares[assetType],
            currentData[indexToken][currentFilledCount].currentAssetTypeTokens[assetType],
            currentData[indexToken][currentFilledCount].currentAssetTypeTokenShares[assetType]
        );
    }


}

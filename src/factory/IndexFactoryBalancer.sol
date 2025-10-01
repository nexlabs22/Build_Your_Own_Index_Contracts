// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {FunctionsOracle} from "../oracle/FunctionsOracle.sol";
import {MainChainBalancer} from "../ccip/MainChainBalancer.sol";
import {IndexFactoryStorage} from "./IndexFactoryStorage.sol";
import {Vault} from "../vault/Vault.sol";
import {FeeCalculation} from "../libraries/FeeCalculation.sol";

error ZeroAmount();
error ZeroAddress();
error WrongETHAmount();

contract IndexFactoryBalancer is
    Initializable,
    OwnableUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;

    FunctionsOracle public functionsOracle;
    IndexFactoryStorage public factoryStorage;
    MainChainBalancer public mainChainBalancer;

    uint256 public updatePortfolioNonce;

    uint256 private constant SHARE_DENOMINATOR = 100e18;

    mapping(uint256 => uint256) public portfolioTotalValueByNonce; // mapping of updatePortfolioNonce to total value
    mapping(uint256 => mapping(uint64 => uint256)) public providerTotalValueByNonce; // mapping of updatePortfolioNonce to total value
    mapping(uint64 => mapping(uint256 => uint256)) public providerNonceToGlobalNonce; // mapping of providerNonce to globalNonce

    function initialize(
        address _functionsOracle,
        address _factoryStorage,
        address _mainChainBalancer
    ) external initializer {
        require(
            _functionsOracle != address(0),
            "Invalid address for _functionsOracle"
        );
        functionsOracle = FunctionsOracle(_functionsOracle);
        factoryStorage = IndexFactoryStorage(_factoryStorage);
        mainChainBalancer = MainChainBalancer(_mainChainBalancer);

        __Ownable_init(msg.sender);
        __Pausable_init();
        __ReentrancyGuard_init();
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function increasePortfolioTotalValueByNonce(uint256 _updatePortfolioNonce, uint256 _totalValue)
        public
    {
        portfolioTotalValueByNonce[_updatePortfolioNonce] += _totalValue;
    }

    // =========================
    // === External Functions ==
    // =========================
    function askValues(address _indexToken) external whenNotPaused nonReentrant {
        uint256 currentFilledCount = functionsOracle.currentFilledCount(
            _indexToken
        );
        uint64[] memory currentProviderIndexes = functionsOracle
            .getCurrentProviderIndexes(_indexToken, currentFilledCount);
        updatePortfolioNonce++;
        for (uint256 i = 0; i < currentProviderIndexes.length; i++) {
        
            if (currentProviderIndexes[i] == 1) {
                askValueCCIP(_indexToken);
            }
        }
    }
    
    function askValueCCIP(
        address _indexToken
    ) internal whenNotPaused nonReentrant returns (uint256 orderNonce) {
        uint256 providerUpdateNonce = mainChainBalancer.askValues(_indexToken);
        providerNonceToGlobalNonce[1][providerUpdateNonce] = updatePortfolioNonce;
        return providerUpdateNonce;
    }

    function completeAskValueCCIP(
        address _indexToken,
        uint256 _updateProviderNonce,
        uint256 _value
    ) external whenNotPaused nonReentrant {
        require(_indexToken != address(0), "Zero address");
        require(_value > 0, "Zero total value");

        uint256 _updatePortfolioNonce = providerNonceToGlobalNonce[1][_updateProviderNonce];
        if (_updatePortfolioNonce == 0) {
            revert("Invalid provider nonce");
        }
        portfolioTotalValueByNonce[_updatePortfolioNonce] += _value;
        providerTotalValueByNonce[_updatePortfolioNonce][1] += _value;
    }
}

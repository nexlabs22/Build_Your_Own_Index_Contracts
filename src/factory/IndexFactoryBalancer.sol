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
import {DinariBalancer} from "../dinari/DinariBalancer.sol";

contract IndexFactoryBalancer is Initializable, OwnableUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    FunctionsOracle public functionsOracle;
    IndexFactoryStorage public factoryStorage;
    MainChainBalancer public mainChainBalancer;
    DinariBalancer public dinariBalancer;

    uint256 public updatePortfolioNonce;

    uint256 private constant SHARE_DENOMINATOR = 100e18;

    mapping(uint256 => uint256) public portfolioTotalValueByNonce; // mapping of updatePortfolioNonce to total value
    mapping(uint256 => mapping(uint64 => uint256)) public providerTotalValueByNonce; // mapping of updatePortfolioNonce to total value
    mapping(uint64 => mapping(uint256 => uint256)) public providerNonceToGlobalNonce; // mapping of providerNonce to globalNonce

    function initialize(
        address _functionsOracle,
        address _factoryStorage,
        address _mainChainBalancer,
        address _dinariBalancer
    ) external initializer {
        require(_functionsOracle != address(0), "Invalid address for _functionsOracle");
        require(_factoryStorage != address(0), "Invalid address for _factoryStorage");
        require(_mainChainBalancer != address(0), "Invalid address for _mainChainBalancer");
        // require(_dinariBalancer != address(0), "Invalid address for _dinariBalancer");
        functionsOracle = FunctionsOracle(_functionsOracle);
        factoryStorage = IndexFactoryStorage(_factoryStorage);
        mainChainBalancer = MainChainBalancer(_mainChainBalancer);
        dinariBalancer = DinariBalancer(_dinariBalancer);

        __Ownable_init(msg.sender);
        __Pausable_init();
        __ReentrancyGuard_init();
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function increasePortfolioTotalValueByNonce(uint256 _updatePortfolioNonce, uint256 _totalValue) public {
        portfolioTotalValueByNonce[_updatePortfolioNonce] += _totalValue;
    }

    // =========================
    // === External Functions ==
    // =========================
    function askValues(address _indexToken) external whenNotPaused nonReentrant {
        // uint8 dinariProviderIndex = dinariBalancer.dinariStorage().providerIndex();
        uint8 dinariProviderIndex;

        uint256 currentFilledCount = functionsOracle.currentFilledCount(_indexToken);

        uint64[] memory currentProviderIndexes =
            functionsOracle.getCurrentProviderIndexes(_indexToken, currentFilledCount);
        updatePortfolioNonce++;
        for (uint256 i = 0; i < currentProviderIndexes.length; i++) {
            if (currentProviderIndexes[i] == 1) {
                askValueCCIP(_indexToken);
            } else if (currentProviderIndexes[i] == dinariProviderIndex) {
                askValuesDinari(_indexToken);
            }
        }
    }

    function firstReweightAction(address _indexToken, uint256 _updatePortfolioNonce)
        external
        whenNotPaused
        nonReentrant
    {
        uint256 currentFilledCount = functionsOracle.currentFilledCount(_indexToken);
        uint256 oracleFilledCount = functionsOracle.oracleFilledCount(_indexToken);
        uint64[] memory currentProviderIndexes =
            functionsOracle.getCurrentProviderIndexes(_indexToken, currentFilledCount);
        for (uint256 i = 0; i < currentProviderIndexes.length; i++) {
            uint256 realProviderMarketShare = (
                providerTotalValueByNonce[_updatePortfolioNonce][currentProviderIndexes[i]] * 100e18
            ) / portfolioTotalValueByNonce[_updatePortfolioNonce];
            uint256 targetProviderMarketShare = functionsOracle.getOracleProviderIndexTotalShares(
                _indexToken, oracleFilledCount, currentProviderIndexes[i]
            );
            if (realProviderMarketShare > targetProviderMarketShare) {
                if (currentProviderIndexes[i] == 1) {
                    reweightCCIP(_indexToken);
                }
            }
        }
    }

    function secondReweightAction(address _indexToken, uint256 _updatePortfolioNonce)
        external
        whenNotPaused
        nonReentrant
    {
        uint256 currentFilledCount = functionsOracle.currentFilledCount(_indexToken);
        uint256 oracleFilledCount = functionsOracle.oracleFilledCount(_indexToken);
        uint64[] memory currentProviderIndexes =
            functionsOracle.getCurrentProviderIndexes(_indexToken, currentFilledCount);
        for (uint256 i = 0; i < currentProviderIndexes.length; i++) {
            uint256 realProviderMarketShare = (
                providerTotalValueByNonce[_updatePortfolioNonce][currentProviderIndexes[i]] * 100e18
            ) / portfolioTotalValueByNonce[_updatePortfolioNonce];
            uint256 targetProviderMarketShare = functionsOracle.getOracleProviderIndexTotalShares(
                _indexToken, oracleFilledCount, currentProviderIndexes[i]
            );
            if (realProviderMarketShare < targetProviderMarketShare) {
                if (currentProviderIndexes[i] == 1) {
                    reweightCCIP(_indexToken);
                }
            }
        }
    }

    function askValueCCIP(address _indexToken) internal whenNotPaused returns (uint256 orderNonce) {
        uint256 providerUpdateNonce = mainChainBalancer.askValues(_indexToken);
        require(providerUpdateNonce > 0, "Zero provider nonce in ask values");
        require(updatePortfolioNonce > 0, "Zero portfolio nonce in ask values");
        providerNonceToGlobalNonce[1][providerUpdateNonce] = updatePortfolioNonce;
        return providerUpdateNonce;
    }

    function completeAskValueCCIP(uint256 _updateProviderNonce, uint256 _value) external whenNotPaused {
        require(_value > 0, "Zero total value");
        require(_updateProviderNonce > 0, "Zero provider nonce");

        uint256 _updatePortfolioNonce = providerNonceToGlobalNonce[1][_updateProviderNonce];
        if (_updatePortfolioNonce == 0) {
            revert("Invalid provider nonce");
        }
        portfolioTotalValueByNonce[_updatePortfolioNonce] += _value;
        providerTotalValueByNonce[_updatePortfolioNonce][1] += _value;
    }

    function askValuesDinari(address _indexToken) internal whenNotPaused nonReentrant returns (uint256 orderNonce) {
        uint8 providerIndex = dinariBalancer.dinariStorage().providerIndex();
        uint256 providerUpdateNonce = dinariBalancer.askValues(_indexToken);
        providerNonceToGlobalNonce[providerIndex][providerUpdateNonce] = updatePortfolioNonce;
    }

    function completeDinariAskValues(uint256 _updateProviderNonce, uint256 _value)
        external
        whenNotPaused
        nonReentrant
    {
        require(_value > 0, "Zero total value");
        uint8 providerIndex = dinariBalancer.dinariStorage().providerIndex();

        uint256 _updatePortfolioNonce = providerNonceToGlobalNonce[providerIndex][_updateProviderNonce];
        if (_updatePortfolioNonce == 0) {
            revert("Invalid provider nonce");
        }
        portfolioTotalValueByNonce[_updatePortfolioNonce] += _value;
        providerTotalValueByNonce[_updatePortfolioNonce][providerIndex] += _value;
    }

    function reweightCCIP(address _indexToken) internal whenNotPaused nonReentrant returns (uint256 orderNonce) {
        // to be implemented
    }
}

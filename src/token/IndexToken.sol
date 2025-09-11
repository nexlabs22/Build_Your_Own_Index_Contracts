// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "../utils/proposable/ProposableOwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "./interfaces/TokenInterface.sol";

/// @title Index Token
/// @author NEX Labs Protocol
/// @notice The main token contract for Index Token (NEX Labs Protocol)
/// @dev This contract uses an upgradeable pattern
contract IndexToken is
    Initializable,
    ContextUpgradeable,
    ERC20Upgradeable,
    ProposableOwnableUpgradeable,
    PausableUpgradeable,
    TokenInterface
{
    uint256 internal constant SCALAR = 1e20;

    // Inflation rate (per day) on total supply, to be accrued to the feeReceiver.
    uint256 public feeRatePerDayScaled;

    // Most recent timestamp when fee was accured.
    uint256 public feeTimestamp;

    // Address that can claim fees accrued.
    address public feeReceiver;

    // Address that can publish a new methodology.
    address public methodologist;

    string public methodology;

    uint256 public supplyCeiling;

    mapping(address => bool) public isRestricted;
    mapping(address => bool) public isMinter;

    modifier onlyMethodologist() {
        require(msg.sender == methodologist, "IndexToken: caller is not the methodologist");
        _;
    }

    modifier onlyMinter() {
        require(isMinter[msg.sender], "IndexToken: caller is not the minter");
        _;
    }

    function initialize(
        string memory tokenName,
        string memory tokenSymbol,
        uint256 _feeRatePerDayScaled,
        address _feeReceiver,
        uint256 _supplyCeiling
    ) external override initializer {
        require(bytes(tokenName).length > 0, "token name cannot be empty");
        require(bytes(tokenSymbol).length > 0, "token symbol cannot be empty");
        require(_feeRatePerDayScaled > 0, "fee rate must be greater than 0");
        require(_feeReceiver != address(0), "fee receiver cannot be the zero address");
        require(_supplyCeiling > 0, "supply ceiling must be greater than 0");

        __Ownable_init(msg.sender);
        __Pausable_init();
        __ERC20_init(tokenName, tokenSymbol);
        __Context_init();

        feeRatePerDayScaled = _feeRatePerDayScaled;
        feeReceiver = _feeReceiver;
        supplyCeiling = _supplyCeiling;
        feeTimestamp = block.timestamp;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice External mint function
    /// @dev Mint function can only be called externally by the controller
    /// @param to address
    /// @param amount uint256
    function mint(address to, uint256 amount) external override whenNotPaused onlyMinter {
        require(to != address(0), "mint to the zero address");
        require(amount > 0, "mint amount must be greater than 0");
        require(!isRestricted[to], "to is restricted");
        require(!isRestricted[msg.sender], "msg.sender is restricted");
        
        // Calculate potential fee amount first
        uint256 potentialFeeAmount = _calculatePotentialFeeAmount();
        
        // Check supply ceiling for both fee and main amount
        require(totalSupply() + potentialFeeAmount + amount <= supplyCeiling, "will exceed supply ceiling");
        
        _mintToFeeReceiver();
        _mint(to, amount);
    }

    /// @notice External burn function
    /// @dev burn function can only be called externally by the controller
    /// @param from address
    /// @param amount uint256
    function burn(address from, uint256 amount) external override whenNotPaused onlyMinter {
        require(from != address(0), "burn from the zero address");
        require(!isRestricted[from], "from is restricted");
        require(!isRestricted[msg.sender], "msg.sender is restricted");
        _mintToFeeReceiver();
        _burn(from, amount);
    }

    function _mintToFeeReceiver() internal {
        // total number of days elapsed
        uint256 _days = (block.timestamp - feeTimestamp) / 1 days;

        if (_days >= 1) {
            uint256 initial = totalSupply();
            uint256 supply = initial;
            uint256 _feeRate = feeRatePerDayScaled;

            // Use a logarithmic approximation for compounding
            uint256 compoundedFeeRate = SCALAR + (_feeRate * _days);
            // Calculate the compounded supply
            supply = (supply * compoundedFeeRate) / SCALAR;

            uint256 amount = supply - initial;  // This is the FEE amount
            feeTimestamp += 1 days * _days;

            require(totalSupply() + amount <= supplyCeiling, "will exceed supply ceiling");

            _mint(feeReceiver, amount);  // Mints the FEE

            emit MintFeeToReceiver(feeReceiver, block.timestamp, totalSupply(), amount);
        }
    }

    /// @notice Expands supply and mints fees to fee reciever
    /// @dev Can only be called by the owner externally,
    /// @dev _mintToFeeReciver is the internal function and is called after each supply/rate change
    function mintToFeeReceiver() external override onlyOwner whenNotPaused {
        _mintToFeeReceiver();
    }

    /// @notice Only owner function for setting the methodologist
    /// @param _methodologist address
    function setMethodologist(address _methodologist) external override onlyOwner {
        require(_methodologist != address(0), "methodologist cannot be the zero address");
        methodologist = _methodologist;
        emit MethodologistSet(_methodologist);
    }

    /// @notice Callable only by the methodoligst to store on chain data about the underlying weight of the token
    /// @param _methodology string
    function setMethodology(string memory _methodology) external override onlyMethodologist {
        require(bytes(_methodology).length > 0, "methodology cannot be empty");
        methodology = _methodology;
        emit MethodologySet(_methodology);
    }

    /// @notice Ownable function to set the fee rate
    /// @dev Given the annual fee rate this function sets and calculates the rate per second
    /// @param _feeRatePerDayScaled uint256
    function setFeeRate(uint256 _feeRatePerDayScaled) external override onlyOwner {
        _mintToFeeReceiver();
        feeRatePerDayScaled = _feeRatePerDayScaled;
        emit FeeRateSet(_feeRatePerDayScaled);
    }

    /// @notice Ownable function to set the receiver
    /// @param _feeReceiver address
    function setFeeReceiver(address _feeReceiver) external override onlyOwner {
        require(_feeReceiver != address(0), "fee receiver cannot be the zero address");
        feeReceiver = _feeReceiver;
        emit FeeReceiverSet(_feeReceiver);
    }

    /// @notice Ownable function to set the contract that controls minting
    /// @param _minter address
    function setMinter(address _minter, bool _enable) external override onlyOwner {
        require(_minter != address(0), "minter cannot be the zero address");
        isMinter[_minter] = _enable;
        emit MinterSet(_minter, _enable); 
    }

    /// @notice Ownable function to set the limit at which the total supply cannot exceed
    /// @param _supplyCeiling uint256
    function setSupplyCeiling(uint256 _supplyCeiling) external override onlyOwner {
        supplyCeiling = _supplyCeiling;
        emit SupplyCeilingSet(_supplyCeiling);
    }

    function pause() external override onlyOwner {
        _pause();
    }

    function unpause() external override onlyOwner {
        _unpause();
    }

    /// @notice Compliance feature to blacklist bad actors
    /// @dev Negates current restriction state
    /// @param who address
    function toggleRestriction(address who) external override onlyOwner {
        isRestricted[who] = !isRestricted[who];
        emit ToggledRestricted(who, isRestricted[who]);
    }

    /// @notice Overriden ERC20 transfer to include restriction
    /// @param to address
    /// @param amount uint256
    /// @return bool
    function transfer(address to, uint256 amount) public override whenNotPaused returns (bool) {
        require(to != address(0), "transfer to the zero address");
        require(amount <= balanceOf(msg.sender), "transfer amount exceeds balance");
        require(!isRestricted[msg.sender], "msg.sender is restricted");
        require(!isRestricted[to], "to is restricted");

        _transfer(msg.sender, to, amount);
        return true;
    }

    /// @notice Overriden ERC20 transferFrom to include restriction
    /// @param from address
    /// @param to address
    /// @param amount uint256
    /// @return bool
    function transferFrom(address from, address to, uint256 amount) public override whenNotPaused returns (bool) {
        require(from != address(0), "from cannot be the zero address");
        require(to != address(0), "to cannot be the zero address");
        require(amount <= balanceOf(from), "transfer amount exceeds balance");
        require(!isRestricted[msg.sender], "msg.sender is restricted");
        require(!isRestricted[to], "to is restricted");
        require(!isRestricted[from], "from is restricted");

        _spendAllowance(from, msg.sender, amount);
        _transfer(from, to, amount);
        return true;
    }
}

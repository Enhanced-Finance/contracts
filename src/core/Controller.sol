/**
 * SPDX-License-Identifier: MIT
 */
pragma solidity ^0.8.28;

import {OwnableUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {ReentrancyGuardTransient} from "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuardTransient.sol";
import {Initializable} from "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {MarginVault} from "./libs/MarginVault.sol";
import {Actions} from "./libs/Actions.sol";
import {AddressBookInterface} from "./interfaces/AddressBookInterface.sol";
import {OtokenInterface} from "./interfaces/OtokenInterface.sol";
import {MarginCalculatorInterface} from "./interfaces/MarginCalculatorInterface.sol";
import {OracleInterface} from "./interfaces/OracleInterface.sol";
import {WhitelistInterface} from "./interfaces/WhitelistInterface.sol";
import {MarginPoolInterface} from "./interfaces/MarginPoolInterface.sol";
import {ControllerLogicInterface} from "./interfaces/ControllerLogicInterface.sol";

/**
 * Controller Error Codes
 * C1: sender is not full pauser
 * C2: sender is not partial pauser
 * C3: callee is not a whitelisted address
 * C4: system is partially paused
 * C5: system is fully paused
 * C6: msg.sender is not authorized to run action
 * C7: invalid addressbook address
 * C8: invalid owner address
 * C9: invalid input
 * C10: fullPauser cannot be set to address zero - removed for space
 * C11: partialPauser cannot be set to address zero - removed for space
 * C12: can not run actions for different owners
 * C13: can not run actions on different vaults
 * C14: invalid final vault state
 * C15: can not run actions on inexistent vault
 * C16: cannot deposit long otoken from this address
 * C17: otoken is not whitelisted to be used as collateral
 * C18: otoken used as collateral is already expired
 * C19: can not withdraw an expired otoken
 * C20: cannot deposit collateral from this address
 * C21: asset is not whitelisted to be used as collateral
 * C22: can not withdraw collateral from a vault with an expired short otoken
 * C23: otoken is not whitelisted to be minted
 * C24: can not mint expired otoken
 * C25: cannot burn from this address
 * C26: can not burn expired otoken
 * C27: otoken is not whitelisted to be redeemed
 * C28: can not redeem un-expired otoken
 * C29: asset prices not finalized yet
 * C30: can't settle vault with no otoken
 * C31: can not settle vault with un-expired otoken
 * C32: can not settle undercollateralized vault
 * C33: can not liquidate vault
 * C34: can not leave less than collateral dust
 * C35: invalid vault id
 * C36: cap amount should be greater than zero
 * C37: collateral exceed naked margin cap
 * C38: Redeem time period must be greater than zero
 * C39: Redeem time period has expired
 * C40: Vault settlement type does not match oToken settlement type.
 * C41: Redeem time period has not expired
 * C42: Caller is not Settlement
 * C43: Cannot have physically settled otokens with non physically settled vault, vice versa
 * C44: underlying price is higher than collateral price for physical settlement (unused)
 * C45: cannot redeem OTM physically settled option
 */

/**
 * @title Controller
 * @author Opyn Team
 * @notice Contract that controls the Gamma Protocol and the interaction of all sub contracts
 */
contract Controller is Initializable, OwnableUpgradeable, ReentrancyGuardTransient, UUPSUpgradeable {
    using MarginVault for MarginVault.Vault;

    AddressBookInterface public addressbook;
    WhitelistInterface public whitelist;
    OracleInterface public oracle;
    MarginCalculatorInterface public calculator;
    MarginPoolInterface public pool;
    ControllerLogicInterface public controllerLogic;

    ///@dev scale used in MarginCalculator
    uint256 internal constant BASE = 8;

    /// @notice only address that has permission to interact with the vaults in the system.
    /// the only function that will not be access controlled is Redeem()
    address public manager;

    /// @notice address that has permission to partially pause the system, where system functionality is paused
    /// except redeem and settleVault
    address public partialPauser;

    /// @notice address that has permission to fully pause the system, where all system functionality is paused
    address public fullPauser;

    /// @notice True if all system functionality is paused other than redeem and settle vault
    bool public systemPartiallyPaused;

    /// @notice True if all system functionality is paused
    bool public systemFullyPaused;

    /// @notice True if operators and vault owners are allowed to interact with vaults, false if not
    bool public operatorsEnabled = false;

    /// @dev mapping between an owner address and the number of owner address vaults
    mapping(address => uint256) internal accountVaultCounter;
    /// @dev mapping between an owner address and a specific vault using a vault id
    mapping(address => mapping(uint256 => MarginVault.Vault)) internal vaults;
    /// @dev mapping between an account owner and their approved or unapproved account operators
    mapping(address => mapping(address => bool)) internal operators;

    /******************************************************************** V2.0.0 storage upgrade ******************************************************/

    /// @dev mapping to map vault by each vault type, naked margin vault should be set to 1, spread/max loss vault should be set to 0, physically settled set to 2
    mapping(address => mapping(uint256 => uint256)) internal vaultType;
    /// @dev mapping to store the timestamp at which the vault was last updated, will be updated in every action that changes the vault state or when calling sync()
    mapping(address => mapping(uint256 => uint256)) internal vaultLatestUpdate;

    /// @dev mapping to store cap amount for naked margin vault per options collateral asset (scaled by collateral asset decimals)
    mapping(address => uint256) internal nakedCap;

    /// @dev mapping to store amount of naked margin vaults in pool
    mapping(address => uint256) internal nakedPoolBalance;

    ///@dev mapping to store liquidation states of a naked margin vault
    mapping(address => mapping(uint256 => MarginVault.VaultLiquidationDetails)) internal vaultLiquidationDetails;

    /// @notice emits an event when an account operator is updated for a specific account owner
    event AccountOperatorUpdated(address indexed accountOwner, address indexed operator, bool isSet);
    /// @notice emits an event when a new vault is opened
    event VaultOpened(address indexed accountOwner, uint256 vaultId, uint256 indexed vaultType);
    /// @notice emits an event when a vault is liquidated
    event VaultLiquidated(
        address indexed liquidator,
        address receiver,
        address indexed vaultOwner,
        uint256 auctionPrice,
        uint256 collateralPayout,
        uint256 debtAmount,
        uint256 vaultId,
        address indexed series
    );

    /// @notice emits an event when the system partial paused status changes
    event SystemPartiallyPaused(bool isPaused);
    /// @notice emits an event when the system fully paused status changes
    event SystemFullyPaused(bool isPaused);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice modifier to check if the system is not partially paused, where only redeem and settleVault is allowed
     */
    modifier notPartiallyPaused() {
        _isNotPartiallyPaused();

        _;
    }

    /**
     * @notice modifier to check if the system is not fully paused, where no functionality is allowed
     */
    modifier notFullyPaused() {
        _isNotFullyPaused();

        _;
    }

    /**
     * @notice modifier to check if sender is the fullPauser address
     */
    modifier onlyFullPauser() {
        _onlyFullPauser();
        _;
    }

    function _onlyFullPauser() internal view {
        require(msg.sender == fullPauser, "C1");
    }

    /**
     * @notice modifier to check if the sender is the partialPauser address
     */
    modifier onlyPartialPauser() {
        _onlyPartialPauser();
        _;
    }

    function _onlyPartialPauser() internal view {
        require(msg.sender == partialPauser, "C2");
    }

    /**
     * @notice modifier to check if the sender is the account owner or an approved account operator
     * @param _sender sender address
     */
    modifier onlyAuthorized(address _sender, address _accountOwner) {
        _isAuthorized(_sender, _accountOwner);

        _;
    }

    /**
     * @dev check if the system is not in a partiallyPaused state
     */
    function _isNotPartiallyPaused() internal view {
        require(!systemPartiallyPaused, "C4");
    }

    /**
     * @dev check if the system is not in an fullyPaused state
     */
    function _isNotFullyPaused() internal view {
        require(!systemFullyPaused, "C5");
    }

    /**
     * @dev check if the sender is the manager address
     * @param _sender msg.sender
     */
    function _isAuthorized(address _sender, address) internal view {
        require(_sender == manager, "C6");
    }

    function _revertIfNotManager() internal view {
        require(msg.sender == manager, "C6");
    }

    /**
     * @notice initalize the deployed contract
     * @param _addressBook addressbook module
     * @param _owner account owner address
     */
    function initialize(address _addressBook, address _owner, address _manager) external initializer {
        require(_addressBook != address(0), "C7");
        require(_owner != address(0), "C8");

        __Ownable_init(_owner);
        manager = _manager;
        addressbook = AddressBookInterface(_addressBook);
        _refreshConfigInternal();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @notice send asset amount to margin pool
     * @dev use donate() instead of direct transfer() to store the balance in assetBalance
     * @param _asset asset address
     * @param _amount amount to donate to pool
     */
    function donate(address _asset, uint256 _amount) external {
        _revertIfNotManager();
        pool.transferToPool(_asset, msg.sender, _amount);
    }

    /**
     * @notice lets the manager lend vault collateral out of the margin pool without mutating vault margin accounting
     * @dev EnhancedOptions records per-vault debt and must block redeem/settle while debt is unpaid.
     * @param _asset asset address
     * @param _receiver receiver address
     * @param _amount amount to lend from pool
     */
    function releaseVaultCollateralToCustody(address _asset, address _receiver, uint256 _amount)
        external
        notFullyPaused
    {
        _revertIfNotManager();
        require(_receiver != address(0), "C9");
        require(_amount > 0, "C9");
        pool.transferToUser(_asset, _receiver, _amount);
    }

    /**
     * @notice allows the partialPauser to toggle the systemPartiallyPaused variable and partially pause or partially unpause the system
     * @dev can only be called by the partialPauser
     * @param _partiallyPaused new boolean value to set systemPartiallyPaused to
     */
    function setSystemPartiallyPaused(bool _partiallyPaused) external onlyPartialPauser {
        require(systemPartiallyPaused != _partiallyPaused, "C9");

        systemPartiallyPaused = _partiallyPaused;

        emit SystemPartiallyPaused(systemPartiallyPaused);
    }

    /**
     * @notice allows the fullPauser to toggle the systemFullyPaused variable and fully pause or fully unpause the system
     * @dev can only be called by the fullyPauser
     * @param _fullyPaused new boolean value to set systemFullyPaused to
     */
    function setSystemFullyPaused(bool _fullyPaused) external onlyFullPauser {
        require(systemFullyPaused != _fullyPaused, "C9");

        systemFullyPaused = _fullyPaused;

        emit SystemFullyPaused(systemFullyPaused);
    }

    /**
     * @notice allows the owner to set a new manager
     * @param _manager new manager address
     */
    function setManager(address _manager) external onlyOwner {
        manager = _manager;
    }

    /**
     * @notice allows the owner to set the fullPauser address
     * @dev can only be called by the owner
     * @param _fullPauser new fullPauser address
     */
    function setFullPauser(address _fullPauser) external onlyOwner {
        fullPauser = _fullPauser;
    }

    /**
     * @notice allows the owner to set the partialPauser address
     * @dev can only be called by the owner
     * @param _partialPauser new partialPauser address
     */
    function setPartialPauser(address _partialPauser) external onlyOwner {
        partialPauser = _partialPauser;
    }

    /**
     * @notice allows the owner to toggle operatorsEnabled
     * @param _enabled whether operators are enabled or not
     */
    function setOperatorsEnabled(bool _enabled) external onlyOwner {
        require(!_enabled, "operators cannot be enabled");
        operatorsEnabled = _enabled;
    }

    /**
     * @notice allows a user to give or revoke privileges to an operator which can act on their behalf on their vaults
     * @dev can only be updated by the vault owner
     * @param _operator operator that the sender wants to give privileges to or revoke them from
     * @param _isOperator new boolean value that expresses if the sender is giving or revoking privileges for _operator
     */
    function setOperator(address _operator, bool _isOperator) external {
        require(operators[msg.sender][_operator] != _isOperator, "C9");

        operators[msg.sender][_operator] = _isOperator;

        emit AccountOperatorUpdated(msg.sender, _operator, _isOperator);
    }

    /**
     * @dev updates the configuration of the controller. can only be called by the owner
     */
    function refreshConfiguration() external onlyOwner {
        _refreshConfigInternal();
    }

    /**
     * @notice set cap amount for collateral asset used in naked margin
     * @dev can only be called by owner
     * @param _collateral collateral asset address
     * @param _cap cap amount, should be scaled by collateral asset decimals
     */
    function setNakedCap(address _collateral, uint256 _cap) external onlyOwner {
        require(_cap > 0, "C36");

        nakedCap[_collateral] = _cap;
    }

    /**
     * @notice execute a number of actions on specific vaults
     * @dev can only be called when the system is not fully paused
     * @param _actions array of actions arguments
     */
    function operate(Actions.ActionArgs[] memory _actions) external nonReentrant notFullyPaused {
        (bool vaultUpdated, address vaultOwner, uint256 vaultId) = _runActions(_actions);
        if (vaultUpdated) {
            _verifyFinalState(vaultOwner, vaultId);
            vaultLatestUpdate[vaultOwner][vaultId] = block.timestamp;
        }
    }

    /**
     * @notice sync vault latest update timestamp
     * @dev anyone can update the latest time the vault was touched by calling this function
     * vaultLatestUpdate will sync if the vault is well collateralized
     * @param _owner vault owner address
     * @param _vaultId vault id
     */
    function sync(address _owner, uint256 _vaultId) external nonReentrant notFullyPaused {
        _verifyFinalState(_owner, _vaultId);
        vaultLatestUpdate[_owner][_vaultId] = block.timestamp;
    }

    /**
     * @notice clear a vaults liquidation details
     * @param _vaultId vaultId to return balances for
     */
    function clearVaultLiquidationDetails(uint256 _vaultId) external {
        delete vaultLiquidationDetails[msg.sender][_vaultId];
    }

    /**
     * @notice check if a specific address is an operator for an owner account
     * @param _owner account owner address
     * @param _operator account operator address
     * @return True if the _operator is an approved operator for the _owner account
     */
    function isOperator(address _owner, address _operator) external view returns (bool) {
        return operators[_owner][_operator];
    }

    /**
     * @notice returns the current controller configuration
     * @return whitelist, the address of the whitelist module
     * @return oracle, the address of the oracle module
     * @return calculator, the address of the calculator module
     * @return pool, the address of the pool module
     */
    function getConfiguration() external view returns (address, address, address, address) {
        return (address(whitelist), address(oracle), address(calculator), address(pool));
    }

    /**
     * @notice return a vault's proceeds pre or post expiry, the amount of collateral that can be removed from a vault
     * @param _owner account owner of the vault
     * @param _vaultId vaultId to return balances for
     * @return amount of collateral that can be taken out
     */
    function getProceed(address _owner, uint256 _vaultId) external view returns (uint256) {
        (MarginVault.Vault memory vault, uint256 typeVault,) = getVaultWithDetails(_owner, _vaultId);

        (uint256 netValue, bool isExcess) = calculator.getExcessCollateral(vault, typeVault);

        if (!isExcess) return 0;

        return netValue;
    }

    /**
     * @notice return a vault's past liquidation details
     * @param _owner account owner of the vault
     * @param _vaultId vaultId to return balances for
     * @return series address liquidated
     * @return amount of shorts liquidated
     * @return amount of collateral transferred for liquidation
     */
    function getVaultLiquidationDetails(address _owner, uint256 _vaultId)
        external
        view
        returns (address, uint256, uint256)
    {
        MarginVault.VaultLiquidationDetails memory vault = vaultLiquidationDetails[_owner][_vaultId];
        return (vault.series, vault.shortAmount, vault.collateralAmount);
    }

    /**
     * @notice check if a vault is liquidatable in a specific round id
     * @param _owner vault owner address
     * @param _vaultId vault id to check
     * @return isUnderCollat, true if vault is undercollateralized, the price of 1 repaid otoken and the otoken collateral dust amount
     */
    function isLiquidatable(address _owner, uint256 _vaultId) external view returns (bool, uint256, uint256) {
        (, bool isUnderCollat, uint256 price, uint256 dust) = _isLiquidatable(_owner, _vaultId);
        return (isUnderCollat, price, dust);
    }

    /**
     * @dev return if an expired oToken is ready to be settled, only true when price for underlying,
     * strike and collateral assets at this specific expiry is available in our Oracle module
     * @param _otoken oToken
     */
    function isSettlementAllowed(address _otoken) external view returns (bool) {
        (address underlying, address strike, address collateral, uint256 expiry) = _getOtokenDetails(_otoken);
        return _canSettleAssets(underlying, strike, collateral, expiry);
    }

    /**
     * @dev return if underlying, strike, collateral are all allowed to be settled
     * @param _underlying oToken underlying asset
     * @param _strike oToken strike asset
     * @param _collateral oToken collateral asset
     * @param _expiry otoken expiry timestamp
     * @return True if the oToken has expired AND all oracle prices at the expiry timestamp have been finalized, False if not
     */
    function canSettleAssets(address _underlying, address _strike, address _collateral, uint256 _expiry)
        external
        view
        returns (bool)
    {
        return _canSettleAssets(_underlying, _strike, _collateral, _expiry);
    }

    /**
     * @notice get the number of vaults for a specified account owner
     * @param _accountOwner account owner address
     * @return number of vaults
     */
    function getAccountVaultCounter(address _accountOwner) external view returns (uint256) {
        return accountVaultCounter[_accountOwner];
    }

    /**
     * @notice check if an oToken has expired
     * @param _otoken oToken address
     * @return True if the otoken has expired, False if not
     */
    function hasExpired(address _otoken) external view returns (bool) {
        return block.timestamp >= OtokenInterface(_otoken).expiryTimestamp();
    }

    /**
     * @notice return a specific vault
     * @param _owner account owner
     * @param _vaultId vault id of vault to return
     * @return Vault struct that corresponds to the _vaultId of _owner
     */
    function getVault(address _owner, uint256 _vaultId) external view returns (MarginVault.Vault memory) {
        return (vaults[_owner][_vaultId]);
    }

    /**
     * @notice return a specific vault
     * @param _owner account owner
     * @param _vaultId vault id of vault to return
     * @return Vault struct that corresponds to the _vaultId of _owner, vault type and the latest timestamp when the vault was updated
     */
    function getVaultWithDetails(address _owner, uint256 _vaultId)
        public
        view
        returns (MarginVault.Vault memory, uint256, uint256)
    {
        return (vaults[_owner][_vaultId], vaultType[_owner][_vaultId], vaultLatestUpdate[_owner][_vaultId]);
    }

    /**
     * @notice get cap amount for collateral asset
     * @param _asset collateral asset address
     * @return cap amount
     */
    function getNakedCap(address _asset) external view returns (uint256) {
        return nakedCap[_asset];
    }

    /**
     * @notice get amount of collateral deposited in all naked margin vaults
     * @param _asset collateral asset address
     * @return naked pool balance
     */
    function getNakedPoolBalance(address _asset) external view returns (uint256) {
        return nakedPoolBalance[_asset];
    }

    /**
     * @notice execute a variety of actions
     * @dev for each action in the action array, execute the corresponding action, only one vault can be modified
     * for all actions except SettleVault and Redeem
     * @param _actions array of type Actions.ActionArgs[], which expresses which actions the user wants to execute
     * @return vaultUpdated, indicates if a vault has changed
     * @return owner, the vault owner if a vault has changed
     * @return vaultId, the vault Id if a vault has changed
     */
    function _runActions(Actions.ActionArgs[] memory _actions) internal returns (bool, address, uint256) {
        address vaultOwner;
        uint256 vaultId;
        bool vaultUpdated;

        for (uint256 i = 0; i < _actions.length; i++) {
            Actions.ActionArgs memory action = _actions[i];
            Actions.ActionType actionType = action.actionType;

            // actions except Settle, Redeem and Liquidate are "Vault-updating actinos"
            // only allow update 1 vault in each operate call
            if (
                (actionType != Actions.ActionType.SettleVault) && (actionType != Actions.ActionType.Redeem)
                    && (actionType != Actions.ActionType.Liquidate)
            ) {
                // check if this action is manipulating the same vault as all other actions, if a vault has already been updated
                if (vaultUpdated) {
                    require(vaultOwner == action.owner, "C12");
                    require(vaultId == action.vaultId, "C13");
                }
                vaultUpdated = true;
                vaultId = action.vaultId;
                vaultOwner = action.owner;
            }

            if (actionType == Actions.ActionType.OpenVault) {
                _openVault(Actions._parseOpenVaultArgs(action));
            } else if (actionType == Actions.ActionType.DepositLongOption) {
                _depositLong(Actions._parseDepositArgs(action));
            } else if (actionType == Actions.ActionType.WithdrawLongOption) {
                _withdrawLong(Actions._parseWithdrawArgs(action));
            } else if (actionType == Actions.ActionType.DepositCollateral) {
                _depositCollateral(Actions._parseDepositArgs(action));
            } else if (actionType == Actions.ActionType.WithdrawCollateral) {
                _withdrawCollateral(Actions._parseWithdrawArgs(action));
            } else if (actionType == Actions.ActionType.MintShortOption) {
                _mintOtoken(Actions._parseMintArgs(action));
            } else if (actionType == Actions.ActionType.BurnShortOption) {
                _burnOtoken(Actions._parseBurnArgs(action));
            } else if (actionType == Actions.ActionType.Redeem) {
                _redeem(Actions._parseRedeemArgs(action));
            } else if (actionType == Actions.ActionType.SettleVault) {
                _settleVault(Actions._parseSettleVaultArgs(action));
            } else if (actionType == Actions.ActionType.Liquidate) {
                _liquidate(Actions._parseLiquidateArgs(action));
            }
        }

        return (vaultUpdated, vaultOwner, vaultId);
    }

    /**
     * @notice verify the vault final state after executing all actions
     * @param _owner account owner address
     * @param _vaultId vault id of the final vault
     */
    function _verifyFinalState(address _owner, uint256 _vaultId) internal view {
        (MarginVault.Vault memory vault, uint256 typeVault,) = getVaultWithDetails(_owner, _vaultId);
        bool isValidVault;

        // if physically settled vault past its redeem time period, no collateral is required so vault is always valid
        if (
            typeVault == 2 && _isNotEmpty(vault.shortOtokens)
                && block.timestamp
                    >= OtokenInterface(vault.shortOtokens[0]).expiryTimestamp() + controllerLogic.redeemTimePeriod()
        ) {
            isValidVault = true;
        } else {
            (, isValidVault) = calculator.getExcessCollateral(vault, typeVault);
        }
        require(isValidVault, "C14");
    }

    /**
     * @notice open a new vault inside an account
     * @dev only the account owner or operator can open a vault, cannot be called when system is partiallyPaused or fullyPaused
     * @param _args OpenVaultArgs structure
     */
    function _openVault(Actions.OpenVaultArgs memory _args)
        internal
        notPartiallyPaused
        onlyAuthorized(msg.sender, _args.owner)
    {
        uint256 vaultId = accountVaultCounter[_args.owner] + 1;

        require(_args.vaultId == vaultId, "C15");

        // store new vault
        accountVaultCounter[_args.owner] = vaultId;
        vaultType[_args.owner][vaultId] = _args.vaultType;

        emit VaultOpened(_args.owner, vaultId, _args.vaultType);
    }

    /**
     * @notice deposit a long oToken into a vault
     * @dev only the account owner or operator can deposit a long oToken, cannot be called when system is partiallyPaused or fullyPaused
     * @param _args DepositArgs structure
     */
    function _depositLong(Actions.DepositArgs memory _args)
        internal
        notPartiallyPaused
        onlyAuthorized(msg.sender, _args.owner)
    {
        require(_checkVaultId(_args.owner, _args.vaultId), "C35");
        // only allow vault owner or vault operator to deposit long otoken
        require((_args.from == msg.sender) || (_args.from == _args.owner), "C16");

        controllerLogic.handleDepositLong(_args);
    }

    /**
     * @notice withdraw a long oToken from a vault
     * @dev only the account owner or operator can withdraw a long oToken, cannot be called when system is partiallyPaused or fullyPaused
     * @param _args WithdrawArgs structure
     */
    function _withdrawLong(Actions.WithdrawArgs memory _args)
        internal
        notPartiallyPaused
        onlyAuthorized(msg.sender, _args.owner)
    {
        require(_checkVaultId(_args.owner, _args.vaultId), "C35");

        controllerLogic.handleWithdrawLong(_args);
    }

    /**
     * @notice deposit a collateral asset into a vault
     * @dev only the account owner or operator can deposit collateral, cannot be called when system is partiallyPaused or fullyPaused
     * @param _args DepositArgs structure
     */
    function _depositCollateral(Actions.DepositArgs memory _args)
        internal
        notPartiallyPaused
        onlyAuthorized(msg.sender, _args.owner)
    {
        require(_checkVaultId(_args.owner, _args.vaultId), "C35");
        // only allow vault owner or vault operator to deposit collateral
        require((_args.from == msg.sender) || (_args.from == _args.owner), "C20");

        controllerLogic.handleDepositCollateral(_args);
    }

    /**
     * @notice withdraw a collateral asset from a vault
     * @dev only the account owner or operator can withdraw collateral, cannot be called when system is partiallyPaused or fullyPaused
     * @param _args WithdrawArgs structure
     */
    function _withdrawCollateral(Actions.WithdrawArgs memory _args)
        internal
        notPartiallyPaused
        onlyAuthorized(msg.sender, _args.owner)
    {
        require(_checkVaultId(_args.owner, _args.vaultId), "C35");

        controllerLogic.handleWithdrawCollateral(_args);
    }

    /**
     * @notice mint short oTokens from a vault which creates an obligation that is recorded in the vault
     * @dev only the account owner or operator can mint an oToken, cannot be called when system is partiallyPaused or fullyPaused
     * @param _args MintArgs structure
     */
    function _mintOtoken(Actions.MintArgs memory _args)
        internal
        notPartiallyPaused
        onlyAuthorized(msg.sender, _args.owner)
    {
        require(_checkVaultId(_args.owner, _args.vaultId), "C35");

        controllerLogic.handleMintOtoken(_args, vaultType[_args.owner][_args.vaultId]);
    }

    /**
     * @notice burn oTokens to reduce or remove the minted oToken obligation recorded in a vault
     * @dev only the account owner or operator can burn an oToken, cannot be called when system is partiallyPaused or fullyPaused
     * @param _args MintArgs structure
     */
    function _burnOtoken(Actions.BurnArgs memory _args)
        internal
        notPartiallyPaused
        onlyAuthorized(msg.sender, _args.owner)
    {
        // check that vault id is valid for this vault owner
        require(_checkVaultId(_args.owner, _args.vaultId), "C35");
        // only allow vault owner or vault operator to burn otoken
        require((_args.from == msg.sender) || (_args.from == _args.owner), "C25");

        controllerLogic.handleBurnOtoken(_args, vaultType[_args.owner][_args.vaultId]);
    }

    /**
     * @notice redeem an oToken after expiry, receiving the payout of the oToken in the collateral asset
     * @dev cannot be called when system is fullyPaused
     * @param _args RedeemArgs structure
     */
    function _redeem(Actions.RedeemArgs memory _args) internal {
        _revertIfNotManager();
        controllerLogic.handleRedeem(_args, msg.sender);
    }

    /**
     * @notice settle a vault after expiry, removing the net proceeds/collateral after both long and short oToken payouts have settled
     * @dev deletes a vault of vaultId after net proceeds/collateral is removed, cannot be called when system is fullyPaused
     * @param _args SettleVaultArgs structure
     */
    function _settleVault(Actions.SettleVaultArgs memory _args) internal onlyAuthorized(msg.sender, _args.owner) {
        require(_checkVaultId(_args.owner, _args.vaultId), "C35");

        controllerLogic.handleSettle(_args);
    }

    /**
     * @notice liquidate naked margin vault
     * @dev can liquidate different vaults id in the same operate() call
     * @param _args liquidation action arguments struct
     */
    function _liquidate(Actions.LiquidateArgs memory _args) internal notPartiallyPaused {
        _revertIfNotManager();
        require(_checkVaultId(_args.owner, _args.vaultId), "C35");

        // check if vault is undercollateralized
        // the price is the amount of collateral asset to pay per 1 repaid debt(otoken)
        // collateralDust is the minimum amount of collateral that can be left in the vault when a partial liquidation occurs
        (MarginVault.Vault memory vault, bool isUnderCollat, uint256 price, uint256 collateralDust) =
            _isLiquidatable(_args.owner, _args.vaultId);

        require(isUnderCollat, "C33");

        // amount of collateral to offer to liquidator
        uint256 collateralToSell = _args.amount * price / 1e8;

        // if vault is partially liquidated (amount of short otoken is still greater than zero)
        // make sure remaining collateral amount is greater than dust amount
        if (vault.shortAmounts[0] - _args.amount > 0) {
            require(vault.collateralAmounts[0] - collateralToSell >= collateralDust, "C34");
        }

        // burn short otoken from liquidator address, index of short otoken hardcoded at 0
        // this should always work, if vault have no short otoken, it will not reach this step
        OtokenInterface(vault.shortOtokens[0]).burnOtoken(msg.sender, _args.amount);
        // increment the vault liquidation details to store the fact that this vault was liquidated
        MarginVault.VaultLiquidationDetails storage vaultLiqDetails =
            vaultLiquidationDetails[_args.owner][_args.vaultId];
        address series = vault.shortOtokens[0];
        if (vaultLiqDetails.series == vault.shortOtokens[0]) {
            vaultLiqDetails.shortAmount = uint128(uint256(vaultLiqDetails.shortAmount) + _args.amount);
            vaultLiqDetails.collateralAmount = uint128(uint256(vaultLiqDetails.collateralAmount) + collateralToSell);
        } else {
            vaultLiqDetails.series = vault.shortOtokens[0];
            vaultLiqDetails.shortAmount = uint128(_args.amount);
            vaultLiqDetails.collateralAmount = uint128(collateralToSell);
        }
        // decrease amount of collateral in liquidated vault, index of collateral to decrease is hardcoded at 0
        vaults[_args.owner][_args.vaultId].removeCollateral(vault.collateralAssets[0], collateralToSell, 0);

        // decrease amount of short otoken in liquidated vault, index of short otoken to decrease is hardcoded at 0
        vaults[_args.owner][_args.vaultId].removeShort(vault.shortOtokens[0], _args.amount, 0);

        // decrease internal naked margin collateral amount
        nakedPoolBalance[vault.collateralAssets[0]] = nakedPoolBalance[vault.collateralAssets[0]] - collateralToSell;

        pool.transferToUser(vault.collateralAssets[0], _args.receiver, collateralToSell);

        emit VaultLiquidated(
            msg.sender, _args.receiver, _args.owner, price, collateralToSell, _args.amount, _args.vaultId, series
        );
    }

    /**
     * @notice check if a vault id is valid for a given account owner address
     * @param _accountOwner account owner address
     * @param _vaultId vault id to check
     * @return True if the _vaultId is valid, False if not
     */
    function _checkVaultId(address _accountOwner, uint256 _vaultId) internal view returns (bool) {
        return ((_vaultId > 0) && (_vaultId <= accountVaultCounter[_accountOwner]));
    }

    function _isNotEmpty(address[] memory _array) internal pure returns (bool) {
        return (_array.length > 0) && (_array[0] != address(0));
    }

    /**
     * @notice check if a vault is liquidatable in a specific round id
     * @param _owner vault owner address
     * @param _vaultId vault id to check
     * @return vault struct, isLiquidatable, true if vault is undercollateralized, the price of 1 repaid otoken and the otoken collateral dust amount
     */
    function _isLiquidatable(address _owner, uint256 _vaultId)
        internal
        view
        returns (MarginVault.Vault memory, bool, uint256, uint256)
    {
        (MarginVault.Vault memory vault, uint256 typeVault,) = getVaultWithDetails(_owner, _vaultId);
        (bool isUnderCollat, uint256 price, uint256 collateralDust) = calculator.isLiquidatable(vault, typeVault);

        return (vault, isUnderCollat, price, collateralDust);
    }

    /**
     * @dev get otoken detail, from both otoken versions
     */
    function _getOtokenDetails(address _otoken) internal view returns (address, address, address, uint256) {
        OtokenInterface otoken = OtokenInterface(_otoken);
        try otoken.getOtokenDetails() returns (
            address collateral, address underlying, address strike, uint256, uint256 expiry, bool, bool
        ) {
            return (collateral, underlying, strike, expiry);
        } catch {
            return (otoken.collateralAsset(), otoken.underlyingAsset(), otoken.strikeAsset(), otoken.expiryTimestamp());
        }
    }

    /**
     * @dev return if an expired oToken is ready to be settled, only true when price for underlying,
     * strike and collateral assets at this specific expiry is available in our Oracle module
     * @return True if the oToken has expired AND all oracle prices at the expiry timestamp have been finalized, False if not
     */
    function _canSettleAssets(address _underlying, address _strike, address _collateral, uint256 _expiry)
        internal
        view
        returns (bool)
    {
        return oracle.isDisputePeriodOver(_underlying, _expiry) && oracle.isDisputePeriodOver(_strike, _expiry)
            && oracle.isDisputePeriodOver(_collateral, _expiry);
    }

    /**
     * @dev updates the internal configuration of the controller
     */
    function _refreshConfigInternal() internal {
        whitelist = WhitelistInterface(addressbook.getWhitelist());
        oracle = OracleInterface(addressbook.getOracle());
        calculator = MarginCalculatorInterface(addressbook.getMarginCalculator());
        pool = MarginPoolInterface(addressbook.getMarginPool());
        controllerLogic = ControllerLogicInterface(addressbook.getControllerLogic());
    }

    function increaseNakedPoolBalance(address _asset, uint256 _amount) external {
        require(msg.sender == addressbook.getControllerLogic(), "C42");
        nakedPoolBalance[_asset] = nakedPoolBalance[_asset] + _amount;
    }

    function reduceNakedPoolBalance(address _asset, uint256 _amount) external {
        require(msg.sender == addressbook.getControllerLogic(), "C42");
        nakedPoolBalance[_asset] = nakedPoolBalance[_asset] - _amount;
    }

    enum VaultActions {
        AddShort,
        RemoveShort,
        AddLong,
        RemoveLong,
        AddCollateral,
        RemoveCollateral,
        Delete
    }

    function updateVault(VaultActions _action, address _owner, uint256 _vaultId, address _asset, uint256 _amount)
        external
    {
        require(msg.sender == addressbook.getControllerLogic(), "C42");

        if (_action == VaultActions.AddShort) {
            vaults[_owner][_vaultId].addShort(_asset, _amount, 0); // _asset is otoken
        }
        if (_action == VaultActions.RemoveShort) {
            vaults[_owner][_vaultId].removeShort(_asset, _amount, 0); // _asset is otoken
        }
        if (_action == VaultActions.AddLong) {
            vaults[_owner][_vaultId].addLong(_asset, _amount, 0);
        }
        if (_action == VaultActions.RemoveLong) {
            vaults[_owner][_vaultId].removeLong(_asset, _amount, 0);
        }
        if (_action == VaultActions.AddCollateral) {
            vaults[_owner][_vaultId].addCollateral(_asset, _amount, 0);
        }
        if (_action == VaultActions.RemoveCollateral) {
            vaults[_owner][_vaultId].removeCollateral(_asset, _amount, 0);
        }
        if (_action == VaultActions.Delete) {
            delete vaults[_owner][_vaultId];
        }
    }
}

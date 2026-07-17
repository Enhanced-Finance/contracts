// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {SignatureChecker} from "lib/openzeppelin-contracts/contracts/utils/cryptography/SignatureChecker.sol";
import {Math} from "lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import {ReentrancyGuard} from "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {OwnableUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {
    EIP712Upgradeable
} from "lib/openzeppelin-contracts-upgradeable/contracts/utils/cryptography/EIP712Upgradeable.sol";
import {UUPSUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";

import {IEnhancedOptions} from "../../core/interfaces/IEnhancedOptions.sol";
import {ISwapRouter} from "../../core/interfaces/ISwapRouter.sol";
import {EnhancedVaultCycleLib} from "./libs/EnhancedVaultCycleLib.sol";
import {EnhancedVaultRecordsLib} from "./libs/EnhancedVaultRecordsLib.sol";

/**
 * @title Vault (v2)
 * @notice Manages multiple isolated option-writing vaults with per-user fund accounting
 *         (`userFunds`) and O(1) settlement math via cumulative ratio accumulators.
 *
 *         Each vault is identified by keccak256(abi.encode(VaultParams)).
 *         Runtime flow is the three-step cycle pipeline:
 *         `settlePreviousCycle` -> `processQueuedUsers` -> `startNextCycle`.
 *         Users deposit/withdraw/buyback against user-level balances, and queue processing
 *         applies settled-cycle math plus pending transitions exactly once per user/cycle.
 *
 *         The operator drives each cycle to open EnhancedOptions positions.
 *         Premiums and principal scaling are tracked via cumulative accumulators
 *         (inspired by Synthetix StakingRewards), enabling O(1) nextCycle settlement.
 */
contract EnhancedVault is EIP712Upgradeable, OwnableUpgradeable, ReentrancyGuard, UUPSUpgradeable {
    using SafeERC20 for IERC20;

    // ─────────────────────────────────────────────────────────────────────────
    // Constants
    // ─────────────────────────────────────────────────────────────────────────

    // Keep 1e18 precision to stay compatible with existing accounting/storage assumptions.
    uint256 private constant PRECISION = 1e18;
    // minPrincipalRatio / buybackPriceRatio precision base (10000 = 100%).
    uint256 private constant RATIO_BASE = 10_000;
    // protocolFeeRate precision base (10000000 = 100%) for the per-cycle settlement fee.
    uint256 private constant PROTOCOL_FEE_RATE_BASE = 10_000_000;
    int256 private constant MAX_SIGNED_BPS = 10_000;
    uint256 internal constant MAX_BATCH_SIZE = 100;

    bytes32 private constant VAULT_ORDER_TYPEHASH = keccak256("VaultOrder(bytes32 vaultHash,bytes32 payloadHash)");

    // ─────────────────────────────────────────────────────────────────────────
    // Structs
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Immutable identity fields of a vault.
    struct VaultParams {
        uint256 cycleDuration;
        address underlyingAsset;
        address collateralAsset;
        address strikeAsset;
        bool isPut;
        uint256 capacity;
        uint256 minInvestmentAmount;
        uint256 startTime;
        // Signed bps offset reserved for strike selection metadata. It is hashed and emitted,
        // but this version does not apply it to order placement logic.
        int256 strikePriceBps;
        uint256 minPrincipalRatio;
        int256 buybackPriceRatio;
    }

    /// @notice Runtime state for each registered vault
    struct VaultState {
        VaultParams params;
        bool isActive;
        uint256 currentCycleId; // current cycle (starts at 1)
        uint256 currentCycleStart; // timestamp when current cycle began
        uint256 totalDeposited; // running total of collateral held (capacity check)
        bool isPaused;
        bool isEnd;
        uint256 protocolFeeRate; // per-cycle protocol fee rate charged during cycle settlement
    }

    /// @notice Per-cycle record
    struct CycleRecord {
        uint256 totalActiveCollateral; // total active collateral at cycle start
        uint256 remainingActiveCollateral; // active collateral not allocated to orders in this cycle
        uint256 totalPremium; // total premium distributed in this cycle
        uint256 collateralRatio; // principal scaling ratio (PRECISION)
        uint256 premiumRatio; // premium per unit active collateral (PRECISION)
    }

    enum CyclePhase {
        OPEN,
        SETTLED,
        PROCESSING_DONE,
        ENDED
    }

    struct UserFund {
        uint256 activePrincipal;
        uint256 pendingActivePrincipal;
        uint256 pendingWithdrawAmount;
        uint256 stoppedPrincipal;
        uint256 systemPausedPrincipal;
        uint256 materializedPremium;
        uint256 entryCumCollateral;
        uint256 entryCumPremium;
        uint256 initialAmountTotal;
        uint256 nextRecordId;
        bool buybackEnabled;
        bool exists;
        bool autoBuyEnabled;
    }

    /// @notice Full view of a user's position for a vault, with all amounts scaled to their real values.
    struct UserPosition {
        uint256 activeBalance; // activePrincipal scaled by cumCollateral ratio — real collateralAsset value
        uint256 pendingDeposit; // pendingActivePrincipal waiting to enter next cycle (collateralAsset)
        uint256 pendingWithdrawAmount; // requested withdraw not yet processed (collateralAsset)
        uint256 claimableWithdraw; // stoppedPrincipal ready to claim via claimWithdraw (collateralAsset)
        uint256 claimableSystemPaused; // systemPausedPrincipal ready to withdraw via withdraw() (collateralAsset)
        uint256 claimablePremium; // materializedPremium ready to claim via claimPremium (strikeAsset)
        uint256 projectedPremium; // claimablePremium + un-materialized accrued premium (strikeAsset)
    }

    enum FundRecordType {
        DEPOSIT,
        WITHDRAW_REQUEST,
        WITHDRAW
    }

    struct FundRecord {
        uint256 id;
        bytes32 vaultHash;
        address user;
        FundRecordType recordType;
        uint256 amount;
        uint256 createdCycleId;
        bool isExitAll;
    }

    struct TransitionQueue {
        address[] users;
        uint256 queueLenSnapshot; // logical queue length in OPEN; frozen length after settlement
        uint256 processedCount;
        uint256 queueCycleId;
    }

    struct CycleSettlement {
        uint256 totalReturned;
        uint256 totalPremium;
        uint256 activeCol;
        uint256 protocolFee;
        uint256 netActiveCollateral;
    }

    struct CycleAdvanceState {
        uint256 settledCycleId;
        uint256 nextCycleId;
        uint256 capReduction;
        uint256 totalReturned;
        uint256 totalPremium;
        bool initialized;
    }

    /// @notice Uniswap V3 swap parameters for buyback
    struct SwapParams {
        uint256 amountIn; // total premium input (must <= Σ available premium)
        uint256 amountOutMinimum; // minimum collateral output (slippage protection)
        uint256 deadline; // swap deadline
        uint24 fee; // pool fee tier (e.g. 3000 = 0.3%)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // State
    // ─────────────────────────────────────────────────────────────────────────

    address public operator;
    address public vaultSigner;
    IEnhancedOptions public enhancedOptions;

    /// @dev vaultHash → vault runtime state
    mapping(bytes32 => VaultState) public vaults;

    /// @dev vaultHash → cycleId → vault IDs opened in that cycle
    mapping(bytes32 => mapping(uint256 => uint256[])) private _vaultIds;

    /// @dev vaultHash → user → user fund record
    mapping(bytes32 => mapping(address => UserFund)) public userFunds;

    /// @dev vaultHash → transition queue metadata
    mapping(bytes32 => TransitionQueue) private _transitionQueues;

    /// @dev vaultHash → user → whether currently queued
    mapping(bytes32 => mapping(address => bool)) public queued;

    /// @dev vaultHash → cycle phase
    mapping(bytes32 => CyclePhase) public vaultPhases;

    /// @dev vaultHash → cycle advancement staging data between settle/process/start
    mapping(bytes32 => CycleAdvanceState) private _cycleAdvanceStates;

    /// @dev vaultHash → user → settled cycle id when this user was processed
    mapping(bytes32 => mapping(address => uint256)) private _processedQueueCycle;

    /// @dev vaultHash -> user -> recordId -> pending record detail
    mapping(bytes32 => mapping(address => mapping(uint256 => FundRecord))) private pendingDepositRecords;
    mapping(bytes32 => mapping(address => mapping(uint256 => FundRecord))) private pendingWithdrawRequestRecords;
    mapping(bytes32 => mapping(address => mapping(uint256 => FundRecord))) private pendingWithdrawRecords;

    /// @dev vaultHash -> user -> pending record ids
    mapping(bytes32 => mapping(address => uint256[])) private pendingDepositIds;
    mapping(bytes32 => mapping(address => uint256[])) private pendingWithdrawRequestIds;
    mapping(bytes32 => mapping(address => uint256[])) private pendingWithdrawIds;

    /// @dev vaultHash -> user -> recordId -> index + 1 in pending IDs array
    mapping(bytes32 => mapping(address => mapping(uint256 => uint256))) private pendingDepositIndex;
    mapping(bytes32 => mapping(address => mapping(uint256 => uint256))) private pendingWithdrawRequestIndex;
    mapping(bytes32 => mapping(address => mapping(uint256 => uint256))) private pendingWithdrawIndex;

    /// @dev vaultHash -> user -> full-exit request record id while the full-exit flow is open.
    mapping(bytes32 => mapping(address => uint256)) private pendingExitAllRequestId;

    /// @dev vaultHash → cycleId → CycleRecord
    mapping(bytes32 => mapping(uint256 => CycleRecord)) public cycleRecords;

    /// @dev vaultHash → cycleId → cumulative collateral scaling factor (PRECISION)
    mapping(bytes32 => mapping(uint256 => uint256)) public cumCollateral;

    /// @dev vaultHash → cycleId → cumulative premium per unit initial principal (PRECISION)
    mapping(bytes32 => mapping(uint256 => uint256)) public cumPremium;

    /// @dev vaultHash → premium accumulated in the current cycle (strikeAsset units)
    mapping(bytes32 => uint256) private _cyclePremium;

    /// @dev Uniswap V3 swap router for buyback
    address public swapRouter;

    /// @notice Current recipient for claimed protocol fees.
    address public protocolFeeRecipient;

    /// @notice Accrued protocol fees per vault, denominated in that vault's collateralAsset.
    /// @dev Fees are deducted from user TVL during cycle settlement; claiming only transfers the already-accrued balance.
    mapping(bytes32 => uint256) public protocolFeeAccrued;

    // ─────────────────────────────────────────────────────────────────────────
    // Events
    // ─────────────────────────────────────────────────────────────────────────

    event VaultCreated(
        bytes32 indexed vaultHash,
        uint256 cycleDuration,
        address underlyingAsset,
        address collateralAsset,
        address strikeAsset,
        bool isPut,
        uint256 capacity,
        uint256 minInvestmentAmount,
        uint256 startTime,
        int256 strikePriceBps,
        uint256 minPrincipalRatio,
        int256 buybackPriceRatio,
        uint256 protocolFeeRate
    );
    event VaultProtocolFeeRateChanged(bytes32 indexed vaultHash, uint256 oldRate, uint256 newRate);
    event Deposited(bytes32 indexed vaultHash, address indexed user, uint256 recordId, uint256 amount);
    event WithdrawRequested(bytes32 indexed vaultHash, address indexed user, uint256 recordId, uint256 amount);
    // event UserQueued(bytes32 indexed vaultHash, address indexed user);
    /// @notice Emitted when a cycle's options are settled and accounting finalized.
    event CycleSettled(
        bytes32 indexed vaultHash,
        uint256 indexed settledCycleId,
        uint256 totalActiveCollateral,
        uint256 allocatedCollateral,
        uint256 totalReturned,
        uint256 totalPremium
    );
    /// @notice Emitted when a new cycle opens.
    event CycleStarted(
        bytes32 indexed vaultHash,
        uint256 indexed newCycleId,
        uint256 totalActiveCollateral,
        uint256 cycleStart,
        uint256 cycleEnd
    );
    event OrderCreated(bytes32 indexed vaultHash, uint256 vaultId);
    event BuybackExecuted(bytes32 indexed vaultHash, uint256 totalPremiumSpent, uint256 totalCollateralReceived);
    event BuybackAllocatedToUser(bytes32 indexed vaultHash, address indexed user, uint256 collateralReceived);
    event BuybackEnabledSet(bytes32 indexed vaultHash, address indexed user, bool enabled);
    event AutoBuyEnabledSet(bytes32 indexed vaultHash, address indexed user, bool enabled);
    event FundRecordCreated(
        bytes32 indexed vaultHash,
        address indexed user,
        uint256 indexed recordId,
        FundRecordType recordType,
        uint256 amount
    );
    event FundRecordCanceled(
        bytes32 indexed vaultHash,
        address indexed user,
        uint256 indexed recordId,
        FundRecordType recordType,
        uint256 amount
    );
    event FundRecordConverted(
        bytes32 indexed vaultHash,
        address indexed user,
        uint256 indexed fromRecordId,
        uint256 toRecordId,
        uint256 amount
    );
    event FundRecordClaimed(
        bytes32 indexed vaultHash,
        address indexed user,
        uint256 indexed recordId,
        FundRecordType recordType,
        uint256 amount
    );
    event UserSystemPaused(bytes32 indexed vaultHash, address indexed user, uint256 amount);
    // event ClaimedActive(bytes32 indexed vaultHash, address indexed user, uint256 amount);
    // event PremiumClaimed(bytes32 indexed vaultHash, address indexed user, uint256 amount);
    event VaultTerminated(bytes32 indexed vaultHash);

    // ─────────────────────────────────────────────────────────────────────────
    // Errors
    // ─────────────────────────────────────────────────────────────────────────

    error NotOperator();
    error CycleProcessingLocked();
    error VaultNotFound();
    error VaultNotActive();
    error VaultPaused();
    error VaultEnded();
    error VaultNotEnded();
    error VaultAlreadyExists();
    error ZeroAddress();
    error ZeroCycleDuration();
    error ZeroStartTime();
    error BelowMinInvestment();
    error CapacityExceeded();
    error InvalidSignature();
    error NotActive();
    error CycleNotFinished();
    error InsufficientPremium();
    error InvalidBatchSize();
    error WrongTaker();
    error MustBeCashSettled();
    error WrongUnderlying();
    error WrongCollateral();
    error WrongStrikeAsset();
    error WrongOptionType();
    error WrongExpiry();
    error ExpiryInPast();
    error InsufficientRemainingActiveCollateral();
    error BuybackDeadlineExpired();
    error BuybackDisabled(address user);
    error ZeroAmount();
    error InvalidCyclePhase();
    error QueueProcessingIncomplete();
    error RecordNotPending();
    error RecordCycleMismatch();
    error InsufficientPendingAmount();
    error UserNotBelowMinPrincipalRatio(address user);
    error WithdrawConversionPreviewMismatch();
    error FundNotFound();
    error AutoBuyPremiumClaimDisabled();

    // ─────────────────────────────────────────────────────────────────────────
    // Modifiers
    // ─────────────────────────────────────────────────────────────────────────

    modifier onlyOperator() {
        _onlyOperator();
        _;
    }

    modifier vaultExists(bytes32 vaultHash) {
        _vaultExists(vaultHash);
        _;
    }

    function _onlyOperator() internal view {
        if (msg.sender != operator) revert NotOperator();
    }

    function _vaultExists(bytes32 vaultHash) internal view {
        if (vaults[vaultHash].params.cycleDuration == 0) revert VaultNotFound();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Constructor / Initializer
    // ─────────────────────────────────────────────────────────────────────────

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _enhancedOptions,
        address _operator,
        address _vaultSigner,
        address _protocolFeeRecipient
    ) external initializer {
        if (_enhancedOptions == address(0)) revert ZeroAddress();
        if (_operator == address(0)) revert ZeroAddress();
        if (_vaultSigner == address(0)) revert ZeroAddress();
        if (_protocolFeeRecipient == address(0)) revert ZeroAddress();

        __EIP712_init("Vault", "0.0.0");
        __Ownable_init_unchained(msg.sender);

        enhancedOptions = IEnhancedOptions(_enhancedOptions);
        operator = _operator;
        vaultSigner = _vaultSigner;
        protocolFeeRecipient = _protocolFeeRecipient;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    // ─────────────────────────────────────────────────────────────────────────
    // Owner admin
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Register a new vault.
     */
    function createVault(VaultParams calldata _params, uint256 protocolFeeRate)
        external
        onlyOwner
        returns (bytes32 vaultHash)
    {
        if (_params.cycleDuration == 0) revert ZeroCycleDuration();
        if (_params.startTime == 0) revert ZeroStartTime();
        if (_params.collateralAsset == address(0)) revert ZeroAddress();
        if (_params.underlyingAsset == address(0)) revert ZeroAddress();
        if (_params.strikeAsset == address(0)) revert ZeroAddress();
        _requireValidSignedBps(_params.strikePriceBps);
        _requireValidSignedBps(_params.buybackPriceRatio);
        _requireValidProtocolFeeRate(protocolFeeRate);

        vaultHash = keccak256(abi.encode(_params));
        if (vaults[vaultHash].params.cycleDuration != 0) revert VaultAlreadyExists();

        VaultState storage st = vaults[vaultHash];
        st.params = _params;
        st.isActive = true;
        st.currentCycleId = 1;
        st.currentCycleStart = _params.startTime;
        st.protocolFeeRate = protocolFeeRate;

        // Fresh mappings default to zero, so only write the non-zero accumulator seed here.
        cumCollateral[vaultHash][0] = PRECISION;
        vaultPhases[vaultHash] = CyclePhase.OPEN;
        _transitionQueues[vaultHash].queueCycleId = 1;

        emit VaultCreated(
            vaultHash,
            _params.cycleDuration,
            _params.underlyingAsset,
            _params.collateralAsset,
            _params.strikeAsset,
            _params.isPut,
            _params.capacity,
            _params.minInvestmentAmount,
            _params.startTime,
            _params.strikePriceBps,
            _params.minPrincipalRatio,
            _params.buybackPriceRatio,
            protocolFeeRate
        );
    }

    function _requireValidSignedBps(int256 ratio) internal pure {
        // Keep all signed vault ratios within +/-100% so off-chain config mistakes fail fast.
        if (ratio < -MAX_SIGNED_BPS || ratio > MAX_SIGNED_BPS) revert();
    }

    function _requireValidProtocolFeeRate(uint256 protocolFeeRate) internal pure {
        if (protocolFeeRate > PROTOCOL_FEE_RATE_BASE) revert();
    }

    function setVaultActive(bytes32 vaultHash, bool _active) external onlyOwner vaultExists(vaultHash) {
        vaults[vaultHash].isActive = _active;
    }

    function setVaultPaused(bytes32 vaultHash, bool _paused) external onlyOwner vaultExists(vaultHash) {
        vaults[vaultHash].isPaused = _paused;
    }

    function setVaultEnd(bytes32 vaultHash, bool _end) external onlyOwner vaultExists(vaultHash) {
        vaults[vaultHash].isEnd = _end;
    }

    function setVaultProtocolFeeRate(bytes32 vaultHash, uint256 protocolFeeRate)
        external
        onlyOwner
        vaultExists(vaultHash)
    {
        _requireValidProtocolFeeRate(protocolFeeRate);
        uint256 oldRate = vaults[vaultHash].protocolFeeRate;
        vaults[vaultHash].protocolFeeRate = protocolFeeRate;
        emit VaultProtocolFeeRateChanged(vaultHash, oldRate, protocolFeeRate);
    }

    function pauseVault(bytes32 vaultHash) external onlyOperator vaultExists(vaultHash) {
        _requireActive(vaultHash);
        vaults[vaultHash].isPaused = true;
    }

    function setOperator(address _operator) external onlyOwner {
        if (_operator == address(0)) revert ZeroAddress();
        operator = _operator;
    }

    function setVaultSigner(address _signer) external onlyOwner {
        if (_signer == address(0)) revert ZeroAddress();
        vaultSigner = _signer;
    }

    function marginPool() public view returns (address) {
        return enhancedOptions.marginPool();
    }

    function setProtocolFeeRecipient(address _recipient) external onlyOwner {
        if (_recipient == address(0)) revert ZeroAddress();
        protocolFeeRecipient = _recipient;
    }

    /// @notice sets approval for the margin pool to remove funds for an asset
    function setAssetApprovalMarginPool(address _asset, bool _approval) external {
        _checkOwner();
        address marginPool_ = marginPool();
        if (marginPool_ == address(0)) revert ZeroAddress();
        _forceApprove(_asset, marginPool_, _approval ? type(uint256).max : 0);
    }

    /// @notice kept for deployment compatibility; buyback now grants per-swap router allowance
    function setAssetApprovalSwapRouter(address _asset, bool _approval) external {
        _checkOwner();
        if (swapRouter == address(0)) revert ZeroAddress();
        _forceApprove(_asset, swapRouter, _approval ? type(uint256).max : 0);
    }

    function _forceApprove(address _asset, address _spender, uint256 _amount) internal {
        IERC20(_asset).forceApprove(_spender, _amount);
    }

    function setSwapRouter(address _router) external onlyOwner {
        if (_router == address(0)) revert ZeroAddress();
        swapRouter = _router;
    }

    function setEnhancedOptions(address _enhancedOptions) external onlyOwner {
        if (_enhancedOptions == address(0)) revert ZeroAddress();
        enhancedOptions = IEnhancedOptions(_enhancedOptions);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // User write entrypoints (OPEN phase)
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Deposit collateral into vault pending balance.
     *         Pending collateral is merged into active only when queue processing
     *         runs for the settled cycle.
     */
    function deposit(bytes32 vaultHash, uint256 amount) external nonReentrant vaultExists(vaultHash) {
        VaultState storage st = vaults[vaultHash];
        address user = msg.sender;

        _requireUserWritable(vaultHash);
        _requireOpenPhase(vaultHash);
        _requireNoExitAllPending(vaultHash, user);
        if (amount < st.params.minInvestmentAmount) revert BelowMinInvestment();
        if (st.totalDeposited + amount > st.params.capacity) revert CapacityExceeded();

        // Pull collateral
        IERC20(st.params.collateralAsset).safeTransferFrom(user, address(this), amount);
        UserFund storage fund = userFunds[vaultHash][user];
        if (!fund.exists) {
            fund.exists = true;
            fund.buybackEnabled = false;
            fund.autoBuyEnabled = true;
        }
        fund.pendingActivePrincipal += amount;
        fund.initialAmountTotal += amount;
        unchecked {
            st.totalDeposited += amount;
        }
        uint256 recordId = _addPendingDeposit(vaultHash, user, amount);
        _enqueueUser(vaultHash, user);

        emit Deposited(vaultHash, user, recordId, amount);
    }

    function cancelDeposit(bytes32 vaultHash, uint256 recordId) external nonReentrant vaultExists(vaultHash) {
        _requireUserWritable(vaultHash);
        FundRecord memory rec = EnhancedVaultRecordsLib.getPendingRecord(
            pendingDepositRecords[vaultHash][msg.sender],
            pendingDepositIndex[vaultHash][msg.sender],
            recordId,
            FundRecordType.DEPOSIT
        );
        if (vaultPhases[vaultHash] != CyclePhase.OPEN) revert CycleProcessingLocked();
        if (vaults[vaultHash].currentCycleId != rec.createdCycleId) revert RecordCycleMismatch();

        UserFund storage fund = userFunds[vaultHash][msg.sender];
        if (fund.pendingActivePrincipal < rec.amount || fund.initialAmountTotal < rec.amount) {
            revert InsufficientPendingAmount();
        }

        fund.pendingActivePrincipal -= rec.amount;
        fund.initialAmountTotal -= rec.amount;

        VaultState storage st = vaults[vaultHash];
        _releaseCollateral(st, msg.sender, rec.amount);

        emit FundRecordCanceled(vaultHash, msg.sender, recordId, rec.recordType, rec.amount);
        _removePendingDeposit(vaultHash, msg.sender, recordId);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // User withdraw request / cancel
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice User-initiated withdraw request against active principal.
     *         The effective withdraw amount is clamped during queue processing
     *         after settled-cycle principal scaling is applied.
     */
    function withdraw(bytes32 vaultHash, uint256 amount) external {
        withdraw(vaultHash, amount, false);
    }

    function withdraw(bytes32 vaultHash, uint256 amount, bool isExitAll) public nonReentrant vaultExists(vaultHash) {
        _requireActiveAndNotPaused(vaultHash);
        _requireOpenPhase(vaultHash);
        UserFund storage fund = userFunds[vaultHash][msg.sender];

        _requireNoExitAllPending(vaultHash, msg.sender);

        if (isExitAll) {
            if (amount != 0) revert ZeroAmount();
            if (
                fund.activePrincipal == 0 && fund.pendingActivePrincipal == 0 && fund.systemPausedPrincipal == 0
                    && fund.stoppedPrincipal == 0
            ) {
                revert NotActive();
            }
            uint256 exitAllRecordId = _addPendingWithdrawRequest(vaultHash, msg.sender, 0, true);
            pendingExitAllRequestId[vaultHash][msg.sender] = exitAllRecordId;
            _enqueueUser(vaultHash, msg.sender);
            emit WithdrawRequested(vaultHash, msg.sender, exitAllRecordId, 0);
            return;
        }

        if (amount == 0) revert ZeroAmount();
        // System-pause fast path: user has pre-settled funds, bypass queue.
        if (fund.systemPausedPrincipal > 0) {
            if (amount > fund.systemPausedPrincipal) revert InsufficientPendingAmount();
            uint256 settledCycleId = _settledCycleId(vaultHash);
            uint256 principalBeforeExit = _projectSettledActive(fund, cumCollateral[vaultHash][settledCycleId])
                + fund.pendingActivePrincipal + fund.systemPausedPrincipal;
            _reduceInitialAmountProRata(fund, amount, principalBeforeExit);
            fund.systemPausedPrincipal -= amount;
            unchecked {
                fund.stoppedPrincipal += amount;
            }
            uint256 _recordId = _addPendingWithdraw(vaultHash, msg.sender, amount);
            emit WithdrawRequested(vaultHash, msg.sender, _recordId, amount);
            return;
        }
        if (fund.activePrincipal == 0) revert NotActive();
        fund.pendingWithdrawAmount += amount;
        // Capacity enforcement lives in _addPendingWithdrawRequest to avoid duplicating the same
        // runtime-size-expensive check in both the public entrypoint and the record constructor.
        uint256 recordId = _addPendingWithdrawRequest(vaultHash, msg.sender, amount, false);

        _enqueueUser(vaultHash, msg.sender);

        emit WithdrawRequested(vaultHash, msg.sender, recordId, amount);
    }

    function cancelWithdraw(bytes32 vaultHash, uint256 recordId) external nonReentrant vaultExists(vaultHash) {
        _requireUserWritable(vaultHash);
        FundRecord memory rec = EnhancedVaultRecordsLib.getPendingRecord(
            pendingWithdrawRequestRecords[vaultHash][msg.sender],
            pendingWithdrawRequestIndex[vaultHash][msg.sender],
            recordId,
            FundRecordType.WITHDRAW_REQUEST
        );

        UserFund storage fund = userFunds[vaultHash][msg.sender];
        if (!rec.isExitAll) {
            if (fund.pendingWithdrawAmount < rec.amount) revert InsufficientPendingAmount();
            fund.pendingWithdrawAmount -= rec.amount;
        } else if (pendingExitAllRequestId[vaultHash][msg.sender] == recordId) {
            delete pendingExitAllRequestId[vaultHash][msg.sender];
        }

        emit FundRecordCanceled(vaultHash, msg.sender, recordId, rec.recordType, rec.amount);
        _removePendingWithdrawRequest(vaultHash, msg.sender, recordId);
    }

    function claimWithdraw(bytes32 vaultHash, uint256 recordId) external nonReentrant vaultExists(vaultHash) {
        _requireActiveAndNotPaused(vaultHash);
        VaultState storage st = vaults[vaultHash];
        FundRecord memory rec = EnhancedVaultRecordsLib.getPendingRecord(
            pendingWithdrawRecords[vaultHash][msg.sender],
            pendingWithdrawIndex[vaultHash][msg.sender],
            recordId,
            FundRecordType.WITHDRAW
        );
        UserFund storage fund = userFunds[vaultHash][msg.sender];
        if (fund.stoppedPrincipal < rec.amount) revert InsufficientPendingAmount();

        fund.stoppedPrincipal -= rec.amount;
        _releaseCollateral(st, msg.sender, rec.amount);
        emit FundRecordClaimed(vaultHash, msg.sender, recordId, rec.recordType, rec.amount);
        _removePendingWithdraw(vaultHash, msg.sender, recordId);
    }

    /**
     * @notice Claim materialized premium (strikeAsset) accumulated from option selling.
     *         Only claimable when the vault is active and not paused.
     *         Settled premium and current-cycle premium already received by the vault are materialized on demand.
     *
     * @param vaultHash  Target vault
     * @param amount        Amount of strikeAsset to claim (must be <= materializedPremium)
     */
    function claimPremium(bytes32 vaultHash, uint256 amount) external nonReentrant vaultExists(vaultHash) {
        _requireActiveAndNotPaused(vaultHash);
        if (amount == 0) revert ZeroAmount();

        VaultState storage st = vaults[vaultHash];
        UserFund storage fund = userFunds[vaultHash][msg.sender];
        if (fund.autoBuyEnabled || fund.buybackEnabled) revert AutoBuyPremiumClaimDisabled();

        uint256 cycleCumPremium = _premiumAccumulator(vaultHash);
        uint256 premium = _materializeProjectedPremium(fund, cycleCumPremium);
        if (premium > 0) {
            fund.entryCumPremium = cycleCumPremium;
        }

        if (fund.materializedPremium < amount) revert InsufficientPremium();
        fund.materializedPremium -= amount;

        _transferAsset(st.params.strikeAsset, msg.sender, amount);
        // emit PremiumClaimed(vaultHash, msg.sender, amount);
    }

    /**
     * @notice Claim active principal after the vault has reached the ENDED phase.
     *         Applies the final settlement ratio to activePrincipal and transfers funds.
     *         Also returns any unactivated pendingActivePrincipal at 1:1.
     *
     * @param vaultHash  Target vault
     */
    function claimActive(bytes32 vaultHash) external nonReentrant vaultExists(vaultHash) {
        _requireActive(vaultHash);
        if (vaultPhases[vaultHash] != CyclePhase.ENDED) revert InvalidCyclePhase();

        UserFund storage fund = userFunds[vaultHash][msg.sender];
        if (fund.activePrincipal == 0 && fund.pendingActivePrincipal == 0 && fund.systemPausedPrincipal == 0) {
            revert NotActive();
        }

        VaultState storage st = vaults[vaultHash];
        // In ENDED phase, currentCycleId is the last settled cycle (startNextCycle was never called).
        uint256 cycleCumCollateral = cumCollateral[vaultHash][st.currentCycleId];
        _materializeProjectedPremium(fund, cumPremium[vaultHash][st.currentCycleId]);
        uint256 settledAmount = _projectSettledActive(fund, cycleCumCollateral);

        // Also return pending deposit that was never activated
        uint256 pendingAmount = fund.pendingActivePrincipal;
        uint256 systemPausedAmount = fund.systemPausedPrincipal;

        uint256 totalAmount = settledAmount + pendingAmount + systemPausedAmount;
        if (totalAmount == 0) revert ZeroAmount();

        fund.activePrincipal = 0;
        fund.entryCumCollateral = 0;
        fund.pendingActivePrincipal = 0;
        fund.systemPausedPrincipal = 0;
        _reduceInitialAmountProRata(fund, totalAmount, totalAmount);

        _releaseCollateral(st, msg.sender, totalAmount);
        // emit ClaimedActive(vaultHash, msg.sender, totalAmount);
    }

    function setBuybackEnabled(bytes32 vaultHash, bool enabled) external vaultExists(vaultHash) {
        UserFund storage fund = userFunds[vaultHash][msg.sender];
        if (!fund.exists) revert FundNotFound();
        fund.buybackEnabled = enabled;
        emit BuybackEnabledSet(vaultHash, msg.sender, enabled);
    }

    function setAutoBuyEnabled(bytes32 vaultHash, bool enabled) external vaultExists(vaultHash) {
        UserFund storage fund = userFunds[vaultHash][msg.sender];
        if (!fund.exists) revert FundNotFound();
        fund.autoBuyEnabled = enabled;
        emit AutoBuyEnabledSet(vaultHash, msg.sender, enabled);
    }

    function claimProtocolFees(bytes32 vaultHash) external nonReentrant vaultExists(vaultHash) {
        address recipient = protocolFeeRecipient;
        if (msg.sender != owner() && msg.sender != recipient) revert();
        if (recipient == address(0)) revert ZeroAddress();

        uint256 amount = protocolFeeAccrued[vaultHash];
        if (amount == 0) revert ZeroAmount();
        protocolFeeAccrued[vaultHash] = 0;

        _transferAsset(vaults[vaultHash].params.collateralAsset, recipient, amount);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Operator force pause
    // ─────────────────────────────────────────────────────────────────────────

    // ─────────────────────────────────────────────────────────────────────────
    // Buyback (operator)
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Batch buyback: spend user premium (strikeAsset) via Uniswap V3 swap
     *         to acquire collateralAsset, then add collateral into user pendingActivePrincipal.
     *
     *         Premium deduction and collateral distribution are both proportional to
     *         deficit ratio: userDeficit / totalDeficit.
     *
     * @param vaultHash   Target vault
     * @param users          User addresses to buyback for
     * @param swapParams     Uniswap V3 swap parameters (amountIn <= Σ available premium)
     */
    function buyback(bytes32 vaultHash, address[] calldata users, SwapParams calldata swapParams)
        external
        nonReentrant
        onlyOperator
        vaultExists(vaultHash)
    {
        _requireActiveAndNotPaused(vaultHash);
        if (vaultPhases[vaultHash] == CyclePhase.ENDED) revert InvalidCyclePhase();
        _requireOpenPhase(vaultHash);
        if (block.timestamp > swapParams.deadline) revert BuybackDeadlineExpired();
        if (users.length == 0 || users.length > MAX_BATCH_SIZE) revert InvalidBatchSize();
        if (swapParams.amountIn == 0) revert ZeroAmount();
        VaultState storage st = vaults[vaultHash];
        uint256 cycleCumPremium = _premiumAccumulator(vaultHash);
        uint256 itemLen = users.length;
        uint256 totalAvailablePremium;
        uint256[] memory availablePremiums = new uint256[](itemLen);

        for (uint256 i; i < itemLen;) {
            UserFund storage fund = userFunds[vaultHash][users[i]];
            if (!(fund.buybackEnabled || fund.autoBuyEnabled)) revert BuybackDisabled(users[i]);
            uint256 premium = _materializeProjectedPremium(fund, cycleCumPremium);
            if (premium > 0) {
                fund.entryCumPremium = cycleCumPremium;
            }
            uint256 available = fund.materializedPremium;
            if (available == 0) revert InsufficientPremium();
            availablePremiums[i] = available;
            unchecked {
                totalAvailablePremium += available;
            }
            unchecked {
                ++i;
            }
        }

        if (swapParams.amountIn > totalAvailablePremium) revert InsufficientPremium();

        uint256[] memory premiumSpent =
            _deductUserBuybackPremiums(vaultHash, users, availablePremiums, totalAvailablePremium, swapParams.amountIn);

        address strikeAsset = st.params.strikeAsset;
        address collateralAsset = st.params.collateralAsset;

        uint256 amountOut = ISwapRouter(swapRouter)
            .exactInputSingle(
                ISwapRouter.ExactInputSingleParams({
                    tokenIn: strikeAsset,
                    tokenOut: collateralAsset,
                    fee: swapParams.fee,
                    recipient: address(this),
                    amountIn: swapParams.amountIn,
                    amountOutMinimum: swapParams.amountOutMinimum,
                    sqrtPriceLimitX96: 0
                })
            );

        st.totalDeposited += amountOut;
        _allocateBuybackToUsers(vaultHash, users, premiumSpent, swapParams.amountIn, amountOut);

        emit BuybackExecuted(vaultHash, swapParams.amountIn, amountOut);
    }

    function _deductUserBuybackPremiums(
        bytes32 vaultHash,
        address[] calldata users,
        uint256[] memory availablePremiums,
        uint256 totalAvailablePremium,
        uint256 amountIn
    ) internal returns (uint256[] memory premiumSpent) {
        uint256 itemLen = users.length;
        premiumSpent = new uint256[](itemLen);

        uint256 deducted;
        for (uint256 i; i < itemLen;) {
            uint256 premiumShare =
                i == itemLen - 1 ? amountIn - deducted : amountIn * availablePremiums[i] / totalAvailablePremium;
            UserFund storage fund = userFunds[vaultHash][users[i]];
            if (premiumShare > fund.materializedPremium) revert InsufficientPremium();
            fund.materializedPremium -= premiumShare;
            premiumSpent[i] = premiumShare;
            unchecked {
                deducted += premiumShare;
            }
            unchecked {
                ++i;
            }
        }
    }

    function _allocateBuybackToUsers(
        bytes32 vaultHash,
        address[] calldata users,
        uint256[] memory premiumSpent,
        uint256 totalPremiumSpent,
        uint256 amountOut
    ) internal {
        uint256 itemLen = users.length;
        uint256[] memory shares = new uint256[](itemLen);
        uint256 distributed;
        for (uint256 i; i < itemLen;) {
            uint256 share = amountOut * premiumSpent[i] / totalPremiumSpent;
            shares[i] = share;
            unchecked {
                distributed += share;
            }
            unchecked {
                ++i;
            }
        }

        uint256 remainder = amountOut - distributed;
        for (uint256 i; i < itemLen && remainder > 0;) {
            unchecked {
                shares[i] += 1;
                remainder -= 1;
            }
            unchecked {
                ++i;
            }
        }

        for (uint256 i; i < itemLen;) {
            address user = users[i];
            UserFund storage fund = userFunds[vaultHash][user];
            fund.pendingActivePrincipal += shares[i];
            _enqueueUser(vaultHash, user);
            emit BuybackAllocatedToUser(vaultHash, user, shares[i]);
            unchecked {
                ++i;
            }
        }
    }

    function _processQueuedUsers(bytes32 vaultHash, uint256 offset, uint256 limit) internal {
        if (vaultPhases[vaultHash] != CyclePhase.SETTLED) revert InvalidCyclePhase();
        if (limit == 0 || limit > MAX_BATCH_SIZE) revert InvalidBatchSize();

        TransitionQueue storage queue = _transitionQueues[vaultHash];
        uint256 queueLen = queue.queueLenSnapshot;
        if (offset >= queueLen) return;

        uint256 end = offset + limit;
        if (end > queueLen) end = queueLen;

        CycleAdvanceState storage advance = _cycleAdvanceStates[vaultHash];
        uint256 settledCycleId = advance.settledCycleId;
        uint256 nextCycleId = advance.nextCycleId;
        uint256 cycleCumCollateral = cumCollateral[vaultHash][settledCycleId];
        uint256 cycleCumPremium = cumPremium[vaultHash][settledCycleId];

        for (uint256 i = offset; i < end;) {
            address user = queue.users[i];
            if (_processQueuedUserForCycle(
                    vaultHash, user, settledCycleId, nextCycleId, cycleCumCollateral, cycleCumPremium
                )) {
                unchecked {
                    queue.processedCount += 1;
                }
            }
            unchecked {
                ++i;
            }
        }

        if (queue.processedCount == queueLen) {
            vaultPhases[vaultHash] = CyclePhase.PROCESSING_DONE;
        }
    }

    function _processQueuedUserForCycle(
        bytes32 vaultHash,
        address user,
        uint256 settledCycleId,
        uint256 nextCycleId,
        uint256 cycleCumCollateral,
        uint256 cycleCumPremium
    ) internal returns (bool processed) {
        if (_processedQueueCycle[vaultHash][user] == settledCycleId) return false;
        int256 delta = _processSingleQueuedUser(vaultHash, user, cycleCumCollateral, cycleCumPremium);
        _applyUserActiveDelta(vaultHash, nextCycleId, delta);
        _processedQueueCycle[vaultHash][user] = settledCycleId;
        queued[vaultHash][user] = false;
        return true;
    }

    function _processSingleQueuedUser(
        bytes32 vaultHash,
        address user,
        uint256 cycleCumCollateral,
        uint256 cycleCumPremium
    ) internal returns (int256 activeDelta) {
        UserFund storage fund = userFunds[vaultHash][user];
        uint256 exitAllRequestId = pendingExitAllRequestId[vaultHash][user];
        if (
            fund.activePrincipal == 0 && fund.pendingActivePrincipal == 0 && fund.pendingWithdrawAmount == 0
                && exitAllRequestId == 0 && fund.entryCumCollateral == 0 && fund.entryCumPremium == 0
        ) {
            return 0;
        }
        VaultState storage st = vaults[vaultHash];
        uint256 settledActive = _projectSettledActive(fund, cycleCumCollateral);
        _materializeProjectedPremium(fund, cycleCumPremium);
        if (exitAllRequestId != 0) {
            return _processExitAllQueuedUser(vaultHash, user, exitAllRequestId, settledActive);
        }
        uint256 stopAmount = _convertWithdrawRequestRecordsToWithdraw(vaultHash, user, settledActive);
        uint256 principalBeforeExit = settledActive + fund.pendingActivePrincipal + fund.systemPausedPrincipal;
        _reduceInitialAmountProRata(fund, stopAmount, principalBeforeExit);

        uint256 remainingActive = settledActive - stopAmount;
        unchecked {
            fund.stoppedPrincipal += stopAmount;
        }

        // Candidate active balance for next cycle: remaining settled + new deposits.
        uint256 candidateActive = remainingActive + fund.pendingActivePrincipal;
        uint256 totalCandidate = candidateActive + fund.systemPausedPrincipal;

        uint256 newActive;
        if (cycleCumCollateral == 0) {
            uint256 pendingDepositRefund = _convertPendingDepositRecordsToWithdraw(vaultHash, user);
            fund.initialAmountTotal =
                fund.initialAmountTotal >= pendingDepositRefund ? fund.initialAmountTotal - pendingDepositRefund : 0;
            unchecked {
                fund.stoppedPrincipal += pendingDepositRefund;
                fund.systemPausedPrincipal += candidateActive - pendingDepositRefund;
            }
        } else if (_isBelowMinPrincipalRatio(st, totalCandidate, fund.initialAmountTotal)) {
            _markPendingDepositRecordsConverted(vaultHash, user);
            unchecked {
                fund.systemPausedPrincipal += candidateActive;
            }
        } else {
            _markPendingDepositRecordsConverted(vaultHash, user);
            newActive = totalCandidate;
            fund.systemPausedPrincipal = 0;
        }

        fund.activePrincipal = newActive;
        fund.pendingActivePrincipal = 0;
        fund.pendingWithdrawAmount = 0;

        if (newActive > 0) {
            fund.entryCumCollateral = cycleCumCollateral;
            fund.entryCumPremium = cycleCumPremium;
        } else {
            fund.entryCumCollateral = 0;
            fund.entryCumPremium = 0;
        }

        return int256(newActive) - int256(settledActive);
    }

    function _processExitAllQueuedUser(bytes32 vaultHash, address user, uint256 requestId, uint256 settledActive)
        internal
        returns (int256 activeDelta)
    {
        EnhancedVaultRecordsLib.processExitAllQueuedUser(
            pendingDepositIds[vaultHash][user],
            pendingDepositRecords[vaultHash][user],
            pendingDepositIndex[vaultHash][user],
            pendingWithdrawRequestIds[vaultHash][user],
            pendingWithdrawRequestRecords[vaultHash][user],
            pendingWithdrawRequestIndex[vaultHash][user],
            pendingWithdrawIds[vaultHash][user],
            pendingWithdrawRecords[vaultHash][user],
            pendingWithdrawIndex[vaultHash][user],
            userFunds,
            vaults,
            vaultHash,
            user,
            requestId,
            settledActive
        );
        delete pendingExitAllRequestId[vaultHash][user];
        return -int256(settledActive);
    }

    function _convertPendingDepositRecordsToWithdraw(bytes32 vaultHash, address user)
        internal
        returns (uint256 refunded)
    {
        return EnhancedVaultRecordsLib.convertPendingDepositRecordsToWithdraw(
            pendingDepositIds[vaultHash][user],
            pendingDepositRecords[vaultHash][user],
            pendingDepositIndex[vaultHash][user],
            pendingWithdrawIds[vaultHash][user],
            pendingWithdrawRecords[vaultHash][user],
            pendingWithdrawIndex[vaultHash][user],
            userFunds,
            vaults,
            vaultHash,
            user
        );
    }

    function _markPendingDepositRecordsConverted(bytes32 vaultHash, address user) internal {
        EnhancedVaultRecordsLib.markPendingDepositRecordsConverted(
            pendingDepositIds[vaultHash][user],
            pendingDepositRecords[vaultHash][user],
            pendingDepositIndex[vaultHash][user],
            vaultHash,
            user
        );
    }

    function _convertWithdrawRequestRecordsToWithdraw(bytes32 vaultHash, address user, uint256 settledActive)
        internal
        returns (uint256 stopAmount)
    {
        return EnhancedVaultRecordsLib.convertWithdrawRequestRecordsToWithdraw(
            userFunds,
            pendingWithdrawRequestIds[vaultHash][user],
            pendingWithdrawRequestRecords[vaultHash][user],
            pendingWithdrawRequestIndex[vaultHash][user],
            pendingWithdrawIds[vaultHash][user],
            pendingWithdrawRecords[vaultHash][user],
            pendingWithdrawIndex[vaultHash][user],
            vaults,
            vaultHash,
            user,
            settledActive
        );
    }

    function _nextRecordId(bytes32 vaultHash, address user) internal returns (uint256 recordId) {
        return EnhancedVaultRecordsLib.nextRecordId(userFunds, vaultHash, user);
    }

    function _addPendingDeposit(bytes32 vaultHash, address user, uint256 amount) internal returns (uint256 recordId) {
        return EnhancedVaultRecordsLib.addPendingDeposit(
            userFunds,
            pendingDepositIds[vaultHash][user],
            pendingDepositRecords[vaultHash][user],
            pendingDepositIndex[vaultHash][user],
            vaults,
            vaultHash,
            user,
            amount
        );
    }

    function _addPendingWithdrawRequest(bytes32 vaultHash, address user, uint256 amount, bool isExitAll)
        internal
        returns (uint256 recordId)
    {
        return EnhancedVaultRecordsLib.addPendingWithdrawRequest(
            userFunds,
            pendingWithdrawRequestIds[vaultHash][user],
            pendingWithdrawRequestRecords[vaultHash][user],
            pendingWithdrawRequestIndex[vaultHash][user],
            pendingWithdrawIds[vaultHash][user],
            vaults,
            vaultHash,
            user,
            amount,
            isExitAll
        );
    }

    function _addPendingWithdraw(bytes32 vaultHash, address user, uint256 amount) internal returns (uint256 recordId) {
        return _addPendingWithdraw(vaultHash, user, amount, false);
    }

    function _addPendingWithdraw(bytes32 vaultHash, address user, uint256 amount, bool isExitAll)
        internal
        returns (uint256 recordId)
    {
        return EnhancedVaultRecordsLib.addPendingWithdraw(
            userFunds,
            pendingWithdrawIds[vaultHash][user],
            pendingWithdrawRecords[vaultHash][user],
            pendingWithdrawIndex[vaultHash][user],
            vaults,
            vaultHash,
            user,
            amount,
            isExitAll
        );
    }

    function _removePendingDeposit(bytes32 vaultHash, address user, uint256 recordId) internal {
        _removePendingRecord(
            pendingDepositIds[vaultHash][user],
            pendingDepositIndex[vaultHash][user],
            pendingDepositRecords[vaultHash][user],
            recordId
        );
    }

    function _removePendingWithdrawRequest(bytes32 vaultHash, address user, uint256 recordId) internal {
        _removePendingRecord(
            pendingWithdrawRequestIds[vaultHash][user],
            pendingWithdrawRequestIndex[vaultHash][user],
            pendingWithdrawRequestRecords[vaultHash][user],
            recordId
        );
    }

    function _removePendingWithdraw(bytes32 vaultHash, address user, uint256 recordId) internal {
        _removePendingRecord(
            pendingWithdrawIds[vaultHash][user],
            pendingWithdrawIndex[vaultHash][user],
            pendingWithdrawRecords[vaultHash][user],
            recordId
        );
    }

    function _removePendingRecord(
        uint256[] storage ids,
        mapping(uint256 => uint256) storage indexMap,
        mapping(uint256 => FundRecord) storage recordMap,
        uint256 recordId
    ) internal {
        EnhancedVaultRecordsLib.removePendingRecord(ids, indexMap, recordMap, recordId);
    }

    function _applyUserActiveDelta(bytes32 vaultHash, uint256 nextId, int256 delta) internal {
        CycleRecord storage nextRec = cycleRecords[vaultHash][nextId];
        if (delta > 0) {
            uint256 inc = uint256(delta);
            nextRec.totalActiveCollateral += inc;
            nextRec.remainingActiveCollateral += inc;
        } else if (delta < 0) {
            uint256 dec = uint256(-delta);
            nextRec.totalActiveCollateral -= dec;
            nextRec.remainingActiveCollateral -= dec;
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Cycle management (operator) — O(1)
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Settle the ended cycle and advance to the next one.
     *         Processes all queued users and starts next cycle in one transaction.
     *
     * @param vaultHash  Target vault
     */
    function nextCycle(bytes32 vaultHash) external nonReentrant onlyOperator vaultExists(vaultHash) {
        _requireActiveAndNotEnded(vaultHash);
        _settlePreviousCycle(vaultHash);
        uint256 queueLen = _transitionQueues[vaultHash].queueLenSnapshot;
        uint256 offset;
        while (offset < queueLen) {
            uint256 batch = queueLen - offset;
            if (batch > MAX_BATCH_SIZE) batch = MAX_BATCH_SIZE;
            _processQueuedUsers(vaultHash, offset, batch);
            unchecked {
                offset += batch;
            }
        }
        _startNextCycle(vaultHash);
    }

    function settlePreviousCycle(bytes32 vaultHash) external nonReentrant onlyOperator vaultExists(vaultHash) {
        _requireActive(vaultHash);
        _settlePreviousCycle(vaultHash);
    }

    function processQueuedUsers(bytes32 vaultHash, uint256 offset, uint256 limit)
        external
        nonReentrant
        onlyOperator
        vaultExists(vaultHash)
    {
        _requireActive(vaultHash);
        _processQueuedUsers(vaultHash, offset, limit);
    }

    function startNextCycle(bytes32 vaultHash) external nonReentrant onlyOperator vaultExists(vaultHash) {
        _requireActiveAndNotEnded(vaultHash);
        _startNextCycle(vaultHash);
    }

    /**
     * @notice Terminate the vault after the final cycle has been fully settled and queue
     *         processed. Transitions the phase to ENDED so users can call claimActive().
     *         Must only be called when isEnd=true and phase is PROCESSING_DONE.
     *
     * @param vaultHash  Target vault
     */
    function endVault(bytes32 vaultHash) external nonReentrant onlyOperator vaultExists(vaultHash) {
        _requireActive(vaultHash);
        VaultState storage st = vaults[vaultHash];
        if (!st.isEnd) revert VaultNotEnded();
        if (vaultPhases[vaultHash] != CyclePhase.PROCESSING_DONE) revert InvalidCyclePhase();

        TransitionQueue storage queue = _transitionQueues[vaultHash];
        if (queue.processedCount != queue.queueLenSnapshot) revert QueueProcessingIncomplete();

        // Apply cap reduction and finalize (mirrors _startNextCycle bookkeeping, but does not open a new cycle)
        CycleAdvanceState storage advance = _cycleAdvanceStates[vaultHash];
        if (advance.initialized) {
            _decreaseTotalDeposited(st, advance.capReduction);
            delete _cycleAdvanceStates[vaultHash];
        }

        queue.queueLenSnapshot = 0;
        queue.processedCount = 0;
        queue.queueCycleId = 0;
        vaultPhases[vaultHash] = CyclePhase.ENDED;
        emit VaultTerminated(vaultHash);
    }

    function systemPauseFunds(bytes32 vaultHash, address[] calldata users)
        external
        nonReentrant
        onlyOperator
        vaultExists(vaultHash)
    {
        _requireActive(vaultHash);
        if (vaultPhases[vaultHash] != CyclePhase.SETTLED) revert InvalidCyclePhase();
        uint256 len = users.length;
        if (len == 0 || len > MAX_BATCH_SIZE) revert InvalidBatchSize();

        CycleAdvanceState storage advance = _cycleAdvanceStates[vaultHash];
        if (!advance.initialized) revert InvalidCyclePhase();
        uint256 settledCycleId = advance.settledCycleId;
        VaultState storage st = vaults[vaultHash];
        uint256 cycleCumCollateral = cumCollateral[vaultHash][settledCycleId];
        uint256 cycleCumPremium = cumPremium[vaultHash][settledCycleId];

        for (uint256 i; i < len;) {
            address user = users[i];
            UserFund storage fund = userFunds[vaultHash][user];
            if (fund.activePrincipal == 0 && fund.pendingActivePrincipal == 0) {
                unchecked {
                    ++i;
                }
                continue;
            }
            uint256 settledActive = _projectSettledActive(fund, cycleCumCollateral);
            (uint256 previewStopAmount, uint256 candidatePrincipal) =
                _previewPrincipalCandidateAfterWithdrawConversion(fund, settledActive);
            if (!_isBelowMinPrincipalRatio(st, candidatePrincipal, fund.initialAmountTotal)) {
                revert UserNotBelowMinPrincipalRatio(user);
            }
            _materializeProjectedPremium(fund, cycleCumPremium);

            uint256 stopAmount = _convertWithdrawRequestRecordsToWithdraw(vaultHash, user, settledActive);
            if (stopAmount != previewStopAmount) revert WithdrawConversionPreviewMismatch();
            uint256 principalBeforeExit = settledActive + fund.pendingActivePrincipal + fund.systemPausedPrincipal;
            _reduceInitialAmountProRata(fund, stopAmount, principalBeforeExit);
            unchecked {
                fund.stoppedPrincipal += stopAmount;
            }
            fund.pendingWithdrawAmount = 0;

            uint256 pausedAmount = (settledActive - stopAmount) + fund.pendingActivePrincipal;
            _markPendingDepositRecordsConverted(vaultHash, user);

            unchecked {
                fund.systemPausedPrincipal += pausedAmount;
            }
            fund.activePrincipal = 0;
            fund.pendingActivePrincipal = 0;
            fund.entryCumCollateral = 0;
            fund.entryCumPremium = 0;

            _applyUserActiveDelta(vaultHash, advance.nextCycleId, -int256(settledActive));
            emit UserSystemPaused(vaultHash, user, pausedAmount);
            unchecked {
                ++i;
            }
        }
    }

    function _projectSettledActive(UserFund storage fund, uint256 cycleCumCollateral) internal view returns (uint256) {
        if (fund.activePrincipal == 0 || fund.entryCumCollateral == 0) return fund.activePrincipal;
        return fund.activePrincipal * cycleCumCollateral / fund.entryCumCollateral;
    }

    function _previewPrincipalCandidateAfterWithdrawConversion(UserFund storage fund, uint256 settledActive)
        internal
        view
        returns (uint256 stopAmount, uint256 candidatePrincipal)
    {
        stopAmount = fund.pendingWithdrawAmount > settledActive ? settledActive : fund.pendingWithdrawAmount;
        candidatePrincipal = settledActive - stopAmount + fund.pendingActivePrincipal + fund.systemPausedPrincipal;
    }

    function _projectPremium(UserFund storage fund, uint256 cycleCumPremium) internal view returns (uint256) {
        if (fund.activePrincipal == 0 || fund.entryCumCollateral == 0 || cycleCumPremium < fund.entryCumPremium) {
            return 0;
        }
        return fund.activePrincipal * (cycleCumPremium - fund.entryCumPremium) / fund.entryCumCollateral;
    }

    function _materializeProjectedPremium(UserFund storage fund, uint256 cycleCumPremium)
        internal
        returns (uint256 premium)
    {
        premium = _projectPremium(fund, cycleCumPremium);
        if (premium > 0) {
            unchecked {
                fund.materializedPremium += premium;
            }
        }
    }

    function _isBelowMinPrincipalRatio(VaultState storage st, uint256 principal, uint256 initialAmountTotal)
        internal
        view
        returns (bool)
    {
        if (initialAmountTotal == 0) return false;
        uint256 principalRatio = principal * RATIO_BASE / initialAmountTotal;
        return int256(principalRatio) < int256(st.params.minPrincipalRatio);
    }

    function _reduceInitialAmountProRata(UserFund storage fund, uint256 exitAmount, uint256 principalBeforeExit)
        internal
    {
        uint256 initialAmountTotal = fund.initialAmountTotal;
        if (exitAmount == 0 || initialAmountTotal == 0) return;
        if (principalBeforeExit == 0 || exitAmount >= principalBeforeExit) {
            fund.initialAmountTotal = 0;
            return;
        }
        uint256 basisReduction = Math.mulDiv(initialAmountTotal, exitAmount, principalBeforeExit);
        fund.initialAmountTotal = initialAmountTotal - basisReduction;
    }

    function _settlePreviousCycle(bytes32 vaultHash) internal {
        if (vaultPhases[vaultHash] != CyclePhase.OPEN) revert InvalidCyclePhase();
        VaultState storage st = vaults[vaultHash];
        if (block.timestamp < st.currentCycleStart + st.params.cycleDuration) revert CycleNotFinished();

        uint256 cycleId = st.currentCycleId;
        CycleSettlement memory settled = _settleCycleAndUpdateAccumulators(vaultHash, cycleId, st);
        uint256 nextId = cycleId + 1;

        uint256 capReduction =
            _advanceCycleState(vaultHash, cycleId, nextId, settled.activeCol, settled.netActiveCollateral);

        CycleAdvanceState storage advance = _cycleAdvanceStates[vaultHash];
        advance.settledCycleId = cycleId;
        advance.nextCycleId = nextId;
        advance.capReduction = capReduction;
        advance.totalReturned = settled.totalReturned;
        advance.totalPremium = settled.totalPremium;
        advance.initialized = true;

        CycleRecord storage settledRec = cycleRecords[vaultHash][cycleId];
        emit CycleSettled(
            vaultHash,
            cycleId,
            settledRec.totalActiveCollateral,
            settledRec.totalActiveCollateral > settledRec.remainingActiveCollateral
                ? settledRec.totalActiveCollateral - settledRec.remainingActiveCollateral
                : 0,
            settled.totalReturned,
            settled.totalPremium
        );

        TransitionQueue storage queue = _transitionQueues[vaultHash];
        queue.processedCount = 0;
        queue.queueCycleId = cycleId;
        vaultPhases[vaultHash] = queue.queueLenSnapshot == 0 ? CyclePhase.PROCESSING_DONE : CyclePhase.SETTLED;
    }

    function _startNextCycle(bytes32 vaultHash) internal {
        if (vaultPhases[vaultHash] != CyclePhase.PROCESSING_DONE) revert InvalidCyclePhase();
        TransitionQueue storage queue = _transitionQueues[vaultHash];
        if (queue.processedCount != queue.queueLenSnapshot) revert QueueProcessingIncomplete();

        CycleAdvanceState storage advance = _cycleAdvanceStates[vaultHash];
        if (!advance.initialized) revert InvalidCyclePhase();

        VaultState storage st = vaults[vaultHash];
        _decreaseTotalDeposited(st, advance.capReduction);
        st.currentCycleId = advance.nextCycleId;
        st.currentCycleStart = _alignedCycleStart(st.params.startTime, st.params.cycleDuration);

        emit CycleStarted(
            vaultHash,
            st.currentCycleId,
            cycleRecords[vaultHash][st.currentCycleId].totalActiveCollateral,
            st.currentCycleStart,
            st.currentCycleStart + st.params.cycleDuration
        );

        delete _cycleAdvanceStates[vaultHash];
        queue.queueLenSnapshot = 0;
        queue.processedCount = 0;

        vaultPhases[vaultHash] = CyclePhase.OPEN;
    }

    function _settleCycleAndUpdateAccumulators(bytes32 vaultHash, uint256 cycleId, VaultState storage st)
        internal
        returns (CycleSettlement memory settled)
    {
        return EnhancedVaultCycleLib.settleCycleAndUpdateAccumulators(
            enhancedOptions,
            _vaultIds,
            _cyclePremium,
            cycleRecords,
            cumCollateral,
            cumPremium,
            protocolFeeAccrued,
            vaultHash,
            cycleId,
            st
        );
    }

    function _alignedCycleStart(uint256 vaultStart, uint256 duration) internal view returns (uint256) {
        uint256 elapsed = block.timestamp - vaultStart;
        // slither-disable-next-line divide-before-multiply
        return vaultStart + (elapsed / duration) * duration;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Create order (operator)
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Open a new option position via EnhancedOptions.
     */
    function createOrder(bytes32 vaultHash, bytes calldata payload, bytes calldata vaultSig, bool useTrustedMaker)
        external
        nonReentrant
        onlyOperator
        vaultExists(vaultHash)
    {
        _requireActiveAndNotPaused(vaultHash);
        _requireOpenPhase(vaultHash);
        VaultState storage st = vaults[vaultHash];
        uint256 orderCollateral = _validateCreateOrder(st, vaultHash, payload, vaultSig);

        (uint256 vaultId, uint256 premium) = useTrustedMaker
            ? enhancedOptions.ingressoNewTrustedTakerAndMakerPosition(payload)
            : enhancedOptions.ingressoNewTrustedTakerPosition(payload);

        CycleRecord storage rec = cycleRecords[vaultHash][st.currentCycleId];
        if (orderCollateral > rec.remainingActiveCollateral) revert InsufficientRemainingActiveCollateral();
        rec.remainingActiveCollateral -= orderCollateral;

        _vaultIds[vaultHash][st.currentCycleId].push(vaultId);
        _cyclePremium[vaultHash] += premium;
        rec.totalPremium += premium;
        rec.premiumRatio = rec.totalActiveCollateral == 0 ? 0 : rec.totalPremium * PRECISION / rec.totalActiveCollateral;
        emit OrderCreated(vaultHash, vaultId);
    }

    function _validateCreateOrder(
        VaultState storage st,
        bytes32 vaultHash,
        bytes calldata payload,
        bytes calldata vaultSig
    ) internal view returns (uint256 orderCollateral) {
        bytes32 orderDigest = _hashTypedDataV4(
            keccak256(abi.encode(VAULT_ORDER_TYPEHASH, vaultHash, keccak256(payload)))
        );
        if (!SignatureChecker.isValidSignatureNow(vaultSigner, orderDigest, vaultSig)) {
            revert InvalidSignature();
        }

        return EnhancedVaultCycleLib.validateOrder(st.params, payload, st.currentCycleStart, address(this));
    }

    function _advanceCycleState(
        bytes32 vaultHash,
        uint256 cycleId,
        uint256 nextId,
        uint256 activeCol,
        uint256 netActiveCollateral
    ) internal returns (uint256 capReduction) {
        return EnhancedVaultCycleLib.advanceCycleState(
            cycleRecords, vaultHash, cycleId, nextId, activeCol, netActiveCollateral
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Views
    // ─────────────────────────────────────────────────────────────────────────

    function getVaultIds(bytes32 vaultHash, uint256 cycleId) external view returns (uint256[] memory) {
        return _vaultIds[vaultHash][cycleId];
    }

    function getQueueProgress(bytes32 vaultHash)
        external
        view
        returns (CyclePhase phase, uint256 queueLen, uint256 processedCount, uint256 remaining, bool canStartNextCycle)
    {
        TransitionQueue storage queue = _transitionQueues[vaultHash];
        phase = vaultPhases[vaultHash];
        queueLen = queue.queueLenSnapshot;
        processedCount = queue.processedCount;
        remaining = queueLen > processedCount ? queueLen - processedCount : 0;
        canStartNextCycle = phase == CyclePhase.PROCESSING_DONE && remaining == 0;
    }

    function getQueueUsers(bytes32 vaultHash, uint256 offset, uint256 limit) external view returns (address[] memory) {
        TransitionQueue storage queue = _transitionQueues[vaultHash];
        uint256 len = queue.queueLenSnapshot;
        if (offset >= len || limit == 0) return new address[](0);

        uint256 end = offset + limit;
        if (end > len) end = len;
        uint256 outLen = end - offset;
        address[] memory users = new address[](outLen);
        for (uint256 i; i < outLen;) {
            users[i] = queue.users[offset + i];
            unchecked {
                ++i;
            }
        }
        return users;
    }

    function getPendingDeposits(bytes32 vaultHash, address user) external view returns (FundRecord[] memory) {
        return EnhancedVaultRecordsLib.buildPendingRecords(
            pendingDepositIds[vaultHash][user], pendingDepositRecords[vaultHash][user]
        );
    }

    function getPendingWithdrawRequests(bytes32 vaultHash, address user) external view returns (FundRecord[] memory) {
        return EnhancedVaultRecordsLib.buildPendingRecords(
            pendingWithdrawRequestIds[vaultHash][user], pendingWithdrawRequestRecords[vaultHash][user]
        );
    }

    function getPendingWithdraws(bytes32 vaultHash, address user) external view returns (FundRecord[] memory) {
        return EnhancedVaultRecordsLib.buildPendingRecords(
            pendingWithdrawIds[vaultHash][user], pendingWithdrawRecords[vaultHash][user]
        );
    }

    /// @notice Returns the user's full position in a vault with all amounts scaled to their real values.
    ///         activeBalance is the proper withdraw upper bound.
    function getMyPosition(bytes32 vaultHash, address user) external view returns (UserPosition memory pos) {
        uint256 settledCycleId = _settledCycleId(vaultHash);
        UserFund storage fund = userFunds[vaultHash][user];

        uint256 cycleCumPremium = _premiumAccumulator(vaultHash);

        // Scaled active balance (collateralAsset)
        pos.activeBalance = _projectSettledActive(fund, cumCollateral[vaultHash][settledCycleId]);

        // Pending amounts (no scaling — not yet active)
        pos.pendingDeposit = fund.pendingActivePrincipal;
        pos.pendingWithdrawAmount = fund.pendingWithdrawAmount;
        if (pendingExitAllRequestId[vaultHash][user] != 0) pos.pendingWithdrawAmount = pos.activeBalance;

        // Already-claimable collateral amounts
        pos.claimableWithdraw = fund.stoppedPrincipal;
        pos.claimableSystemPaused = fund.systemPausedPrincipal;

        // Materialized premium already processed by queue (strikeAsset)
        pos.claimablePremium = fund.materializedPremium;

        // Projected premium = materialized + un-materialized since last queue processing
        pos.projectedPremium = pos.claimablePremium + _projectPremium(fund, cycleCumPremium);
    }

    function _premiumAccumulator(bytes32 vaultHash) internal view returns (uint256 cycleCumPremium) {
        uint256 settledCycleId = _settledCycleId(vaultHash);
        cycleCumPremium = cumPremium[vaultHash][settledCycleId];
        if (vaultPhases[vaultHash] != CyclePhase.OPEN) return cycleCumPremium;

        CycleRecord storage rec = cycleRecords[vaultHash][vaults[vaultHash].currentCycleId];
        if (rec.premiumRatio == 0) return cycleCumPremium;

        cycleCumPremium += rec.premiumRatio * cumCollateral[vaultHash][settledCycleId] / PRECISION;
    }

    function _settledCycleId(bytes32 vaultHash) internal view returns (uint256 settledCycleId) {
        settledCycleId = vaults[vaultHash].currentCycleId;
        if (vaultPhases[vaultHash] == CyclePhase.OPEN && settledCycleId > 0) {
            unchecked {
                --settledCycleId;
            }
        }
    }

    function _requireOpenPhase(bytes32 vaultHash) internal view {
        if (vaultPhases[vaultHash] != CyclePhase.OPEN) revert CycleProcessingLocked();
    }

    function _decreaseTotalDeposited(VaultState storage st, uint256 amount) internal {
        st.totalDeposited = st.totalDeposited >= amount ? st.totalDeposited - amount : 0;
    }

    function _releaseCollateral(VaultState storage st, address to, uint256 amount) internal {
        _decreaseTotalDeposited(st, amount);
        _transferAsset(st.params.collateralAsset, to, amount);
    }

    function _transferAsset(address asset, address to, uint256 amount) internal {
        IERC20(asset).safeTransfer(to, amount);
    }

    function _requireNoExitAllPending(bytes32 vaultHash, address user) internal view {
        if (pendingExitAllRequestId[vaultHash][user] != 0) revert();
    }

    function _requireActive(bytes32 vaultHash) internal view {
        if (!vaults[vaultHash].isActive) revert VaultNotActive();
    }

    function _requireActiveAndNotEnded(bytes32 vaultHash) internal view {
        VaultState storage st = vaults[vaultHash];
        if (!st.isActive) revert VaultNotActive();
        if (st.isEnd) revert VaultEnded();
    }

    function _requireActiveAndNotPaused(bytes32 vaultHash) internal view {
        VaultState storage st = vaults[vaultHash];
        if (!st.isActive) revert VaultNotActive();
        if (st.isPaused) revert VaultPaused();
    }

    function _requireUserWritable(bytes32 vaultHash) internal view {
        VaultState storage st = vaults[vaultHash];
        if (!st.isActive) revert VaultNotActive();
        if (st.isPaused) revert VaultPaused();
        if (st.isEnd) revert VaultEnded();
    }

    function _enqueueUser(bytes32 vaultHash, address user) internal {
        if (queued[vaultHash][user]) return;
        queued[vaultHash][user] = true;

        TransitionQueue storage queue = _transitionQueues[vaultHash];
        uint256 index = queue.queueLenSnapshot;
        if (index < queue.users.length) {
            queue.users[index] = user;
        } else {
            queue.users.push(user);
        }
        unchecked {
            queue.queueLenSnapshot = index + 1;
        }
        // emit UserQueued(vaultHash, user);
    }
}

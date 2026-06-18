/**
 * SPDX-License-Identifier: MIT
 */
pragma solidity ^0.8.28;

import {MMarket} from "./MMarket.sol";
import {Parser} from "./libs/Parser.sol";
import {Actions} from "./libs/Actions.sol";
import {MMarketOperations} from "./libs/MMarketOperations.sol";
import {MarginVault} from "./libs/MarginVault.sol";
// import {IOtoken} from "./interfaces/IOtoken.sol";
// import {IAavePool} from "./interfaces/IAavePool.sol";
// import {ISwapRouter} from "./interfaces/ISwapRouter.sol";
import {IController} from "./interfaces/IController.sol";
import {IOtokenFactory} from "./interfaces/IOtokenFactory.sol";
import {MarginCalculatorInterface} from "./interfaces/MarginCalculatorInterface.sol";
import {OtokenInterface} from "./interfaces/OtokenInterface.sol";

import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "lib/solmate/src/utils/SafeTransferLib.sol";
import {SignatureChecker} from "lib/openzeppelin-contracts/contracts/utils/cryptography/SignatureChecker.sol";
import {OwnableUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {ReentrancyGuard} from "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {
    EIP712Upgradeable
} from "lib/openzeppelin-contracts-upgradeable/contracts/utils/cryptography/EIP712Upgradeable.sol";
import {UUPSUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title Enhanced - this contract is the operator on both mmarket and Gamma
 * @dev assumed no funds are stored on this contract
 */
contract EnhancedOptions is EIP712Upgradeable, OwnableUpgradeable, ReentrancyGuard, UUPSUpgradeable {
    /// @dev operator
    address public operator;
    /// @dev mmarket
    MMarket public mmarket;
    /// @dev controller
    IController public controller;
    /// @dev otokenfactory
    IOtokenFactory public factory;
    /// @dev Hyperlend Pool contract - used for Flash Loans
    address public flashLoanPool;
    /// @dev Hyperswap router
    address public swapRouter;
    /// @dev Margin pool contract
    address public marginPool;
    /// @dev Fee recipient
    address public feeRecipient;
    /// @dev Trusted enhanced signer for offchain quotes
    address public enhancedSigner;
    /// @dev Period during ControllerLogic.redeemTimePeriod after which ITM options can be flash loan redeemed.
    ///      If equal to or greater than redeemTimePeriod, there is no flash loan redeem period.
    ///      If set to zero then the whole redeemTimePeriod allows flash loan redemptions.
    uint256 flashLoanRedeemPeriodStart;
    /// @dev mapping to track used digests to prevent replay attacks
    mapping(bytes32 => bool) internal isDigestUsed;
    /// @dev addresses authorized to call ingressoNewTrustedTakerPosition and ingressoSettle without confirmation sig
    mapping(address => bool) public trustedTakers;
    /// @dev addresses authorized to call ingressoNewTrustedMakerPosition and ingressoSettle without quote sig
    mapping(address => bool) public trustedMakers;
    /// @dev maker => receiver: if set, ingressoRedeem uses receiver as the redemption payee instead of maker
    mapping(address => address) public makerWhitelist;
    /// @dev owner => vaultId => custody release accounting
    mapping(address => mapping(uint256 => CustodyRelease)) public vaultCustodyReleases;
    /// @dev owner => vault ids with outstanding custody releases, used to guard maker redemption while outstanding
    mapping(address => uint256[]) internal vaultsWithOutstandingRelease;
    /// @dev owner => vaultId => whether vaultsWithOutstandingRelease already contains the vault id
    mapping(address => mapping(uint256 => bool)) internal isVaultReleaseTracked;
    /// @dev maker => custodian => max custody release as basis points of each vault's deposited asset amount.
    ///      A non-zero entry both authorizes the (maker, custodian) pair and sets its custody limit;
    ///      bps == 0 means the custodian is not authorized to receive releases from this maker.
    mapping(address => mapping(address => uint256)) public makerCustodyLimitBps;
    /// @dev owner => vaultId => maker that bought the short otokens minted from this vault.
    ///      Appended after existing storage for upgrade safety.
    mapping(address => mapping(uint256 => address)) public vaultMakers;

    /// @notice emits an event when there is a change in operator
    event OperatorChanged(address newOperator, address oldOperator);
    /// @notice emits when a trusted taker is added/removed
    event TrustedTakerSet(address indexed taker, bool trusted);
    /// @notice emits when a trusted maker is added/removed
    event TrustedMakerSet(address indexed maker, bool trusted);
    /// @notice emits when a maker's whitelisted receiver is set or removed
    event MakerWhitelistSet(address indexed maker, address indexed receiver);
    /// @notice emits when a (maker, custodian) custody limit is set or cleared
    event MakerCustodyLimitBpsSet(address indexed maker, address indexed custodian, uint256 bps);
    /// @notice emits when vault collateral is released to a custodian
    event CollateralReleasedToCustody(
        address indexed owner,
        uint256 indexed vaultId,
        address indexed asset,
        address custodian,
        uint256 amount,
        uint256 outstandingAmount
    );
    /// @notice emits when collateral is returned from custody
    event CollateralReturnedFromCustody(
        address indexed owner,
        uint256 indexed vaultId,
        address indexed asset,
        address payer,
        uint256 amount,
        uint256 outstandingAmount
    );
    /// @notice emits when operator donates assets from this contract into Gamma margin pool
    event Donated(address indexed asset, uint256 amount);

    error ZeroAddress();
    error ZeroMaker();
    error ZeroReceiver();
    error ZeroAsset();
    error ZeroAmount();
    error ZeroOwner();
    error BadOperator();
    error Unauthorized();
    error CustodyLimitTooHigh();
    error SystemFullyPaused();
    error CustodianNotAuthorized();
    error CustodyAuthorizationExpired();
    error EmptyCustodyReleaseRequests();
    error InvalidCustodyReleaseSignature();
    error CustodianMismatch();
    error CustodyReleaseAssetMismatch();
    error EmptyReturnRequests();
    error ArrayLengthMismatch();
    error ReturnExceedsOutstanding();
    error InvalidQuoteSignature();
    error InvalidConfirmationSignature();
    error TakerMustBeCaller();
    error InvalidTransferSignature();
    error InvalidTransferIsDeposit();
    error NotSupported();
    error OutstandingCustodyRelease();
    error QuantityExceedsQuote();
    error CannotReleaseFromExpiredVault();
    error ExceedsVaultDeposit();
    error ExceedsMakerCustodyLimit();
    error MakerNotVaultMaker();
    error SignatureAlreadyUsed();
    error InvalidOperationsArray();
    error InvalidActionsArray();
    error MmarketWithdrawnAssetIsNotRedeemedOtoken();
    error RedeemReceiverInvalid();
    error RedeemAmountMustBeWithdrawAmount();
    error InvalidWithdrawRecipient();
    error SettleReceiverMustBeVaultOwner();

    address internal constant ZERO_ADDRESS = address(0x0);
    uint256 internal constant MAX_CUSTODY_LIMIT_BPS = 10_000;

    string internal constant QUOTE_TYPE =
        "Quote(address assetAddress,uint256 chainId,bool isPut,bool isPhysicallySettled,uint256 strike,uint64 expiry,address maker,uint64 nonce,uint256 price,uint256 quantity,bool isTakerBuy,uint64 validUntil,address usd,address collateralAsset)";

    string internal constant CONFIRMATION_TYPE =
        "Confirmation(address maker,address assetAddress,uint256 chainId,uint64 expiry,bool isPut,bool isPhysicallySettled,uint64 nonce,uint256 price,uint256 quantity,uint64 quoteNonce,bytes quoteSignature,uint256 strike,address taker,bool isTakerBuy,address usd,address collateralAsset,uint256 collateralAmount)";

    string internal constant TRANSFER_TYPE =
        "Transfer(address user,address asset,uint256 chainId,uint256 amount,bool isDeposit,uint64 nonce)";

    string public constant OTC_TRADE_TYPE =
        "OtcTrade(uint256 chainId,address user1,address user2,address asset1,address asset2,uint256 amount1,uint256 amount2,uint64 nonce)";

    string internal constant CUSTODY_RELEASE_TYPE =
        "CustodyRelease(address maker,address receiver,uint256 chainId,uint64 nonce,uint64 validUntil,bytes32 requestsHash)";

    string internal constant CUSTODY_RELEASE_REQUEST_TYPE =
        "CustodyReleaseRequest(address owner,uint256 vaultId,address asset,uint256 amount)";

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() external initializer {
        __EIP712_init("enhanced", "0.0.0");
        __Ownable_init_unchained(msg.sender);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function setOperator(address _operator) external {
        _checkOwner();
        if (_operator == ZERO_ADDRESS) revert ZeroAddress();
        emit OperatorChanged(_operator, operator);
        operator = _operator;
    }

    function setController(address _controller) external {
        _checkOwner();
        if (_controller == ZERO_ADDRESS) revert ZeroAddress();
        controller = IController(_controller);
    }

    function setMMarket(address _mmarket) external {
        _checkOwner();
        if (_mmarket == ZERO_ADDRESS) revert ZeroAddress();
        mmarket = MMarket(_mmarket);
    }

    function setFactory(address _factory) external {
        _checkOwner();
        if (_factory == ZERO_ADDRESS) revert ZeroAddress();
        factory = IOtokenFactory(_factory);
    }

    function setFlashLoanPool(address _flashLoanPool) external {
        _checkOwner();
        if (_flashLoanPool == ZERO_ADDRESS) revert ZeroAddress();
        flashLoanPool = _flashLoanPool;
    }

    function setSwapRouter(address _swapRouter) external {
        _checkOwner();
        if (_swapRouter == ZERO_ADDRESS) revert ZeroAddress();
        swapRouter = _swapRouter;
    }

    function setMarginPool(address _marginPool) external {
        _checkOwner();
        if (_marginPool == ZERO_ADDRESS) revert ZeroAddress();
        marginPool = _marginPool;
    }

    function setFeeRecipient(address _feeRecipient) external {
        _checkOwner();
        if (_feeRecipient == ZERO_ADDRESS) revert ZeroAddress();
        feeRecipient = _feeRecipient;
    }

    function setEnhancedSigner(address _enhancedSigner) external {
        _checkOwner();
        if (_enhancedSigner == ZERO_ADDRESS) revert ZeroAddress();
        enhancedSigner = _enhancedSigner;
    }

    function setFlashLoanRedeemPeriodStart(uint256 _flashLoanRedeemPeriodStart) external {
        _checkOwner();
        flashLoanRedeemPeriodStart = _flashLoanRedeemPeriodStart;
    }

    function setTrustedTaker(address _taker, bool _trusted) external {
        _checkOwner();
        trustedTakers[_taker] = _trusted;
        emit TrustedTakerSet(_taker, _trusted);
    }

    function setTrustedMaker(address _maker, bool _trusted) external {
        _checkOwner();
        trustedMakers[_maker] = _trusted;
        emit TrustedMakerSet(_maker, _trusted);
    }

    /// @notice Set or remove a maker's whitelisted receiver for redemption.
    ///         Pass receiver = address(0) to remove the entry.
    function setMakerWhitelist(address _maker, address _receiver) external {
        _checkOwner();
        if (_maker == ZERO_ADDRESS) revert ZeroMaker();
        makerWhitelist[_maker] = _receiver;
        emit MakerWhitelistSet(_maker, _receiver);
    }

    /// @notice Authorize a (maker, receiver) pair for vault collateral borrowing and set its
    ///         credit limit as basis points of each vault's deposited asset amount.
    ///         Example: 7000 allows borrowing up to 70% of the matching asset deposited in the vault.
    ///         Pass _bps = 0 to remove the authorization.
    function setMakerCustodyLimitBps(address _maker, address _receiver, uint256 _bps) external {
        _checkOwner();
        if (_maker == ZERO_ADDRESS) revert ZeroMaker();
        if (_receiver == ZERO_ADDRESS) revert ZeroReceiver();
        if (_bps > MAX_CUSTODY_LIMIT_BPS) revert CustodyLimitTooHigh();
        makerCustodyLimitBps[_maker][_receiver] = _bps;
        emit MakerCustodyLimitBpsSet(_maker, _receiver, _bps);
    }

    /// @notice sets approval for the margin pool to remove funds for an asset
    function setAssetApproval(address _asset, bool _approval) external {
        _checkOwner();
        if (_approval) {
            _forceApprove(_asset, address(marginPool), type(uint256).max);
        } else {
            _forceApprove(_asset, address(marginPool), 0);
        }
    }

    function _forceApprove(address _asset, address _spender, uint256 _amount) internal {
        ERC20 token = ERC20(_asset);
        uint256 allowance = token.allowance(address(this), _spender);
        if (allowance != 0) {
            SafeTransferLib.safeApprove(token, _spender, 0);
        }
        if (_amount != 0) {
            SafeTransferLib.safeApprove(token, _spender, _amount);
        }
    }

    function _checkOperator() internal view {
        if (operator != _msgSender()) revert BadOperator();
    }

    function _checkOperatorOrTrustedTaker() internal view {
        if (operator != _msgSender() && !trustedTakers[_msgSender()]) revert Unauthorized();
    }

    function _checkTrustedMaker(address maker) internal view {
        if (!trustedMakers[maker]) revert Unauthorized();
    }

    struct Otoken {
        address collateral;
        address underlying;
        address strikeAsset;
        uint256 strike;
        uint256 expiration;
        bool isPut;
        bool isPhysicallySettled;
        address vaultOwner;
    }

    struct CustodyReleaseRequest {
        address owner;
        uint256 vaultId;
        address asset;
        uint256 amount;
    }

    struct CustodyRelease {
        address custodian;
        address asset;
        uint256 releasedAmount;
        uint256 outstandingAmount;
    }

    function ingressoRedeem(MMarketOperations.Operation[] memory operations, Actions.ActionArgs[] memory actions)
        external
        nonReentrant
    {
        _checkOperator();
        _doRedeem(operations, actions);
    }

    function _doRedeem(MMarketOperations.Operation[] memory operations, Actions.ActionArgs[] memory actions) internal {
        if (!(operations.length == 1 && operations[0].operationType == MMarketOperations.OperationType.Withdraw)) {
            revert InvalidOperationsArray();
        }
        if (!(actions.length == 1 && actions[0].actionType == Actions.ActionType.Redeem)) revert InvalidActionsArray();
        if (operations[0].asset1 != actions[0].asset) revert MmarketWithdrawnAssetIsNotRedeemedOtoken();
        address whitelistedReceiver = makerWhitelist[operations[0].user1];
        address expectedReceiver = whitelistedReceiver != ZERO_ADDRESS ? whitelistedReceiver : operations[0].user1;
        if (actions[0].secondAddress != expectedReceiver) revert RedeemReceiverInvalid();
        if (operations[0].amount1 != actions[0].amount) revert RedeemAmountMustBeWithdrawAmount();
        if (operations[0].user2 != address(this)) revert InvalidWithdrawRecipient();
        _revertIfOutstandingCustody(operations[0].user1);
        mmarket.operate(operations);
        controller.operate(actions);
    }

    function ingressoSettle(Actions.ActionArgs[] memory actions) external nonReentrant {
        _checkOperatorOrTrustedTaker();
        uint256 len = actions.length;
        for (uint256 i = 0; i < len; i++) {
            if (actions[i].actionType != Actions.ActionType.SettleVault) revert InvalidActionsArray();
            if (actions[i].secondAddress != actions[i].owner) revert SettleReceiverMustBeVaultOwner();
            _revertIfOutstandingCustody(actions[i].owner);
        }
        controller.operate(actions);
    }

    function ingressoReleaseCollateralToCustody(
        address maker,
        address receiver,
        uint64 nonce,
        uint64 validUntil,
        CustodyReleaseRequest[] calldata requests,
        bytes calldata signature
    ) external nonReentrant {
        _checkOperator();
        if (controller.systemFullyPaused()) revert SystemFullyPaused();
        if (maker == ZERO_ADDRESS) revert ZeroMaker();
        if (receiver == ZERO_ADDRESS) revert ZeroReceiver();
        uint256 bps = makerCustodyLimitBps[maker][receiver];
        if (bps == 0) revert CustodianNotAuthorized();
        if (block.timestamp > validUntil) revert CustodyAuthorizationExpired();
        if (requests.length == 0) revert EmptyCustodyReleaseRequests();

        bytes32 digest = _getCustodyReleaseDigest(maker, receiver, nonce, validUntil, requests);
        _consumeDigest(digest);
        if (!SignatureChecker.isValidSignatureNow(maker, digest, signature)) {
            revert InvalidCustodyReleaseSignature();
        }

        for (uint256 i = 0; i < requests.length; i++) {
            CustodyReleaseRequest calldata request = requests[i];
            if (request.owner == ZERO_ADDRESS) revert ZeroOwner();
            if (request.asset == ZERO_ADDRESS) revert ZeroAsset();
            if (request.amount == 0) revert ZeroAmount();

            CustodyRelease storage release = vaultCustodyReleases[request.owner][request.vaultId];
            if (release.releasedAmount != 0) {
                if (release.custodian != receiver) revert CustodianMismatch();
                if (release.asset != request.asset) revert CustodyReleaseAssetMismatch();
            } else {
                release.custodian = receiver;
                release.asset = request.asset;
            }

            uint256 newOutstandingAmount = release.outstandingAmount + request.amount;
            _validateCustodyLimit(maker, request.owner, request.vaultId, request.asset, newOutstandingAmount, bps);

            release.releasedAmount += request.amount;
            release.outstandingAmount = newOutstandingAmount;
            if (!isVaultReleaseTracked[request.owner][request.vaultId]) {
                isVaultReleaseTracked[request.owner][request.vaultId] = true;
                vaultsWithOutstandingRelease[request.owner].push(request.vaultId);
            }

            controller.releaseVaultCollateralToCustody(request.asset, receiver, request.amount);

            emit CollateralReleasedToCustody(
                request.owner, request.vaultId, request.asset, receiver, request.amount, release.outstandingAmount
            );
        }
    }

    function ingressoReturnFromCustody(address owner, uint256[] calldata vaultIds, uint256[] calldata amounts)
        external
        nonReentrant
    {
        if (owner == ZERO_ADDRESS) revert ZeroOwner();
        if (vaultIds.length != amounts.length) revert ArrayLengthMismatch();
        if (vaultIds.length == 0) revert EmptyReturnRequests();

        for (uint256 i = 0; i < vaultIds.length; i++) {
            uint256 amount = amounts[i];
            if (amount == 0) revert ZeroAmount();

            CustodyRelease storage release = vaultCustodyReleases[owner][vaultIds[i]];

            if (amount > release.outstandingAmount) {
                amount = release.outstandingAmount;
            }

            release.outstandingAmount -= amount;
            SafeTransferLib.safeTransferFrom(ERC20(release.asset), msg.sender, address(this), amount);
            if (ERC20(release.asset).allowance(address(this), marginPool) < amount) {
                _forceApprove(release.asset, marginPool, type(uint256).max);
            }
            controller.donate(release.asset, amount);
            if (release.outstandingAmount == 0) {
                _removeTrackedRelease(owner, vaultIds[i]);
            }

            emit CollateralReturnedFromCustody(
                owner, vaultIds[i], release.asset, msg.sender, amount, release.outstandingAmount
            );
        }
    }

    function ingressoNewUserPosition(bytes calldata payload) external nonReentrant {
        _checkOperator();
        _doNewUserPosition(payload);
    }

    function _doNewUserPosition(bytes calldata payload) internal {
        (
            Parser.Quote memory mmQuote,
            Parser.Confirmation memory sellerConfirmation,
            bytes memory quoteSig,
            bytes memory confSig,
            uint256 fee
        ) = Parser.parseQuoteAndConfirmation(payload);

        bytes32 quoteDigest = getQuoteDigest(mmQuote);
        bytes32 confDigest = getConfirmationDigest(sellerConfirmation);

        _consumeDigest(quoteDigest);
        _consumeDigest(confDigest);
        if (!SignatureChecker.isValidSignatureNow(mmQuote.maker, quoteDigest, quoteSig)) {
            revert InvalidQuoteSignature();
        }
        if (!SignatureChecker.isValidSignatureNow(sellerConfirmation.taker, confDigest, confSig)) {
            revert InvalidConfirmationSignature();
        }
        _validateQuoteQuantity(mmQuote, sellerConfirmation);

        _executeNewPosition(sellerConfirmation, fee);
    }

    /**
     * @notice Same as ingressoNewUserPosition but skips confirmation signature verification.
     *         Callable by operator or any address in the trustedTakers whitelist (e.g. strategy contracts).
     *         Authorized callers are trusted to have validated the order parameters off-chain.
     */
    function ingressoNewTrustedTakerPosition(bytes calldata payload)
        external
        nonReentrant
        returns (uint256 vaultId, uint256 totalPremium)
    {
        _checkOperatorOrTrustedTaker();

        (
            Parser.Quote memory mmQuote,
            Parser.Confirmation memory sellerConfirmation,
            bytes memory quoteSig,,
            uint256 fee
        ) = Parser.parseQuoteAndConfirmation(payload);

        bytes32 quoteDigest = getQuoteDigest(mmQuote);
        _consumeDigest(quoteDigest);
        if (!SignatureChecker.isValidSignatureNow(mmQuote.maker, quoteDigest, quoteSig)) {
            revert InvalidQuoteSignature();
        }
        require(sellerConfirmation.taker == msg.sender, TakerMustBeCaller());
        _validateQuoteQuantity(mmQuote, sellerConfirmation);

        (vaultId, totalPremium) = _executeNewPosition(sellerConfirmation, fee);
    }

    /**
     * @notice Same as ingressoNewUserPosition but skips quote signature verification.
     *         Callable by operator.
     *         Authorized callers are trusted to have validated the order parameters off-chain.
     */
    function ingressoNewTrustedMakerPosition(bytes calldata payload)
        external
        nonReentrant
        returns (uint256 vaultId, uint256 totalPremium)
    {
        _checkOperator();
        (vaultId, totalPremium) = _doNewTrustedMakerPosition(payload);
    }

    /**
     * @notice Same as ingressoNewUserPosition but skips quote signature verification.
     *         Callable by operator.
     *         Authorized callers are trusted to have validated the order parameters off-chain.
     */
    function _doNewTrustedMakerPosition(bytes calldata payload)
        internal
        returns (uint256 vaultId, uint256 totalPremium)
    {
        (
            Parser.Quote memory mmQuote,
            Parser.Confirmation memory sellerConfirmation,,
            bytes memory confSig,
            uint256 fee
        ) = Parser.parseQuoteAndConfirmation(payload);
        _checkTrustedMaker(mmQuote.maker);

        bytes32 confDigest = getConfirmationDigest(sellerConfirmation);

        _consumeDigest(confDigest);
        if (!SignatureChecker.isValidSignatureNow(sellerConfirmation.taker, confDigest, confSig)) {
            revert InvalidConfirmationSignature();
        }

        (vaultId, totalPremium) = _executeNewPosition(sellerConfirmation, fee);
    }

    /**
     * @notice Same as ingressoNewUserPosition but skips both quote and confirmation signature verification.
     *         Callable by operator or trusted taker. Maker must be trusted and taker must be caller.
     */
    function ingressoNewTrustedTakerAndMakerPosition(bytes calldata payload)
        external
        nonReentrant
        returns (uint256 vaultId, uint256 totalPremium)
    {
        _checkOperatorOrTrustedTaker();

        (Parser.Quote memory mmQuote, Parser.Confirmation memory sellerConfirmation,,, uint256 fee) =
            Parser.parseQuoteAndConfirmation(payload);
        _checkTrustedMaker(mmQuote.maker);

        bytes32 quoteDigest = getQuoteDigest(mmQuote);
        bytes32 confDigest = getConfirmationDigest(sellerConfirmation);

        _consumeDigest(quoteDigest);
        _consumeDigest(confDigest);
        require(sellerConfirmation.taker == msg.sender, TakerMustBeCaller());
        _validateQuoteQuantity(mmQuote, sellerConfirmation);

        (vaultId, totalPremium) = _executeNewPosition(sellerConfirmation, fee);
    }

    /**
     * @notice Build and execute a new option position.
     *         Steps:
     *         1. Actions.OpenVault
     *         2. Actions.DepositCollateral
     *         3. Actions.MintShortOption
     *         4. Operations.Deposit  (increment seller's otoken balance on mmarket)
     *         5. Operations.ConductTrade
     *         6. Operations.Withdraw (withdraw premium to seller's wallet)
     *         7. CONDITIONAL Operations.Withdraw (fee payment)
     */
    function _executeNewPosition(Parser.Confirmation memory sellerConfirmation, uint256 fee)
        internal
        returns (uint256 vaultId, uint256 totalPremium)
    {
        vaultId = controller.getAccountVaultCounter(sellerConfirmation.taker) + 1;
        totalPremium = sellerConfirmation.quantity * sellerConfirmation.price
            * (10 ** ERC20(sellerConfirmation.usd).decimals()) / 1e36;

        Actions.ActionArgs[] memory actions = new Actions.ActionArgs[](3);
        MMarketOperations.Operation[] memory operations;
        if (fee == 0) {
            operations = new MMarketOperations.Operation[](3);
        } else {
            operations = new MMarketOperations.Operation[](4);
        }
        address otokenAddress = getOrDeployOtoken(
            Otoken({
                collateral: sellerConfirmation.collateralAsset,
                underlying: sellerConfirmation.assetAddress,
                strikeAsset: sellerConfirmation.usd,
                strike: sellerConfirmation.strike,
                expiration: sellerConfirmation.expiry,
                isPut: sellerConfirmation.isPut,
                isPhysicallySettled: sellerConfirmation.isPhysicallySettled,
                vaultOwner: sellerConfirmation.taker
            })
        );

        actions[0] = Actions.ActionArgs(
            Actions.ActionType.OpenVault,
            sellerConfirmation.taker, // vault owner
            ZERO_ADDRESS, // secondAddress
            ZERO_ADDRESS, // asset
            vaultId, // vault ID
            0, // asset amount
            0, // index
            abi.encode(sellerConfirmation.isPhysicallySettled ? 2 : 0) // data bytes (vault type)
        );

        actions[1] = Actions.ActionArgs(
            Actions.ActionType.DepositCollateral,
            sellerConfirmation.taker, // vault owner
            sellerConfirmation.taker, // secondAddress
            sellerConfirmation.collateralAsset, // asset
            vaultId, // vault ID
            sellerConfirmation.collateralAmount, // asset amount
            0, // index (not used)
            bytes("") // data bytes (not used)
        );

        actions[2] = Actions.ActionArgs(
            Actions.ActionType.MintShortOption,
            sellerConfirmation.taker, // vault owner
            address(this), // secondAddress to send otoken to
            otokenAddress, // otoken to mint
            vaultId, // vault ID
            sellerConfirmation.quantity / 1e10, // asset amount in e8
            0, // index (not used)
            bytes("") // data bytes (not used)
        );

        operations[0] = MMarketOperations.Operation(
            MMarketOperations.OperationType.Deposit,
            sellerConfirmation.taker, // increment this user's balance
            address(this), // take from enhanced (otoken already held here)
            otokenAddress,
            ZERO_ADDRESS, // asset 2
            sellerConfirmation.quantity / 1e10, // quantity in e8
            0,
            bytes("")
        );

        operations[1] = MMarketOperations.Operation(
            MMarketOperations.OperationType.ConductTrade,
            sellerConfirmation.maker, // sell otoken to this address
            sellerConfirmation.taker, // this user receives premium
            sellerConfirmation.usd, // asset 1
            otokenAddress, // asset 2
            totalPremium, // amount of premium
            sellerConfirmation.quantity / 1e10, // quantity in e8
            bytes("")
        );

        operations[2] = MMarketOperations.Operation(
            MMarketOperations.OperationType.Withdraw,
            sellerConfirmation.taker, // decrement balance from this address
            sellerConfirmation.taker, // withdraw premium to this address
            sellerConfirmation.usd, // asset 1
            ZERO_ADDRESS, // asset 2 (not used)
            totalPremium,
            0,
            bytes("")
        );

        if (fee > 0) {
            // apply fee
            operations[3] = MMarketOperations.Operation(
                MMarketOperations.OperationType.Withdraw,
                sellerConfirmation.maker, // user 1
                feeRecipient, // user 2
                sellerConfirmation.usd, // asset 1
                ZERO_ADDRESS, // asset 2
                fee, // amount 1
                0, // amount 2
                bytes("")
            );
        }

        controller.operate(actions);
        mmarket.operate(operations);
    }

    function ingressoTransferAsset(bytes calldata payload) external nonReentrant {
        _checkOperator();
        _doTransferAsset(payload);
    }

    function _doTransferAsset(bytes calldata payload) internal {
        (Parser.Transfer memory transfer, bytes memory sig) = Parser.parseTransfer(payload);

        bytes32 digest = getTransferDigest(transfer);

        _consumeDigest(digest);
        if (!SignatureChecker.isValidSignatureNow(transfer.user, digest, sig)) {
            revert InvalidTransferSignature();
        }

        MMarketOperations.Operation[] memory operations = new MMarketOperations.Operation[](1);

        operations[0] = MMarketOperations.Operation(
            transfer.isDeposit ? MMarketOperations.OperationType.Deposit : MMarketOperations.OperationType.Withdraw,
            transfer.user, // user 1
            transfer.user, // user 2
            transfer.asset, // asset 1
            ZERO_ADDRESS, // asset 2 not used
            transfer.amount, // amount 1 in asset decimals
            0, // amount 2 not used
            bytes("")
        );

        mmarket.operate(operations);
    }

    function ingressoMMarketDeposit(bytes calldata payload) external nonReentrant {
        _checkOperator();
        _doDepositTransferAsset(payload);
    }

    function _doDepositTransferAsset(bytes calldata payload) internal {
        (Parser.Transfer memory transfer, bytes memory sig) = Parser.parseTransfer(payload);

        if (!transfer.isDeposit) {
            revert InvalidTransferIsDeposit();
        }
        bytes32 digest = getTransferDigest(transfer);

        _consumeDigest(digest);
        address effectivePayer = transfer.payer != address(0) ? transfer.payer : transfer.user;
        if (!SignatureChecker.isValidSignatureNow(effectivePayer, digest, sig)) {
            revert InvalidTransferSignature();
        }

        MMarketOperations.Operation[] memory operations = new MMarketOperations.Operation[](1);

        operations[0] = MMarketOperations.Operation(
            MMarketOperations.OperationType.Deposit,
            transfer.user, // user 1
            effectivePayer, // user 2 (payer, falls back to user when payer is zero address)
            transfer.asset, // asset 1
            ZERO_ADDRESS, // asset 2 not used
            transfer.amount, // amount 1 in asset decimals
            0, // amount 2 not used
            bytes("")
        );

        mmarket.operate(operations);
    }

    /**
     * @notice Composite: transfer asset into mmarket then open a new user position.
     *         Atomically executes ingressoTransferAsset + ingressoNewUserPosition in one tx.
     * @param transferPayload Signed Transfer payload (must be isDeposit=true).
     * @param orderPayload    Signed Quote+Confirmation payload for the new position.
     */
    function ingressoDepositAndOpen(bytes calldata transferPayload, bytes calldata orderPayload) external nonReentrant {
        _checkOperator();
        _doDepositTransferAsset(transferPayload);
        _doNewUserPosition(orderPayload);
    }

    /**
     * @notice Composite: transfer asset into mmarket then open a new user position.
     *         Atomically executes ingressoTransferAsset + ingressoNewUserPosition in one tx.
     * @param transferPayload Signed Transfer payload (must be isDeposit=true).
     * @param orderPayload    Signed Quote+Confirmation payload for the new position.
     */
    function ingressoTrustedMakerDepositAndOpen(bytes calldata transferPayload, bytes calldata orderPayload)
        external
        nonReentrant
    {
        _checkOperator();
        _doDepositTransferAsset(transferPayload);
        _doNewTrustedMakerPosition(orderPayload);
    }

    function ingressoOTCTrade(bytes calldata payload) external {
        revert NotSupported();
    }

    // function ingressoOTCTrade(bytes calldata payload) external nonReentrant {
    //     _checkOperator();
    //     (Parser.OTCTrade memory otcTrade, bytes memory sig) = Parser.parseOTCTrade(payload);

    //     bytes32 digest = getOTCTradeDigest(otcTrade);

    //     _consumeDigest(digest);
    //     if (!SignatureChecker.isValidSignatureNow(enhancedSigner, digest, sig)) {
    //         revert("invalid OTC Trade signature");
    //     }

    //     MMarketOperations.Operation[] memory operations = new MMarketOperations.Operation[](1);

    //     operations[0] = MMarketOperations.Operation(
    //         MMarketOperations.OperationType.ConductTrade,
    //         otcTrade.user1, // user 1
    //         otcTrade.user2, // user 2
    //         otcTrade.asset1, // asset 1
    //         otcTrade.asset2, // asset 2
    //         otcTrade.amount1, // amount 1 in asset1 decimals
    //         otcTrade.amount2, // amount 2 in asset2 decimals
    //         bytes("")
    //     );

    //     mmarket.operate(operations);
    // }

    /**
     * @notice Either retrieves the option token if it already exists, or deploy it
     */
    function getOrDeployOtoken(Otoken memory otoken) internal returns (address) {
        address otokenFromFactory = factory.getOtoken(
            otoken.underlying,
            otoken.strikeAsset,
            otoken.collateral,
            otoken.strike,
            otoken.expiration,
            otoken.isPut,
            otoken.isPhysicallySettled,
            otoken.vaultOwner
        );
        if (otokenFromFactory != address(0)) {
            if (ERC20(otokenFromFactory).allowance(address(this), address(mmarket)) == 0) {
                SafeTransferLib.safeApprove(ERC20(otokenFromFactory), address(mmarket), type(uint256).max);
            }
            return otokenFromFactory;
        }

        address otokenCreated = factory.createOtoken(
            otoken.underlying,
            otoken.strikeAsset,
            otoken.collateral,
            otoken.strike,
            otoken.expiration,
            otoken.isPut,
            otoken.isPhysicallySettled,
            otoken.vaultOwner
        );
        SafeTransferLib.safeApprove(ERC20(otokenCreated), address(mmarket), type(uint256).max);
        return otokenCreated;
    }

    /**
     * @notice send asset amount to margin pool
     * @dev use donate() instead of direct transfer() to store the balance in assetBalance
     * @param _asset asset address
     * @param _amount amount to donate to pool
     */
    function donate(address _asset, uint256 _amount) external {
        _checkOperator();
        if (ERC20(_asset).allowance(address(this), marginPool) < _amount) {
            _forceApprove(_asset, marginPool, _amount);
        }
        controller.donate(_asset, _amount);
        emit Donated(_asset, _amount);
    }

    // /**
    //  * @notice Executes a flash loan to this contract. Logic and repayment contained in executeOperation()
    //  */
    // function flashLoanRedeem(address asset, uint256 amount, bytes calldata params) external {
    //     _checkOperator();

    //     IAavePool(flashLoanPool).flashLoanSimple(address(this), asset, amount, params, 0);
    // }

    // /**
    //  * @notice Callback from flash loan provider. Executes a physical option redemption using loaned funds, then swaps collateral back into borrowed asset to repay loan.
    //  */
    // function executeOperation(
    //     address asset, // loaned asset
    //     uint256 amount, // loaned amount
    //     uint256 premium, // the fee amount to repay
    //     address initiator, // the address of the flash loan initiator
    //     bytes calldata params // params passed when initiating the flash loan
    // )
    //     external
    //     nonReentrant
    //     returns (bool)
    // {
    //     require(msg.sender == flashLoanPool, "Caller is not flashLoanPool");
    //     require(initiator == address(this), "UNAUTHORIZED"); // make sure the flash loan call came from our access controlled function

    //     (Actions.ActionArgs memory args, address redeemer, bytes memory swapRoute, uint256 amountInMaximum) =
    //         Actions._constructFlashLoanRedeemActionArgs(params);

    //     require(
    //         block.timestamp > IOtoken(args.asset).expiryTimestamp() + flashLoanRedeemPeriodStart,
    //         "flash loan redeem period not started"
    //     );

    //     _retrieveOtokenForFlashLoanRedeem(redeemer, args.asset, args.amount);

    //     Actions.ActionArgs[] memory argsArray = new Actions.ActionArgs[](1);
    //     argsArray[0] = args;

    //     controller.operate(argsArray);

    //     // ====== hyperswap tx ========
    //     address collateral = IOtoken(args.asset).collateralAsset();

    //     SafeTransferLib.safeApprove(ERC20(collateral), swapRouter, amountInMaximum);

    //     {
    //         ISwapRouter.ExactOutputParams memory swapParams = ISwapRouter.ExactOutputParams({
    //             path: swapRoute,
    //             recipient: address(this),
    //             deadline: block.timestamp,
    //             amountOut: premium + amount - ERC20(asset).balanceOf(address(this)),
    //             amountInMaximum: amountInMaximum
    //         });

    //         // Executes the swap to repay loan
    //         ISwapRouter(swapRouter).exactOutput(swapParams);
    //     }
    //     // zero out approval
    //     SafeTransferLib.safeApprove(ERC20(collateral), swapRouter, 0);

    //     // ====== send profit to redeemer ========
    //     // no funds held on contract so any balance should belong to user
    //     {
    //         uint256 userProfitCollateral = ERC20(collateral).balanceOf(address(this));
    //         SafeTransferLib.safeTransfer(ERC20(collateral), redeemer, userProfitCollateral);
    //     }

    //     // ====== Hyperlend flash loan repayment ========
    //     SafeTransferLib.safeApprove(ERC20(asset), flashLoanPool, premium + amount);

    //     return true;
    // }

    function _retrieveOtokenForFlashLoanRedeem(address redeemer, address otoken, uint256 amount) internal {
        // create operation to withdraw otoken from mmarket
        MMarketOperations.Operation[] memory operationsArray = new MMarketOperations.Operation[](1);
        MMarketOperations.Operation memory withdrawOperation = MMarketOperations.Operation(
            MMarketOperations.OperationType.Withdraw,
            redeemer, // user to withdraw from
            address(this), // withdraw to this address
            otoken, // otoken address
            address(0), // asset_2 not needed
            amount, // amount of otoken to withdraw
            0, // amount_2 not needed
            bytes("0")
        );
        operationsArray[0] = withdrawOperation;

        mmarket.operate(operationsArray);
    }

    /////////////// --  EIP-712 FUNCTIONS -- ///////////////

    function getQuoteDigest(Parser.Quote memory q) internal view returns (bytes32) {
        bytes32 typeHash = keccak256(bytes(QUOTE_TYPE));
        bytes32 structHash;

        bytes memory encodedFirstHalf =
            abi.encode(typeHash, q.assetAddress, q.chainId, q.isPut, q.isPhysicallySettled, q.strike, q.expiry);

        bytes memory encodedSecondHalf =
            abi.encode(q.maker, q.nonce, q.price, q.quantity, q.isTakerBuy, q.validUntil, q.usd, q.collateralAsset);

        structHash = keccak256(bytes.concat(encodedFirstHalf, encodedSecondHalf));

        return _hashTypedDataV4(structHash);
    }

    function getConfirmationDigest(Parser.Confirmation memory c) internal view returns (bytes32) {
        bytes32 typeHash = keccak256(bytes(CONFIRMATION_TYPE));
        bytes32 sigHash = keccak256(c.quoteSignature);

        bytes memory firstHalf = abi.encode(
            typeHash, c.maker, c.assetAddress, c.chainId, c.expiry, c.isPut, c.isPhysicallySettled, c.nonce, c.price
        );

        bytes memory secondHalf = abi.encode(
            c.quantity,
            c.quoteNonce,
            sigHash,
            c.strike,
            c.taker,
            c.isTakerBuy,
            c.usd,
            c.collateralAsset,
            c.collateralAmount
        );

        bytes memory fullEncoded = bytes.concat(firstHalf, secondHalf);

        bytes32 structHash = keccak256(fullEncoded);

        return _hashTypedDataV4(structHash);
    }

    function getTransferDigest(Parser.Transfer memory t) internal view returns (bytes32) {
        bytes32 typeHash = keccak256(bytes(TRANSFER_TYPE));

        bytes32 structHash = keccak256(abi.encode(typeHash, t.user, t.asset, t.chainId, t.amount, t.isDeposit, t.nonce));

        return _hashTypedDataV4(structHash);
    }

    function getOTCTradeDigest(Parser.OTCTrade memory otc) public view returns (bytes32) {
        bytes32 typeHash = keccak256(bytes(OTC_TRADE_TYPE));

        bytes32 structHash = keccak256(
            abi.encode(
                typeHash, otc.chainId, otc.user1, otc.user2, otc.asset1, otc.asset2, otc.amount1, otc.amount2, otc.nonce
            )
        );

        return _hashTypedDataV4(structHash);
    }

    function getCustodyReleaseDigest(
        address maker,
        address receiver,
        uint64 nonce,
        uint64 validUntil,
        CustodyReleaseRequest[] calldata requests
    ) external view returns (bytes32) {
        return _getCustodyReleaseDigest(maker, receiver, nonce, validUntil, requests);
    }

    function _getCustodyReleaseDigest(
        address maker,
        address receiver,
        uint64 nonce,
        uint64 validUntil,
        CustodyReleaseRequest[] calldata requests
    ) internal view returns (bytes32) {
        bytes32 typeHash = keccak256(bytes(CUSTODY_RELEASE_TYPE));
        bytes32 structHash = keccak256(
            abi.encode(
                typeHash, maker, receiver, block.chainid, nonce, validUntil, _custodyReleaseRequestsHash(requests)
            )
        );

        return _hashTypedDataV4(structHash);
    }

    function _custodyReleaseRequestsHash(CustodyReleaseRequest[] calldata requests) internal pure returns (bytes32) {
        bytes32 typeHash = keccak256(bytes(CUSTODY_RELEASE_REQUEST_TYPE));
        bytes32[] memory hashes = new bytes32[](requests.length);
        for (uint256 i = 0; i < requests.length; i++) {
            hashes[i] = keccak256(
                abi.encode(typeHash, requests[i].owner, requests[i].vaultId, requests[i].asset, requests[i].amount)
            );
        }
        return keccak256(abi.encodePacked(hashes));
    }

    function _revertIfOutstandingCustody(address owner) internal view {
        uint256[] storage vaultIds = vaultsWithOutstandingRelease[owner];
        uint256 len = vaultIds.length;
        for (uint256 i = 0; i < len; i++) {
            if (vaultCustodyReleases[owner][vaultIds[i]].outstandingAmount != 0) {
                revert OutstandingCustodyRelease();
            }
        }
    }

    function _removeTrackedRelease(address owner, uint256 vaultId) internal {
        if (!isVaultReleaseTracked[owner][vaultId]) return;

        uint256[] storage vaultIds = vaultsWithOutstandingRelease[owner];
        uint256 len = vaultIds.length;
        for (uint256 i = 0; i < len; i++) {
            if (vaultIds[i] != vaultId) continue;

            uint256 lastIndex = len - 1;
            if (i != lastIndex) {
                vaultIds[i] = vaultIds[lastIndex];
            }
            vaultIds.pop();
            isVaultReleaseTracked[owner][vaultId] = false;
            return;
        }

        isVaultReleaseTracked[owner][vaultId] = false;
    }

    function _validateQuoteQuantity(Parser.Quote memory mmQuote, Parser.Confirmation memory sellerConfirmation)
        internal
        pure
    {
        require(sellerConfirmation.quantity <= mmQuote.quantity, QuantityExceedsQuote());
    }

    function _validateCustodyLimit(
        address maker,
        address owner,
        uint256 vaultId,
        address asset,
        uint256 newOutstandingAmount,
        uint256 bps
    ) internal view {
        if (vaultMakers[owner][vaultId] != maker) revert MakerNotVaultMaker();

        (MarginVault.Vault memory vault,,) = controller.getVaultWithDetails(owner, vaultId);
        if (vault.shortOtokens.length > 0) {
            require(
                OtokenInterface(vault.shortOtokens[0]).expiryTimestamp() > block.timestamp,
                CannotReleaseFromExpiredVault()
            );
        }

        uint256 vaultDepositAmount = _getVaultAssetDepositAmount(vault, asset);
        require(newOutstandingAmount <= vaultDepositAmount, ExceedsVaultDeposit());

        uint256 creditLimit = vaultDepositAmount * bps / MAX_CUSTODY_LIMIT_BPS;
        require(newOutstandingAmount <= creditLimit, ExceedsMakerCustodyLimit());
    }

    function _getVaultAssetDepositAmount(MarginVault.Vault memory vault, address asset)
        internal
        pure
        returns (uint256)
    {
        uint256 len = vault.collateralAssets.length;
        for (uint256 i = 0; i < len; i++) {
            if (vault.collateralAssets[i] == asset) {
                return vault.collateralAmounts[i];
            }
        }
        return 0;
    }

    function _consumeDigest(bytes32 digest) internal {
        if (isDigestUsed[digest]) revert SignatureAlreadyUsed();
        isDigestUsed[digest] = true;
    }
}

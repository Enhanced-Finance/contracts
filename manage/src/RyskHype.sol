/**
 * SPDX-License-Identifier: UNLICENSED
 */
pragma solidity ^0.8.22;

import "./library/Parser.sol";
import "./library/Actions.sol";
import "./MMarket.sol";
import "./interfaces/IOtoken.sol";
import "./interfaces/IAavePool.sol";
import "./interfaces/ISwapRouterHype.sol";
import "./interfaces/IController.sol";
import "./interfaces/IOtokenFactory.sol";
import "./library/MMarketOperations.sol";

import "lib/solmate/src/tokens/ERC20.sol";
import "lib/solmate/src/utils/SafeTransferLib.sol";
import "lib/openzeppelin-contracts/contracts/utils/cryptography/SignatureChecker.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/utils/cryptography/EIP712Upgradeable.sol";

/**
 * @title Rysk - this contract is the operator on both mmarket and Gamma
 * @dev assumed no funds are stored on this contract
 */
contract RyskHype is EIP712Upgradeable, OwnableUpgradeable, ReentrancyGuard {
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
    /// @dev Trusted rysk signer for offchain quotes
    address public ryskSigner;
    /// @dev Period during ControllerLogic.redeemTimePeriod after which ITM options can be flash loan redeemed.
    ///      If equal to or greater than redeemTimePeriod, there is no flash loan redeem period.
    ///      If set to zero then the whole redeemTimePeriod allows flash loan redemptions.
    uint256 flashLoanRedeemPeriodStart;
    /// @dev mapping to track used digests to prevent replay attacks
    mapping(bytes32 => bool) internal isDigestUsed;

    /// @notice emits an event when there is a change in operator
    event OperatorChanged(address newOperator, address oldOperator);

    address internal constant ZERO_ADDRESS = address(0x0);

    string internal constant QUOTE_TYPE =
        "Quote(address assetAddress,uint256 chainId,bool isPut,uint256 strike,uint64 expiry,address maker,uint64 nonce,uint256 price,uint256 quantity,bool isTakerBuy,uint64 validUntil,address usd,address collateralAsset)";

    string internal constant CONFIRMATION_TYPE =
        "Confirmation(address maker,address assetAddress,uint256 chainId,uint64 expiry,bool isPut,uint64 nonce,uint256 price,uint256 quantity,uint64 quoteNonce,bytes quoteSignature,uint256 strike,address taker,bool isTakerBuy,address usd,address collateralAsset,uint256 collateralAmount)";

    string internal constant TRANSFER_TYPE =
        "Transfer(address user,address asset,uint256 chainId,uint256 amount,bool isDeposit,uint64 nonce)";

    string public constant OTC_TRADE_TYPE =
        "OTCTrade(uint256 chainId,address user1,address user2,address asset1,address asset2,uint256 amount1,uint256 amount2,uint64 nonce)";

    function initialize() external initializer {
        __EIP712_init("rysk", "0.0.0");
        __Ownable_init(msg.sender);
    }

    function setOperator(address _operator) external {
        _checkOwner();
        emit OperatorChanged(_operator, operator);
        operator = _operator;
    }

    function setController(address _controller) external {
        _checkOwner();
        controller = IController(_controller);
    }

    function setMMarket(address _mmarket) external {
        _checkOwner();
        mmarket = MMarket(_mmarket);
    }

    function setFactory(address _factory) external {
        _checkOwner();
        factory = IOtokenFactory(_factory);
    }

    function setFlashLoanPool(address _flashLoanPool) external {
        _checkOwner();
        flashLoanPool = _flashLoanPool;
    }

    function setSwapRouter(address _swapRouter) external {
        _checkOwner();
        swapRouter = _swapRouter;
    }

    function setMarginPool(address _marginPool) external {
        _checkOwner();
        marginPool = _marginPool;
    }

    function setFeeRecipient(address _feeRecipient) external {
        _checkOwner();
        feeRecipient = _feeRecipient;
    }

    function setRyskSigner(address _ryskSigner) external {
        _checkOwner();
        ryskSigner = _ryskSigner;
    }

    function setFlashLoanRedeemPeriodStart(uint256 _flashLoanRedeemPeriodStart) external {
        _checkOwner();
        flashLoanRedeemPeriodStart = _flashLoanRedeemPeriodStart;
    }

    /// @notice sets approval for the margin pool to remove funds for an asset
    function setAssetApproval(address _asset, bool _approval) external {
        _checkOwner();
        if (_approval) {
            SafeTransferLib.safeApprove(ERC20(_asset), address(marginPool), type(uint256).max);
        } else {
            SafeTransferLib.safeApprove(ERC20(_asset), address(marginPool), 0);
        }
    }

    function _checkOperator() internal view {
        if (operator != _msgSender()) revert("bad operator");
    }

    struct Otoken {
        address collateral;
        address underlying;
        address strikeAsset;
        uint256 strike;
        uint256 expiration;
        bool isPut;
        bool isPhysicallySettled;
    }

    function ingresso_redeem(MMarketOperations.Operation[] memory operations, Actions.ActionArgs[] memory actions)
        external
        nonReentrant
    {
        _checkOperator();
        require(
            operations.length == 1 && operations[0].operationType == MMarketOperations.OperationType.Withdraw,
            "invalid operations array"
        );
        require(actions.length == 1 && actions[0].actionType == Actions.ActionType.Redeem, "invalid actions array");
        require(operations[0].asset_1 == actions[0].asset, "mmarket withdrawn asset is not redeemed otoken");
        require(operations[0].user_1 == actions[0].secondAddress, "redeem receiver must be otoken owner");
        require(operations[0].amount_1 == actions[0].amount, "redeem amount must be withdraw amount");
        require(operations[0].user_2 == address(this), "invalid withdraw recipient");
        mmarket.operate(operations);
        controller.operate(actions);
    }

    function ingresso_settle(Actions.ActionArgs[] memory actions) external nonReentrant {
        _checkOperator();
        uint256 len = actions.length;
        for (uint256 i = 0; i < len; i++) {
            require(actions[i].actionType == Actions.ActionType.SettleVault, "invalid actions array");
            require(actions[i].secondAddress == actions[i].owner, "settle receiver must be vault owner");
        }
        controller.operate(actions);
    }

    function ingresso_newUserPosition(bytes calldata payload) external nonReentrant {
        _checkOperator();

        (
            Parser.Quote memory mmQuote,
            Parser.Confirmation memory sellerConfirmation,
            bytes memory quoteSig,
            bytes memory confSig,
            uint256 fee
        ) = Parser.parseQuoteAndConfirmation(payload);

        bytes32 quoteDigest = getQuoteDigest(mmQuote);
        bytes32 confDigest = getConfirmationDigest(sellerConfirmation);

        if (!checkSignature(mmQuote.maker, quoteDigest, quoteSig)) {
            revert("invalid quote signature");
        }

        if (!checkSignature(sellerConfirmation.taker, confDigest, confSig)) {
            revert("invalid confirmation signature");
        }
        isDigestUsed[quoteDigest] = true;
        isDigestUsed[confDigest] = true;

        // now confirmed that signatures are correct, build the actions to execute the trade
        // 1. Actions.OpenVault
        // 2. Actions.DepositCollateral
        // 3. Actions.MintShortOption
        // 4. Operations.Deposit (increment user's otoken balance on mmarket)
        // 5. Operations.ConductTrade
        // 6. Operations.Withdraw (withdraw premium to seller's wallet)
        // 7. CONDITIONAL - Operations.Withdraw (handle fee payment)

        uint256 vaultId = controller.getAccountVaultCounter(sellerConfirmation.taker) + 1;
        uint256 totalPremium = sellerConfirmation.quantity * sellerConfirmation.price
            * (10 ** ERC20(sellerConfirmation.usd).decimals()) / 1e36;

        Actions.ActionArgs[] memory actions = new Actions.ActionArgs[](3);
        MMarketOperations.Operation[] memory operations;
        if (fee == 0) {
            operations = new MMarketOperations.Operation[](3);
        } else {
            operations = new MMarketOperations.Operation[](4);
        }
        address otokenAddress = getOrDeployOtoken(
            Otoken(
                sellerConfirmation.collateralAsset,
                sellerConfirmation.assetAddress,
                sellerConfirmation.usd,
                sellerConfirmation.strike,
                sellerConfirmation.expiry,
                sellerConfirmation.isPut,
                true
            )
        );

        actions[0] = Actions.ActionArgs(
            Actions.ActionType.OpenVault,
            sellerConfirmation.taker, // vault owner
            ZERO_ADDRESS, // secondAddress
            ZERO_ADDRESS, // asset
            vaultId, // vault ID
            0, // asset amount
            0, // index
            abi.encode(2) // data bytes (vault type)
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
            address(this), // take from rysk (otoken already held here)
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

    function ingresso_transferAsset(bytes calldata payload) external nonReentrant {
        _checkOperator();
        (Parser.Transfer memory transfer, bytes memory sig) = Parser.parseTransfer(payload);

        bytes32 digest = getTransferDigest(transfer);

        if (!checkSignature(transfer.user, digest, sig)) {
            revert("invalid transfer signature");
        }

        isDigestUsed[digest] = true;

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

    function ingresso_OTCTrade(bytes calldata payload) external nonReentrant {
        _checkOperator();
        (Parser.OTCTrade memory otcTrade, bytes memory sig) = Parser.parseOTCTrade(payload);

        bytes32 digest = getOTCTradeDigest(otcTrade);

        if (!checkSignature(ryskSigner, digest, sig)) {
            revert("invalid OTC Trade signature");
        }

        isDigestUsed[digest] = true;

        MMarketOperations.Operation[] memory operations = new MMarketOperations.Operation[](1);

        operations[0] = MMarketOperations.Operation(
            MMarketOperations.OperationType.ConductTrade,
            otcTrade.user1, // user 1
            otcTrade.user2, // user 2
            otcTrade.asset1, // asset 1
            otcTrade.asset2, // asset 2
            otcTrade.amount1, // amount 1 in asset1 decimals
            otcTrade.amount2, // amount 2 in asset2 decimals
            bytes("")
        );

        mmarket.operate(operations);
    }

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
            otoken.isPhysicallySettled
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
            otoken.isPhysicallySettled
        );
        SafeTransferLib.safeApprove(ERC20(otokenCreated), address(mmarket), type(uint256).max);
        return otokenCreated;
    }

    /**
     * @notice Executes a flash loan to this contract. Logic and repayment contained in executeOperation()
     */
    function flashLoanRedeem(address asset, uint256 amount, bytes calldata params) external {
        _checkOperator();

        IAavePool(flashLoanPool).flashLoanSimple(address(this), asset, amount, params, 0);
    }

    /**
     * @notice Callback from flash loan provider. Executes a physical option redemption using loaned funds, then swaps collateral back into borrowed asset to repay loan.
     */
    function executeOperation(
        address asset, // loaned asset
        uint256 amount, // loaned amount
        uint256 premium, // the fee amount to repay
        address initiator, // the address of the flash loan initiator
        bytes calldata params // params passed when initiating the flash loan
    )
        external
        nonReentrant
        returns (bool)
    {
        require(msg.sender == flashLoanPool, "Caller is not flashLoanPool");
        require(initiator == address(this), "UNAUTHORIZED"); // make sure the flash loan call came from our access controlled function

        (Actions.ActionArgs memory args, address redeemer, bytes memory swapRoute, uint256 amountInMaximum) =
            Actions._constructFlashLoanRedeemActionArgs(params);

        require(
            block.timestamp > IOtoken(args.asset).expiryTimestamp() + flashLoanRedeemPeriodStart,
            "flash loan redeem period not started"
        );

        _retrieveOtokenForFlashLoanRedeem(redeemer, args.asset, args.amount);

        Actions.ActionArgs[] memory argsArray = new Actions.ActionArgs[](1);
        argsArray[0] = args;

        controller.operate(argsArray);

        // ====== hyperswap tx ========
        address collateral = IOtoken(args.asset).collateralAsset();

        SafeTransferLib.safeApprove(ERC20(collateral), swapRouter, amountInMaximum);

        {
            ISwapRouterHype.ExactOutputParams memory swapParams = ISwapRouterHype.ExactOutputParams({
                path: swapRoute,
                recipient: address(this),
                deadline: block.timestamp,
                amountOut: premium + amount - ERC20(asset).balanceOf(address(this)),
                amountInMaximum: amountInMaximum
            });

            // Executes the swap to repay loan
            ISwapRouterHype(swapRouter).exactOutput(swapParams);
        }
        // zero out approval
        SafeTransferLib.safeApprove(ERC20(collateral), swapRouter, 0);

        // ====== send profit to redeemer ========
        // no funds held on contract so any balance should belong to user
        {
            uint256 userProfitCollateral = ERC20(collateral).balanceOf(address(this));
            SafeTransferLib.safeTransfer(ERC20(collateral), redeemer, userProfitCollateral);
        }

        // ====== Hyperlend flash loan repayment ========
        SafeTransferLib.safeApprove(ERC20(asset), flashLoanPool, premium + amount);

        return true;
    }

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

        bytes memory encodedFirstHalf = abi.encode(typeHash, q.assetAddress, q.chainId, q.isPut, q.strike, q.expiry);

        bytes memory encodedSecondHalf =
            abi.encode(q.maker, q.nonce, q.price, q.quantity, q.isTakerBuy, q.validUntil, q.usd, q.collateralAsset);

        structHash = keccak256(bytes.concat(encodedFirstHalf, encodedSecondHalf));

        return _hashTypedDataV4(structHash);
    }

    function getConfirmationDigest(Parser.Confirmation memory c) internal view returns (bytes32) {
        bytes32 typeHash = keccak256(bytes(CONFIRMATION_TYPE));
        bytes32 sigHash = keccak256(c.quoteSignature);

        bytes memory firstHalf =
            abi.encode(typeHash, c.maker, c.assetAddress, c.chainId, c.expiry, c.isPut, c.nonce, c.price);

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

    /// @notice function to check a account corresponds to the signature of a given digest, or is a valid ERC 1271 sig
    /// @dev uses ECDSA, to get the digest you can use getDigest with the Action or MMarketOperation struct
    /// @param account the trader of the action/operation, should correspond to the signer
    /// @param digest the hashed version of the action/operation
    /// @param signature the EIP712 signature corresponding to the action/operation, signed by the trader
    function checkSignature(address account, bytes32 digest, bytes memory signature) internal view returns (bool) {
        if (isDigestUsed[digest]) revert("signature already used");
        return SignatureChecker.isValidSignatureNow(account, digest, signature);
    }
}

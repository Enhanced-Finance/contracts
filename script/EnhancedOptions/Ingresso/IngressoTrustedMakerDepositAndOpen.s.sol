// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {EnhancedOptions} from "src/core/EnhancedOptions.sol";
import {Parser} from "src/core/libs/Parser.sol";
import {stdJson} from "lib/forge-std/src/StdJson.sol";

/// @notice Executes `ingressoTrustedMakerDepositAndOpen`.
///
///         Atomic: deposit transfer asset + open trusted maker position.
///         Transfer payload: payer signs Transfer digest (130 or 150 bytes).
///         Order payload: 377-byte Quote+Confirmation; only taker signs confirmation.
///         Maker must be registered as trustedMaker in EnhancedOptions.
contract IngressoTrustedMakerDepositAndOpen is Script {
    using stdJson for string;

    // --- Transfer Configuration ---
    uint256 constant TRANSFER_CHAIN_ID = 11155111;
    uint256 constant DEPOSIT_AMOUNT = 1000000 * 1e18; // 18 decimals
    uint64 constant TRANSFER_NONCE = 1;

    // --- Quote / Confirmation Configuration ---
    uint256 constant CHAIN_ID = 11155111;
    bool constant IS_PUT = false;
    bool constant IS_PHYSICALLY_SETTLED = false;
    uint256 constant STRIKE = 6670000; // 8 decimals
    uint64 constant EXPIRY = 1800000000;
    uint64 constant NONCE = 1;
    uint256 constant PRICE = 687e12; // 18 decimals
    uint256 constant QUOTE_QUANTITY = 1000000 * 1e18;
    uint256 constant QUANTITY = 1000000 * 1e18;
    bool constant IS_TAKER_BUY = true;
    uint64 constant VALID_UNTIL = 1800000000;
    uint256 constant COLLATERAL_AMOUNT = 1000000 * 1e18;
    uint256 constant MAKER_FEE = 0;
    uint256 constant TAKER_FEE = 0;
    // ----------------------------------------------------

    bytes32 constant TRANSFER_TYPEHASH =
        keccak256("Transfer(address user,address asset,uint256 chainId,uint256 amount,bool isDeposit,uint64 nonce)");

    bytes32 constant QUOTE_TYPEHASH = keccak256(
        "Quote(address assetAddress,uint256 chainId,bool isPut,bool isPhysicallySettled,uint256 strike,uint64 expiry,address maker,uint64 nonce,uint256 price,uint256 quantity,bool isTakerBuy,uint64 validUntil,address usd,address collateralAsset)"
    );
    bytes32 constant CONFIRMATION_TYPEHASH = keccak256(
        "Confirmation(address maker,address assetAddress,uint256 chainId,uint64 expiry,bool isPut,bool isPhysicallySettled,uint64 nonce,uint256 price,uint256 quantity,uint64 quoteNonce,bytes quoteSignature,uint256 strike,address taker,bool isTakerBuy,address usd,address collateralAsset,uint256 collateralAmount)"
    );

    bytes32 constant EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 constant NAME_HASH = keccak256(bytes("enhanced"));
    bytes32 constant VERSION_HASH = keccak256(bytes("0.0.0"));

    function run() public {
        address DEPOSIT_ASSET = vm.envAddress("STRIKE");
        address assetAddress = vm.envAddress("UNDERLYING");
        address usd = vm.envAddress("STRIKE");
        address collateralAsset = vm.envOr("COLLATERAL_ASSET", assetAddress);

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        uint256 makerPrivateKey = vm.envUint("MAKER_PRIVATE_KEY");
        address maker = vm.addr(makerPrivateKey);

        uint256 takerPrivateKey = vm.envUint("TAKER_PRIVATE_KEY");
        address taker = vm.addr(takerPrivateKey);

        uint256 userPrivateKey = vm.envUint("USER_PRIVATE_KEY");
        address user = vm.addr(userPrivateKey);

        address payerAddress = vm.envOr("PAYER", address(0));
        bool hasDedicatedPayer = payerAddress != address(0);
        address payer = hasDedicatedPayer ? payerAddress : user;
        uint256 payerPrivateKey = hasDedicatedPayer ? vm.envUint("PAYER_PRIVATE_KEY") : userPrivateKey;

        console.log("Deployer (Operator):", deployer);
        console.log("Maker (trusted):", maker);
        console.log("Taker:", taker);
        console.log("User:", user);
        console.log("Payer:", payer);

        uint256 chainId = block.chainid;
        string memory chainIdStr = vm.toString(chainId);
        string memory deployPath = string.concat(vm.projectRoot(), "/.deploy/", chainIdStr, ".json");

        require(vm.isFile(deployPath), "Deploy file not found");
        string memory deployJson = vm.readFile(deployPath);
        address enhancedOptionsAddr = deployJson.readAddress(".EnhancedOptions.proxyAddress");
        require(enhancedOptionsAddr != address(0), "EnhancedOptions proxy not found");
        address mmarketAddr = deployJson.readAddress(".MMarket.proxyAddress");
        require(mmarketAddr != address(0), "MMarket proxy not found");

        bytes32 domainSeparator = _buildDomainSeparator(enhancedOptionsAddr, chainId);

        // ==========================================
        // 0. Approve: payer -> MMarket
        // ==========================================
        // vm.startBroadcast(payerPrivateKey);
        // IERC20 depositAsset = IERC20(DEPOSIT_ASSET);
        // uint256 allowance = depositAsset.allowance(payer, mmarketAddr);
        // if (allowance < DEPOSIT_AMOUNT) {
        //     console.log("Approving deposit token (payer -> MMarket)...");
        //     depositAsset.approve(mmarketAddr, type(uint256).max);
        // }
        // vm.stopBroadcast();

        // ==========================================
        // 1. Build transferPayload (same as IngressoMMarketDeposit)
        // ==========================================
        Parser.Transfer memory transfer = Parser.Transfer({
            user: user,
            asset: DEPOSIT_ASSET,
            chainId: TRANSFER_CHAIN_ID,
            amount: DEPOSIT_AMOUNT,
            isDeposit: true,
            nonce: TRANSFER_NONCE,
            payer: hasDedicatedPayer ? payer : address(0)
        });

        bytes32 transferDigest = _getTransferDigest(transfer, domainSeparator);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(payerPrivateKey, transferDigest);
        bytes memory transferSig = abi.encodePacked(r, s, v);

        bytes memory transferPayload = hasDedicatedPayer
            ? _packTransferWithPayer(transfer, transferSig, payer)
            : _packTransfer(transfer, transferSig);

        console.log("Transfer payload length:", transferPayload.length);

        // ==========================================
        // 2. Build orderPayload (377-byte Quote+Confirmation)
        //    Only taker signs confirmation. No quote signature needed.
        // ==========================================
        Parser.Quote memory quote = Parser.Quote({
            assetAddress: assetAddress,
            chainId: CHAIN_ID,
            isPut: IS_PUT,
            isPhysicallySettled: IS_PHYSICALLY_SETTLED,
            strike: STRIKE,
            expiry: EXPIRY,
            maker: maker,
            nonce: NONCE,
            price: PRICE,
            quantity: QUOTE_QUANTITY,
            isTakerBuy: IS_TAKER_BUY,
            validUntil: VALID_UNTIL,
            usd: usd,
            collateralAsset: collateralAsset
        });

        // empty quote signature — contract skips quote sig verification for trusted maker
        bytes memory emptyQuoteSig = new bytes(65);

        Parser.Confirmation memory confirmation = Parser.Confirmation({
            maker: maker,
            assetAddress: assetAddress,
            chainId: CHAIN_ID,
            expiry: EXPIRY,
            isPut: IS_PUT,
            isPhysicallySettled: IS_PHYSICALLY_SETTLED,
            nonce: NONCE,
            price: PRICE,
            quantity: QUANTITY,
            quoteNonce: NONCE,
            quoteSignature: emptyQuoteSig,
            strike: STRIKE,
            taker: taker,
            isTakerBuy: IS_TAKER_BUY,
            usd: usd,
            collateralAsset: collateralAsset,
            collateralAmount: COLLATERAL_AMOUNT
        });

        // Taker signs confirmation
        bytes32 confDigest = _getConfirmationDigest(confirmation, domainSeparator);
        (v, r, s) = vm.sign(takerPrivateKey, confDigest);
        bytes memory confSig = abi.encodePacked(r, s, v);

        bytes memory orderPayload = _packPayload(quote, confirmation, emptyQuoteSig, confSig, MAKER_FEE, TAKER_FEE);
        console.log("Order payload length:", orderPayload.length);
        require(orderPayload.length == 377, "Invalid order payload length, expected 377");

        // ==========================================
        // 3. Execute
        // ==========================================
        console.log("Executing IngressoTrustedMakerDepositAndOpen on:", enhancedOptionsAddr);

        vm.startBroadcast(deployerPrivateKey);
        EnhancedOptions(enhancedOptionsAddr).ingressoTrustedMakerDepositAndOpen(transferPayload, orderPayload);
        vm.stopBroadcast();

        console.log("IngressoTrustedMakerDepositAndOpen executed successfully");
    }

    // ==========================================
    // Transfer helpers (from IngressoMMarketDeposit)
    // ==========================================

    function _getTransferDigest(Parser.Transfer memory t, bytes32 domainSeparator) internal pure returns (bytes32) {
        bytes32 structHash =
            keccak256(abi.encode(TRANSFER_TYPEHASH, t.user, t.asset, t.chainId, t.amount, t.isDeposit, t.nonce));
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }

    function _packTransfer(Parser.Transfer memory t, bytes memory sig) internal pure returns (bytes memory) {
        return abi.encodePacked(
            t.asset, // 20
            uint128(t.amount), // 16
            bool(t.isDeposit), // 1
            uint64(t.nonce), // 8
            sig, // 65
            t.user // 20
        );
    }

    function _packTransferWithPayer(Parser.Transfer memory t, bytes memory sig, address payer)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodePacked(
            t.asset, // 20
            uint128(t.amount), // 16
            bool(t.isDeposit), // 1
            uint64(t.nonce), // 8
            sig, // 65
            t.user, // 20
            payer // 20
        );
    }

    // ==========================================
    // Quote / Confirmation helpers (from IngressoNewUserPosition)
    // ==========================================

    function _buildDomainSeparator(address verifyingContract, uint256 chainId) internal pure returns (bytes32) {
        return keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, NAME_HASH, VERSION_HASH, chainId, verifyingContract));
    }

    function _getConfirmationDigest(Parser.Confirmation memory c, bytes32 domainSeparator)
        internal
        pure
        returns (bytes32)
    {
        bytes32 sigHash = keccak256(c.quoteSignature);
        bytes32 structHash = keccak256(
            abi.encodePacked(
                abi.encode(
                    CONFIRMATION_TYPEHASH,
                    c.maker,
                    c.assetAddress,
                    c.chainId,
                    c.expiry,
                    c.isPut,
                    c.isPhysicallySettled,
                    c.nonce,
                    c.price
                ),
                abi.encode(
                    c.quantity,
                    c.quoteNonce,
                    sigHash,
                    c.strike,
                    c.taker,
                    c.isTakerBuy,
                    c.usd,
                    c.collateralAsset,
                    c.collateralAmount
                )
            )
        );
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }

    function _packPayload(
        Parser.Quote memory q,
        Parser.Confirmation memory c,
        bytes memory quoteSig,
        bytes memory confSig,
        uint256 protocolFee,
        uint256 makerFee
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(
            c.maker, // 20
            q.assetAddress, // 20
            uint64(q.expiry), // 8
            bool(q.isPut), // 1
            bool(q.isPhysicallySettled), // 1
            uint64(c.nonce), // 8
            uint128(q.price), // 16
            uint128(q.quantity), // 16
            uint128(c.quantity), // 16
            uint64(q.nonce), // 8
            quoteSig, // 65
            confSig, // 65
            uint128(q.strike), // 16
            c.taker, // 20
            bool(q.isTakerBuy), // 1
            uint64(q.validUntil), // 8
            q.usd, // 20
            q.collateralAsset, // 20
            uint128(c.collateralAmount), // 16
            uint128(protocolFee), // 16
            uint128(makerFee) // 16
        );
    }
}

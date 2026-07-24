/**
 * SPDX-License-Identifier: MIT
 */
pragma solidity ^0.8.22;

library Parser {
    enum OperationType {
        GAMMA,
        MMARKET
    }

    struct Quote {
        address assetAddress; // underlying
        uint256 chainId;
        bool isPut;
        bool isPhysicallySettled;
        uint256 strike; // e8
        uint64 expiry;
        address maker;
        uint64 nonce;
        uint256 price; // e18
        uint256 quantity; // e18
        bool isTakerBuy;
        uint64 validUntil;
        address usd;
        address collateralAsset;
    }

    struct Confirmation {
        address maker;
        address assetAddress;
        uint256 chainId;
        uint64 expiry;
        bool isPut;
        bool isPhysicallySettled;
        uint64 nonce;
        uint256 price; // e18 quote price per 1 whole option (normalized fixed-point)
        uint256 quantity; // e18 option amount; minted otoken amount uses quantity / 1e10 (e8)
        uint64 quoteNonce;
        bytes quoteSignature;
        uint256 strike; // e8
        address taker;
        bool isTakerBuy;
        address usd;
        address collateralAsset;
        uint256 collateralAmount; // token native decimals of collateralAsset
    }

    struct Transfer {
        address user;
        address asset;
        uint256 chainId;
        uint256 amount; // asset decimals
        bool isDeposit;
        uint64 nonce;
        address payer; // zero address means user pays themselves
    }

    function quoteStructHash(Quote memory q) public pure returns (bytes32) {
        bytes32 typeHash = keccak256(
            "Quote(address assetAddress,uint256 chainId,bool isPut,bool isPhysicallySettled,uint256 strike,uint64 expiry,address maker,uint64 nonce,uint256 price,uint256 quantity,bool isTakerBuy,uint64 validUntil,address usd,address collateralAsset)"
        );
        bytes memory firstHalf =
            abi.encode(typeHash, q.assetAddress, q.chainId, q.isPut, q.isPhysicallySettled, q.strike, q.expiry);
        bytes memory secondHalf =
            abi.encode(q.maker, q.nonce, q.price, q.quantity, q.isTakerBuy, q.validUntil, q.usd, q.collateralAsset);
        return keccak256(bytes.concat(firstHalf, secondHalf));
    }

    function confirmationStructHash(Confirmation memory c) public pure returns (bytes32) {
        bytes32 typeHash = keccak256(
            "Confirmation(address maker,address assetAddress,uint256 chainId,uint64 expiry,bool isPut,bool isPhysicallySettled,uint64 nonce,uint256 price,uint256 quantity,uint64 quoteNonce,bytes quoteSignature,uint256 strike,address taker,bool isTakerBuy,address usd,address collateralAsset,uint256 collateralAmount)"
        );
        bytes memory firstHalf = abi.encode(
            typeHash, c.maker, c.assetAddress, c.chainId, c.expiry, c.isPut, c.isPhysicallySettled, c.nonce, c.price
        );
        bytes memory secondHalf = abi.encode(
            c.quantity,
            c.quoteNonce,
            keccak256(c.quoteSignature),
            c.strike,
            c.taker,
            c.isTakerBuy,
            c.usd,
            c.collateralAsset,
            c.collateralAmount
        );
        return keccak256(bytes.concat(firstHalf, secondHalf));
    }

    function transferStructHash(Transfer memory t) public pure returns (bytes32) {
        bytes32 typeHash = keccak256(
            "Transfer(address user,address asset,uint256 chainId,uint256 amount,bool isDeposit,uint64 nonce)"
        );
        return keccak256(abi.encode(typeHash, t.user, t.asset, t.chainId, t.amount, t.isDeposit, t.nonce));
    }

    /// @notice Parse a packed payload into both Quote and Confirmation structs
    /// @dev Parses 377-byte payload into Quote + Confirmation + sigs for both
    /// @dev also returns additional data needed to create an option position
    function parseQuoteAndConfirmation(bytes memory payload)
        public
        view
        returns (
            Quote memory q,
            Confirmation memory c,
            bytes memory quoteSig,
            bytes memory confSig,
            uint256 protocolFee,
            uint256 makerFee
        )
    {
        // expected length:
        // 20 (maker) + 20 (asset) + 8 (expiry) +
        // 1 (isPut) + 1 (isPhysicallySettled) + 8 (confirmationNonce) + 16 (price) +
        // 16 (quoteQuantity) + 16 (confirmationQuantity) + 8 (quoteNonce) + 65 (quoteSig) +
        // 65 (confSig) + 16 (strike) + 20 (taker) +
        // 1 (isTakerBuy) + 8 (validUntil) + 20 (usd) +
        // 20 (collateralAsset) + 16 (collateralAmount) + 16 (protocolFee) + 16 (makerFee)
        // = 377 bytes total
        require(payload.length == 377, "Invalid payload length");

        quoteSig = new bytes(65);
        confSig = new bytes(65);

        assembly {
            let qPtr := q
            let cPtr := c

            // --- Confirmation fields ---
            mstore(cPtr, mload(add(payload, 20))) // maker
            mstore(add(cPtr, 0x20), mload(add(payload, 40))) // assetAddress
            mstore(add(cPtr, 0x40), chainid()) // chainId
            mstore(add(cPtr, 0x60), mload(add(payload, 48))) // expiry
            mstore(add(cPtr, 0x80), and(mload(add(payload, 49)), 0xFF)) // isPut (mask all but last byte)
            mstore(add(cPtr, 0xA0), and(mload(add(payload, 50)), 0xFF)) // isPhysicallySettled (mask all but last byte)
            mstore(add(cPtr, 0xC0), mload(add(payload, 58))) // nonce (confirmationNonce)
            mstore(add(cPtr, 0xE0), mload(add(payload, 74))) // price
            mstore(add(cPtr, 0x100), mload(add(payload, 106))) // quantity
            mstore(add(cPtr, 0x120), mload(add(payload, 114))) // quoteNonce
            mstore(add(cPtr, 0x140), quoteSig) // quoteSignature pointer
            mstore(add(cPtr, 0x160), mload(add(payload, 260))) // strike
            mstore(add(cPtr, 0x180), mload(add(payload, 280))) // taker
            mstore(add(cPtr, 0x1A0), and(mload(add(payload, 281)), 0xFF)) // isTakerBuy (mask all but last byte)
            mstore(add(cPtr, 0x1C0), mload(add(payload, 309))) // usd
            mstore(add(cPtr, 0x1E0), mload(add(payload, 329))) // collateralAsset
            mstore(add(cPtr, 0x200), mload(add(payload, 345))) // collateralAmount

            // --- Quote fields ---
            mstore(qPtr, mload(add(payload, 40))) // assetAddress
            mstore(add(qPtr, 0x20), chainid()) // chainId
            mstore8(add(qPtr, 0x40), and(mload(add(payload, 49)), 0xFF)) // isPut (mask all but last byte)
            mstore8(add(qPtr, 0x60), and(mload(add(payload, 50)), 0xFF)) // isPhysicallySettled (mask all but last byte)
            mstore(add(qPtr, 0x80), mload(add(payload, 260))) // strike
            mstore(add(qPtr, 0xA0), mload(add(payload, 48))) // expiry
            mstore(add(qPtr, 0xC0), mload(add(payload, 20))) // maker
            mstore(add(qPtr, 0xE0), mload(add(payload, 114))) // nonce = quoteNonce
            mstore(add(qPtr, 0x100), mload(add(payload, 74))) // price
            mstore(add(qPtr, 0x120), mload(add(payload, 90))) // quantity
            mstore(add(qPtr, 0x140), and(mload(add(payload, 281)), 0xFF)) // isTakerBuy (mask all but last byte)
            mstore(add(qPtr, 0x160), mload(add(payload, 289))) // validUntil
            mstore(add(qPtr, 0x180), mload(add(payload, 309))) // usd
            mstore(add(qPtr, 0x1A0), mload(add(payload, 329))) // collateralAsset

            // --- Extract signatures safely ---
            // Quote signature
            mstore(add(quoteSig, 32), mload(add(payload, 146))) // bytes 0-31
            mstore(add(quoteSig, 64), mload(add(payload, 178))) // bytes 32-63
            mstore8(add(quoteSig, 96), byte(0, mload(add(payload, 210)))) // byte 64

            // Confirmation signature
            mstore(add(confSig, 32), mload(add(payload, 211))) // bytes 0-31
            mstore(add(confSig, 64), mload(add(payload, 243))) // bytes 32-63
            mstore8(add(confSig, 96), byte(0, mload(add(payload, 275)))) // byte 64

            // --- Extract fees ---
            protocolFee := mload(add(payload, 361))
            makerFee := mload(add(payload, 377))
        }

        // --- Cast uint128 → uint256 outside assembly ---
        q.strike = uint256(uint128(q.strike));
        q.price = uint256(uint128(q.price));
        q.quantity = uint256(uint128(q.quantity));

        c.strike = uint256(uint128(c.strike));
        c.price = uint256(uint128(c.price));
        c.quantity = uint256(uint128(c.quantity));
        c.collateralAmount = uint256(uint128(c.collateralAmount));

        protocolFee = uint256(uint128(protocolFee));
        makerFee = uint256(uint128(makerFee));
    }

    /// @notice Parse a packed payload into a Transfer struct and its signature
    /// @dev Parses 130-byte or 150-byte payload into Transfer + signature.
    ///      130 bytes: without payer (payer defaults to address(0), meaning user pays themselves).
    ///      150 bytes: with payer appended as the last 20 bytes.
    ///
    ///      Layout (data bytes):
    ///        0–19   : asset (20)
    ///       20–35   : amount (16)
    ///          36   : isDeposit (1)
    ///       37–44   : nonce (8)
    ///       45–109  : signature (65)
    ///      110–129  : user (20)
    ///      130–149  : payer (20, 150-byte variant only)
    function parseTransfer(bytes memory payload) public view returns (Transfer memory t, bytes memory sig) {
        require(payload.length == 130 || payload.length == 150, "Invalid payload length");

        sig = new bytes(65);

        assembly {
            let tPtr := t

            // --- Transfer fields ---
            mstore(tPtr, mload(add(payload, 130))) // user
            mstore(add(tPtr, 0x20), mload(add(payload, 20))) // asset
            mstore(add(tPtr, 0x40), chainid()) // chainid
            mstore(add(tPtr, 0x60), mload(add(payload, 36))) // amount
            mstore(add(tPtr, 0x80), and(mload(add(payload, 37)), 0xFF)) // isDeposit (mask all but last byte)
            mstore(add(tPtr, 0xA0), mload(add(payload, 45))) // nonce
            // payer (slot 0xC0) left as zero; populated below for 150-byte payloads

            // --- Extract signature ---
            mstore(add(sig, 32), mload(add(payload, 77))) // bytes 0–31
            mstore(add(sig, 64), mload(add(payload, 109))) // bytes 32–63
            mstore8(add(sig, 96), byte(0, mload(add(payload, 141)))) // byte 64
        }

        // Parse payer from the trailing 20 bytes of the 150-byte variant.
        if (payload.length == 150) {
            assembly {
                mstore(add(t, 0xC0), mload(add(payload, 150))) // payer
            }
        }

        // Cast uint128 → uint256 for amount
        t.amount = uint256(uint128(t.amount));
    }
}

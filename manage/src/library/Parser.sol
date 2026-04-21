/**
 * SPDX-License-Identifier: UNLICENSED
 */
pragma solidity ^0.8.22;

import "./Actions.sol";
import "./MMarketOperations.sol";

library Parser {
    enum OperationType {
        GAMMA,
        MMARKET
    }

    struct Quote {
        address assetAddress; // underlying
        uint256 chainId;
        bool isPut;
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
        uint64 nonce;
        uint256 price; // e18
        uint256 quantity; // e18
        uint64 quoteNonce;
        bytes quoteSignature;
        uint256 strike; // e8
        address taker;
        bool isTakerBuy;
        address usd;
        address collateralAsset;
        uint256 collateralAmount; // collateralAsset decimals
    }

    struct Transfer {
        address user;
        address asset;
        uint256 chainId;
        uint256 amount; // asset decimals
        bool isDeposit;
        uint64 nonce;
    }

    struct OTCTrade {
        uint256 chainId;
        address user1;
        address user2;
        address asset1;
        address asset2;
        uint256 amount1; // asset1 decimals
        uint256 amount2; // asset2 decimals
        uint64 nonce;
    }

    /// @notice Parse a packed payload into both Quote and Confirmation structs
    /// @dev Parses 344-byte payload into Quote + Confirmation + sigs for both
    /// @dev also returns additional data needed to create an option position
    function parseQuoteAndConfirmation(bytes memory payload)
        public
        view
        returns (Quote memory q, Confirmation memory c, bytes memory quoteSig, bytes memory confSig, uint256 fee)
    {
        // expected length:
        // 20 (maker) + 20 (asset) + 8 (expiry) +
        // 1 (isPut) + 8 (confirmationNonce) + 16 (price) +
        // 16 (quantity) + 8 (quoteNonce) + 65 (quoteSig) +
        // 65 (confSig) + 16 (strike) + 20 (taker) +
        // 1 (isTakerBuy) + 8 (validUntil) + 20 (usd) +
        // 20 (collateralAsset) + 16 (collateralAmount) + 16 (fee)
        // = 344 bytes total
        require(payload.length == 344, "Invalid payload length");

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
            mstore(add(cPtr, 0xA0), mload(add(payload, 57))) // nonce (confirmationNonce)
            mstore(add(cPtr, 0xC0), mload(add(payload, 73))) // price
            mstore(add(cPtr, 0xE0), mload(add(payload, 89))) // quantity
            mstore(add(cPtr, 0x100), mload(add(payload, 97))) // quoteNonce
            mstore(add(cPtr, 0x120), quoteSig) // quoteSignature pointer
            mstore(add(cPtr, 0x140), mload(add(payload, 243))) // strike
            mstore(add(cPtr, 0x160), mload(add(payload, 263))) // taker
            mstore(add(cPtr, 0x180), and(mload(add(payload, 264)), 0xFF)) // isTakerBuy (mask all but last byte)
            mstore(add(cPtr, 0x1A0), mload(add(payload, 292))) // usd
            mstore(add(cPtr, 0x1C0), mload(add(payload, 312))) // collateralAsset
            mstore(add(cPtr, 0x1E0), mload(add(payload, 328))) // collateralAmount

            // --- Quote fields ---
            mstore(qPtr, mload(add(payload, 40))) // assetAddress
            mstore(add(qPtr, 0x20), chainid()) // chainId
            mstore8(add(qPtr, 0x40), and(mload(add(payload, 49)), 0xFF)) // isPut (mask all but last byte)
            mstore(add(qPtr, 0x60), mload(add(payload, 243))) // strike
            mstore(add(qPtr, 0x80), mload(add(payload, 48))) // expiry
            mstore(add(qPtr, 0xA0), mload(add(payload, 20))) // maker
            mstore(add(qPtr, 0xC0), mload(add(payload, 97))) // nonce = quoteNonce
            mstore(add(qPtr, 0xE0), mload(add(payload, 73))) // price
            mstore(add(qPtr, 0x100), mload(add(payload, 89))) // quantity
            mstore(add(qPtr, 0x120), and(mload(add(payload, 264)), 0xFF)) // isTakerBuy (mask all but last byte)
            mstore(add(qPtr, 0x140), mload(add(payload, 272))) // validUntil
            mstore(add(qPtr, 0x160), mload(add(payload, 292))) // usd
            mstore(add(qPtr, 0x180), mload(add(payload, 312))) // collateralAsset

            // --- Extract signatures safely ---
            // Quote signature
            mstore(add(quoteSig, 32), mload(add(payload, 129))) // bytes 0-31
            mstore(add(quoteSig, 64), mload(add(payload, 161))) // bytes 32-63
            mstore8(add(quoteSig, 96), byte(0, mload(add(payload, 193)))) // byte 64

            // Confirmation signature
            mstore(add(confSig, 32), mload(add(payload, 194))) // bytes 0-31
            mstore(add(confSig, 64), mload(add(payload, 226))) // bytes 32-63
            mstore8(add(confSig, 96), byte(0, mload(add(payload, 258)))) // byte 64

            // --- Extract fee ---
            fee := mload(add(payload, 344))
        }

        // --- Cast uint128 → uint256 outside assembly ---
        q.strike = uint256(uint128(q.strike));
        q.price = uint256(uint128(q.price));
        q.quantity = uint256(uint128(q.quantity));

        c.strike = uint256(uint128(c.strike));
        c.price = uint256(uint128(c.price));
        c.quantity = uint256(uint128(c.quantity));
        c.collateralAmount = uint256(uint128(c.collateralAmount));

        fee = uint256(uint128(fee));
    }

    /// @notice Parse a packed payload into a Transfer struct and its signature
    /// @dev Parses 130-byte payload into Transfer + signature
    function parseTransfer(bytes memory payload) public view returns (Transfer memory t, bytes memory sig) {
        // expected length:
        // 20 (asset) + 16 (amount) + 1 (isDeposit) + 8 (nonce) + 65 (sig) +
        // 20 (user)
        // = 130 bytes total
        require(payload.length == 130, "Invalid payload length");

        sig = new bytes(65);

        assembly {
            let tPtr := t

            // --- Transfer fields ---
            mstore(tPtr, mload(add(payload, 130))) // asset
            mstore(add(tPtr, 0x20), mload(add(payload, 20))) // asset
            mstore(add(tPtr, 0x40), chainid()) // chainid
            mstore(add(tPtr, 0x60), mload(add(payload, 36))) // amount
            mstore(add(tPtr, 0x80), and(mload(add(payload, 37)), 0xFF)) // isDeposit (mask all but last byte)
            mstore(add(tPtr, 0xA0), mload(add(payload, 45))) // nonce

            // --- Extract signature ---
            mstore(add(sig, 32), mload(add(payload, 77))) // bytes 0–31
            mstore(add(sig, 64), mload(add(payload, 109))) // bytes 32–63
            mstore8(add(sig, 96), byte(0, mload(add(payload, 141)))) // byte 64
        }

        // Cast uint128 → uint256 for amount
        t.amount = uint256(uint128(t.amount));
    }

    function parseOTCTrade(bytes memory payload) public view returns (OTCTrade memory t, bytes memory sig) {
        // expected length:
        // 20 (user1) + 20 (user2) +
        // 20 (asset1) + 20 (asset2) +
        // 16 (amount1) + 16 (amount2) +
        // 8 (nonce) + 65 (sig)
        // = 185 bytes total

        require(payload.length == 185, "Invalid payload length");

        sig = new bytes(65);

        assembly {
            let tPtr := t

            // --- OTCTrade fields ---
            mstore(tPtr, chainid()) // chainId
            mstore(add(tPtr, 0x20), mload(add(payload, 20))) // user1
            mstore(add(tPtr, 0x40), mload(add(payload, 40))) // user2
            mstore(add(tPtr, 0x60), mload(add(payload, 60))) // asset1
            mstore(add(tPtr, 0x80), mload(add(payload, 80))) // asset2
            mstore(add(tPtr, 0xA0), mload(add(payload, 96))) // amount1
            mstore(add(tPtr, 0xC0), mload(add(payload, 112))) // amount2
            mstore(add(tPtr, 0xE0), mload(add(payload, 120))) // nonce

            // --- Extract signature ---
            mstore(add(sig, 32), mload(add(payload, 152))) // bytes 0-31
            mstore(add(sig, 64), mload(add(payload, 184))) // bytes 32-63
            mstore8(add(sig, 96), byte(0, mload(add(payload, 216)))) // byte 64
        }

        // --- Cast uint128 → uint256 outside assembly ---
        t.amount1 = uint256(uint128(t.amount1));
        t.amount2 = uint256(uint128(t.amount2));
    }
}

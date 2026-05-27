// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "lib/forge-std/src/Test.sol";
import "src/core/libs/Parser.sol";

contract ParserTest is Test {
    function parseTransferClean(bytes memory payload) internal view returns (Parser.Transfer memory t, bytes memory sig) {
        require(payload.length == 130 || payload.length == 150, "Invalid payload length");

        sig = new bytes(65);

        assembly {
            let tPtr := t

            // --- Transfer fields ---
            mstore(tPtr, and(mload(add(payload, 130)), 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)) // user
            mstore(add(tPtr, 0x20), and(mload(add(payload, 20)), 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)) // asset
            mstore(add(tPtr, 0x40), chainid()) // chainid
            mstore(add(tPtr, 0x60), and(mload(add(payload, 36)), 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)) // amount
            mstore(add(tPtr, 0x80), and(mload(add(payload, 37)), 0xFF)) // isDeposit (mask all but last byte)
            mstore(add(tPtr, 0xA0), and(mload(add(payload, 45)), 0xFFFFFFFFFFFFFFFF)) // nonce
            // payer (slot 0xC0) left as zero; populated below for 150-byte payloads

            // --- Extract signature ---
            mstore(add(sig, 32), mload(add(payload, 77))) // bytes 0–31
            mstore(add(sig, 64), mload(add(payload, 109))) // bytes 32–63
            mstore8(add(sig, 96), byte(0, mload(add(payload, 141)))) // byte 64
        }

        // Parse payer from the trailing 20 bytes of the 150-byte variant.
        if (payload.length == 150) {
            assembly {
                mstore(add(t, 0xC0), and(mload(add(payload, 150)), 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)) // payer
            }
        }
    }

    function testParseTransfer() public {
        bytes memory payload = vm.parseBytes("0xea2d8c2c17a36eaa77765505b325e0c8b0918057000000000000000000000000000f19f0010000000069eb3aa37aed731b46da2eb3ef071daf19a8651c3f4bfe4355c04fd6522275410077be2610126da1d6131f29b6118935bfdadec480fe137b16cdc9ed17646c8cf157f8a91cd157f637262b0e6af035baa35a5475e56b100d1b");
        
        (Parser.Transfer memory t, bytes memory sig) = parseTransferClean(payload);
        
        console.log("user:", t.user);
        console.log("asset:", t.asset);
        console.log("amount:", t.amount);
        console.log("isDeposit:", t.isDeposit);
        console.log("nonce:", t.nonce);
        console.log("payer:", t.payer);
        console.logBytes(sig);
        
        // Let's also hash it exactly as done in _getTransferDigest to see the result
        bytes32 TRANSFER_TYPEHASH = keccak256("Transfer(address user,address asset,uint256 chainId,uint256 amount,bool isDeposit,uint64 nonce)");
        bytes32 structHash = keccak256(abi.encode(TRANSFER_TYPEHASH, t.user, t.asset, t.chainId, t.amount, t.isDeposit, t.nonce));
        console.log("structHash:");
        console.logBytes32(structHash);
    }
}

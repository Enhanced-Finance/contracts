// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Parser} from "src/core/libs/Parser.sol";

contract ParserHarness {
    function parseQuoteAndConfirmation(bytes memory payload)
        external
        view
        returns (
            Parser.Quote memory q,
            Parser.Confirmation memory c,
            bytes memory quoteSig,
            bytes memory confSig,
            uint256 protocolFee,
            uint256 makerFee
        )
    {
        return Parser.parseQuoteAndConfirmation(payload);
    }
}

contract ParserQuoteAndConfirmationTest is Test {
    address internal constant PARSER_LIBRARY = 0x848368Aa602C0634900992CBB3fD7B1E040080c0;

    ParserHarness internal harness;

    function setUp() external {
        vm.etch(PARSER_LIBRARY, type(Parser).runtimeCode);
        harness = new ParserHarness();
    }

    function test_parseQuoteAndConfirmation_usesRenamedFeeFields() external view {
        string memory parserSource = vm.readFile(string.concat(vm.projectRoot(), "/src/core/libs/Parser.sol"));

        assertFalse(
            _contains(parserSource, string.concat("taker", "Fee")),
            "parser should not expose the retired taker fee name"
        );
        assertTrue(_contains(parserSource, "protocolFee"), "parser should expose protocolFee");
    }

    function test_parseQuoteAndConfirmation_readsSeparateQuoteAndConfirmationQuantities() external view {
        uint256 quoteQuantity = 11e18;
        uint256 confirmationQuantity = 7e18;

        bytes memory payload = abi.encodePacked(
            address(0x1001),
            address(0x2002),
            uint64(1_775_548_800),
            false,
            false,
            uint64(12),
            uint128(3e17),
            uint128(quoteQuantity),
            uint128(confirmationQuantity),
            uint64(34),
            bytes.concat(bytes32(uint256(0xAA)), bytes32(uint256(0xBB)), bytes1(0x1b)),
            bytes.concat(bytes32(uint256(0xCC)), bytes32(uint256(0xDD)), bytes1(0x1c)),
            uint128(4_601_520),
            address(0x3003),
            true,
            uint64(1_800_000_000),
            address(0x4004),
            address(0x5005),
            uint128(13e18),
            uint128(2e16),
            uint128(3e16)
        );

        (Parser.Quote memory q, Parser.Confirmation memory c,,, uint256 protocolFee, uint256 makerFee) =
            harness.parseQuoteAndConfirmation(payload);

        assertEq(payload.length, 377);
        assertEq(q.quantity, quoteQuantity);
        assertEq(c.quantity, confirmationQuantity);
        assertEq(protocolFee, 2e16);
        assertEq(makerFee, 3e16);
    }

    function test_parseQuoteAndConfirmation_rejectsLegacyPayloadLength() external {
        bytes memory legacyPayload = abi.encodePacked(
            address(0x1001),
            address(0x2002),
            uint64(1_775_548_800),
            false,
            false,
            uint64(12),
            uint128(3e17),
            uint128(7e18),
            uint64(34),
            bytes.concat(bytes32(uint256(0xAA)), bytes32(uint256(0xBB)), bytes1(0x1b)),
            bytes.concat(bytes32(uint256(0xCC)), bytes32(uint256(0xDD)), bytes1(0x1c)),
            uint128(4_601_520),
            address(0x3003),
            true,
            uint64(1_800_000_000),
            address(0x4004),
            address(0x5005),
            uint128(13e18),
            uint128(2e16)
        );

        vm.expectRevert();
        harness.parseQuoteAndConfirmation(legacyPayload);
    }

    function _contains(string memory text, string memory needle) internal pure returns (bool) {
        bytes memory textBytes = bytes(text);
        bytes memory needleBytes = bytes(needle);
        if (needleBytes.length > textBytes.length) return false;

        for (uint256 i; i <= textBytes.length - needleBytes.length; i++) {
            bool matches = true;
            for (uint256 j; j < needleBytes.length; j++) {
                if (textBytes[i + j] != needleBytes[j]) {
                    matches = false;
                    break;
                }
            }
            if (matches) return true;
        }
        return false;
    }
}

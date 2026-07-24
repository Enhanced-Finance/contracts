// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "lib/forge-std/src/Test.sol";

contract DeprecatedEnhancedOptionsFeaturesTest is Test {
    function testRetiredContractAndParserNamesAreAbsent() external view {
        string memory optionsSource = vm.readFile("src/core/EnhancedOptions.sol");
        string memory parserSource = vm.readFile("src/core/libs/Parser.sol");

        assertFalse(_contains(optionsSource, "enhancedSigner"), "enhanced signer remains in EnhancedOptions");
        assertFalse(_contains(optionsSource, "OTC_TRADE_TYPE"), "OTC type remains in EnhancedOptions");
        assertFalse(_contains(optionsSource, "getOTCTradeDigest"), "OTC digest remains in EnhancedOptions");
        assertFalse(
            _contains(optionsSource, "_retrieveOtokenForFlashLoanRedeem"),
            "flash-loan redeem helper remains in EnhancedOptions"
        );
        assertFalse(_contains(optionsSource, "NotSupported"), "retired NotSupported error remains in EnhancedOptions");
        assertFalse(_contains(parserSource, "OTCTrade"), "OTC parser surface remains");
    }

    function testRetiredScriptAndMakeTargetsAreAbsent() external view {
        string memory configureScript = vm.readFile("script/EnhancedOptions/ConfigureEnhancedOptions.s.sol");
        string memory makefile = vm.readFile("Makefile");

        assertFalse(_contains(configureScript, "enhancedSigner"), "configure script still uses enhanced signer");
        assertFalse(_contains(makefile, "ingresso_otc_trade"), "stale OTC Make target remains");
    }

    function testRetiredEnhancedOptionsConfigKeysAreAbsent() external view {
        _assertRetiredConfigKeysAbsent(vm.readFile("config/11155111.json"));
        _assertRetiredConfigKeysAbsent(vm.readFile("config/1328.json"));
    }

    function _assertRetiredConfigKeysAbsent(string memory json) internal view {
        assertFalse(vm.keyExistsJson(json, ".EnhancedOptions.enhancedSigner"), "enhancedSigner config key remains");
        assertFalse(vm.keyExistsJson(json, ".EnhancedOptions.flashLoanPool"), "flashLoanPool config key remains");
        assertFalse(vm.keyExistsJson(json, ".EnhancedOptions.swapRouter"), "Options swapRouter config key remains");
        assertFalse(
            vm.keyExistsJson(json, ".EnhancedOptions.flashLoanRedeemPeriodStart"),
            "flashLoanRedeemPeriodStart config key remains"
        );
    }

    function _contains(string memory value, string memory needle) internal pure returns (bool) {
        bytes memory valueBytes = bytes(value);
        bytes memory needleBytes = bytes(needle);

        if (needleBytes.length == 0 || needleBytes.length > valueBytes.length) return false;

        for (uint256 i = 0; i <= valueBytes.length - needleBytes.length; i++) {
            bool matches = true;
            for (uint256 j = 0; j < needleBytes.length; j++) {
                if (valueBytes[i + j] != needleBytes[j]) {
                    matches = false;
                    break;
                }
            }
            if (matches) return true;
        }

        return false;
    }
}

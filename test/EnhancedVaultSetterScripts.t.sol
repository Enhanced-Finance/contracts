// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {SetEnhancedOptions} from "../script/EnhancedVault/optionals/SetEnhancedOptions.s.sol";
import {SetVaultProtocolFeeRate} from "../script/EnhancedVault/optionals/SetVaultProtocolFeeRate.s.sol";

contract EnhancedVaultSetterScriptsTest is Test {
    function testVaultSetterScripts_ShouldBeDeployable() external {
        assertTrue(address(new SetEnhancedOptions()) != address(0));
        assertTrue(address(new SetVaultProtocolFeeRate()) != address(0));
    }
}

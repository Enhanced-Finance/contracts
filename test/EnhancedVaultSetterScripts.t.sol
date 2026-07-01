// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {SetEnhancedOptions} from "../script/EnhancedVault/optionals/SetEnhancedOptions.s.sol";

contract EnhancedVaultSetterScriptsTest is Test {
    function testSetEnhancedOptionsScript_ShouldBeDeployable() external {
        assertTrue(address(new SetEnhancedOptions()) != address(0));
    }
}

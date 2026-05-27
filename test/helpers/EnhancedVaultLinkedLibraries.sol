// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {EnhancedVaultCycleLib} from "../../src/periphery/vault/libs/EnhancedVaultCycleLib.sol";
import {EnhancedVaultRecordsLib} from "../../src/periphery/vault/libs/EnhancedVaultRecordsLib.sol";

abstract contract EnhancedVaultLinkedLibraries is Test {
    address internal constant ENHANCED_VAULT_RECORDS_LIBRARY_PLACEHOLDER = 0x644Dea82274Fa367f061216E7bB9a582af8E937D;
    address internal constant ENHANCED_VAULT_CYCLE_LIBRARY_PLACEHOLDER = 0xfe533b0e5Df0450c53e5EdB9A85944fF8E7D8e38;

    function _etchEnhancedVaultLibraries() internal {
        vm.etch(ENHANCED_VAULT_RECORDS_LIBRARY_PLACEHOLDER, type(EnhancedVaultRecordsLib).runtimeCode);
        vm.etch(ENHANCED_VAULT_CYCLE_LIBRARY_PLACEHOLDER, type(EnhancedVaultCycleLib).runtimeCode);
    }
}

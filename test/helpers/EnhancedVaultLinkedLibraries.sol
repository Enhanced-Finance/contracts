// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {EnhancedVaultCycleLib} from "../../src/periphery/vault/libs/EnhancedVaultCycleLib.sol";
import {EnhancedVaultRecordsLib} from "../../src/periphery/vault/libs/EnhancedVaultRecordsLib.sol";

abstract contract EnhancedVaultLinkedLibraries is Test {
    address internal constant ENHANCED_VAULT_RECORDS_LIBRARY_PLACEHOLDER = 0x7930ab9Bdd4bc04e1fe3B1102A0915b4A74904A8;
    address internal constant ENHANCED_VAULT_RECORDS_LIBRARY_CURRENT = 0xF1078cfca9EB0119e9dA321e21Ab61D50C6b4b79;
    address internal constant ENHANCED_VAULT_CYCLE_LIBRARY_PLACEHOLDER = 0x497c8513AB92cAb4d645637587c64e033D825bb1;
    address internal constant ENHANCED_VAULT_CYCLE_LIBRARY_LEGACY = 0x14202F50753e90Cd9192C703c908Ef7CaBE91354;
    address internal constant ENHANCED_VAULT_CYCLE_LIBRARY_CURRENT = 0x6281EDA7967415D31A03F10818a470028dd7a4B1;
    address internal constant ENHANCED_VAULT_CYCLE_LIBRARY_CURRENT_2 = 0x36A621f3Af6Ba0E2adcE886595516d4Fc782C972;

    function _etchEnhancedVaultLibraries() internal {
        vm.etch(ENHANCED_VAULT_RECORDS_LIBRARY_PLACEHOLDER, type(EnhancedVaultRecordsLib).runtimeCode);
        vm.etch(ENHANCED_VAULT_RECORDS_LIBRARY_CURRENT, type(EnhancedVaultRecordsLib).runtimeCode);
        vm.etch(ENHANCED_VAULT_CYCLE_LIBRARY_PLACEHOLDER, type(EnhancedVaultCycleLib).runtimeCode);
        vm.etch(ENHANCED_VAULT_CYCLE_LIBRARY_LEGACY, type(EnhancedVaultCycleLib).runtimeCode);
        vm.etch(ENHANCED_VAULT_CYCLE_LIBRARY_CURRENT, type(EnhancedVaultCycleLib).runtimeCode);
        vm.etch(ENHANCED_VAULT_CYCLE_LIBRARY_CURRENT_2, type(EnhancedVaultCycleLib).runtimeCode);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console} from "forge-std/Script.sol";
import {EnhancedVault} from "src/periphery/vault/EnhancedVault.sol";
import {BaseEnhancedVaultScript} from "./BaseEnhancedVaultScript.s.sol";

/// @notice Compatibility wrapper around the three-step cycle flow:
/// settlePreviousCycle -> processQueuedUsers (paged) -> startNextCycle.
/// Prefer explicit step scripts for ops (`SettlePreviousCycle/ProcessQueuedUsers/StartNextCycle`).
contract NextCycle is BaseEnhancedVaultScript {
    bytes32 constant VAULT_HASH = 0x9832d172f61a4ac7cca7bad266a425d65bcb8fb83a3d195c378972572c5f2c3b;
    uint256 constant PROCESS_LIMIT = 100;

    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        (EnhancedVault vault, address vaultAddr) = _loadVault();

        console.log("EnhancedVault:", vaultAddr);
        console.log("vaultHash:", vm.toString(VAULT_HASH));

        vm.startBroadcast(privateKey);
        vault.settlePreviousCycle(VAULT_HASH);

        (,,, uint256 remaining,) = vault.getQueueProgress(VAULT_HASH);
        uint256 offset;
        while (remaining > 0) {
            uint256 batch = remaining > PROCESS_LIMIT ? PROCESS_LIMIT : remaining;
            vault.processQueuedUsers(VAULT_HASH, offset, batch);
            offset += batch;
            (,,, remaining,) = vault.getQueueProgress(VAULT_HASH);
        }

        vault.startNextCycle(VAULT_HASH);
        vm.stopBroadcast();
    }
}

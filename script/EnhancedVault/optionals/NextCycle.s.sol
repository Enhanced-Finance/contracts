// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console} from "forge-std/Script.sol";
import {EnhancedVault} from "src/periphery/vault/EnhancedVault.sol";
import {BaseEnhancedVaultScript} from "./BaseEnhancedVaultScript.s.sol";

/// @notice Compatibility wrapper around the three-step cycle flow:
/// settlePreviousCycle -> processQueuedUsers (paged) -> startNextCycle.
/// Prefer explicit step scripts for ops (`SettlePreviousCycle/ProcessQueuedUsers/StartNextCycle`).
contract NextCycle is BaseEnhancedVaultScript {
    uint256 constant PROCESS_LIMIT = 100;

    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        bytes32 vaultHash = vm.envBytes32("VAULT_HASH");
        (EnhancedVault vault, address vaultAddr) = _loadVault();

        console.log("EnhancedVault:", vaultAddr);
        console.log("vaultHash:", vm.toString(vaultHash));

        vm.startBroadcast(privateKey);
        vault.settlePreviousCycle(vaultHash);

        (,,, uint256 remaining,) = vault.getQueueProgress(vaultHash);
        uint256 offset;
        while (remaining > 0) {
            uint256 batch = remaining > PROCESS_LIMIT ? PROCESS_LIMIT : remaining;
            vault.processQueuedUsers(vaultHash, offset, batch);
            offset += batch;
            (,,, remaining,) = vault.getQueueProgress(vaultHash);
        }

        vault.startNextCycle(vaultHash);
        vm.stopBroadcast();
    }
}

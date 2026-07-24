// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console} from "forge-std/Script.sol";
import {EnhancedVault} from "src/periphery/vault/EnhancedVault.sol";
import {BaseEnhancedVaultScript} from "./BaseEnhancedVaultScript.s.sol";

contract SystemPauseFunds is BaseEnhancedVaultScript {
    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        bytes32 vaultHash = vm.envBytes32("VAULT_HASH");
        (EnhancedVault vault, address vaultAddr) = _loadVault();

        // --- Configuration: populate users before running ---
        address[] memory users = vm.envAddress("USERS", ",");
        // ----------------------------------------------------

        console.log("EnhancedVault:", vaultAddr);
        console.log("vaultHash:", vm.toString(vaultHash));
        console.log("users count:", users.length);

        vm.startBroadcast(privateKey);
        vault.systemPauseFunds(vaultHash, users);
        vm.stopBroadcast();
    }
}

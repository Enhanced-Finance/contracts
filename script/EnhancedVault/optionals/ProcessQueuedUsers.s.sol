// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console} from "forge-std/Script.sol";
import {EnhancedVault} from "src/periphery/vault/EnhancedVault.sol";
import {BaseEnhancedVaultScript} from "./BaseEnhancedVaultScript.s.sol";

contract ProcessQueuedUsers is BaseEnhancedVaultScript {
    uint256 constant OFFSET = 0;
    uint256 constant LIMIT = 100;

    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        bytes32 vaultHash = vm.envBytes32("VAULT_HASH");
        (EnhancedVault vault, address vaultAddr) = _loadVault();

        console.log("EnhancedVault:", vaultAddr);
        console.log("vaultHash:", vm.toString(vaultHash));
        console.log("offset:", OFFSET);
        console.log("limit:", LIMIT);

        vm.startBroadcast(privateKey);
        vault.processQueuedUsers(vaultHash, OFFSET, LIMIT);
        vm.stopBroadcast();
    }
}

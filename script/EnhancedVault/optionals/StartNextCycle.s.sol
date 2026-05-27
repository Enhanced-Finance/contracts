// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console} from "forge-std/Script.sol";
import {EnhancedVault} from "src/periphery/vault/EnhancedVault.sol";
import {BaseEnhancedVaultScript} from "./BaseEnhancedVaultScript.s.sol";

contract StartNextCycle is BaseEnhancedVaultScript {
    bytes32 constant VAULT_HASH = 0x62636cc6f993b3d3f0b9eedb473ce0bc98695e5bd02e667fa6b3552c5f5b7c29;

    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        (EnhancedVault vault, address vaultAddr) = _loadVault();

        console.log("EnhancedVault:", vaultAddr);
        console.log("vaultHash:", vm.toString(VAULT_HASH));

        vm.startBroadcast(privateKey);
        vault.startNextCycle(VAULT_HASH);
        vm.stopBroadcast();
    }
}


// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console} from "forge-std/Script.sol";
import {EnhancedVault} from "src/periphery/vault/EnhancedVault.sol";
import {BaseEnhancedVaultScript} from "./BaseEnhancedVaultScript.s.sol";

contract SetVaultActive is BaseEnhancedVaultScript {
    bool constant IS_ACTIVE = true;

    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        bytes32 vaultHash = vm.envBytes32("VAULT_HASH");
        (EnhancedVault vault, address vaultAddr) = _loadVault();

        console.log("EnhancedVault:", vaultAddr);
        console.log("vaultHash:", vm.toString(vaultHash));
        console.log("isActive:", IS_ACTIVE);

        vm.startBroadcast(privateKey);
        vault.setVaultActive(vaultHash, IS_ACTIVE);
        vm.stopBroadcast();
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console} from "forge-std/Script.sol";
import {EnhancedVault} from "src/periphery/vault/EnhancedVault.sol";
import {BaseEnhancedVaultScript} from "./BaseEnhancedVaultScript.s.sol";

contract SetVaultSigner is BaseEnhancedVaultScript {
    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address newVaultSigner = vm.envAddress("NEW_VAULT_SIGNER");
        (EnhancedVault vault, address vaultAddr) = _loadVault();

        console.log("EnhancedVault:", vaultAddr);
        console.log("newVaultSigner:", newVaultSigner);

        vm.startBroadcast(privateKey);
        vault.setVaultSigner(newVaultSigner);
        vm.stopBroadcast();
    }
}

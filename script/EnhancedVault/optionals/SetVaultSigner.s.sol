// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console} from "forge-std/Script.sol";
import {EnhancedVault} from "src/periphery/vault/EnhancedVault.sol";
import {BaseEnhancedVaultScript} from "./BaseEnhancedVaultScript.s.sol";

contract SetVaultSigner is BaseEnhancedVaultScript {
    address constant NEW_VAULT_SIGNER = 0x591e577E688f0Ec1F93B9Cc6E31D16472807aE8d;

    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        (EnhancedVault vault, address vaultAddr) = _loadVault();

        console.log("EnhancedVault:", vaultAddr);
        console.log("newVaultSigner:", NEW_VAULT_SIGNER);

        vm.startBroadcast(privateKey);
        vault.setVaultSigner(NEW_VAULT_SIGNER);
        vm.stopBroadcast();
    }
}


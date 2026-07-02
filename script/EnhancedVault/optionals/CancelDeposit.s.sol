// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console} from "forge-std/Script.sol";
import {EnhancedVault} from "src/periphery/vault/EnhancedVault.sol";
import {BaseEnhancedVaultScript} from "./BaseEnhancedVaultScript.s.sol";

contract CancelDeposit is BaseEnhancedVaultScript {
    function run() public {
        uint256 privateKey = vm.envUint("TAKER_PRIVATE_KEY");
        bytes32 vaultHash = vm.envBytes32("VAULT_HASH");
        uint256 depositRecordId = vm.envUint("DEPOSIT_RECORD_ID");
        (EnhancedVault vault, address vaultAddr) = _loadVault();

        console.log("EnhancedVault:", vaultAddr);
        console.log("vaultHash:", vm.toString(vaultHash));
        console.log("depositRecordId:", vm.toString(depositRecordId));

        vm.startBroadcast(privateKey);
        vault.cancelDeposit(vaultHash, depositRecordId);
        vm.stopBroadcast();
    }
}

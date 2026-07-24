// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console} from "forge-std/Script.sol";
import {EnhancedVault} from "src/periphery/vault/EnhancedVault.sol";
import {BaseEnhancedVaultScript} from "./BaseEnhancedVaultScript.s.sol";

contract WithdrawFund is BaseEnhancedVaultScript {
    uint256 constant AMOUNT = 1e18;

    function run() public {
        uint256 privateKey = vm.envUint("TAKER_PRIVATE_KEY");
        bytes32 vaultHash = vm.envBytes32("VAULT_HASH");
        (EnhancedVault vault, address vaultAddr) = _loadVault();

        console.log("EnhancedVault:", vaultAddr);
        console.log("vaultHash:", vm.toString(vaultHash));

        vm.startBroadcast(privateKey);
        vault.withdraw(vaultHash, AMOUNT);
        vm.stopBroadcast();
    }
}

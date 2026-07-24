// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console} from "forge-std/Script.sol";
import {EnhancedVault} from "src/periphery/vault/EnhancedVault.sol";
import {BaseEnhancedVaultScript} from "./BaseEnhancedVaultScript.s.sol";

contract SetVaultProtocolFeeRate is BaseEnhancedVaultScript {
    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        bytes32 vaultHash = vm.envBytes32("VAULT_HASH");
        uint256 protocolFeeRate = vm.envUint("PROTOCOL_FEE_RATE"); // precision: 10000000 (100000 = 1%)
        (EnhancedVault vault, address vaultAddr) = _loadVault();

        console.log("EnhancedVault:", vaultAddr);
        console.log("vaultHash:", vm.toString(vaultHash));
        console.log("protocolFeeRate:", protocolFeeRate);

        vm.startBroadcast(privateKey);
        vault.setVaultProtocolFeeRate(vaultHash, protocolFeeRate);
        vm.stopBroadcast();
    }
}

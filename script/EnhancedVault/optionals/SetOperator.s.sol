// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console} from "forge-std/Script.sol";
import {EnhancedVault} from "src/periphery/vault/EnhancedVault.sol";
import {BaseEnhancedVaultScript} from "./BaseEnhancedVaultScript.s.sol";

contract SetOperator is BaseEnhancedVaultScript {
    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address newOperator = vm.envAddress("NEW_OPERATOR");
        (EnhancedVault vault, address vaultAddr) = _loadVault();

        console.log("EnhancedVault:", vaultAddr);
        console.log("newOperator:", newOperator);

        vm.startBroadcast(privateKey);
        vault.setOperator(newOperator);
        vm.stopBroadcast();
    }
}

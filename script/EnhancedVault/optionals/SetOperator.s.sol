// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console} from "forge-std/Script.sol";
import {EnhancedVault} from "src/periphery/vault/EnhancedVault.sol";
import {BaseEnhancedVaultScript} from "./BaseEnhancedVaultScript.s.sol";

contract SetOperator is BaseEnhancedVaultScript {
    address constant NEW_OPERATOR = 0x591e577E688f0Ec1F93B9Cc6E31D16472807aE8d;

    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        (EnhancedVault vault, address vaultAddr) = _loadVault();

        console.log("EnhancedVault:", vaultAddr);
        console.log("newOperator:", NEW_OPERATOR);

        vm.startBroadcast(privateKey);
        vault.setOperator(NEW_OPERATOR);
        vm.stopBroadcast();
    }
}


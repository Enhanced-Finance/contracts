// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console} from "forge-std/Script.sol";
import {EnhancedVault} from "src/periphery/vault/EnhancedVault.sol";
import {BaseEnhancedVaultScript} from "./BaseEnhancedVaultScript.s.sol";

contract SetSwapRouter is BaseEnhancedVaultScript {
    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address newSwapRouter = vm.envAddress("NEW_SWAP_ROUTER");
        (EnhancedVault vault, address vaultAddr) = _loadVault();

        console.log("EnhancedVault:", vaultAddr);
        console.log("newSwapRouter:", newSwapRouter);

        vm.startBroadcast(privateKey);
        vault.setSwapRouter(newSwapRouter);
        vm.stopBroadcast();
    }
}

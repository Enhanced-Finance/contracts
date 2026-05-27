// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console} from "forge-std/Script.sol";
import {EnhancedVault} from "src/periphery/vault/EnhancedVault.sol";
import {BaseEnhancedVaultScript} from "./BaseEnhancedVaultScript.s.sol";

contract SetSwapRouter is BaseEnhancedVaultScript {
    address constant NEW_SWAP_ROUTER = 0xB76104Fc40b933C28FDB02E48B1242A78ca1b411;

    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        (EnhancedVault vault, address vaultAddr) = _loadVault();

        console.log("EnhancedVault:", vaultAddr);
        console.log("newSwapRouter:", NEW_SWAP_ROUTER);

        vm.startBroadcast(privateKey);
        vault.setSwapRouter(NEW_SWAP_ROUTER);
        vm.stopBroadcast();
    }
}


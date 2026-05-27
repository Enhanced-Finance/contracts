// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console} from "forge-std/Script.sol";
import {EnhancedVault} from "src/periphery/vault/EnhancedVault.sol";
import {BaseEnhancedVaultScript} from "./BaseEnhancedVaultScript.s.sol";

contract SetAssetApprovalRouter is BaseEnhancedVaultScript {
    // Asset to approve/revoke for swapRouter spending.
    address constant ASSET = 0x134b5f74d65a34eb6F9CdaD5eD664b45A167cC43;
    bool constant APPROVAL = true;

    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        (EnhancedVault vault, address vaultAddr) = _loadVault();

        console.log("EnhancedVault:", vaultAddr);
        console.log("asset:", ASSET);
        console.log("approval:", APPROVAL);

        vm.startBroadcast(privateKey);
        vault.setAssetApprovalSwapRouter(ASSET, APPROVAL);
        vm.stopBroadcast();
    }
}

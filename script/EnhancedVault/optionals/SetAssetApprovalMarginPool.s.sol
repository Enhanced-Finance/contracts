// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console} from "forge-std/Script.sol";
import {EnhancedVault} from "src/periphery/vault/EnhancedVault.sol";
import {BaseEnhancedVaultScript} from "./BaseEnhancedVaultScript.s.sol";

contract SetAssetApproval is BaseEnhancedVaultScript {
    // Asset to approve/revoke for marginPool spending.
    address ASSET = vm.envAddress("UNDERLYING");
    bool constant APPROVAL = true;

    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        (EnhancedVault vault, address vaultAddr) = _loadVault();

        console.log("EnhancedVault:", vaultAddr);
        console.log("asset:", ASSET);
        console.log("approval:", APPROVAL);

        vm.startBroadcast(privateKey);
        vault.setAssetApprovalMarginPool(ASSET, APPROVAL);
        vm.stopBroadcast();
    }
}

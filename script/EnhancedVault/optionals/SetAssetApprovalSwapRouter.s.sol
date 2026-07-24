// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console} from "forge-std/Script.sol";
import {EnhancedVault} from "src/periphery/vault/EnhancedVault.sol";
import {BaseEnhancedVaultScript} from "./BaseEnhancedVaultScript.s.sol";

contract SetAssetApprovalRouter is BaseEnhancedVaultScript {
    bool constant APPROVAL = true;

    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address asset = vm.envAddress("ASSET");
        (EnhancedVault vault, address vaultAddr) = _loadVault();

        console.log("EnhancedVault:", vaultAddr);
        console.log("asset:", asset);
        console.log("approval:", APPROVAL);

        vm.startBroadcast(privateKey);
        vault.setAssetApprovalSwapRouter(asset, APPROVAL);
        vm.stopBroadcast();
    }
}

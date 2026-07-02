// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console} from "forge-std/Script.sol";
import {EnhancedOptions} from "src/core/EnhancedOptions.sol";
import {BaseEnhancedOptionsScript} from "./BaseEnhancedOptionsScript.s.sol";

contract SetAssetApproval is BaseEnhancedOptionsScript {
    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address asset = vm.envAddress("ASSET");
        bool approval = vm.envBool("APPROVAL");
        (EnhancedOptions enhancedOptions, address enhancedOptionsAddr) = _loadEnhancedOptions();

        console.log("EnhancedOptions:", enhancedOptionsAddr);
        console.log("asset:", asset);
        console.log("approval:", approval);

        vm.startBroadcast(privateKey);
        enhancedOptions.setAssetApproval(asset, approval);
        vm.stopBroadcast();
    }
}

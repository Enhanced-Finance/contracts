// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console} from "forge-std/Script.sol";
import {EnhancedOptions} from "src/core/EnhancedOptions.sol";
import {BaseEnhancedOptionsScript} from "./BaseEnhancedOptionsScript.s.sol";

contract SetMarginPool is BaseEnhancedOptionsScript {
    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address newMarginPool = vm.envAddress("NEW_MARGIN_POOL");
        (EnhancedOptions enhancedOptions, address enhancedOptionsAddr) = _loadEnhancedOptions();

        console.log("EnhancedOptions:", enhancedOptionsAddr);
        console.log("newMarginPool:", newMarginPool);

        vm.startBroadcast(privateKey);
        enhancedOptions.setMarginPool(newMarginPool);
        vm.stopBroadcast();
    }
}

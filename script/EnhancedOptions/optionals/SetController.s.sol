// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console} from "forge-std/Script.sol";
import {EnhancedOptions} from "src/core/EnhancedOptions.sol";
import {BaseEnhancedOptionsScript} from "./BaseEnhancedOptionsScript.s.sol";

contract SetController is BaseEnhancedOptionsScript {
    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address newController = vm.envAddress("NEW_CONTROLLER");
        (EnhancedOptions enhancedOptions, address enhancedOptionsAddr) = _loadEnhancedOptions();

        console.log("EnhancedOptions:", enhancedOptionsAddr);
        console.log("newController:", newController);

        vm.startBroadcast(privateKey);
        enhancedOptions.setController(newController);
        vm.stopBroadcast();
    }
}

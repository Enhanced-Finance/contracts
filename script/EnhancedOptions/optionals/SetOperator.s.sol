// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console} from "forge-std/Script.sol";
import {EnhancedOptions} from "src/core/EnhancedOptions.sol";
import {BaseEnhancedOptionsScript} from "./BaseEnhancedOptionsScript.s.sol";

contract SetOperator is BaseEnhancedOptionsScript {
    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address newOperator = vm.envAddress("NEW_OPERATOR");
        (EnhancedOptions enhancedOptions, address enhancedOptionsAddr) = _loadEnhancedOptions();

        console.log("EnhancedOptions:", enhancedOptionsAddr);
        console.log("newOperator:", newOperator);

        vm.startBroadcast(privateKey);
        enhancedOptions.setOperator(newOperator);
        vm.stopBroadcast();
    }
}

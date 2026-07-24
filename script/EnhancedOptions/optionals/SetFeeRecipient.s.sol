// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console} from "forge-std/Script.sol";
import {EnhancedOptions} from "src/core/EnhancedOptions.sol";
import {BaseEnhancedOptionsScript} from "./BaseEnhancedOptionsScript.s.sol";

contract SetFeeRecipient is BaseEnhancedOptionsScript {
    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address newFeeRecipient = vm.envAddress("NEW_FEE_RECIPIENT");
        (EnhancedOptions enhancedOptions, address enhancedOptionsAddr) = _loadEnhancedOptions();

        console.log("EnhancedOptions:", enhancedOptionsAddr);
        console.log("newFeeRecipient:", newFeeRecipient);

        vm.startBroadcast(privateKey);
        enhancedOptions.setFeeRecipient(newFeeRecipient);
        vm.stopBroadcast();
    }
}

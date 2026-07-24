// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console} from "forge-std/Script.sol";
import {EnhancedOptions} from "src/core/EnhancedOptions.sol";
import {BaseEnhancedOptionsScript} from "./BaseEnhancedOptionsScript.s.sol";

contract SetMMarket is BaseEnhancedOptionsScript {
    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address newMMarket = vm.envAddress("NEW_MMARKET");
        (EnhancedOptions enhancedOptions, address enhancedOptionsAddr) = _loadEnhancedOptions();

        console.log("EnhancedOptions:", enhancedOptionsAddr);
        console.log("newMMarket:", newMMarket);

        vm.startBroadcast(privateKey);
        enhancedOptions.setMMarket(newMMarket);
        vm.stopBroadcast();
    }
}

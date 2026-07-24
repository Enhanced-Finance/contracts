// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console} from "forge-std/Script.sol";
import {EnhancedOptions} from "src/core/EnhancedOptions.sol";
import {BaseEnhancedOptionsScript} from "./BaseEnhancedOptionsScript.s.sol";

contract SetTrustedTaker is BaseEnhancedOptionsScript {
    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address taker = vm.envAddress("TAKER");
        bool trusted = vm.envBool("TRUSTED");
        (EnhancedOptions enhancedOptions, address enhancedOptionsAddr) = _loadEnhancedOptions();

        console.log("EnhancedOptions:", enhancedOptionsAddr);
        console.log("taker:", taker);
        console.log("trusted:", trusted);

        vm.startBroadcast(privateKey);
        enhancedOptions.setTrustedTaker(taker, trusted);
        vm.stopBroadcast();
    }
}

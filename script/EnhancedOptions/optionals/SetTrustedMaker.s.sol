// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console} from "forge-std/Script.sol";
import {EnhancedOptions} from "src/core/EnhancedOptions.sol";
import {BaseEnhancedOptionsScript} from "./BaseEnhancedOptionsScript.s.sol";

contract SetTrustedMaker is BaseEnhancedOptionsScript {
    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address maker = vm.envAddress("MAKER");
        bool trusted = vm.envBool("TRUSTED");
        (EnhancedOptions enhancedOptions, address enhancedOptionsAddr) = _loadEnhancedOptions();

        console.log("EnhancedOptions:", enhancedOptionsAddr);
        console.log("maker:", maker);
        console.log("trusted:", trusted);

        vm.startBroadcast(privateKey);
        enhancedOptions.setTrustedMaker(maker, trusted);
        vm.stopBroadcast();
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console} from "forge-std/Script.sol";
import {EnhancedOptions} from "src/core/EnhancedOptions.sol";
import {BaseEnhancedOptionsScript} from "./BaseEnhancedOptionsScript.s.sol";

contract SetMakerCustodyLimitBps is BaseEnhancedOptionsScript {
    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address maker = vm.envAddress("MAKER");
        address receiver = vm.envAddress("RECEIVER");
        uint256 bps = vm.envUint("BPS");
        (EnhancedOptions enhancedOptions, address enhancedOptionsAddr) = _loadEnhancedOptions();

        console.log("EnhancedOptions:", enhancedOptionsAddr);
        console.log("maker:", maker);
        console.log("receiver:", receiver);
        console.log("bps:", bps);

        vm.startBroadcast(privateKey);
        enhancedOptions.setMakerCustodyLimitBps(maker, receiver, bps);
        vm.stopBroadcast();
    }
}

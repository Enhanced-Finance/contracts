// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {EnhancedOptions} from "src/core/EnhancedOptions.sol";

abstract contract BaseEnhancedOptionsScript is Script {
    using stdJson for string;

    function _loadEnhancedOptions()
        internal
        view
        returns (EnhancedOptions enhancedOptions, address enhancedOptionsAddr)
    {
        string memory chainIdStr = vm.toString(block.chainid);
        string memory deployPath = string.concat(vm.projectRoot(), "/.deploy/", chainIdStr, ".json");

        require(vm.isFile(deployPath), "Deploy file not found");
        string memory deployJson = vm.readFile(deployPath);
        enhancedOptionsAddr = deployJson.readAddress(".EnhancedOptions.proxyAddress");
        require(enhancedOptionsAddr != address(0), "EnhancedOptions proxy not found");

        enhancedOptions = EnhancedOptions(enhancedOptionsAddr);
    }
}

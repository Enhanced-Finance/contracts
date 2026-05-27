// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {EnhancedVault} from "src/periphery/vault/EnhancedVault.sol";

abstract contract BaseEnhancedVaultScript is Script {
    using stdJson for string;

    function _loadVault() internal view returns (EnhancedVault vault, address vaultAddr) {
        string memory chainIdStr = vm.toString(block.chainid);
        string memory deployPath = string.concat(vm.projectRoot(), "/.deploy/", chainIdStr, ".json");

        require(vm.isFile(deployPath), "Deploy file not found");
        string memory deployJson = vm.readFile(deployPath);
        vaultAddr = deployJson.readAddress(".EnhancedVault.proxyAddress");
        require(vaultAddr != address(0), "EnhancedVault proxy not found");

        vault = EnhancedVault(vaultAddr);
    }
}


// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console} from "forge-std/Script.sol";
import {EnhancedVault} from "src/periphery/vault/EnhancedVault.sol";
import {BaseEnhancedVaultScript} from "./BaseEnhancedVaultScript.s.sol";
import {Strings} from "lib/openzeppelin-contracts/contracts/utils/Strings.sol";
import {stdJson} from "forge-std/StdJson.sol";

contract SetEnhancedOptions is BaseEnhancedVaultScript {
    using Strings for address;
    using stdJson for string;

    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");

        string memory chainIdStr = vm.toString(block.chainid);
        string memory deployDir = string.concat(vm.projectRoot(), "/.deploy/");

        if (!vm.isDir(deployDir)) {
            vm.createDir(deployDir, true);
        }

        string memory path = string.concat(deployDir, chainIdStr, ".json");
        string memory json = vm.readFile(path);

        // Resolve EnhancedOptions address: .deploy file takes priority, else env var
        address enhancedOptions;
        if (vm.keyExists(json, ".EnhancedOptions.proxyAddress")) {
            enhancedOptions = json.readAddress(".EnhancedOptions.proxyAddress");
        }
        if (enhancedOptions == address(0)) {
            enhancedOptions = vm.envAddress("VAULT_ENHANCED_OPTIONS");
        }
        require(enhancedOptions != address(0), "EnhancedOptions address not found");

        (EnhancedVault vault, address vaultAddr) = _loadVault();

        console.log("EnhancedVault:", vaultAddr);
        console.log("newEnhancedOptions:", enhancedOptions);

        vm.startBroadcast(privateKey);
        vault.setEnhancedOptions(enhancedOptions);
        vm.stopBroadcast();
    }
}

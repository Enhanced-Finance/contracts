// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console} from "forge-std/Script.sol";
import {EnhancedVault} from "src/periphery/vault/EnhancedVault.sol";
import {BaseEnhancedVaultScript} from "./BaseEnhancedVaultScript.s.sol";
import {stdJson} from "forge-std/StdJson.sol";

contract SetMarginPool is BaseEnhancedVaultScript {
    using stdJson for string;

    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        string memory chainIdStr = vm.toString(block.chainid);
        string memory deployPath = string.concat(vm.projectRoot(), "/.deploy/", chainIdStr, ".json");
        require(vm.isFile(deployPath), "Deploy file not found");
        string memory deployJson = vm.readFile(deployPath);
        address newMarginPool = deployJson.readAddress(".MarginPool.proxyAddress");
        require(newMarginPool != address(0), "MarginPool proxy not found");

        (EnhancedVault vault, address vaultAddr) = _loadVault();

        console.log("EnhancedVault:", vaultAddr);
        console.log("newMarginPool:", newMarginPool);

        vm.startBroadcast(privateKey);
        vault.setMarginPool(newMarginPool);
        vm.stopBroadcast();
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {Strings} from "lib/openzeppelin-contracts/contracts/utils/Strings.sol";

contract DeployEnhancedVaultCycleLib is Script {
    using Strings for address;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        string memory chainIdStr = vm.toString(block.chainid);

        vm.startBroadcast(deployerPrivateKey);
        address cycleLib = deployCode("src/periphery/vault/libs/EnhancedVaultCycleLib.sol:EnhancedVaultCycleLib");
        vm.stopBroadcast();

        require(cycleLib.code.length != 0, "Cycle library deployment failed");

        string memory deployDir = string.concat(vm.projectRoot(), "/.deploy/");
        if (!vm.isDir(deployDir)) vm.createDir(deployDir, true);
        string memory path = string.concat(deployDir, chainIdStr, ".json");
        if (!vm.isFile(path)) vm.writeJson("{}", path);

        vm.writeJson(string.concat("\"", cycleLib.toHexString(), "\""), path, ".EnhancedVault.cycleLibraryAddress");
        vm.writeJson(
            string.concat(
                "\"forge verify-contract --chain-id ",
                chainIdStr,
                " ",
                cycleLib.toHexString(),
                " src/periphery/vault/libs/EnhancedVaultCycleLib.sol:EnhancedVaultCycleLib\""
            ),
            path,
            ".EnhancedVault.cycleLibraryVerifyCommand"
        );

        console.log("EnhancedVaultCycleLib deployed at:", cycleLib);
        console.log("Update foundry.toml libraries before deploying EnhancedVault implementation.");
    }
}

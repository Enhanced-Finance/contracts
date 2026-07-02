// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {Strings} from "lib/openzeppelin-contracts/contracts/utils/Strings.sol";

contract DeployEnhancedVaultRecordsLib is Script {
    using Strings for address;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        string memory chainIdStr = vm.toString(block.chainid);

        vm.startBroadcast(deployerPrivateKey);
        address recordsLib = deployCode("src/periphery/vault/libs/EnhancedVaultRecordsLib.sol:EnhancedVaultRecordsLib");
        vm.stopBroadcast();

        require(recordsLib.code.length != 0, "Records library deployment failed");

        string memory deployDir = string.concat(vm.projectRoot(), "/.deploy/");
        if (!vm.isDir(deployDir)) vm.createDir(deployDir, true);
        string memory path = string.concat(deployDir, chainIdStr, ".json");
        if (!vm.isFile(path)) vm.writeJson("{}", path);

        vm.writeJson(string.concat("\"", recordsLib.toHexString(), "\""), path, ".EnhancedVault.recordsLibraryAddress");
        vm.writeJson(
            string.concat(
                "\"forge verify-contract --chain-id ",
                chainIdStr,
                " ",
                recordsLib.toHexString(),
                " src/periphery/vault/libs/EnhancedVaultRecordsLib.sol:EnhancedVaultRecordsLib\""
            ),
            path,
            ".EnhancedVault.recordsLibraryVerifyCommand"
        );

        console.log("EnhancedVaultRecordsLib deployed at:", recordsLib);
        console.log("Update foundry.toml libraries before deploying EnhancedVault implementation.");
    }
}

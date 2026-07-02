// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {Strings} from "lib/openzeppelin-contracts/contracts/utils/Strings.sol";

contract DeployEnhancedVaultLibraries is Script {
    using Strings for uint256;
    using Strings for address;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        uint256 chainId = block.chainid;
        string memory chainIdStr = chainId.toString();

        console.log("Deploying EnhancedVault linked libraries on chain ID:", chainIdStr);

        vm.startBroadcast(deployerPrivateKey);
        address recordsLib = deployCode("src/periphery/vault/libs/EnhancedVaultRecordsLib.sol:EnhancedVaultRecordsLib");
        address cycleLib = deployCode("src/periphery/vault/libs/EnhancedVaultCycleLib.sol:EnhancedVaultCycleLib");
        vm.stopBroadcast();

        console.log("EnhancedVaultRecordsLib deployed at:", recordsLib);
        console.log("EnhancedVaultCycleLib deployed at:", cycleLib);
        require(recordsLib.code.length != 0, "Records library deployment failed");
        require(cycleLib.code.length != 0, "Cycle library deployment failed");

        string memory deployDir = string.concat(vm.projectRoot(), "/.deploy/");

        if (!vm.isDir(deployDir)) {
            vm.createDir(deployDir, true);
        }

        string memory path = string.concat(deployDir, chainIdStr, ".json");

        if (!vm.isFile(path)) {
            vm.writeJson("{}", path);
        }

        vm.writeJson(string.concat("\"", recordsLib.toHexString(), "\""), path, ".EnhancedVault.recordsLibraryAddress");
        vm.writeJson(string.concat("\"", cycleLib.toHexString(), "\""), path, ".EnhancedVault.cycleLibraryAddress");
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
        console.log("EnhancedVault library deployment info saved to:", path);
        console.log("Update foundry.toml libraries before deploying EnhancedVault implementation.");
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {Strings} from "lib/openzeppelin-contracts/contracts/utils/Strings.sol";

contract DeployMarginVaultLib is Script {
    using Strings for address;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        string memory chainIdStr = vm.toString(block.chainid);

        vm.startBroadcast(deployerPrivateKey);
        address marginVaultLib = deployCode("src/core/libs/MarginVault.sol:MarginVault");
        vm.stopBroadcast();

        require(marginVaultLib.code.length != 0, "MarginVault library deployment failed");

        string memory deployDir = string.concat(vm.projectRoot(), "/.deploy/");
        if (!vm.isDir(deployDir)) vm.createDir(deployDir, true);
        string memory path = string.concat(deployDir, chainIdStr, ".json");
        if (!vm.isFile(path)) vm.writeJson("{}", path);

        vm.writeJson(string.concat("\"", marginVaultLib.toHexString(), "\""), path, ".MarginVault.libraryAddress");
        vm.writeJson(
            string.concat(
                "\"forge verify-contract --chain-id ",
                chainIdStr,
                " ",
                marginVaultLib.toHexString(),
                " src/core/libs/MarginVault.sol:MarginVault\""
            ),
            path,
            ".MarginVault.libraryVerifyCommand"
        );

        console.log("MarginVault library deployed at:", marginVaultLib);
        console.log("Update foundry.toml libraries before deploying linked implementations.");
    }
}

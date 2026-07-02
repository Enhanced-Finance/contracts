// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {Strings} from "lib/openzeppelin-contracts/contracts/utils/Strings.sol";

contract DeployParserLib is Script {
    using Strings for address;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        string memory chainIdStr = vm.toString(block.chainid);

        vm.startBroadcast(deployerPrivateKey);
        address parserLib = deployCode("src/core/libs/Parser.sol:Parser");
        vm.stopBroadcast();

        require(parserLib.code.length != 0, "Parser library deployment failed");

        string memory deployDir = string.concat(vm.projectRoot(), "/.deploy/");
        if (!vm.isDir(deployDir)) vm.createDir(deployDir, true);
        string memory path = string.concat(deployDir, chainIdStr, ".json");
        if (!vm.isFile(path)) vm.writeJson("{}", path);

        vm.writeJson(string.concat("\"", parserLib.toHexString(), "\""), path, ".EnhancedOptions.parserLibraryAddress");
        vm.writeJson(
            string.concat(
                "\"forge verify-contract --chain-id ",
                chainIdStr,
                " ",
                parserLib.toHexString(),
                " src/core/libs/Parser.sol:Parser\""
            ),
            path,
            ".EnhancedOptions.parserLibraryVerifyCommand"
        );

        console.log("Parser library deployed at:", parserLib);
        console.log("Update foundry.toml libraries before deploying EnhancedOptions implementation.");
    }
}

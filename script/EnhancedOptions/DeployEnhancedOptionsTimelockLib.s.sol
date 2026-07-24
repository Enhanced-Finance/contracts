// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {Strings} from "lib/openzeppelin-contracts/contracts/utils/Strings.sol";

contract DeployEnhancedOptionsTimelockLib is Script {
    using Strings for address;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        string memory chainIdStr = vm.toString(block.chainid);

        vm.startBroadcast(deployerPrivateKey);
        address timelockLib = deployCode("src/core/libs/EnhancedOptionsTimelockLib.sol:EnhancedOptionsTimelockLib");
        vm.stopBroadcast();

        require(timelockLib.code.length != 0, "Timelock library deployment failed");

        string memory deployDir = string.concat(vm.projectRoot(), "/.deploy/");
        if (!vm.isDir(deployDir)) vm.createDir(deployDir, true);
        string memory path = string.concat(deployDir, chainIdStr, ".json");
        if (!vm.isFile(path)) vm.writeJson("{}", path);

        vm.writeJson(
            string.concat("\"", timelockLib.toHexString(), "\""), path, ".EnhancedOptions.timelockLibraryAddress"
        );
        vm.writeJson(
            string.concat(
                "\"forge verify-contract --chain-id ",
                chainIdStr,
                " ",
                timelockLib.toHexString(),
                " src/core/libs/EnhancedOptionsTimelockLib.sol:EnhancedOptionsTimelockLib\""
            ),
            path,
            ".EnhancedOptions.timelockLibraryVerifyCommand"
        );

        console.log("EnhancedOptionsTimelockLib deployed at:", timelockLib);
        console.log("Update foundry.toml libraries before deploying EnhancedOptions implementation.");
    }
}

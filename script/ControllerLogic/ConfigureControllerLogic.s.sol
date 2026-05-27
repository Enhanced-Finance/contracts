// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {ControllerLogic} from "src/core/ControllerLogic.sol";
import {stdJson} from "forge-std/StdJson.sol";

contract ConfigureControllerLogic is Script {
    using stdJson for string;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        uint256 chainId = block.chainid;
        string memory chainIdStr = vm.toString(chainId);
        string memory deployPath = string.concat(vm.projectRoot(), "/.deploy/", chainIdStr, ".json");
        string memory configPath = string.concat(vm.projectRoot(), "/config/", chainIdStr, ".json");
        
        require(vm.isFile(deployPath), "Deploy file not found");
        require(vm.isFile(configPath), "Config file not found");
        
        string memory deployJson = vm.readFile(deployPath);
        string memory configJson = vm.readFile(configPath);

        address controllerLogicAddr = deployJson.readAddress(".ControllerLogic.proxyAddress");
        require(controllerLogicAddr != address(0), "ControllerLogic proxy not found");
        
        ControllerLogic controllerLogic = ControllerLogic(controllerLogicAddr);
        console.log("Configuring ControllerLogic at:", controllerLogicAddr);

        vm.startBroadcast(deployerPrivateKey);

        // Configure Redeem Time Period
        if (vm.keyExists(configJson, ".ControllerLogic.redeemTimePeriod")) {
            uint256 desired = configJson.readUint(".ControllerLogic.redeemTimePeriod");
            if (controllerLogic.redeemTimePeriod() != desired) {
                console.log("Updating Redeem Time Period...");
                controllerLogic.setRedeemTimePeriod(desired);
            }
        }

        vm.stopBroadcast();
    }
}

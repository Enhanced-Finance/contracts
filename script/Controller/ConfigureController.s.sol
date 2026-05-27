// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {Controller} from "src/core/Controller.sol";
import {stdJson} from "forge-std/StdJson.sol";

contract ConfigureController is Script {
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

        address controllerAddr = deployJson.readAddress(".Controller.proxyAddress");
        require(controllerAddr != address(0), "Controller proxy not found");

        Controller controller = Controller(controllerAddr);
        console.log("Configuring Controller at:", controllerAddr);

        vm.startBroadcast(deployerPrivateKey);

        // Configure Full Pauser
        if (vm.keyExists(configJson, ".Controller.fullPauser")) {
            address desiredFullPauser = configJson.readAddress(".Controller.fullPauser");
            if (controller.fullPauser() != desiredFullPauser && desiredFullPauser != address(0)) {
                console.log("Updating Full Pauser...");
                controller.setFullPauser(desiredFullPauser);
            }
        }

        // Configure Partial Pauser
        if (vm.keyExists(configJson, ".Controller.partialPauser")) {
            address desiredPartialPauser = configJson.readAddress(".Controller.partialPauser");
            if (controller.partialPauser() != desiredPartialPauser && desiredPartialPauser != address(0)) {
                console.log("Updating Partial Pauser...");
                controller.setPartialPauser(desiredPartialPauser);
            }
        }

        // Configure Manager (use EnhancedOptions proxy if available)
        address desiredManager;
        if (vm.keyExists(deployJson, ".EnhancedOptions.proxyAddress")) {
            desiredManager = deployJson.readAddress(".EnhancedOptions.proxyAddress");
        } else if (vm.keyExists(configJson, ".Controller.manager")) {
            desiredManager = configJson.readAddress(".Controller.manager");
        }

        if (desiredManager != address(0) && controller.manager() != desiredManager) {
            console.log("Updating Manager to EnhancedOptions/Configured Address:", desiredManager);
            controller.setManager(desiredManager);
        }

        // Configure Operators Enabled
        if (vm.keyExists(configJson, ".Controller.operatorsEnabled")) {
            bool desired = configJson.readBool(".Controller.operatorsEnabled");
            if (controller.operatorsEnabled() != desired) {
                console.log("Updating Operators Enabled...");
                controller.setOperatorsEnabled(desired);
            }
        }

        vm.stopBroadcast();
    }
}

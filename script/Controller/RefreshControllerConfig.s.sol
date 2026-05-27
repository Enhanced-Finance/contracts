// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {Controller} from "src/core/Controller.sol";
import {ControllerLogic} from "src/core/ControllerLogic.sol";
import {stdJson} from "forge-std/StdJson.sol";

contract RefreshControllerConfig is Script {
    using stdJson for string;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        uint256 chainId = block.chainid;
        string memory chainIdStr = vm.toString(chainId);
        string memory deployPath = string.concat(vm.projectRoot(), "/.deploy/", chainIdStr, ".json");

        require(vm.isFile(deployPath), "Deploy file not found");
        string memory deployJson = vm.readFile(deployPath);
        
        address controllerAddr = deployJson.readAddress(".Controller.proxyAddress");
        address controllerLogicAddr = deployJson.readAddress(".ControllerLogic.proxyAddress");
        
        require(controllerAddr != address(0), "Controller proxy not found");
        require(controllerLogicAddr != address(0), "ControllerLogic proxy not found");

        vm.startBroadcast(deployerPrivateKey);

        console.log("Refreshing Controller configuration...");
        Controller(controllerAddr).refreshConfiguration();
        
        console.log("Refreshing ControllerLogic configuration...");
        ControllerLogic(controllerLogicAddr).refreshConfiguration();

        vm.stopBroadcast();

        console.log("Configuration refreshed successfully.");
    }
}

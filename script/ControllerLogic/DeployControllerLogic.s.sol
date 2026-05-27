// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {ControllerLogic} from "src/core/ControllerLogic.sol";
import {Strings} from "lib/openzeppelin-contracts/contracts/utils/Strings.sol";

contract DeployControllerLogic is Script {
    using Strings for uint256;
    using Strings for address;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        uint256 chainId = block.chainid;
        string memory chainIdStr = chainId.toString();
        
        console.log("Deploying ControllerLogic Implementation on chain ID:", chainIdStr);

        vm.startBroadcast(deployerPrivateKey);
        ControllerLogic impl = new ControllerLogic();
        vm.stopBroadcast();

        console.log("Implementation deployed at:", address(impl));

        string memory jsonObj = "deployment_data";
        string memory deployDir = string.concat(vm.projectRoot(), "/.deploy/");
        
        if (!vm.isDir(deployDir)) {
            vm.createDir(deployDir, true);
        }

        string memory path = string.concat(deployDir, chainIdStr, ".json");
        
        if (!vm.isFile(path)) {
            vm.writeJson("{}", path);
        }
        
        vm.serializeString(jsonObj, "contractName", "ControllerLogic");
        vm.serializeAddress(jsonObj, "implementationAddress", address(impl));
        
        string memory verifyImplCmd = string.concat(
            "forge verify-contract --chain-id ", chainIdStr, 
            " --num-of-optimizations 200 --watch ", 
            Strings.toHexString(address(impl)), 
            " src/ControllerLogic.sol:ControllerLogic"
        );
        string memory finalJson = vm.serializeString(jsonObj, "verifyImplementationCommand", verifyImplCmd);
        
        vm.writeJson(finalJson, path, ".ControllerLogic");
        console.log("Deployment info saved to:", path);
    }
}

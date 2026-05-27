// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {Controller} from "src/core/Controller.sol";
import {Strings} from "lib/openzeppelin-contracts/contracts/utils/Strings.sol";

contract DeployController is Script {
    using Strings for uint256;
    using Strings for address;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        uint256 chainId = block.chainid;
        string memory chainIdStr = chainId.toString();
        
        console.log("Deploying Controller Implementation on chain ID:", chainIdStr);

        vm.startBroadcast(deployerPrivateKey);
        Controller impl = new Controller();
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
        
        vm.serializeString(jsonObj, "contractName", "Controller");
        vm.serializeAddress(jsonObj, "implementationAddress", address(impl));
        
        string memory verifyImplCmd = string.concat(
            "forge verify-contract --chain-id ", chainIdStr, 
            " --num-of-optimizations 200 --watch ", 
            Strings.toHexString(address(impl)), 
            " src/Controller.sol:Controller"
        );
        string memory finalJson = vm.serializeString(jsonObj, "verifyImplementationCommand", verifyImplCmd);
        
        vm.writeJson(finalJson, path, ".Controller");
        console.log("Deployment info saved to:", path);
    }
}

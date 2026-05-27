// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {MarginCalculator} from "src/core/MarginCalculator.sol";
import {Strings} from "lib/openzeppelin-contracts/contracts/utils/Strings.sol";

contract DeployMarginCalculator is Script {
    using Strings for uint256;
    using Strings for address;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        uint256 chainId = block.chainid;
        string memory chainIdStr = chainId.toString();
        
        console.log("Deploying MarginCalculator Implementation on chain ID:", chainIdStr);

        vm.startBroadcast(deployerPrivateKey);
        MarginCalculator impl = new MarginCalculator();
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
        
        vm.serializeString(jsonObj, "contractName", "MarginCalculator");
        vm.serializeAddress(jsonObj, "implementationAddress", address(impl));
        
        string memory verifyImplCmd = string.concat(
            "forge verify-contract --chain-id ", chainIdStr, 
            " --num-of-optimizations 200 --watch ", 
            Strings.toHexString(address(impl)), 
            " src/MarginCalculator.sol:MarginCalculator"
        );
        string memory finalJson = vm.serializeString(jsonObj, "verifyImplementationCommand", verifyImplCmd);
        
        vm.writeJson(finalJson, path, ".MarginCalculator");
        console.log("Deployment info saved to:", path);
    }
}

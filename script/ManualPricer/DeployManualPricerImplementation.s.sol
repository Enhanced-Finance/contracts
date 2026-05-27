// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {ManualPricer} from "src/core/ManualPricer.sol";
import {Strings} from "lib/openzeppelin-contracts/contracts/utils/Strings.sol";
import {stdJson} from "forge-std/StdJson.sol";

contract DeployManualPricerImplementation is Script {
    using Strings for uint256;
    using Strings for address;
    using stdJson for string;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        uint256 chainId = block.chainid;
        string memory chainIdStr = chainId.toString();

        string memory deployDir = string.concat(vm.projectRoot(), "/.deploy/");
        if (!vm.isDir(deployDir)) {
            vm.createDir(deployDir, true);
        }
        string memory path = string.concat(deployDir, chainIdStr, ".json");
        if (!vm.isFile(path)) {
            vm.writeJson("{}", path);
        }
        string memory existingDeployJson = vm.readFile(path);

        console.log("Deploying ManualPricer Implementation on chain ID:", chainIdStr);

        // Check if implementation already exists in file, if not deploy
        address implementation;
        if (vm.keyExists(existingDeployJson, ".ManualPricer_Implementation.implementationAddress")) {
            implementation = existingDeployJson.readAddress(".ManualPricer_Implementation.implementationAddress");
            console.log("Using existing ManualPricer Implementation at:", implementation);
        } else {
            vm.startBroadcast(deployerPrivateKey);
            ManualPricer impl = new ManualPricer();
            vm.stopBroadcast();
            implementation = address(impl);
            console.log("Deployed new ManualPricer Implementation at:", implementation);

            // Save Implementation Info
            string memory jsonObj = "deployment_data";
            vm.serializeString(jsonObj, "contractName", "ManualPricer");
            vm.serializeAddress(jsonObj, "implementationAddress", implementation);
            string memory verifyImplCmd = string.concat(
                "forge verify-contract --chain-id ",
                chainIdStr,
                " --num-of-optimizations 200 --watch ",
                Strings.toHexString(implementation),
                " src/ManualPricer.sol:ManualPricer"
            );
            vm.serializeString(jsonObj, "verifyImplementationCommand", verifyImplCmd);
            vm.writeJson(
                vm.serializeString(jsonObj, "verifyImplementationCommand", verifyImplCmd),
                path,
                ".ManualPricer_Implementation"
            );
        }
    }
}

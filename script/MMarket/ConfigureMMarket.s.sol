// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {MMarket} from "src/core/MMarket.sol";
import {stdJson} from "forge-std/StdJson.sol";

contract ConfigureMMarket is Script {
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

        address mmarketAddr = deployJson.readAddress(".MMarket.proxyAddress");
        require(mmarketAddr != address(0), "MMarket proxy not found");

        // MMarket mmarket = MMarket(mmarketAddr); // MMarket doesn't have public getter for operator in the provided interface snippet
        // We assume we can set it blindly or if we had a getter we'd check.
        // Assuming setOperator is present.
        console.log("Configuring MMarket at:", mmarketAddr);

        vm.startBroadcast(deployerPrivateKey);

        // Configure Operator
        address desiredOperator;
        if (vm.keyExists(deployJson, ".EnhancedOptions.proxyAddress")) {
            desiredOperator = deployJson.readAddress(".EnhancedOptions.proxyAddress");
        } else if (vm.keyExists(configJson, ".MMarket.operator")) {
            desiredOperator = configJson.readAddress(".MMarket.operator");
        }

        if (desiredOperator != address(0)) {
            console.log("Updating Operator to:", desiredOperator);
            MMarket(mmarketAddr).setOperator(desiredOperator);
        }

        vm.stopBroadcast();
    }
}

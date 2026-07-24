// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {MarginPool} from "src/core/MarginPool.sol";
import {stdJson} from "forge-std/StdJson.sol";

contract ConfigureMarginPool is Script {
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

        address poolAddr = deployJson.readAddress(".MarginPool.proxyAddress");
        require(poolAddr != address(0), "MarginPool proxy not found");

        MarginPool pool = MarginPool(poolAddr);
        console.log("Configuring MarginPool at:", poolAddr);

        vm.startBroadcast(deployerPrivateKey);

        // Configure Farmer
        if (vm.keyExists(configJson, ".MarginPool.farmer")) {
            address desiredFarmer = configJson.readAddress(".MarginPool.farmer");
            if (pool.farmer() != desiredFarmer && desiredFarmer != address(0)) {
                console.log("Updating Farmer...");
                pool.setFarmer(desiredFarmer);
            }
        }

        vm.stopBroadcast();
    }
}

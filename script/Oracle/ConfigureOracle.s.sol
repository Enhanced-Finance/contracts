// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {Oracle} from "src/core/Oracle.sol";
import {stdJson} from "forge-std/StdJson.sol";

contract ConfigureOracle is Script {
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

        address oracleAddr = deployJson.readAddress(".Oracle.proxyAddress");
        require(oracleAddr != address(0), "Oracle proxy not found");
        
        Oracle oracle = Oracle(oracleAddr);
        console.log("Configuring Oracle at:", oracleAddr);

        vm.startBroadcast(deployerPrivateKey);

        // Configure Disputer
        if (vm.keyExists(configJson, ".Oracle.disputer")) {
            address desiredDisputer = configJson.readAddress(".Oracle.disputer");
            if (oracle.getDisputer() != desiredDisputer && desiredDisputer != address(0)) {
                console.log("Updating Disputer...");
                oracle.setDisputer(desiredDisputer);
            }
        }

        vm.stopBroadcast();
    }
}

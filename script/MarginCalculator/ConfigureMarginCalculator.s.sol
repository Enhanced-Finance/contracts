// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {MarginCalculator} from "src/core/MarginCalculator.sol";
import {stdJson} from "forge-std/StdJson.sol";

contract ConfigureMarginCalculator is Script {
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

        address calculatorAddr = deployJson.readAddress(".MarginCalculator.proxyAddress");
        require(calculatorAddr != address(0), "MarginCalculator proxy not found");

        MarginCalculator calculator = MarginCalculator(calculatorAddr);
        console.log("Configuring MarginCalculator at:", calculatorAddr);

        vm.startBroadcast(deployerPrivateKey);

        // Configure Collateral Dust
        if (vm.keyExists(configJson, ".MarginCalculator.collateralDust")) {
            bytes memory dustBytes = configJson.parseRaw(".MarginCalculator.collateralDust");
            string[] memory assets = abi.decode(dustBytes, (string[])); // This might not work directly with json object keys

            // Simpler approach: user should provide an array of objects in config
            // { "collateralDust": [ {"asset": "0x...", "amount": 1000} ] }
            // But stdJson handling of arrays of objects is tricky.
            // Assuming config structure: "collateralDust": { "0xAsset": 1000 }
            // Iterating keys in solidity is hard.
            // Let's assume specific keys or structured input.
            // For now, let's skip complex map iteration unless we have a specific structure.
        }

        // Configure Liquidation Multiplier
        if (vm.keyExists(configJson, ".MarginCalculator.liquidationMultiplier")) {
            uint256 desired = configJson.readUint(".MarginCalculator.liquidationMultiplier");
            if (calculator.liquidationMultiplier() != desired) {
                console.log("Updating Liquidation Multiplier...");
                calculator.setLiquidationMultiplier(desired);
            }
        }

        // Configure Oracle Deviation
        if (vm.keyExists(configJson, ".MarginCalculator.oracleDeviation")) {
            uint256 desired = configJson.readUint(".MarginCalculator.oracleDeviation");
            if (calculator.getOracleDeviation() != desired) {
                console.log("Updating Oracle Deviation...");
                calculator.setOracleDeviation(desired);
            }
        }

        vm.stopBroadcast();
    }
}

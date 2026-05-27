// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {ManualPricer} from "src/core/ManualPricer.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {Strings} from "lib/openzeppelin-contracts/contracts/utils/Strings.sol";

contract UpgradeManualPricer is Script {
    using stdJson for string;

    struct AssetConfig {
        address assetAddress;
        address bot;
        uint256 deviationMultiplier;
        address owner;
        uint256 priceTimeValidity;
        string symbol;
    }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        uint256 chainId = block.chainid;
        string memory chainIdStr = vm.toString(chainId);
        string memory deployPath = string.concat(vm.projectRoot(), "/.deploy/", chainIdStr, ".json");
        string memory configPath = string.concat(vm.projectRoot(), "/config/", chainIdStr, ".json");

        require(vm.isFile(deployPath), "Deploy file not found");
        require(vm.isFile(configPath), "Config file not found");

        string memory deployJson = vm.readFile(deployPath);
        string memory configJson = vm.readFile(configPath);
        AssetConfig[] memory assets = abi.decode(configJson.parseRaw(".ManualPricer.assets"), (AssetConfig[]));
        require(assets.length > 0, "No assets found in config");

        vm.startBroadcast(deployerPrivateKey);
        ManualPricer newImplementation = new ManualPricer();
        vm.stopBroadcast();

        string memory verifyImplCmd = string.concat(
            "forge verify-contract --chain-id ",
            chainIdStr,
            " --num-of-optimizations 200 --watch ",
            Strings.toHexString(address(newImplementation)),
            " src/ManualPricer.sol:ManualPricer"
        );

        vm.writeJson(
            string.concat("\"", vm.toString(address(newImplementation)), "\""),
            deployPath,
            ".ManualPricer_Implementation.implementationAddress"
        );
        vm.writeJson(
            string.concat("\"", verifyImplCmd, "\""),
            deployPath,
            ".ManualPricer_Implementation.verifyImplementationCommand"
        );

        for (uint256 i = 0; i < assets.length; i++) {
            string memory keyPrefix = string.concat(".ManualPricer-", assets[i].symbol);
            string memory proxyPath = string.concat(keyPrefix, ".proxyAddress");

            if (!vm.keyExists(deployJson, proxyPath)) {
                continue;
            }

            address proxyAddr = deployJson.readAddress(proxyPath);
            if (proxyAddr == address(0)) {
                continue;
            }

            address onchainOwner = ManualPricer(proxyAddr).owner();
            console.log("ManualPricer owner:", onchainOwner);
            console.log("Upgrade sender:", deployer);
            require(onchainOwner == deployer, "UpgradeManualPricer: PRIVATE_KEY is not proxy owner");

            vm.startBroadcast(deployerPrivateKey);
            ManualPricer(proxyAddr).upgradeToAndCall(address(newImplementation), "");
            vm.stopBroadcast();

            vm.writeJson(
                string.concat("\"", vm.toString(address(newImplementation)), "\""),
                deployPath,
                string.concat(keyPrefix, ".implementationAddress")
            );
            vm.writeJson(
                string.concat("\"", verifyImplCmd, "\""),
                deployPath,
                string.concat(keyPrefix, ".verifyImplementationCommand")
            );

            console.log("ManualPricer upgraded:", assets[i].symbol, proxyAddr);
        }

        console.log("New ManualPricer implementation:", address(newImplementation));
    }
}

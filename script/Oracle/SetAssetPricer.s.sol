// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {Oracle} from "src/core/Oracle.sol";
import {stdJson} from "forge-std/StdJson.sol";

contract SetAssetPricer is Script {
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

        address oracleAddr = deployJson.readAddress(".Oracle.proxyAddress");
        require(oracleAddr != address(0), "Oracle proxy not found");

        AssetConfig[] memory assets = abi.decode(configJson.parseRaw(".ManualPricer.assets"), (AssetConfig[]));
        require(assets.length > 0, "No assets found in config");

        console.log("Executing SetAssetPricer on Oracle:", oracleAddr);
        console.log("Caller (Owner):", deployer);

        Oracle oracle = Oracle(oracleAddr);
        address[] memory assetAddresses = new address[](assets.length);
        address[] memory pricerAddresses = new address[](assets.length);

        for (uint256 i = 0; i < assets.length; i++) {
            string memory symbol = assets[i].symbol;
            address asset = assets[i].assetAddress;
            string memory key = string.concat(".ManualPricer-", symbol);

            require(asset != address(0), string.concat("Asset address not found for ", symbol));
            require(vm.keyExists(deployJson, key), string.concat("ManualPricer deployment not found for ", symbol));

            address pricer = deployJson.readAddress(string.concat(key, ".proxyAddress"));
            require(pricer != address(0), string.concat("ManualPricer proxy not found for ", symbol));

            assetAddresses[i] = asset;
            pricerAddresses[i] = pricer;
        }

        vm.startBroadcast(deployerPrivateKey);

        for (uint256 i = 0; i < assets.length; i++) {
            string memory symbol = assets[i].symbol;

            console.log("Setting pricer for", symbol);
            console.log("Asset:", assetAddresses[i]);
            console.log("Pricer:", pricerAddresses[i]);

            oracle.setAssetPricer(assetAddresses[i], pricerAddresses[i]);
        }

        vm.stopBroadcast();

        console.log("Asset pricers updated successfully.");
    }
}

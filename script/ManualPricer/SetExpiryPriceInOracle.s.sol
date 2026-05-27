// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {ManualPricer} from "src/core/ManualPricer.sol";
import {stdJson} from "forge-std/StdJson.sol";

contract SetExpiryPriceInOracle is Script {
    using stdJson for string;

    // --- Configuration: Set these values before running ---

    // Price data to push
    uint256 constant EXPIRY = 1777035948; // Expiry timestamp

    // The symbol of the asset to set price for (must match config assets)
    string constant ASSET_SYMBOL = "PAXG";
    uint256 constant PRICE = 468687500000; // Price in USD (8 decimals)

    // string constant ASSET_SYMBOL = "TWSEI";
    // uint256 constant PRICE = 6870000; // 6870000; // Price in USD (8 decimals)
    // ----------------------------------------------------

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        uint256 chainId = block.chainid;
        string memory chainIdStr = vm.toString(chainId);
        string memory deployPath = string.concat(vm.projectRoot(), "/.deploy/", chainIdStr, ".json");

        require(vm.isFile(deployPath), "Deploy file not found");
        string memory deployJson = vm.readFile(deployPath);

        string memory key = string.concat(".ManualPricer-", ASSET_SYMBOL);
        require(vm.keyExists(deployJson, key), string.concat("ManualPricer not found for ", ASSET_SYMBOL));

        address pricerProxy = deployJson.readAddress(string.concat(key, ".proxyAddress"));
        require(pricerProxy != address(0), "ManualPricer proxy not found");

        console.log("Setting Expiry Price via ManualPricer for", ASSET_SYMBOL, "at:", pricerProxy);
        console.log("Caller (Bot):", deployer);
        console.log("Expiry:", EXPIRY);
        console.log("Price:", PRICE);

        ManualPricer pricer = ManualPricer(pricerProxy);
        address onchainBot = pricer.bot();
        console.log("Configured bot:", onchainBot);
        require(onchainBot == deployer, "SetExpiryPriceInOracle: PRIVATE_KEY is not bot");

        vm.startBroadcast(deployerPrivateKey);
        pricer.setExpiryPriceInOracle(EXPIRY, PRICE);
        vm.stopBroadcast();

        console.log("Expiry price pushed to Oracle successfully.");
    }
}

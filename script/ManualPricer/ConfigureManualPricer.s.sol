// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {ManualPricer} from "src/core/ManualPricer.sol";
import {stdJson} from "forge-std/StdJson.sol";

contract ConfigureManualPricer is Script {
    using stdJson for string;

    // Default values if not specified in config (though config is preferred)
    uint256 constant DEFAULT_PRICE_TIME_VALIDITY = 86400; // 1 day
    uint256 constant DEFAULT_DEVIATION_MULTIPLIER = 200; // 2.00 (2 decimals)

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

        // Read assets array
        AssetConfig[] memory assets = abi.decode(configJson.parseRaw(".ManualPricer.assets"), (AssetConfig[]));
        require(assets.length > 0, "No assets found in config");

        for (uint256 i = 0; i < assets.length; i++) {
            string memory symbol = assets[i].symbol;
            string memory key = string.concat(".ManualPricer-", symbol);

            if (!vm.keyExists(deployJson, key)) {
                console.log("Skipping configuration for", symbol, "- Proxy not found in deploy file");
                continue;
            }

            address pricerProxy = deployJson.readAddress(string.concat(key, ".proxyAddress"));
            require(pricerProxy != address(0), string.concat("ManualPricer proxy not found for ", symbol));

            console.log("Configuring ManualPricer for", symbol, "at:", pricerProxy);
            _configurePricer(pricerProxy, assets[i], deployerPrivateKey, deployer);
        }

        console.log("ManualPricer configuration complete.");
    }

    function _configurePricer(
        address pricerProxy,
        AssetConfig memory config,
        uint256 deployerPrivateKey,
        address deployer
    ) internal {
        ManualPricer pricer = ManualPricer(pricerProxy);
        address onchainOwner = pricer.owner();
        console.log("Pricer owner:", onchainOwner);
        console.log("Tx sender:", deployer);

        require(onchainOwner == deployer, "ConfigureManualPricer: PRIVATE_KEY is not pricer owner");
        require(
            config.owner == address(0) || config.owner == onchainOwner, "ConfigureManualPricer: config owner mismatch"
        );

        uint256 targetPriceTimeValidity =
            config.priceTimeValidity > 0 ? config.priceTimeValidity : DEFAULT_PRICE_TIME_VALIDITY;
        uint256 targetDeviationMultiplier =
            config.deviationMultiplier > 0 ? config.deviationMultiplier : DEFAULT_DEVIATION_MULTIPLIER;

        vm.startBroadcast(deployerPrivateKey);

        if (pricer.priceTimeValidity() != targetPriceTimeValidity) {
            console.log("Setting Price Time Validity to:", targetPriceTimeValidity);
            pricer.setPriceTimeValidity(targetPriceTimeValidity);
        }

        if (pricer.deviationMultiplier() != targetDeviationMultiplier) {
            console.log("Setting Deviation Multiplier to:", targetDeviationMultiplier);
            pricer.setDeviationMultiplier(targetDeviationMultiplier);
        }

        vm.stopBroadcast();
    }
}

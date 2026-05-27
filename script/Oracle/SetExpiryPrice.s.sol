// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {Oracle} from "src/core/Oracle.sol";
import {stdJson} from "lib/forge-std/src/StdJson.sol";

contract SetExpiryPrice is Script {
    using stdJson for string;

    // --- Configuration: Set these values before running ---
    address ASSET = vm.envAddress("UNDERLYING"); // Asset address (e.g., TWSEI)
    uint256 constant EXPIRY = 1772697600; // Expiry timestamp
    uint256 constant PRICE = 6870000; // Price at expiry (8 decimals usually)

    // ----------------------------------------------------

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        uint256 chainId = block.chainid;
        string memory chainIdStr = vm.toString(chainId);
        string memory deployPath = string.concat(vm.projectRoot(), "/.deploy/", chainIdStr, ".json");

        require(vm.isFile(deployPath), "Deploy file not found");
        string memory deployJson = vm.readFile(deployPath);
        address oracleAddr = deployJson.readAddress(".Oracle.proxyAddress");
        require(oracleAddr != address(0), "Oracle proxy not found");

        console.log("Executing SetExpiryPrice on Oracle:", oracleAddr);
        console.log("Caller:", deployer);
        console.log("Asset:", ASSET);
        console.log("Expiry:", EXPIRY);
        console.log("Price:", PRICE);

        // NOTE: Oracle.setExpiryPrice can only be called by the "Pricer" of the asset.
        // You must ensure that the caller (deployer) is the Pricer, OR that the Pricer allows you to trigger this.
        // In many test setups, the deployer is set as the Pricer directly for simplicity.
        // If a real Pricer contract is used, you cannot call Oracle.setExpiryPrice directly.

        Oracle oracle = Oracle(oracleAddr);
        address pricer = oracle.getPricer(ASSET);
        console.log("Current Pricer for Asset:", pricer);

        if (pricer == deployer) {
            vm.startBroadcast(deployerPrivateKey);
            oracle.setExpiryPrice(ASSET, EXPIRY, PRICE);
            vm.stopBroadcast();
            console.log("Expiry price set successfully.");
        } else {
            console.log("Error: Caller is not the registered Pricer.");
            console.log("You must either:");
            console.log("1. Be the owner and set yourself as Pricer first (using SetAssetPricer script).");
            console.log("2. Or use the specific mechanism of the registered Pricer contract to push the price.");
        }
    }
}

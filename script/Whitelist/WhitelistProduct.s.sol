// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {Whitelist} from "src/core/Whitelist.sol";
import {stdJson} from "forge-std/StdJson.sol";

contract WhitelistProduct is Script {
    using stdJson for string;

    // --- Configuration: Set these values before running ---
    address UNDERLYING = vm.envAddress("UNDERLYING"); // e.g. TWSEI
    address STRIKE = vm.envAddress("STRIKE"); // e.g. TUSDT
    address COLLATERAL = vm.envAddress("UNDERLYING"); // e.g. TWSEI for Call
    bool constant IS_PUT = false; // false for Call
    // ----------------------------------------------------

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        uint256 chainId = block.chainid;
        string memory chainIdStr = vm.toString(chainId);
        string memory deployPath = string.concat(vm.projectRoot(), "/.deploy/", chainIdStr, ".json");

        require(vm.isFile(deployPath), "Deploy file not found");
        string memory deployJson = vm.readFile(deployPath);
        address whitelistAddr = deployJson.readAddress(".Whitelist.proxyAddress");
        require(whitelistAddr != address(0), "Whitelist proxy not found");

        console.log("Executing WhitelistProduct on:", whitelistAddr);
        console.log("Caller (Owner):", deployer);
        console.log("Underlying:", UNDERLYING);
        console.log("Strike:", STRIKE);
        console.log("Collateral:", COLLATERAL);
        console.log("Is Put:", IS_PUT);

        Whitelist whitelist = Whitelist(whitelistAddr);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Check if Collateral is whitelisted, if not, whitelist it.
        if (!whitelist.isWhitelistedCollateral(COLLATERAL)) {
            console.log("Collateral is NOT whitelisted. Whitelisting collateral...");
            whitelist.whitelistCollateral(COLLATERAL);
        } else {
            console.log("Collateral is already whitelisted.");
        }

        // 2. Whitelist Product
        if (!whitelist.isWhitelistedProduct(UNDERLYING, STRIKE, COLLATERAL, IS_PUT)) {
            console.log("Product is NOT whitelisted. Whitelisting product...");
            whitelist.whitelistProduct(UNDERLYING, STRIKE, COLLATERAL, IS_PUT);
        } else {
            console.log("Product is already whitelisted.");
        }

        // 3. Whitelist Covered/Naked Collateral (Optional but good practice)
        // If it's a Call (IS_PUT = false) and Collateral == Underlying, it's Covered Call
        if (!IS_PUT && COLLATERAL == UNDERLYING) {
            if (!whitelist.isCoveredWhitelistedCollateral(COLLATERAL, UNDERLYING, IS_PUT)) {
                console.log("Whitelisting Covered Collateral...");
                whitelist.whitelistCoveredCollateral(COLLATERAL, UNDERLYING, IS_PUT);
            }
        }
        // If it's a Put (IS_PUT = true) and Collateral == Strike (Stable), it's Covered Put (Cash Secured Put)
        if (IS_PUT && COLLATERAL == STRIKE) {
            if (!whitelist.isCoveredWhitelistedCollateral(COLLATERAL, UNDERLYING, IS_PUT)) {
                console.log("Whitelisting Covered Collateral (Put)...");
                whitelist.whitelistCoveredCollateral(COLLATERAL, UNDERLYING, IS_PUT);
            }
        }

        vm.stopBroadcast();

        console.log("WhitelistProduct execution complete.");
    }
}

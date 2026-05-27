// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {EnhancedOptions} from "src/core/EnhancedOptions.sol";
import {stdJson} from "forge-std/StdJson.sol";

/**
 * @notice Manage EnhancedOptions trusted roles from config/<chainId>.json
 *
 * Supported config keys:
 *   Taker role (for trusted taker path):
 *     .EnhancedOptions.trustedTakers     (address[]) -> setTrustedTaker(addr, true)
 *     .EnhancedOptions.untrustedTakers   (address[]) -> setTrustedTaker(addr, false)
 *   Maker role (for trusted maker path):
 *     .EnhancedOptions.trustedMakers     (address[]) -> setTrustedMaker(addr, true)
 *     .EnhancedOptions.untrustedMakers   (address[]) -> setTrustedMaker(addr, false)
 *
 * Backward compatibility:
 *   .EnhancedOptions.trustedOperators / .EnhancedOptions.untrustedOperators
 *   are treated as aliases of trustedTakers / untrustedTakers.
 *
 * Required env vars:
 *   PRIVATE_KEY (must be owner)
 */
contract ManageTrustedOperators is Script {
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

        address enhancedOptionsAddr = deployJson.readAddress(".EnhancedOptions.proxyAddress");
        require(enhancedOptionsAddr != address(0), "EnhancedOptions proxy not found");

        EnhancedOptions enhancedOptions = EnhancedOptions(enhancedOptionsAddr);
        console.log("Managing trusted roles on EnhancedOptions:", enhancedOptionsAddr);

        vm.startBroadcast(deployerPrivateKey);

        // trusted takers (new key)
        if (vm.keyExists(configJson, ".EnhancedOptions.trustedTakers")) {
            address[] memory trusted = configJson.readAddressArray(".EnhancedOptions.trustedTakers");
            for (uint256 i = 0; i < trusted.length; i++) {
                if (!enhancedOptions.trustedTakers(trusted[i])) {
                    console.log("Authorizing trusted taker:", trusted[i]);
                    enhancedOptions.setTrustedTaker(trusted[i], true);
                }
            }
        }

        // trusted takers (legacy alias key)
        if (vm.keyExists(configJson, ".EnhancedOptions.trustedOperators")) {
            address[] memory trusted = configJson.readAddressArray(".EnhancedOptions.trustedOperators");
            for (uint256 i = 0; i < trusted.length; i++) {
                if (!enhancedOptions.trustedTakers(trusted[i])) {
                    console.log("Authorizing trusted taker (legacy key):", trusted[i]);
                    enhancedOptions.setTrustedTaker(trusted[i], true);
                }
            }
        }

        // untrusted takers (new key)
        if (vm.keyExists(configJson, ".EnhancedOptions.untrustedTakers")) {
            address[] memory untrusted = configJson.readAddressArray(".EnhancedOptions.untrustedTakers");
            for (uint256 i = 0; i < untrusted.length; i++) {
                if (enhancedOptions.trustedTakers(untrusted[i])) {
                    console.log("Deauthorizing trusted taker:", untrusted[i]);
                    enhancedOptions.setTrustedTaker(untrusted[i], false);
                }
            }
        }

        // untrusted takers (legacy alias key)
        if (vm.keyExists(configJson, ".EnhancedOptions.untrustedOperators")) {
            address[] memory untrusted = configJson.readAddressArray(".EnhancedOptions.untrustedOperators");
            for (uint256 i = 0; i < untrusted.length; i++) {
                if (enhancedOptions.trustedTakers(untrusted[i])) {
                    console.log("Deauthorizing trusted taker (legacy key):", untrusted[i]);
                    enhancedOptions.setTrustedTaker(untrusted[i], false);
                }
            }
        }

        // trusted makers
        if (vm.keyExists(configJson, ".EnhancedOptions.trustedMakers")) {
            address[] memory trusted = configJson.readAddressArray(".EnhancedOptions.trustedMakers");
            for (uint256 i = 0; i < trusted.length; i++) {
                if (!enhancedOptions.trustedMakers(trusted[i])) {
                    console.log("Authorizing trusted maker:", trusted[i]);
                    enhancedOptions.setTrustedMaker(trusted[i], true);
                }
            }
        }

        // untrusted makers
        if (vm.keyExists(configJson, ".EnhancedOptions.untrustedMakers")) {
            address[] memory untrusted = configJson.readAddressArray(".EnhancedOptions.untrustedMakers");
            for (uint256 i = 0; i < untrusted.length; i++) {
                if (enhancedOptions.trustedMakers(untrusted[i])) {
                    console.log("Deauthorizing trusted maker:", untrusted[i]);
                    enhancedOptions.setTrustedMaker(untrusted[i], false);
                }
            }
        }

        vm.stopBroadcast();
        console.log("ManageTrustedOperators complete.");
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {EnhancedOptions} from "src/core/EnhancedOptions.sol";
import {IEnhancedOptionsTimelock} from "src/core/interfaces/IEnhancedOptionsTimelock.sol";
import {stdJson} from "forge-std/StdJson.sol";

/**
 * @notice Manage EnhancedOptions trusted roles from config/<chainId>.json
 *
 * Supported config keys:
 *   Taker role (for trusted taker path):
 *     .EnhancedOptions.trustedTakers     (address[]) -> schedule/execute trusted taker
 *     .EnhancedOptions.untrustedTakers   (address[]) -> setTrustedTaker(addr, false)
 *   Maker role (for trusted maker path):
 *     .EnhancedOptions.trustedMakers     (address[]) -> schedule/execute trusted maker
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
                _syncTrustedTaker(enhancedOptions, trusted[i], true);
            }
        }

        // trusted takers (legacy alias key)
        if (vm.keyExists(configJson, ".EnhancedOptions.trustedOperators")) {
            address[] memory trusted = configJson.readAddressArray(".EnhancedOptions.trustedOperators");
            for (uint256 i = 0; i < trusted.length; i++) {
                _syncTrustedTaker(enhancedOptions, trusted[i], true);
            }
        }

        // untrusted takers (new key)
        if (vm.keyExists(configJson, ".EnhancedOptions.untrustedTakers")) {
            address[] memory untrusted = configJson.readAddressArray(".EnhancedOptions.untrustedTakers");
            for (uint256 i = 0; i < untrusted.length; i++) {
                _syncTrustedTaker(enhancedOptions, untrusted[i], false);
            }
        }

        // untrusted takers (legacy alias key)
        if (vm.keyExists(configJson, ".EnhancedOptions.untrustedOperators")) {
            address[] memory untrusted = configJson.readAddressArray(".EnhancedOptions.untrustedOperators");
            for (uint256 i = 0; i < untrusted.length; i++) {
                _syncTrustedTaker(enhancedOptions, untrusted[i], false);
            }
        }

        // trusted makers
        if (vm.keyExists(configJson, ".EnhancedOptions.trustedMakers")) {
            address[] memory trusted = configJson.readAddressArray(".EnhancedOptions.trustedMakers");
            for (uint256 i = 0; i < trusted.length; i++) {
                _syncTrustedMaker(enhancedOptions, trusted[i], true);
            }
        }

        // untrusted makers
        if (vm.keyExists(configJson, ".EnhancedOptions.untrustedMakers")) {
            address[] memory untrusted = configJson.readAddressArray(".EnhancedOptions.untrustedMakers");
            for (uint256 i = 0; i < untrusted.length; i++) {
                _syncTrustedMaker(enhancedOptions, untrusted[i], false);
            }
        }

        vm.stopBroadcast();
        console.log("ManageTrustedOperators complete.");
    }

    function _syncTrustedTaker(EnhancedOptions enhancedOptions, address taker, bool desired) internal {
        bool current = enhancedOptions.trustedTakers(taker);
        bytes memory key = abi.encode(taker);
        (, uint64 executeAfter) =
            enhancedOptions.pendingConfigUpdate(IEnhancedOptionsTimelock.TimelockConfigType.TrustedTaker, key);
        if (!desired) {
            if (current || executeAfter != 0) enhancedOptions.setTrustedTaker(taker, false);
            return;
        }
        if (current) return;
        if (executeAfter == 0) {
            console.log("Scheduling trusted taker:", taker);
            enhancedOptions.scheduleConfigUpdate(IEnhancedOptionsTimelock.TimelockConfigType.TrustedTaker, key);
        } else if (block.timestamp >= executeAfter) {
            console.log("Executing trusted taker:", taker);
            enhancedOptions.executeConfigUpdate(IEnhancedOptionsTimelock.TimelockConfigType.TrustedTaker, key);
        } else {
            console.log("Trusted taker pending until:", executeAfter);
        }
    }

    function _syncTrustedMaker(EnhancedOptions enhancedOptions, address maker, bool desired) internal {
        bool current = enhancedOptions.trustedMakers(maker);
        bytes memory key = abi.encode(maker);
        (, uint64 executeAfter) =
            enhancedOptions.pendingConfigUpdate(IEnhancedOptionsTimelock.TimelockConfigType.TrustedMaker, key);
        if (!desired) {
            if (current || executeAfter != 0) enhancedOptions.setTrustedMaker(maker, false);
            return;
        }
        if (current) return;
        if (executeAfter == 0) {
            console.log("Scheduling trusted maker:", maker);
            enhancedOptions.scheduleConfigUpdate(IEnhancedOptionsTimelock.TimelockConfigType.TrustedMaker, key);
        } else if (block.timestamp >= executeAfter) {
            console.log("Executing trusted maker:", maker);
            enhancedOptions.executeConfigUpdate(IEnhancedOptionsTimelock.TimelockConfigType.TrustedMaker, key);
        } else {
            console.log("Trusted maker pending until:", executeAfter);
        }
    }
}

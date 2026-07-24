// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {EnhancedOptions} from "src/core/EnhancedOptions.sol";
import {IEnhancedOptionsTimelock} from "src/core/interfaces/IEnhancedOptionsTimelock.sol";
import {stdJson} from "forge-std/StdJson.sol";

/**
 * @notice Configure EnhancedOptions makerWhitelist & custody limits from config/<chainId>.json.
 *
 * Config keys:
 *   .EnhancedOptions.makerWhitelist       -> array of { "maker": address, "receiver": address }
 *   .EnhancedOptions.makerCustodyLimitBps -> array of { "maker": address, "receiver": address, "bps": uint256 }
 *
 * makerWhitelist changes and non-zero makerCustodyLimitBps changes use the
 * EnhancedOptions 48-hour schedule/execute timelock.
 *
 * For each entry the on-chain value is read; a tx is only sent when the desired
 * value differs. Pass `bps = 0` to revoke authorization for a (maker, receiver) pair.
 *
 * Required env vars:
 *   PRIVATE_KEY (must be EnhancedOptions owner)
 */
contract ConfigureCustodyLimits is Script {
    using stdJson for string;

    struct MakerEntry {
        address maker;
        address receiver;
    }

    struct CustodyLimitEntry {
        uint256 bps;
        address maker;
        address receiver;
    }

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
        console.log("Configuring whitelist mappings on EnhancedOptions:", enhancedOptionsAddr);

        vm.startBroadcast(deployerPrivateKey);

        if (vm.keyExists(configJson, ".EnhancedOptions.makerWhitelist")) {
            bytes memory raw = configJson.parseRaw(".EnhancedOptions.makerWhitelist");
            MakerEntry[] memory entries = abi.decode(raw, (MakerEntry[]));
            for (uint256 i = 0; i < entries.length; i++) {
                address maker = entries[i].maker;
                address desired = entries[i].receiver;
                require(maker != address(0), "makerWhitelist: maker cannot be zero");
                _syncMakerWhitelist(enhancedOptions, maker, desired);
            }
        }

        if (vm.keyExists(configJson, ".EnhancedOptions.makerCustodyLimitBps")) {
            bytes memory raw = configJson.parseRaw(".EnhancedOptions.makerCustodyLimitBps");
            CustodyLimitEntry[] memory entries = abi.decode(raw, (CustodyLimitEntry[]));
            for (uint256 i = 0; i < entries.length; i++) {
                address maker = entries[i].maker;
                address receiver = entries[i].receiver;
                uint256 desiredBps = entries[i].bps;
                require(maker != address(0), "makerCustodyLimitBps: maker cannot be zero");
                require(receiver != address(0), "makerCustodyLimitBps: receiver cannot be zero");

                _syncMakerCustodyLimit(enhancedOptions, maker, receiver, desiredBps);
            }
        }

        vm.stopBroadcast();
        console.log("ConfigureWhitelistMappings complete.");
    }

    function _syncMakerWhitelist(EnhancedOptions enhancedOptions, address maker, address desired) internal {
        address current = enhancedOptions.makerWhitelist(maker);
        bytes memory key = abi.encode(maker);
        (bytes memory pendingData, uint64 executeAfter) =
            enhancedOptions.pendingConfigUpdate(IEnhancedOptionsTimelock.TimelockConfigType.MakerWhitelist, key);
        address pendingValue;
        if (pendingData.length != 0) (, pendingValue) = abi.decode(pendingData, (address, address));

        if (executeAfter != 0 && pendingValue != desired) {
            enhancedOptions.cancelConfigUpdate(IEnhancedOptionsTimelock.TimelockConfigType.MakerWhitelist, key);
            executeAfter = 0;
        }
        if (current == desired) {
            if (executeAfter != 0) {
                enhancedOptions.cancelConfigUpdate(IEnhancedOptionsTimelock.TimelockConfigType.MakerWhitelist, key);
            }
            return;
        }
        if (executeAfter == 0) {
            console.log("Scheduling makerWhitelist:", maker, desired);
            enhancedOptions.scheduleConfigUpdate(
                IEnhancedOptionsTimelock.TimelockConfigType.MakerWhitelist, abi.encode(maker, desired)
            );
        } else if (block.timestamp >= executeAfter) {
            console.log("Executing makerWhitelist:", maker, desired);
            enhancedOptions.executeConfigUpdate(IEnhancedOptionsTimelock.TimelockConfigType.MakerWhitelist, key);
        } else {
            console.log("makerWhitelist pending until:", executeAfter);
        }
    }

    function _syncMakerCustodyLimit(
        EnhancedOptions enhancedOptions,
        address maker,
        address receiver,
        uint256 desiredBps
    ) internal {
        uint256 current = enhancedOptions.makerCustodyLimitBps(maker, receiver);
        bytes memory key = abi.encode(maker, receiver);
        (bytes memory pendingData, uint64 executeAfter) =
            enhancedOptions.pendingConfigUpdate(IEnhancedOptionsTimelock.TimelockConfigType.MakerCustodyLimitBps, key);
        uint256 pendingValue;
        if (pendingData.length != 0) (,, pendingValue) = abi.decode(pendingData, (address, address, uint256));

        if (desiredBps == 0) {
            if (current != 0 || executeAfter != 0) enhancedOptions.setMakerCustodyLimitBps(maker, receiver, 0);
            return;
        }
        if (executeAfter != 0 && pendingValue != desiredBps) {
            enhancedOptions.cancelConfigUpdate(IEnhancedOptionsTimelock.TimelockConfigType.MakerCustodyLimitBps, key);
            executeAfter = 0;
        }
        if (current == desiredBps) {
            if (executeAfter != 0) {
                enhancedOptions.cancelConfigUpdate(
                    IEnhancedOptionsTimelock.TimelockConfigType.MakerCustodyLimitBps, key
                );
            }
            return;
        }
        if (executeAfter == 0) {
            console.log("Scheduling makerCustodyLimitBps:", maker, receiver, desiredBps);
            enhancedOptions.scheduleConfigUpdate(
                IEnhancedOptionsTimelock.TimelockConfigType.MakerCustodyLimitBps,
                abi.encode(maker, receiver, desiredBps)
            );
        } else if (block.timestamp >= executeAfter) {
            console.log("Executing makerCustodyLimitBps:", maker, receiver, desiredBps);
            enhancedOptions.executeConfigUpdate(IEnhancedOptionsTimelock.TimelockConfigType.MakerCustodyLimitBps, key);
        } else {
            console.log("makerCustodyLimitBps pending until:", executeAfter);
        }
    }
}

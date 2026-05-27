// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {EnhancedOptions} from "src/core/EnhancedOptions.sol";
import {stdJson} from "forge-std/StdJson.sol";

/**
 * @notice Configure EnhancedOptions makerWhitelist & borrowerWhitelist from config/<chainId>.json.
 *
 * Config keys:
 *   .EnhancedOptions.makerWhitelist       -> array of { "maker": address, "receiver": address }
 *   .EnhancedOptions.makerCustodyLimitBps -> array of { "maker": address, "receiver": address, "bps": uint256 }
 *
 * Each makerCustodyLimitBps entry calls `setMakerCustodyLimitBps(maker, receiver, bps)`,
 * which both authorizes the (maker, receiver) pair to borrow vault collateral and sets
 * its credit limit (basis points of each vault's deposited asset).
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
                address current = enhancedOptions.makerWhitelist(maker);
                if (current == desired) {
                    console.log("makerWhitelist already up-to-date:", maker);
                    continue;
                }
                console.log("setMakerWhitelist:", maker, "->", desired);
                enhancedOptions.setMakerWhitelist(maker, desired);
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

                uint256 currentBps = enhancedOptions.makerCustodyLimitBps(maker, receiver);
                if (currentBps == desiredBps) {
                    console.log("makerCustodyLimitBps already up-to-date:", maker, receiver);
                    continue;
                }
                console.log("setMakerCustodyLimitBps:", maker, receiver, desiredBps);
                enhancedOptions.setMakerCustodyLimitBps(maker, receiver, desiredBps);
            }
        }

        vm.stopBroadcast();
        console.log("ConfigureWhitelistMappings complete.");
    }
}

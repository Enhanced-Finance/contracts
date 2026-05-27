// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {EnhancedVault} from "src/periphery/vault/EnhancedVault.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {Strings} from "lib/openzeppelin-contracts/contracts/utils/Strings.sol";

contract UpgradeEnhancedVault is Script {
    using stdJson for string;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        uint256 chainId = block.chainid;
        string memory chainIdStr = vm.toString(chainId);
        string memory deployPath = string.concat(vm.projectRoot(), "/.deploy/", chainIdStr, ".json");

        require(vm.isFile(deployPath), "Deploy file not found");
        string memory deployJson = vm.readFile(deployPath);
        address proxyAddr = deployJson.readAddress(".EnhancedVault.proxyAddress");
        require(proxyAddr != address(0), "EnhancedVault proxy not found");
        _validateEnhancedVaultLibraries(deployJson);
        string memory libraryFlags = _enhancedVaultLibraryFlags(deployJson);

        vm.startBroadcast(deployerPrivateKey);
        EnhancedVault newImplementation = new EnhancedVault();
        EnhancedVault(proxyAddr).upgradeToAndCall(address(newImplementation), "");
        vm.stopBroadcast();

        console.log("EnhancedVault upgraded:", proxyAddr);
        console.log("New implementation:", address(newImplementation));

        string memory verifyImplCmd = string.concat(
            "forge verify-contract --chain-id ",
            chainIdStr,
            " --num-of-optimizations 200 --watch ",
            Strings.toHexString(address(newImplementation)),
            libraryFlags,
            " src/periphery/vault/EnhancedVault.sol:EnhancedVault"
        );

        vm.writeJson(
            string.concat("\"", vm.toString(address(newImplementation)), "\""),
            deployPath,
            ".EnhancedVault.implementationAddress"
        );
        vm.writeJson(string.concat("\"", verifyImplCmd, "\""), deployPath, ".EnhancedVault.verifyImplementationCommand");
    }

    function _validateEnhancedVaultLibraries(string memory deployJson)
        internal
        view
        returns (address recordsLib, address cycleLib)
    {
        require(vm.keyExists(deployJson, ".EnhancedVault.recordsLibraryAddress"), "Records library address missing");
        require(vm.keyExists(deployJson, ".EnhancedVault.cycleLibraryAddress"), "Cycle library address missing");

        recordsLib = deployJson.readAddress(".EnhancedVault.recordsLibraryAddress");
        cycleLib = deployJson.readAddress(".EnhancedVault.cycleLibraryAddress");

        require(recordsLib.code.length != 0, "Records library has no code");
        require(cycleLib.code.length != 0, "Cycle library has no code");

        bytes memory creationCode = type(EnhancedVault).creationCode;
        require(_containsLinkedAddress(creationCode, recordsLib), "EnhancedVault not linked to records library");
        require(_containsLinkedAddress(creationCode, cycleLib), "EnhancedVault not linked to cycle library");
    }

    function _enhancedVaultLibraryFlags(string memory deployJson) internal pure returns (string memory) {
        address recordsLib = deployJson.readAddress(".EnhancedVault.recordsLibraryAddress");
        address cycleLib = deployJson.readAddress(".EnhancedVault.cycleLibraryAddress");
        return string.concat(
            " --libraries src/periphery/vault/libs/EnhancedVaultRecordsLib.sol:EnhancedVaultRecordsLib:",
            Strings.toHexString(recordsLib),
            " --libraries src/periphery/vault/libs/EnhancedVaultCycleLib.sol:EnhancedVaultCycleLib:",
            Strings.toHexString(cycleLib)
        );
    }

    function _containsLinkedAddress(bytes memory code, address target) internal pure returns (bool) {
        bytes20 needle = bytes20(target);
        if (code.length < 20) return false;

        for (uint256 i; i <= code.length - 20; ++i) {
            bytes20 found;
            assembly {
                found := mload(add(add(code, 0x20), i))
            }
            if (found == needle) return true;
        }

        return false;
    }
}

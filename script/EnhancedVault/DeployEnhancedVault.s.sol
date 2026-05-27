// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {EnhancedVault} from "src/periphery/vault/EnhancedVault.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {Strings} from "lib/openzeppelin-contracts/contracts/utils/Strings.sol";

contract DeployEnhancedVault is Script {
    using stdJson for string;
    using Strings for uint256;
    using Strings for address;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        uint256 chainId = block.chainid;
        string memory chainIdStr = chainId.toString();

        string memory deployDir = string.concat(vm.projectRoot(), "/.deploy/");

        if (!vm.isDir(deployDir)) {
            vm.createDir(deployDir, true);
        }

        string memory path = string.concat(deployDir, chainIdStr, ".json");

        if (!vm.isFile(path)) {
            vm.writeJson("{}", path);
        }
        string memory deployJson = vm.readFile(path);
        (address recordsLib, address cycleLib) = _validateEnhancedVaultLibraries(deployJson);
        string memory libraryFlags = _enhancedVaultLibraryFlags(deployJson);

        console.log("Deploying EnhancedVault Implementation on chain ID:", chainIdStr);

        vm.startBroadcast(deployerPrivateKey);
        EnhancedVault impl = new EnhancedVault();
        vm.stopBroadcast();

        console.log("Implementation deployed at:", address(impl));

        string memory jsonObj = "deployment_data";
        vm.serializeString(jsonObj, "contractName", "EnhancedVault");
        vm.serializeAddress(jsonObj, "implementationAddress", address(impl));
        vm.serializeAddress(jsonObj, "recordsLibraryAddress", recordsLib);
        vm.serializeAddress(jsonObj, "cycleLibraryAddress", cycleLib);
        if (vm.keyExists(deployJson, ".EnhancedVault.recordsLibraryVerifyCommand")) {
            vm.serializeString(
                jsonObj,
                "recordsLibraryVerifyCommand",
                deployJson.readString(".EnhancedVault.recordsLibraryVerifyCommand")
            );
        }
        if (vm.keyExists(deployJson, ".EnhancedVault.cycleLibraryVerifyCommand")) {
            vm.serializeString(
                jsonObj, "cycleLibraryVerifyCommand", deployJson.readString(".EnhancedVault.cycleLibraryVerifyCommand")
            );
        }
        if (vm.keyExists(deployJson, ".EnhancedVault.proxyAddress")) {
            vm.serializeAddress(jsonObj, "proxyAddress", deployJson.readAddress(".EnhancedVault.proxyAddress"));
        }
        if (vm.keyExists(deployJson, ".EnhancedVault.verifyProxyCommand")) {
            vm.serializeString(
                jsonObj, "verifyProxyCommand", deployJson.readString(".EnhancedVault.verifyProxyCommand")
            );
        }

        string memory verifyImplCmd = string.concat(
            "forge verify-contract --chain-id ",
            chainIdStr,
            " --num-of-optimizations 200 --watch ",
            Strings.toHexString(address(impl)),
            libraryFlags,
            " src/periphery/vault/EnhancedVault.sol:EnhancedVault"
        );
        string memory finalJson = vm.serializeString(jsonObj, "verifyImplementationCommand", verifyImplCmd);

        vm.writeJson(finalJson, path, ".EnhancedVault");
        console.log("Deployment info saved to:", path);
        console.log("EnhancedVault implementation was linked to:");
        console.log("  records library:", recordsLib);
        console.log("  cycle library:", cycleLib);
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
            recordsLib.toHexString(),
            " --libraries src/periphery/vault/libs/EnhancedVaultCycleLib.sol:EnhancedVaultCycleLib:",
            cycleLib.toHexString()
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

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {EnhancedVault} from "src/periphery/vault/EnhancedVault.sol";
import {ERC1967Proxy} from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Strings} from "lib/openzeppelin-contracts/contracts/utils/Strings.sol";
import {stdJson} from "forge-std/StdJson.sol";

/**
 * @notice Deploys the ERC1967 proxy for EnhancedVault.
 *
 * Required env vars:
 *   PRIVATE_KEY                   deployer private key
 *   VAULT_ENHANCED_OPTIONS     address of EnhancedOptions proxy (or read from .deploy)
 *   VAULT_OPERATOR             fallback address of the initial operator
 *   VAULT_SIGNER               fallback address of the vault signer (off-chain quote signer)
 *   VAULT_PROTOCOL_FEE_RECIPIENT fallback address of the protocol fee recipient
 *
 * Operator/signer/protocol fee recipient are read from config/<chainId>.json first:
 *   .EnhancedVault.operator
 *   .EnhancedVault.vaultSigner
 *   .EnhancedVault.protocolFeeRecipient
 * Env vars are only used as fallback.
 */
contract DeployEnhancedVaultProxy is Script {
    using Strings for uint256;
    using stdJson for string;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        uint256 chainId = block.chainid;
        string memory chainIdStr = chainId.toString();
        string memory deployDir = string.concat(vm.projectRoot(), "/.deploy/");
        string memory configPath = string.concat(vm.projectRoot(), "/config/", chainIdStr, ".json");

        if (!vm.isDir(deployDir)) {
            vm.createDir(deployDir, true);
        }

        string memory path = string.concat(deployDir, chainIdStr, ".json");
        string memory json = vm.readFile(path);
        string memory configJson = vm.readFile(configPath);

        address implementation = json.readAddress(".EnhancedVault.implementationAddress");
        string memory verifyImplCmd = json.readString(".EnhancedVault.verifyImplementationCommand");
        require(implementation != address(0), "Implementation address not found in deploy file");

        // Resolve EnhancedOptions address: .deploy file takes priority, else env var
        address enhancedOptions;
        if (vm.keyExists(json, ".EnhancedOptions.proxyAddress")) {
            enhancedOptions = json.readAddress(".EnhancedOptions.proxyAddress");
        }
        if (enhancedOptions == address(0)) {
            enhancedOptions = vm.envAddress("VAULT_ENHANCED_OPTIONS");
        }
        require(enhancedOptions != address(0), "EnhancedOptions address not found");

        address operator;
        if (vm.keyExists(configJson, ".EnhancedVault.operator")) {
            operator = configJson.readAddress(".EnhancedVault.operator");
        } else if (vm.envOr("VAULT_OPERATOR", address(0)) != address(0)) {
            operator = vm.envAddress("VAULT_OPERATOR");
        }

        address vaultSigner;
        if (vm.keyExists(configJson, ".EnhancedVault.vaultSigner")) {
            vaultSigner = configJson.readAddress(".EnhancedVault.vaultSigner");
        } else if (vm.envOr("VAULT_SIGNER", address(0)) != address(0)) {
            vaultSigner = vm.envAddress("VAULT_SIGNER");
        }

        address protocolFeeRecipient;
        if (vm.keyExists(configJson, ".EnhancedVault.protocolFeeRecipient")) {
            protocolFeeRecipient = configJson.readAddress(".EnhancedVault.protocolFeeRecipient");
        } else if (vm.envOr("VAULT_PROTOCOL_FEE_RECIPIENT", address(0)) != address(0)) {
            protocolFeeRecipient = vm.envAddress("VAULT_PROTOCOL_FEE_RECIPIENT");
        }
        require(operator != address(0), "VAULT_OPERATOR not set");
        require(vaultSigner != address(0), "VAULT_SIGNER not set");
        require(protocolFeeRecipient != address(0), "VAULT_PROTOCOL_FEE_RECIPIENT not set");

        console.log("Deploying EnhancedVault Proxy for implementation:", implementation);
        console.log("  enhancedOptions:", enhancedOptions);
        console.log("  operator:", operator);
        console.log("  vaultSigner:", vaultSigner);
        console.log("  protocolFeeRecipient:", protocolFeeRecipient);

        vm.startBroadcast(deployerPrivateKey);
        ERC1967Proxy proxy = new ERC1967Proxy(
            implementation,
            abi.encodeCall(EnhancedVault.initialize, (enhancedOptions, operator, vaultSigner, protocolFeeRecipient))
        );
        vm.stopBroadcast();

        console.log("Proxy deployed at:", address(proxy));

        string memory jsonObj = "deployment_data";
        vm.serializeString(jsonObj, "contractName", "EnhancedVault");
        vm.serializeAddress(jsonObj, "implementationAddress", implementation);
        vm.serializeString(jsonObj, "verifyImplementationCommand", verifyImplCmd);
        if (vm.keyExists(json, ".EnhancedVault.recordsLibraryAddress")) {
            vm.serializeAddress(
                jsonObj, "recordsLibraryAddress", json.readAddress(".EnhancedVault.recordsLibraryAddress")
            );
        }
        if (vm.keyExists(json, ".EnhancedVault.cycleLibraryAddress")) {
            vm.serializeAddress(jsonObj, "cycleLibraryAddress", json.readAddress(".EnhancedVault.cycleLibraryAddress"));
        }
        if (vm.keyExists(json, ".EnhancedVault.recordsLibraryVerifyCommand")) {
            vm.serializeString(
                jsonObj, "recordsLibraryVerifyCommand", json.readString(".EnhancedVault.recordsLibraryVerifyCommand")
            );
        }
        if (vm.keyExists(json, ".EnhancedVault.cycleLibraryVerifyCommand")) {
            vm.serializeString(
                jsonObj, "cycleLibraryVerifyCommand", json.readString(".EnhancedVault.cycleLibraryVerifyCommand")
            );
        }
        vm.serializeAddress(jsonObj, "proxyAddress", address(proxy));
        vm.serializeUint(jsonObj, "blockNumber", block.number);

        string memory verifyProxyCmd = string.concat(
            "forge verify-contract --chain-id ",
            chainIdStr,
            " --num-of-optimizations 200 --watch ",
            Strings.toHexString(address(proxy)),
            " lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy",
            " --constructor-args ",
            Strings.toHexString(
                abi.encode(
                    implementation,
                    abi.encodeCall(
                        EnhancedVault.initialize, (enhancedOptions, operator, vaultSigner, protocolFeeRecipient)
                    )
                )
            )
        );
        string memory finalJson = vm.serializeString(jsonObj, "verifyProxyCommand", verifyProxyCmd);

        vm.writeJson(finalJson, path, ".EnhancedVault");
        console.log("Proxy deployment info updated in:", path);
    }
}

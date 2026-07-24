// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {EnhancedOptions} from "src/core/EnhancedOptions.sol";
import {ERC1967Proxy} from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Strings} from "lib/openzeppelin-contracts/contracts/utils/Strings.sol";
import {stdJson} from "forge-std/StdJson.sol";

contract DeployEnhancedOptionsProxy is Script {
    using Strings for uint256;
    using stdJson for string;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        uint256 chainId = block.chainid;
        string memory chainIdStr = chainId.toString();
        string memory deployDir = string.concat(vm.projectRoot(), "/.deploy/");
        if (!vm.isDir(deployDir)) {
            vm.createDir(deployDir, true);
        }

        string memory path = string.concat(deployDir, chainIdStr, ".json");
        string memory configPath = string.concat(vm.projectRoot(), "/config/", chainIdStr, ".json");
        string memory json = vm.readFile(path);
        string memory configJson = vm.readFile(configPath);
        address implementation = json.readAddress(".EnhancedOptions.implementationAddress");
        string memory verifyImplCmd = json.readString(".EnhancedOptions.verifyImplementationCommand");

        require(implementation != address(0), "Implementation address not found in deploy file");

        address[] memory initialTrustedTakers;
        if (vm.keyExists(configJson, ".EnhancedOptions.trustedTakers")) {
            initialTrustedTakers = configJson.readAddressArray(".EnhancedOptions.trustedTakers");
        } else if (vm.keyExists(configJson, ".EnhancedOptions.trustedOperators")) {
            initialTrustedTakers = configJson.readAddressArray(".EnhancedOptions.trustedOperators");
        } else {
            initialTrustedTakers = new address[](0);
        }

        address[] memory initialTrustedMakers;
        if (vm.keyExists(configJson, ".EnhancedOptions.trustedMakers")) {
            initialTrustedMakers = configJson.readAddressArray(".EnhancedOptions.trustedMakers");
        } else {
            initialTrustedMakers = new address[](0);
        }

        address initialOperator;
        if (vm.keyExists(configJson, ".EnhancedOptions.operator")) {
            initialOperator = configJson.readAddress(".EnhancedOptions.operator");
        }

        address initialCustodyOperator;
        if (vm.keyExists(configJson, ".EnhancedOptions.custodyOperator")) {
            initialCustodyOperator = configJson.readAddress(".EnhancedOptions.custodyOperator");
        } else if (vm.keyExists(configJson, ".EnhancedOptions.operator")) {
            initialCustodyOperator = configJson.readAddress(".EnhancedOptions.operator");
        }
        require(initialOperator != address(0), "EnhancedOptions operator missing");
        require(initialCustodyOperator != address(0), "EnhancedOptions custodyOperator missing");

        console.log("Deploying Proxy for Implementation at:", implementation);
        console.log("Initial operator:", initialOperator);
        console.log("Initial custody operator:", initialCustodyOperator);

        vm.startBroadcast(deployerPrivateKey);
        ERC1967Proxy proxy = new ERC1967Proxy(
            implementation,
            abi.encodeCall(
                EnhancedOptions.initialize,
                (initialTrustedTakers, initialTrustedMakers, initialOperator, initialCustodyOperator)
            )
        );
        vm.stopBroadcast();

        console.log("Proxy deployed at:", address(proxy));

        string memory jsonObj = "deployment_data";

        vm.serializeString(jsonObj, "contractName", "EnhancedOptions");
        vm.serializeAddress(jsonObj, "implementationAddress", implementation);
        vm.serializeString(jsonObj, "verifyImplementationCommand", verifyImplCmd);
        vm.serializeAddress(jsonObj, "proxyAddress", address(proxy));
        vm.serializeUint(jsonObj, "blockNumber", block.number);

        // Verification command for proxy
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
                        EnhancedOptions.initialize,
                        (initialTrustedTakers, initialTrustedMakers, initialOperator, initialCustodyOperator)
                    )
                )
            )
        );
        string memory finalJson = vm.serializeString(jsonObj, "verifyProxyCommand", verifyProxyCmd);

        vm.writeJson(finalJson, path, ".EnhancedOptions");
        console.log("Proxy deployment info updated in:", path);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {EnhancedOptions} from "src/core/EnhancedOptions.sol";
import {Strings} from "lib/openzeppelin-contracts/contracts/utils/Strings.sol";
import {stdJson} from "forge-std/StdJson.sol";

contract DeployEnhancedOptions is Script {
    using Strings for uint256;
    using Strings for address;
    using stdJson for string;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        uint256 chainId = block.chainid;
        string memory chainIdStr = chainId.toString();
        string memory deployDir = string.concat(vm.projectRoot(), "/.deploy/");
        string memory path = string.concat(deployDir, chainIdStr, ".json");
        require(vm.isFile(path), "Deploy file not found");
        string memory deployJson = vm.readFile(path);
        require(vm.keyExists(deployJson, ".EnhancedOptions.parserLibraryAddress"), "Parser library address missing");
        address parserLib = deployJson.readAddress(".EnhancedOptions.parserLibraryAddress");
        require(parserLib.code.length != 0, "Parser library has no code");
        require(vm.keyExists(deployJson, ".EnhancedOptions.timelockLibraryAddress"), "Timelock library address missing");
        address timelockLib = deployJson.readAddress(".EnhancedOptions.timelockLibraryAddress");
        require(timelockLib.code.length != 0, "Timelock library has no code");
        require(
            _containsLinkedAddress(type(EnhancedOptions).creationCode, parserLib), "EnhancedOptions Parser not linked"
        );
        require(_containsLinkedAddress(type(EnhancedOptions).creationCode, timelockLib), "EnhancedOptions not linked");

        console.log("Deploying EnhancedOptions Implementation on chain ID:", chainIdStr);

        vm.startBroadcast(deployerPrivateKey);
        EnhancedOptions impl = new EnhancedOptions();
        vm.stopBroadcast();

        console.log("Implementation deployed at:", address(impl));

        string memory jsonObj = "deployment_data";

        vm.serializeString(jsonObj, "contractName", "EnhancedOptions");
        vm.serializeAddress(jsonObj, "implementationAddress", address(impl));
        vm.serializeAddress(jsonObj, "parserLibraryAddress", parserLib);
        if (vm.keyExists(deployJson, ".EnhancedOptions.parserLibraryVerifyCommand")) {
            vm.serializeString(
                jsonObj,
                "parserLibraryVerifyCommand",
                deployJson.readString(".EnhancedOptions.parserLibraryVerifyCommand")
            );
        }
        vm.serializeAddress(jsonObj, "timelockLibraryAddress", timelockLib);
        if (vm.keyExists(deployJson, ".EnhancedOptions.timelockLibraryVerifyCommand")) {
            vm.serializeString(
                jsonObj,
                "timelockLibraryVerifyCommand",
                deployJson.readString(".EnhancedOptions.timelockLibraryVerifyCommand")
            );
        }

        // Verification command for implementation
        string memory verifyImplCmd = string.concat(
            "forge verify-contract --chain-id ",
            chainIdStr,
            " --num-of-optimizations 200 --watch ",
            Strings.toHexString(address(impl)),
            " --libraries src/core/libs/Parser.sol:Parser:",
            parserLib.toHexString(),
            " --libraries src/core/libs/EnhancedOptionsTimelockLib.sol:EnhancedOptionsTimelockLib:",
            timelockLib.toHexString(),
            " src/core/EnhancedOptions.sol:EnhancedOptions"
        );
        string memory finalJson = vm.serializeString(jsonObj, "verifyImplementationCommand", verifyImplCmd);

        vm.writeJson(finalJson, path, ".EnhancedOptions");
        console.log("Deployment info saved to:", path);
    }

    function _containsLinkedAddress(bytes memory code, address target) internal pure returns (bool) {
        bytes20 needle = bytes20(target);
        if (code.length < 20) return false;
        for (uint256 i; i <= code.length - 20; i++) {
            bytes20 found;
            assembly {
                found := mload(add(add(code, 0x20), i))
            }
            if (found == needle) return true;
        }
        return false;
    }
}

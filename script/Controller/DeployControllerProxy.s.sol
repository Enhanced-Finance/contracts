// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {Controller} from "src/core/Controller.sol";
import {ERC1967Proxy} from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Strings} from "lib/openzeppelin-contracts/contracts/utils/Strings.sol";
import {stdJson} from "forge-std/StdJson.sol";

contract DeployControllerProxy is Script {
    using Strings for uint256;
    using stdJson for string;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        uint256 chainId = block.chainid;
        string memory chainIdStr = chainId.toString();
        string memory deployDir = string.concat(vm.projectRoot(), "/.deploy/");
        string memory path = string.concat(deployDir, chainIdStr, ".json");
        string memory configPath = string.concat(vm.projectRoot(), "/config/", chainIdStr, ".json");

        if (!vm.isDir(deployDir)) {
            vm.createDir(deployDir, true);
        }

        string memory json = vm.readFile(path);
        address implementation = json.readAddress(".Controller.implementationAddress");
        string memory verifyImplCmd = json.readString(".Controller.verifyImplementationCommand");

        require(implementation != address(0), "Implementation address not found in deploy file");

        string memory configJson = vm.readFile(configPath);

        address addressBook;
        if (vm.keyExists(json, ".AddressBook.proxyAddress")) {
            addressBook = json.readAddress(".AddressBook.proxyAddress");
        } else if (vm.keyExists(configJson, ".Controller.addressBook")) {
            addressBook = configJson.readAddress(".Controller.addressBook");
        }

        address owner = configJson.readAddress(".Controller.owner");
        address manager;
        if (vm.keyExists(json, ".EnhancedOptions.proxyAddress")) {
            manager = json.readAddress(".EnhancedOptions.proxyAddress");
        } else if (vm.keyExists(configJson, ".Controller.manager")) {
            manager = configJson.readAddress(".Controller.manager");
        }

        require(addressBook != address(0), "AddressBook address not found in config or deploy file");
        require(owner != address(0), "Owner address not found in config file");
        require(manager != address(0), "Manager address not found in config file");

        console.log("Deploying Controller Proxy for Implementation at:", implementation);
        console.log("AddressBook:", addressBook);
        console.log("Owner:", owner);
        console.log("Manager:", manager);

        vm.startBroadcast(deployerPrivateKey);
        ERC1967Proxy proxy =
            new ERC1967Proxy(implementation, abi.encodeCall(Controller.initialize, (addressBook, owner, manager)));
        vm.stopBroadcast();

        console.log("Proxy deployed at:", address(proxy));

        string memory jsonObj = "deployment_data";

        vm.serializeString(jsonObj, "contractName", "Controller");
        vm.serializeAddress(jsonObj, "implementationAddress", implementation);
        vm.serializeString(jsonObj, "verifyImplementationCommand", verifyImplCmd);
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
                abi.encode(implementation, abi.encodeCall(Controller.initialize, (addressBook, owner, manager)))
            )
        );
        string memory finalJson = vm.serializeString(jsonObj, "verifyProxyCommand", verifyProxyCmd);

        vm.writeJson(finalJson, path, ".Controller");
        console.log("Proxy deployment info updated in:", path);
    }
}

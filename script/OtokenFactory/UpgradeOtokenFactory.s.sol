// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {OtokenFactory} from "src/core/OtokenFactory.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {Strings} from "lib/openzeppelin-contracts/contracts/utils/Strings.sol";

contract UpgradeOtokenFactory is Script {
    using stdJson for string;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        uint256 chainId = block.chainid;
        string memory chainIdStr = vm.toString(chainId);
        string memory deployPath = string.concat(vm.projectRoot(), "/.deploy/", chainIdStr, ".json");

        require(vm.isFile(deployPath), "Deploy file not found");
        string memory deployJson = vm.readFile(deployPath);
        address proxyAddr = deployJson.readAddress(".OtokenFactory.proxyAddress");
        require(proxyAddr != address(0), "OtokenFactory proxy not found");

        vm.startBroadcast(deployerPrivateKey);
        OtokenFactory newImplementation = new OtokenFactory();
        OtokenFactory(proxyAddr).upgradeToAndCall(address(newImplementation), "");
        vm.stopBroadcast();

        string memory verifyImplCmd = string.concat(
            "forge verify-contract --chain-id ",
            chainIdStr,
            " --num-of-optimizations 200 --watch ",
            Strings.toHexString(address(newImplementation)),
            " src/OtokenFactory.sol:OtokenFactory"
        );

        vm.writeJson(
            string.concat("\"", vm.toString(address(newImplementation)), "\""),
            deployPath,
            ".OtokenFactory.implementationAddress"
        );
        vm.writeJson(string.concat("\"", verifyImplCmd, "\""), deployPath, ".OtokenFactory.verifyImplementationCommand");

        console.log("OtokenFactory upgraded:", proxyAddr);
        console.log("New implementation:", address(newImplementation));
    }
}

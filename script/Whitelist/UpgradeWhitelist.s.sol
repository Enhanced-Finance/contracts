// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {Whitelist} from "src/core/Whitelist.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {Strings} from "lib/openzeppelin-contracts/contracts/utils/Strings.sol";

contract UpgradeWhitelist is Script {
    using stdJson for string;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        uint256 chainId = block.chainid;
        string memory chainIdStr = vm.toString(chainId);
        string memory deployPath = string.concat(vm.projectRoot(), "/.deploy/", chainIdStr, ".json");

        require(vm.isFile(deployPath), "Deploy file not found");
        string memory deployJson = vm.readFile(deployPath);
        address proxyAddr = deployJson.readAddress(".Whitelist.proxyAddress");
        require(proxyAddr != address(0), "Whitelist proxy not found");

        vm.startBroadcast(deployerPrivateKey);
        Whitelist newImplementation = new Whitelist();
        Whitelist(proxyAddr).upgradeToAndCall(address(newImplementation), "");
        vm.stopBroadcast();

        string memory verifyImplCmd = string.concat(
            "forge verify-contract --chain-id ",
            chainIdStr,
            " --num-of-optimizations 200 --watch ",
            Strings.toHexString(address(newImplementation)),
            " src/Whitelist.sol:Whitelist"
        );

        vm.writeJson(
            string.concat("\"", vm.toString(address(newImplementation)), "\""),
            deployPath,
            ".Whitelist.implementationAddress"
        );
        vm.writeJson(
            string.concat("\"", verifyImplCmd, "\""),
            deployPath,
            ".Whitelist.verifyImplementationCommand"
        );

        console.log("Whitelist upgraded:", proxyAddr);
        console.log("New implementation:", address(newImplementation));
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {Oracle} from "src/core/Oracle.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {Strings} from "lib/openzeppelin-contracts/contracts/utils/Strings.sol";

contract UpgradeOracle is Script {
    using stdJson for string;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        uint256 chainId = block.chainid;
        string memory chainIdStr = vm.toString(chainId);
        string memory deployPath = string.concat(vm.projectRoot(), "/.deploy/", chainIdStr, ".json");

        require(vm.isFile(deployPath), "Deploy file not found");
        string memory deployJson = vm.readFile(deployPath);
        address proxyAddr = deployJson.readAddress(".Oracle.proxyAddress");
        require(proxyAddr != address(0), "Oracle proxy not found");

        vm.startBroadcast(deployerPrivateKey);
        Oracle newImplementation = new Oracle();
        Oracle(proxyAddr).upgradeToAndCall(address(newImplementation), "");
        vm.stopBroadcast();

        string memory verifyImplCmd = string.concat(
            "forge verify-contract --chain-id ",
            chainIdStr,
            " --num-of-optimizations 200 --watch ",
            Strings.toHexString(address(newImplementation)),
            " src/Oracle.sol:Oracle"
        );

        vm.writeJson(
            string.concat("\"", vm.toString(address(newImplementation)), "\""),
            deployPath,
            ".Oracle.implementationAddress"
        );
        vm.writeJson(string.concat("\"", verifyImplCmd, "\""), deployPath, ".Oracle.verifyImplementationCommand");

        console.log("Oracle upgraded:", proxyAddr);
        console.log("New implementation:", address(newImplementation));
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {MarginPool} from "src/core/MarginPool.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {Strings} from "lib/openzeppelin-contracts/contracts/utils/Strings.sol";

contract UpgradeMarginPool is Script {
    using stdJson for string;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        uint256 chainId = block.chainid;
        string memory chainIdStr = vm.toString(chainId);
        string memory deployPath = string.concat(vm.projectRoot(), "/.deploy/", chainIdStr, ".json");

        require(vm.isFile(deployPath), "Deploy file not found");
        string memory deployJson = vm.readFile(deployPath);
        address proxyAddr = deployJson.readAddress(".MarginPool.proxyAddress");
        require(proxyAddr != address(0), "MarginPool proxy not found");

        vm.startBroadcast(deployerPrivateKey);
        MarginPool newImplementation = new MarginPool();
        MarginPool(proxyAddr).upgradeToAndCall(address(newImplementation), "");
        vm.stopBroadcast();

        string memory verifyImplCmd = string.concat(
            "forge verify-contract --chain-id ",
            chainIdStr,
            " --num-of-optimizations 200 --watch ",
            Strings.toHexString(address(newImplementation)),
            " src/MarginPool.sol:MarginPool"
        );

        vm.writeJson(
            string.concat("\"", vm.toString(address(newImplementation)), "\""),
            deployPath,
            ".MarginPool.implementationAddress"
        );
        vm.writeJson(string.concat("\"", verifyImplCmd, "\""), deployPath, ".MarginPool.verifyImplementationCommand");

        console.log("MarginPool upgraded:", proxyAddr);
        console.log("New implementation:", address(newImplementation));
    }
}

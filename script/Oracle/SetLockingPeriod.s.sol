// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {Oracle} from "src/core/Oracle.sol";
import {stdJson} from "forge-std/StdJson.sol";

contract SetLockingPeriod is Script {
    using stdJson for string;

    // --- Configuration: Set these values before running ---
    uint256 constant LOCKING_PERIOD = 0; // Locking period in seconds (e.g., 0 for instant settlement testing)

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        address pricer = vm.envAddress("PRICER");

        uint256 chainId = block.chainid;
        string memory chainIdStr = vm.toString(chainId);
        string memory deployPath = string.concat(vm.projectRoot(), "/.deploy/", chainIdStr, ".json");

        require(vm.isFile(deployPath), "Deploy file not found");
        string memory deployJson = vm.readFile(deployPath);
        address oracleAddr = deployJson.readAddress(".Oracle.proxyAddress");
        require(oracleAddr != address(0), "Oracle proxy not found");

        console.log("Executing SetLockingPeriod on Oracle:", oracleAddr);
        console.log("Caller (Owner):", deployer);
        console.log("Pricer:", pricer);
        console.log("Locking Period:", LOCKING_PERIOD);

        Oracle oracle = Oracle(oracleAddr);

        vm.startBroadcast(deployerPrivateKey);
        oracle.setLockingPeriod(pricer, LOCKING_PERIOD);
        vm.stopBroadcast();

        console.log("Locking Period updated successfully.");
    }
}

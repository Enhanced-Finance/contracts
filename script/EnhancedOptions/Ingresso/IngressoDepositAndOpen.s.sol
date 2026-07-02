// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {EnhancedOptions} from "src/core/EnhancedOptions.sol";
import {stdJson} from "lib/forge-std/src/StdJson.sol";

contract IngressoDepositAndOpen is Script {
    using stdJson for string;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        uint256 chainId = block.chainid;
        string memory chainIdStr = vm.toString(chainId);
        string memory deployPath = string.concat(vm.projectRoot(), "/.deploy/", chainIdStr, ".json");

        require(vm.isFile(deployPath), "Deploy file not found");
        string memory deployJson = vm.readFile(deployPath);
        address enhancedOptionsAddr = deployJson.readAddress(".EnhancedOptions.proxyAddress");
        require(enhancedOptionsAddr != address(0), "EnhancedOptions proxy not found");

        bytes memory transferPayload = vm.parseBytes(vm.envString("TRANSFER_PAYLOAD"));
        bytes memory orderPayload = vm.parseBytes(vm.envString("ORDER_PAYLOAD"));

        console.log("TRANSFER_PAYLOAD length:", transferPayload.length);
        console.log("ORDER_PAYLOAD length:", orderPayload.length);
        require(
            transferPayload.length == 130 || transferPayload.length == 150,
            "Invalid transfer payload length, expected 130 or 150"
        );
        require(orderPayload.length == 377, "Invalid order payload length, expected 377");

        console.log("Executing IngressoDepositAndOpen on:", enhancedOptionsAddr);
        console.log("Caller (Operator):", deployer);

        vm.startBroadcast(deployerPrivateKey);
        EnhancedOptions(enhancedOptionsAddr).ingressoDepositAndOpen(transferPayload, orderPayload);
        vm.stopBroadcast();

        console.log("IngressoDepositAndOpen executed successfully");
    }
}

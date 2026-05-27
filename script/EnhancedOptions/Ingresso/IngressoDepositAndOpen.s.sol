// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {EnhancedOptions} from "src/core/EnhancedOptions.sol";
import {stdJson} from "lib/forge-std/src/StdJson.sol";

contract IngressoDepositAndOpen is Script {
    using stdJson for string;

    // --- Configuration: set these bytes payloads before running ---
    // transferPayload should be either 130-byte (user pays) or 150-byte (with payer) payload, in 0x-prefixed hex string
    string constant TRANSFER_PAYLOAD =
        "0xea2d8c2c17a36eaa77765505b325e0c8b091805700000000000000000000000000989680010001768269ad03d044a2095c408f0d5707c1650d182f156ad8912a8c47cd567c1f3838bf8c29d6cf44d5b37f81e9511e6a244b1c5f6496c49c14f6f487abadcbfa3e8190f2d1c58e1bd157f637262b0e6af035baa35a5475e56b100d1b";
    // orderPayload should be 361-byte Quote+Confirmation payload, in 0x-prefixed hex string
    string constant ORDER_PAYLOAD =
        "0xd157f637262b0e6af035baa35a5475e56b100d1b5cc75d8c5d9a22ac35d7cb734159b2da5554981f0000000069f3ed000000000000000000019a00000000000000000de0b6b3a764000000000000000000008ac7230489e8000000000000000000008ac7230489e800000000019dd94ede0e0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000d33cb6ca502e2215b0572f050c5a69f59f187a5c4b008770149fe7c8a54edc22404301ee45e90619d7faaca4877b0d421f61f58033feffb16f022d1861b72faa1b0000000000000000000000746a52880056e49a068e368f2d40ffe9314033671cf3402ec1010000000069f3ed00ea2d8c2c17a36eaa77765505b325e0c8b09180575cc75d8c5d9a22ac35d7cb734159b2da5554981f00000000000000008ac7230489e8000000000000000000000000000000000000";

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

        bytes memory transferPayload = vm.parseBytes(TRANSFER_PAYLOAD);
        bytes memory orderPayload = vm.parseBytes(ORDER_PAYLOAD);

        console.log("TRANSFER_PAYLOAD length:", transferPayload.length);
        console.log("ORDER_PAYLOAD length:", orderPayload.length);
        require(
            transferPayload.length == 130 || transferPayload.length == 150,
            "Invalid transfer payload length, expected 130 or 150"
        );
        require(orderPayload.length == 361, "Invalid order payload length, expected 361");

        console.log("Executing IngressoDepositAndOpen on:", enhancedOptionsAddr);
        console.log("Caller (Operator):", deployer);

        vm.startBroadcast(deployerPrivateKey);
        EnhancedOptions(enhancedOptionsAddr).ingressoDepositAndOpen(transferPayload, orderPayload);
        vm.stopBroadcast();

        console.log("IngressoDepositAndOpen executed successfully");
    }
}

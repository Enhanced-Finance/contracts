// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {MockERC20} from "src/core/mocks/MockERC20.sol";

contract DeployMockERC20 is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        string memory name = vm.envOr("MOCK_NAME", string("Wrapped BTC"));
        string memory symbol = vm.envOr("MOCK_SYMBOL", string("WBTC"));
        uint8 decimals = 18;

        console.log("Deploying MockERC20...");
        console.log("Name:", name);
        console.log("Symbol:", symbol);
        console.log("Decimals:", decimals);
        console.log("Deployer:", deployer);

        vm.startBroadcast(deployerPrivateKey);

        MockERC20 mock = new MockERC20(name, symbol, decimals);

        vm.stopBroadcast();

        console.log("Deployed MockERC20 at:", address(mock));
    }
}

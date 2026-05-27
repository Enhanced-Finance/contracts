// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {AddressBook} from "src/core/AddressBook.sol";
import {stdJson} from "forge-std/StdJson.sol";

contract QueryAddressBook is Script {
    using stdJson for string;

    function run() public view {
        uint256 chainId = block.chainid;
        string memory chainIdStr = vm.toString(chainId);
        string memory deployPath = string.concat(vm.projectRoot(), "/.deploy/", chainIdStr, ".json");

        require(vm.isFile(deployPath), "Deploy file not found");
        string memory deployJson = vm.readFile(deployPath);
        address addressBookAddr = deployJson.readAddress(".AddressBook.proxyAddress");
        require(addressBookAddr != address(0), "AddressBook proxy not found");

        AddressBook addressBook = AddressBook(addressBookAddr);

        console.log("=== AddressBook Configuration ===");
        console.log("AddressBook Proxy:", addressBookAddr);
        console.log("---------------------------------");
        
        console.log("Otoken Implementation:", addressBook.getOtokenImpl());
        console.log("Otoken Factory:       ", addressBook.getOtokenFactory());
        console.log("Whitelist:            ", addressBook.getWhitelist());
        console.log("Controller:           ", addressBook.getController());
        console.log("Margin Pool:          ", addressBook.getMarginPool());
        console.log("Margin Calculator:    ", addressBook.getMarginCalculator());
        console.log("Controller Logic:     ", addressBook.getControllerLogic());
        console.log("Liquidation Manager:  ", addressBook.getLiquidationManager());
        console.log("Oracle:               ", addressBook.getOracle());
        console.log("---------------------------------");
    }
}

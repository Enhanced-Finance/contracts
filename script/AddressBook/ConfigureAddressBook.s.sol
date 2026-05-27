// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {AddressBook} from "src/core/AddressBook.sol";
import {stdJson} from "forge-std/StdJson.sol";

contract ConfigureAddressBook is Script {
    using stdJson for string;

    // Keys from AddressBook.sol
    bytes32 private constant OTOKEN_IMPL = keccak256("OTOKEN_IMPL");
    bytes32 private constant OTOKEN_FACTORY = keccak256("OTOKEN_FACTORY");
    bytes32 private constant WHITELIST = keccak256("WHITELIST");
    bytes32 private constant CONTROLLER = keccak256("CONTROLLER");
    bytes32 private constant MARGIN_POOL = keccak256("MARGIN_POOL");
    bytes32 private constant MARGIN_CALCULATOR = keccak256("MARGIN_CALCULATOR");
    bytes32 private constant CONTROLLER_LOGIC = keccak256("CONTROLLER_LOGIC");
    bytes32 private constant ORACLE = keccak256("ORACLE");

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        uint256 chainId = block.chainid;
        string memory chainIdStr = vm.toString(chainId);
        string memory deployDir = string.concat(vm.projectRoot(), "/.deploy/");
        string memory deployPath = string.concat(deployDir, chainIdStr, ".json");

        require(vm.isFile(deployPath), "Deploy file not found");
        string memory json = vm.readFile(deployPath);

        // Get AddressBook Proxy
        address addressBookAddr = json.readAddress(".AddressBook.proxyAddress");
        require(addressBookAddr != address(0), "AddressBook proxy not found");

        AddressBook addressBook = AddressBook(addressBookAddr);
        console.log("Configuring AddressBook at:", addressBookAddr);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Controller
        _checkAndSet(addressBook, CONTROLLER, json, ".Controller.proxyAddress", "Controller");

        // 2. ControllerLogic
        _checkAndSet(addressBook, CONTROLLER_LOGIC, json, ".ControllerLogic.proxyAddress", "ControllerLogic");

        // 3. MarginPool
        _checkAndSet(addressBook, MARGIN_POOL, json, ".MarginPool.proxyAddress", "MarginPool");

        // 4. MarginCalculator
        _checkAndSet(addressBook, MARGIN_CALCULATOR, json, ".MarginCalculator.proxyAddress", "MarginCalculator");

        // 5. Oracle
        _checkAndSet(addressBook, ORACLE, json, ".Oracle.proxyAddress", "Oracle");

        // 6. Whitelist
        _checkAndSet(addressBook, WHITELIST, json, ".Whitelist.proxyAddress", "Whitelist");

        // 7. OtokenFactory
        _checkAndSet(addressBook, OTOKEN_FACTORY, json, ".OtokenFactory.proxyAddress", "OtokenFactory");

        // 8. Otoken Impl (This is implementation, not proxy)
        _checkAndSet(addressBook, OTOKEN_IMPL, json, ".Otoken.implementationAddress", "Otoken Impl");

        vm.stopBroadcast();
    }

    function _checkAndSet(
        AddressBook addressBook,
        bytes32 key,
        string memory json,
        string memory jsonKey,
        string memory name
    ) internal {
        if (vm.keyExists(json, jsonKey)) {
            address newAddr = json.readAddress(jsonKey);
            if (newAddr != address(0)) {
                address currentAddr = addressBook.getAddress(key);
                if (currentAddr != newAddr) {
                    console.log(string.concat("Updating ", name, "..."));
                    addressBook.setAddress(key, newAddr);
                } else {
                    console.log(
                        string.concat(
                            name,
                            " already set correctly. old: ",
                            vm.toString(currentAddr),
                            " new: ",
                            vm.toString(newAddr)
                        )
                    );
                }
            }
        } else {
            console.log(string.concat("Warning: ", name, " not found in deploy file."));
        }
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

interface ISetOtokenImplTarget {
    function getOtokenImpl() external view returns (address);
    function setOtokenImpl(address newOtokenImpl) external;
}

contract SetOtokenImpl is Script {
    using stdJson for string;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        uint256 chainId = block.chainid;
        string memory chainIdStr = vm.toString(chainId);
        string memory deployPath = string.concat(vm.projectRoot(), "/.deploy/", chainIdStr, ".json");

        require(vm.isFile(deployPath), "Deploy file not found");

        string memory deployJson = vm.readFile(deployPath);
        (address addressBookAddr, address otokenImplAddr) = _readDeployAddresses(deployJson);

        console.log("Setting Otoken implementation in AddressBook:", addressBookAddr);
        console.log("Caller (Owner):", deployer);
        console.log("Otoken implementation:", otokenImplAddr);

        vm.startBroadcast(deployerPrivateKey);
        _setOtokenImpl(ISetOtokenImplTarget(addressBookAddr), otokenImplAddr);
        vm.stopBroadcast();

        console.log("SetOtokenImpl execution complete.");
    }

    function _readDeployAddresses(string memory deployJson)
        internal
        view
        returns (address addressBookAddr, address otokenImplAddr)
    {
        require(vm.keyExistsJson(deployJson, ".AddressBook.proxyAddress"), "AddressBook proxy not found");
        require(vm.keyExistsJson(deployJson, ".Otoken.implementationAddress"), "Otoken implementation not found");

        addressBookAddr = deployJson.readAddress(".AddressBook.proxyAddress");
        otokenImplAddr = deployJson.readAddress(".Otoken.implementationAddress");

        require(addressBookAddr != address(0), "AddressBook proxy not found");
        require(otokenImplAddr != address(0), "Otoken implementation not found");
    }

    function _setOtokenImpl(ISetOtokenImplTarget addressBook, address otokenImplAddr) internal {
        require(otokenImplAddr != address(0), "Otoken implementation is zero");

        address currentOtokenImpl = addressBook.getOtokenImpl();
        if (currentOtokenImpl == otokenImplAddr) {
            console.log("Otoken implementation already set:", currentOtokenImpl);
            return;
        }

        console.log("Current Otoken implementation:", currentOtokenImpl);
        addressBook.setOtokenImpl(otokenImplAddr);
        console.log("Updated Otoken implementation:", otokenImplAddr);
    }
}

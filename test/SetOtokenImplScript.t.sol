// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {ISetOtokenImplTarget, SetOtokenImpl} from "../script/OtokenFactory/SetOtokenImpl.s.sol";

contract MockSetOtokenImplTarget is ISetOtokenImplTarget {
    address public otokenImpl;
    uint256 public setOtokenImplCalls;

    constructor(address initialOtokenImpl) {
        otokenImpl = initialOtokenImpl;
    }

    function getOtokenImpl() external view returns (address) {
        return otokenImpl;
    }

    function setOtokenImpl(address newOtokenImpl) external {
        setOtokenImplCalls++;
        otokenImpl = newOtokenImpl;
    }
}

contract SetOtokenImplHarness is SetOtokenImpl {
    function exposedReadDeployAddresses(string memory deployJson)
        external
        view
        returns (address addressBookAddr, address otokenImplAddr)
    {
        return _readDeployAddresses(deployJson);
    }

    function exposedSetOtokenImpl(ISetOtokenImplTarget addressBook, address otokenImplAddr) external {
        _setOtokenImpl(addressBook, otokenImplAddr);
    }
}

contract SetOtokenImplScriptTest is Test {
    SetOtokenImplHarness internal harness;

    function setUp() external {
        harness = new SetOtokenImplHarness();
    }

    function testReadDeployAddresses_ShouldReadAddressBookProxyAndOtokenImplementation() external view {
        string memory deployJson = string.concat(
            '{"AddressBook":{"proxyAddress":"0x0000000000000000000000000000000000000011"},',
            '"Otoken":{"implementationAddress":"0x0000000000000000000000000000000000000022"}}'
        );

        (address addressBookAddr, address otokenImplAddr) = harness.exposedReadDeployAddresses(deployJson);

        assertEq(addressBookAddr, address(0x11), "addressBook proxy mismatch");
        assertEq(otokenImplAddr, address(0x22), "otoken implementation mismatch");
    }

    function testReadDeployAddresses_ShouldRejectMissingAddressBookProxy() external {
        string memory deployJson = '{"Otoken":{"implementationAddress":"0x0000000000000000000000000000000000000022"}}';

        vm.expectRevert("AddressBook proxy not found");
        harness.exposedReadDeployAddresses(deployJson);
    }

    function testReadDeployAddresses_ShouldRejectMissingOtokenImplementation() external {
        string memory deployJson = '{"AddressBook":{"proxyAddress":"0x0000000000000000000000000000000000000011"}}';

        vm.expectRevert("Otoken implementation not found");
        harness.exposedReadDeployAddresses(deployJson);
    }

    function testSetOtokenImpl_ShouldUpdateWhenDifferent() external {
        MockSetOtokenImplTarget target = new MockSetOtokenImplTarget(address(0x11));

        harness.exposedSetOtokenImpl(target, address(0x22));

        assertEq(target.otokenImpl(), address(0x22), "otoken implementation should update");
        assertEq(target.setOtokenImplCalls(), 1, "setter should be called once");
    }

    function testSetOtokenImpl_ShouldSkipWhenAlreadySet() external {
        MockSetOtokenImplTarget target = new MockSetOtokenImplTarget(address(0x22));

        harness.exposedSetOtokenImpl(target, address(0x22));

        assertEq(target.otokenImpl(), address(0x22), "otoken implementation should stay unchanged");
        assertEq(target.setOtokenImplCalls(), 0, "setter should not be called");
    }

    function testSetOtokenImpl_ShouldRejectZeroImplementation() external {
        MockSetOtokenImplTarget target = new MockSetOtokenImplTarget(address(0x11));

        vm.expectRevert("Otoken implementation is zero");
        harness.exposedSetOtokenImpl(target, address(0));
    }
}

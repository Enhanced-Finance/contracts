// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {EnhancedOptions} from "src/core/EnhancedOptions.sol";
import {IEnhancedOptionsTimelock} from "src/core/interfaces/IEnhancedOptionsTimelock.sol";
import {EnhancedOptionsTimelockLib} from "src/core/libs/EnhancedOptionsTimelockLib.sol";

contract EnhancedOptionsTimelockTest is Test {
    address internal constant ENHANCED_OPTIONS_TIMELOCK_LIBRARY_PLACEHOLDER =
        0xeF3cD61FDc9a41e32F6100FBef544bAB712dec9e;

    EnhancedOptions internal enhancedOptions;

    address internal trustedTaker = address(0x1001);
    address internal trustedMaker = address(0x2002);
    address internal maker = address(0x3003);
    address internal receiver = address(0x4004);
    address internal nextReceiver = address(0x5005);
    address internal stranger = address(0x6006);

    function setUp() external {
        vm.etch(ENHANCED_OPTIONS_TIMELOCK_LIBRARY_PLACEHOLDER, type(EnhancedOptionsTimelockLib).runtimeCode);
        enhancedOptions = new EnhancedOptions();
        _unlockInitializers(address(enhancedOptions));
        address[] memory initialTrustedTakers = new address[](1);
        initialTrustedTakers[0] = trustedTaker;
        address[] memory initialTrustedMakers = new address[](1);
        initialTrustedMakers[0] = trustedMaker;
        enhancedOptions.initialize(initialTrustedTakers, initialTrustedMakers, address(0x0A11CE), address(0xC0570D1));
    }

    function testInitialize_ShouldSetInitialTrustedRoles() external view {
        assertTrue(enhancedOptions.trustedTakers(trustedTaker));
        assertTrue(enhancedOptions.trustedMakers(trustedMaker));
        assertEq(enhancedOptions.operator(), address(0x0A11CE));
        assertEq(enhancedOptions.custodyOperator(), address(0xC0570D1));
    }

    function testRuntimeCodeSize_ShouldStayWithinEip170Limit() external view {
        assertLe(address(enhancedOptions).code.length, 24_576);
    }

    function testInitialize_ShouldRejectZeroTrustedRole() external {
        EnhancedOptions fresh = new EnhancedOptions();
        _unlockInitializers(address(fresh));
        address[] memory initialTrustedTakers = new address[](1);
        initialTrustedTakers[0] = address(0);

        vm.expectRevert(IEnhancedOptionsTimelock.ZeroAddress.selector);
        fresh.initialize(initialTrustedTakers, new address[](0), address(0x0A11CE), address(0xC0570D1));
    }

    function testInitialize_ShouldRejectZeroOperator() external {
        EnhancedOptions fresh = new EnhancedOptions();
        _unlockInitializers(address(fresh));

        vm.expectRevert(IEnhancedOptionsTimelock.ZeroAddress.selector);
        fresh.initialize(new address[](0), new address[](0), address(0), address(0xC0570D1));
    }

    function testInitialize_ShouldRejectZeroCustodyOperator() external {
        EnhancedOptions fresh = new EnhancedOptions();
        _unlockInitializers(address(fresh));

        vm.expectRevert(IEnhancedOptionsTimelock.ZeroAddress.selector);
        fresh.initialize(new address[](0), new address[](0), address(0x0A11CE), address(0));
    }

    function testSetTrustedTaker_ShouldRejectImmediateAuthorization() external {
        vm.expectRevert();
        enhancedOptions.setTrustedTaker(stranger, true);
    }

    function testTrustedTaker_ShouldScheduleAndExecuteAfter48Hours() external {
        bytes memory key = abi.encode(stranger);
        enhancedOptions.scheduleConfigUpdate(IEnhancedOptionsTimelock.TimelockConfigType.TrustedTaker, key);
        (bytes memory pendingData, uint64 executeAfter) =
            enhancedOptions.pendingConfigUpdate(IEnhancedOptionsTimelock.TimelockConfigType.TrustedTaker, key);

        assertEq(abi.decode(pendingData, (address)), stranger);
        assertEq(executeAfter, block.timestamp + 48 hours);
        assertFalse(enhancedOptions.trustedTakers(stranger));

        vm.warp(executeAfter - 1);
        vm.expectRevert();
        enhancedOptions.executeConfigUpdate(IEnhancedOptionsTimelock.TimelockConfigType.TrustedTaker, key);

        vm.warp(executeAfter);
        enhancedOptions.executeConfigUpdate(IEnhancedOptionsTimelock.TimelockConfigType.TrustedTaker, key);

        assertTrue(enhancedOptions.trustedTakers(stranger));
        (pendingData, executeAfter) =
            enhancedOptions.pendingConfigUpdate(IEnhancedOptionsTimelock.TimelockConfigType.TrustedTaker, key);
        assertEq(pendingData.length, 0);
        assertEq(executeAfter, 0);
    }

    function testTrustedTaker_RevokeShouldBeImmediateAndCancelPending() external {
        bytes memory key = abi.encode(stranger);
        enhancedOptions.scheduleConfigUpdate(IEnhancedOptionsTimelock.TimelockConfigType.TrustedTaker, key);
        enhancedOptions.setTrustedTaker(stranger, false);

        assertFalse(enhancedOptions.trustedTakers(stranger));
        (, uint64 executeAfter) =
            enhancedOptions.pendingConfigUpdate(IEnhancedOptionsTimelock.TimelockConfigType.TrustedTaker, key);
        assertEq(executeAfter, 0);
    }

    function testTrustedMaker_ShouldScheduleExecuteAndRevokeImmediately() external {
        bytes memory key = abi.encode(stranger);
        enhancedOptions.scheduleConfigUpdate(IEnhancedOptionsTimelock.TimelockConfigType.TrustedMaker, key);
        (, uint64 executeAfter) =
            enhancedOptions.pendingConfigUpdate(IEnhancedOptionsTimelock.TimelockConfigType.TrustedMaker, key);

        vm.warp(executeAfter);
        enhancedOptions.executeConfigUpdate(IEnhancedOptionsTimelock.TimelockConfigType.TrustedMaker, key);
        assertTrue(enhancedOptions.trustedMakers(stranger));

        enhancedOptions.setTrustedMaker(stranger, false);
        assertFalse(enhancedOptions.trustedMakers(stranger));
    }

    function testMakerWhitelist_AllChangesIncludingClearShouldBeDelayed() external {
        bytes memory key = abi.encode(maker);
        enhancedOptions.scheduleConfigUpdate(
            IEnhancedOptionsTimelock.TimelockConfigType.MakerWhitelist, abi.encode(maker, receiver)
        );
        (bytes memory pendingData, uint64 executeAfter) =
            enhancedOptions.pendingConfigUpdate(IEnhancedOptionsTimelock.TimelockConfigType.MakerWhitelist, key);
        (address pendingMaker, address pendingReceiver) = abi.decode(pendingData, (address, address));
        assertEq(pendingMaker, maker);
        assertEq(pendingReceiver, receiver);
        assertEq(executeAfter, block.timestamp + 48 hours);
        assertEq(enhancedOptions.makerWhitelist(maker), address(0));

        vm.warp(executeAfter);
        enhancedOptions.executeConfigUpdate(IEnhancedOptionsTimelock.TimelockConfigType.MakerWhitelist, key);
        assertEq(enhancedOptions.makerWhitelist(maker), receiver);

        enhancedOptions.scheduleConfigUpdate(
            IEnhancedOptionsTimelock.TimelockConfigType.MakerWhitelist, abi.encode(maker, address(0))
        );
        (, uint64 clearAfter) =
            enhancedOptions.pendingConfigUpdate(IEnhancedOptionsTimelock.TimelockConfigType.MakerWhitelist, key);
        assertEq(enhancedOptions.makerWhitelist(maker), receiver);

        vm.warp(clearAfter);
        enhancedOptions.executeConfigUpdate(IEnhancedOptionsTimelock.TimelockConfigType.MakerWhitelist, key);
        assertEq(enhancedOptions.makerWhitelist(maker), address(0));
    }

    function testMakerWhitelist_ShouldRequireCancelBeforeReplacingPendingValue() external {
        bytes memory key = abi.encode(maker);
        enhancedOptions.scheduleConfigUpdate(
            IEnhancedOptionsTimelock.TimelockConfigType.MakerWhitelist, abi.encode(maker, receiver)
        );

        vm.expectRevert();
        enhancedOptions.scheduleConfigUpdate(
            IEnhancedOptionsTimelock.TimelockConfigType.MakerWhitelist, abi.encode(maker, nextReceiver)
        );

        enhancedOptions.cancelConfigUpdate(IEnhancedOptionsTimelock.TimelockConfigType.MakerWhitelist, key);
        enhancedOptions.scheduleConfigUpdate(
            IEnhancedOptionsTimelock.TimelockConfigType.MakerWhitelist, abi.encode(maker, nextReceiver)
        );

        (bytes memory pendingData,) =
            enhancedOptions.pendingConfigUpdate(IEnhancedOptionsTimelock.TimelockConfigType.MakerWhitelist, key);
        (, address pendingReceiver) = abi.decode(pendingData, (address, address));
        assertEq(pendingReceiver, nextReceiver);
    }

    function testMakerCustodyLimit_NonZeroChangesShouldBeDelayed() external {
        bytes memory key = abi.encode(maker, receiver);
        enhancedOptions.scheduleConfigUpdate(
            IEnhancedOptionsTimelock.TimelockConfigType.MakerCustodyLimitBps, abi.encode(maker, receiver, uint256(7000))
        );
        (bytes memory pendingData, uint64 executeAfter) =
            enhancedOptions.pendingConfigUpdate(IEnhancedOptionsTimelock.TimelockConfigType.MakerCustodyLimitBps, key);
        (address pendingMaker, address pendingReceiver, uint256 pendingBps) =
            abi.decode(pendingData, (address, address, uint256));
        assertEq(pendingMaker, maker);
        assertEq(pendingReceiver, receiver);
        assertEq(pendingBps, 7000);
        assertEq(enhancedOptions.makerCustodyLimitBps(maker, receiver), 0);

        vm.warp(executeAfter);
        enhancedOptions.executeConfigUpdate(IEnhancedOptionsTimelock.TimelockConfigType.MakerCustodyLimitBps, key);
        assertEq(enhancedOptions.makerCustodyLimitBps(maker, receiver), 7000);

        enhancedOptions.scheduleConfigUpdate(
            IEnhancedOptionsTimelock.TimelockConfigType.MakerCustodyLimitBps, abi.encode(maker, receiver, uint256(5000))
        );
        (, uint64 lowerAfter) =
            enhancedOptions.pendingConfigUpdate(IEnhancedOptionsTimelock.TimelockConfigType.MakerCustodyLimitBps, key);
        assertEq(enhancedOptions.makerCustodyLimitBps(maker, receiver), 7000);

        vm.warp(lowerAfter);
        enhancedOptions.executeConfigUpdate(IEnhancedOptionsTimelock.TimelockConfigType.MakerCustodyLimitBps, key);
        assertEq(enhancedOptions.makerCustodyLimitBps(maker, receiver), 5000);
    }

    function testMakerCustodyLimit_ShouldRejectImmediateNonZeroAndValuesAboveMaximum() external {
        vm.expectRevert(IEnhancedOptionsTimelock.TimelockRequired.selector);
        enhancedOptions.setMakerCustodyLimitBps(maker, receiver, 7000);

        vm.expectRevert(IEnhancedOptionsTimelock.CustodyLimitTooHigh.selector);
        enhancedOptions.scheduleConfigUpdate(
            IEnhancedOptionsTimelock.TimelockConfigType.MakerCustodyLimitBps,
            abi.encode(maker, receiver, uint256(10_001))
        );
    }

    function testScheduleConfigUpdate_ShouldRejectMalformedBytes() external {
        vm.expectRevert();
        enhancedOptions.scheduleConfigUpdate(IEnhancedOptionsTimelock.TimelockConfigType.TrustedTaker, hex"01");
    }

    function testMakerCustodyLimit_ClearShouldBeImmediateAndCancelPending() external {
        bytes memory key = abi.encode(maker, receiver);
        enhancedOptions.scheduleConfigUpdate(
            IEnhancedOptionsTimelock.TimelockConfigType.MakerCustodyLimitBps, abi.encode(maker, receiver, uint256(7000))
        );
        (, uint64 executeAfter) =
            enhancedOptions.pendingConfigUpdate(IEnhancedOptionsTimelock.TimelockConfigType.MakerCustodyLimitBps, key);
        vm.warp(executeAfter);
        enhancedOptions.executeConfigUpdate(IEnhancedOptionsTimelock.TimelockConfigType.MakerCustodyLimitBps, key);

        enhancedOptions.scheduleConfigUpdate(
            IEnhancedOptionsTimelock.TimelockConfigType.MakerCustodyLimitBps, abi.encode(maker, receiver, uint256(5000))
        );
        enhancedOptions.setMakerCustodyLimitBps(maker, receiver, 0);

        assertEq(enhancedOptions.makerCustodyLimitBps(maker, receiver), 0);
        (bytes memory pendingData, uint64 pendingAfter) =
            enhancedOptions.pendingConfigUpdate(IEnhancedOptionsTimelock.TimelockConfigType.MakerCustodyLimitBps, key);
        assertEq(pendingData.length, 0);
        assertEq(pendingAfter, 0);
    }

    function testTimelockManagement_ShouldBeOwnerOnly() external {
        vm.startPrank(stranger);
        vm.expectRevert();
        enhancedOptions.scheduleConfigUpdate(
            IEnhancedOptionsTimelock.TimelockConfigType.TrustedTaker, abi.encode(address(0x7007))
        );
        vm.expectRevert();
        enhancedOptions.scheduleConfigUpdate(
            IEnhancedOptionsTimelock.TimelockConfigType.MakerWhitelist, abi.encode(maker, receiver)
        );
        vm.expectRevert();
        enhancedOptions.scheduleConfigUpdate(
            IEnhancedOptionsTimelock.TimelockConfigType.MakerCustodyLimitBps, abi.encode(maker, receiver, uint256(7000))
        );
        vm.stopPrank();
    }

    function _unlockInitializers(address target) internal {
        bytes32 initializableStorageSlot = 0xf0c57e16840df040f15088dc2f81fe391c3923bec73e23a9662efc9c229c6a00;
        vm.store(target, initializableStorageSlot, bytes32(0));
    }
}

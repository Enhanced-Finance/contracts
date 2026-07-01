// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {EnhancedOptions} from "src/core/EnhancedOptions.sol";
import {IEnhancedOptionsTimelock} from "src/core/interfaces/IEnhancedOptionsTimelock.sol";
import {EnhancedOptionsTimelockLib} from "src/core/libs/EnhancedOptionsTimelockLib.sol";
import {ManageTrustedOperators} from "../script/EnhancedOptions/ManageTrustedOperators.s.sol";
import {ConfigureCustodyLimits} from "../script/EnhancedOptions/ConfigureCustodyLimits.s.sol";

contract ManageTrustedOperatorsHarness is ManageTrustedOperators {
    function exposedSyncTrustedTaker(EnhancedOptions target, address taker, bool desired) external {
        _syncTrustedTaker(target, taker, desired);
    }

    function exposedSyncTrustedMaker(EnhancedOptions target, address maker, bool desired) external {
        _syncTrustedMaker(target, maker, desired);
    }
}

contract ConfigureCustodyLimitsHarness is ConfigureCustodyLimits {
    function exposedSyncMakerWhitelist(EnhancedOptions target, address maker, address receiver) external {
        _syncMakerWhitelist(target, maker, receiver);
    }

    function exposedSyncMakerCustodyLimit(EnhancedOptions target, address maker, address receiver, uint256 bps)
        external
    {
        _syncMakerCustodyLimit(target, maker, receiver, bps);
    }
}

contract EnhancedOptionsTimelockScriptsTest is Test {
    address internal constant ENHANCED_OPTIONS_TIMELOCK_LIBRARY_PLACEHOLDER =
        0xeF3cD61FDc9a41e32F6100FBef544bAB712dec9e;

    EnhancedOptions internal trustedTarget;
    EnhancedOptions internal custodyTarget;
    ManageTrustedOperatorsHarness internal trustedHarness;
    ConfigureCustodyLimitsHarness internal custodyHarness;

    address internal taker = address(0x1001);
    address internal maker = address(0x2002);
    address internal receiver = address(0x3003);

    function setUp() external {
        vm.etch(ENHANCED_OPTIONS_TIMELOCK_LIBRARY_PLACEHOLDER, type(EnhancedOptionsTimelockLib).runtimeCode);
        trustedHarness = new ManageTrustedOperatorsHarness();
        custodyHarness = new ConfigureCustodyLimitsHarness();
        trustedTarget = _deployTarget();
        custodyTarget = _deployTarget();
        trustedTarget.transferOwnership(address(trustedHarness));
        custodyTarget.transferOwnership(address(custodyHarness));
    }

    function testTrustedScript_ShouldScheduleExecuteAndRevoke() external {
        trustedHarness.exposedSyncTrustedTaker(trustedTarget, taker, true);
        (, uint64 executeAfter) = trustedTarget.pendingConfigUpdate(
            IEnhancedOptionsTimelock.TimelockConfigType.TrustedTaker, abi.encode(taker)
        );
        assertGt(executeAfter, 0);
        assertFalse(trustedTarget.trustedTakers(taker));

        vm.warp(executeAfter);
        trustedHarness.exposedSyncTrustedTaker(trustedTarget, taker, true);
        assertTrue(trustedTarget.trustedTakers(taker));

        trustedHarness.exposedSyncTrustedTaker(trustedTarget, taker, false);
        assertFalse(trustedTarget.trustedTakers(taker));
    }

    function testCustodyScript_ShouldScheduleWhitelistAndExecuteAfterDelay() external {
        custodyHarness.exposedSyncMakerWhitelist(custodyTarget, maker, receiver);
        (, uint64 executeAfter) = custodyTarget.pendingConfigUpdate(
            IEnhancedOptionsTimelock.TimelockConfigType.MakerWhitelist, abi.encode(maker)
        );
        assertEq(custodyTarget.makerWhitelist(maker), address(0));

        vm.warp(executeAfter);
        custodyHarness.exposedSyncMakerWhitelist(custodyTarget, maker, receiver);
        assertEq(custodyTarget.makerWhitelist(maker), receiver);
    }

    function testCustodyScript_ShouldScheduleNonZeroLimitAndClearImmediately() external {
        custodyHarness.exposedSyncMakerCustodyLimit(custodyTarget, maker, receiver, 7000);
        (, uint64 executeAfter) = custodyTarget.pendingConfigUpdate(
            IEnhancedOptionsTimelock.TimelockConfigType.MakerCustodyLimitBps, abi.encode(maker, receiver)
        );

        vm.warp(executeAfter);
        custodyHarness.exposedSyncMakerCustodyLimit(custodyTarget, maker, receiver, 7000);
        assertEq(custodyTarget.makerCustodyLimitBps(maker, receiver), 7000);

        custodyHarness.exposedSyncMakerCustodyLimit(custodyTarget, maker, receiver, 0);
        assertEq(custodyTarget.makerCustodyLimitBps(maker, receiver), 0);
    }

    function _deployTarget() internal returns (EnhancedOptions target) {
        target = new EnhancedOptions();
        bytes32 initializableStorageSlot = 0xf0c57e16840df040f15088dc2f81fe391c3923bec73e23a9662efc9c229c6a00;
        vm.store(address(target), initializableStorageSlot, bytes32(0));
        target.initialize(new address[](0), new address[](0), address(0x0A11CE), address(0xC0570D1));
    }
}

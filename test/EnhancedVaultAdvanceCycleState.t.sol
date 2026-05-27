// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {EnhancedVault} from "../src/periphery/vault/EnhancedVault.sol";
import {EnhancedVaultLinkedLibraries} from "./helpers/EnhancedVaultLinkedLibraries.sol";

contract EnhancedVaultHarness is EnhancedVault {
    function seedCycleRecord(
        bytes32 vaultHash,
        uint256 cycleId,
        uint256 totalActiveCollateral,
        uint256 remainingActiveCollateral
    ) external {
        CycleRecord storage rec = cycleRecords[vaultHash][cycleId];
        rec.totalActiveCollateral = totalActiveCollateral;
        rec.remainingActiveCollateral = remainingActiveCollateral;
    }

    function exposedAdvanceCycleState(
        bytes32 vaultHash,
        uint256 cycleId,
        uint256 nextId,
        uint256 activeCol,
        uint256 totalReturned
    ) external returns (uint256) {
        return _advanceCycleState(vaultHash, cycleId, nextId, activeCol, totalReturned);
    }
}

contract EnhancedVaultAdvanceCycleStateTest is EnhancedVaultLinkedLibraries {
    EnhancedVaultHarness internal harness;

    bytes32 internal constant VAULT_HASH = keccak256("vault");
    uint256 internal constant CYCLE_ID = 8;
    uint256 internal constant NEXT_ID = 9;

    function setUp() external {
        _etchEnhancedVaultLibraries();
        harness = new EnhancedVaultHarness();
    }

    function _cycleRecord(bytes32 vaultHash, uint256 cycleId)
        internal
        view
        returns (EnhancedVault.CycleRecord memory rec)
    {
        (
            rec.totalActiveCollateral,
            rec.remainingActiveCollateral,
            rec.totalPremium,
            rec.collateralRatio,
            rec.premiumRatio
        ) = harness.cycleRecords(vaultHash, cycleId);
    }

    function testAdvanceCycleState_ShouldKeepRemainingActiveCollateral_WhenNoOrders() external {
        harness.seedCycleRecord({
            vaultHash: VAULT_HASH, cycleId: CYCLE_ID, totalActiveCollateral: 100, remainingActiveCollateral: 100
        });

        harness.exposedAdvanceCycleState({
            vaultHash: VAULT_HASH, cycleId: CYCLE_ID, nextId: NEXT_ID, activeCol: 100, totalReturned: 0
        });

        EnhancedVault.CycleRecord memory nextRec = _cycleRecord(VAULT_HASH, NEXT_ID);
        assertEq(nextRec.totalActiveCollateral, 100, "remaining active collateral should carry into next cycle");
    }

    function testAdvanceCycleState_ShouldMatchBehavior_WhenAllCollateralSettled() external {
        harness.seedCycleRecord({
            vaultHash: VAULT_HASH, cycleId: CYCLE_ID, totalActiveCollateral: 100, remainingActiveCollateral: 0
        });

        uint256 capReduction = harness.exposedAdvanceCycleState({
            vaultHash: VAULT_HASH, cycleId: CYCLE_ID, nextId: NEXT_ID, activeCol: 100, totalReturned: 80
        });

        EnhancedVault.CycleRecord memory nextRec = _cycleRecord(VAULT_HASH, NEXT_ID);
        assertEq(nextRec.totalActiveCollateral, 80, "next active collateral mismatch");
        assertEq(capReduction, 20, "capacity reduction mismatch");
    }

    function testAdvanceCycleState_ShouldIncludeRemainingAndReturned_WhenPartiallySettled() external {
        harness.seedCycleRecord({
            vaultHash: VAULT_HASH, cycleId: CYCLE_ID, totalActiveCollateral: 100, remainingActiveCollateral: 25
        });

        harness.exposedAdvanceCycleState({
            vaultHash: VAULT_HASH, cycleId: CYCLE_ID, nextId: NEXT_ID, activeCol: 100, totalReturned: 55
        });

        EnhancedVault.CycleRecord memory nextRec = _cycleRecord(VAULT_HASH, NEXT_ID);
        assertEq(nextRec.totalActiveCollateral, 80, "next active should be remaining + returned");
    }
}

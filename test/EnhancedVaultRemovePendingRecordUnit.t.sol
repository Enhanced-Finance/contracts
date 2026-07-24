// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {EnhancedVault} from "../src/periphery/vault/EnhancedVault.sol";
import {EnhancedVaultLinkedLibraries} from "./helpers/EnhancedVaultLinkedLibraries.sol";

contract RemovePendingRecordHarness is EnhancedVault {
    uint256[] private _ids;
    mapping(uint256 => uint256) private _indexMap;
    mapping(uint256 => FundRecord) private _recordMap;

    function seedRecord(uint256 id, uint256 amount) external {
        _ids.push(id);
        _indexMap[id] = _ids.length;
        _recordMap[id] = FundRecord({
            id: id,
            vaultHash: bytes32(id),
            user: address(0xBEEF),
            recordType: FundRecordType.DEPOSIT,
            amount: amount,
            createdCycleId: 1,
            isExitAll: false
        });
    }

    function removeRecord(uint256 id) external {
        _removePendingRecord(_ids, _indexMap, _recordMap, id);
    }

    function getIds() external view returns (uint256[] memory out) {
        uint256 len = _ids.length;
        out = new uint256[](len);
        for (uint256 i; i < len; i++) {
            out[i] = _ids[i];
        }
    }

    function getIndexPlusOne(uint256 id) external view returns (uint256) {
        return _indexMap[id];
    }

    function recordExists(uint256 id) external view returns (bool) {
        return _recordMap[id].user != address(0);
    }
}

contract EnhancedVaultRemovePendingRecordUnitTest is EnhancedVaultLinkedLibraries {
    RemovePendingRecordHarness internal harness;

    function setUp() external {
        _etchEnhancedVaultLibraries();
        harness = new RemovePendingRecordHarness();
    }

    function testRemovePendingRecord_ShouldSwapAndUpdateIndex_WhenRemovingMiddle() external {
        harness.seedRecord(1, 10);
        harness.seedRecord(2, 20);
        harness.seedRecord(3, 30);

        harness.removeRecord(2);

        uint256[] memory ids = harness.getIds();
        assertEq(ids.length, 2, "length should shrink by one");
        assertEq(ids[0], 1, "head should remain");
        assertEq(ids[1], 3, "tail should be moved into removed slot");
        assertEq(harness.getIndexPlusOne(1), 1, "head index should stay 1-based");
        assertEq(harness.getIndexPlusOne(3), 2, "moved tail index should be updated");
        assertEq(harness.getIndexPlusOne(2), 0, "removed id index should be cleared");
        assertFalse(harness.recordExists(2), "removed record payload should be deleted");
    }

    function testRemovePendingRecord_ShouldKeepIndicesStable_WhenRemovingTail() external {
        harness.seedRecord(11, 10);
        harness.seedRecord(22, 20);
        harness.seedRecord(33, 30);

        harness.removeRecord(33);

        uint256[] memory ids = harness.getIds();
        assertEq(ids.length, 2, "length should shrink by one");
        assertEq(ids[0], 11, "head should stay unchanged");
        assertEq(ids[1], 22, "middle should stay unchanged");
        assertEq(harness.getIndexPlusOne(11), 1, "head index should stay 1-based");
        assertEq(harness.getIndexPlusOne(22), 2, "second index should stay 1-based");
        assertEq(harness.getIndexPlusOne(33), 0, "removed tail index should be cleared");
        assertFalse(harness.recordExists(33), "removed tail payload should be deleted");
    }

    function testRemovePendingRecord_ShouldSupportSingleElementRemoval() external {
        harness.seedRecord(77, 100);

        harness.removeRecord(77);

        uint256[] memory ids = harness.getIds();
        assertEq(ids.length, 0, "single remove should empty list");
        assertEq(harness.getIndexPlusOne(77), 0, "removed id index should be cleared");
        assertFalse(harness.recordExists(77), "removed payload should be deleted");
    }

    function testRemovePendingRecord_ShouldRevert_WhenRecordNotPending() external {
        harness.seedRecord(1, 10);

        vm.expectRevert(EnhancedVault.RecordNotPending.selector);
        harness.removeRecord(999);
    }
}

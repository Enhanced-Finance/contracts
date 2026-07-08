// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {EnhancedVault} from "../EnhancedVault.sol";

library EnhancedVaultRecordsLib {
    uint256 internal constant MAX_PENDING_DEPOSITS_PER_USER = 64;
    uint256 internal constant MAX_PENDING_EXIT_RECORDS_PER_USER = 64;

    event FundRecordCreated(
        bytes32 indexed vaultHash,
        address indexed user,
        uint256 indexed recordId,
        EnhancedVault.FundRecordType recordType,
        uint256 amount
    );
    event FundRecordConverted(
        bytes32 indexed vaultHash,
        address indexed user,
        uint256 indexed fromRecordId,
        uint256 toRecordId,
        uint256 amount
    );
    error RecordNotFound();
    error RecordTypeMismatch();
    error RecordNotPending();
    error PendingRecordLimitExceeded();

    function convertPendingDepositRecordsToWithdraw(
        uint256[] storage pendingDepositIds,
        mapping(uint256 => EnhancedVault.FundRecord) storage pendingDepositRecords,
        mapping(uint256 => uint256) storage pendingDepositIndex,
        uint256[] storage pendingWithdrawIds,
        mapping(uint256 => EnhancedVault.FundRecord) storage pendingWithdrawRecords,
        mapping(uint256 => uint256) storage pendingWithdrawIndex,
        mapping(bytes32 => mapping(address => EnhancedVault.UserFund)) storage userFunds,
        mapping(bytes32 => EnhancedVault.VaultState) storage vaults,
        bytes32 vaultHash,
        address user
    ) public returns (uint256 refunded) {
        uint256[] memory records = copyIds(pendingDepositIds);
        uint256 len = records.length;
        for (uint256 i; i < len;) {
            uint256 rid = records[i];
            uint256 amount = pendingDepositRecords[rid].amount;
            removePendingRecord(pendingDepositIds, pendingDepositIndex, pendingDepositRecords, rid);
            uint256 withdrawId;
            if (amount > 0) {
                withdrawId = addPendingWithdraw(
                    userFunds,
                    pendingWithdrawIds,
                    pendingWithdrawRecords,
                    pendingWithdrawIndex,
                    vaults,
                    vaultHash,
                    user,
                    amount,
                    false
                );
                unchecked {
                    refunded += amount;
                }
            }
            emit FundRecordConverted(vaultHash, user, rid, withdrawId, amount);
            unchecked {
                ++i;
            }
        }
    }

    function markPendingDepositRecordsConverted(
        uint256[] storage pendingDepositIds,
        mapping(uint256 => EnhancedVault.FundRecord) storage pendingDepositRecords,
        mapping(uint256 => uint256) storage pendingDepositIndex,
        bytes32 vaultHash,
        address user
    ) public {
        uint256[] memory records = copyIds(pendingDepositIds);
        uint256 len = records.length;
        for (uint256 i; i < len;) {
            uint256 rid = records[i];
            uint256 amount = pendingDepositRecords[rid].amount;
            removePendingRecord(pendingDepositIds, pendingDepositIndex, pendingDepositRecords, rid);
            emit FundRecordConverted(vaultHash, user, rid, 0, amount);
            unchecked {
                ++i;
            }
        }
    }

    function processExitAllQueuedUser(
        uint256[] storage pendingDepositIds,
        mapping(uint256 => EnhancedVault.FundRecord) storage pendingDepositRecords,
        mapping(uint256 => uint256) storage pendingDepositIndex,
        uint256[] storage pendingWithdrawRequestIds,
        mapping(uint256 => EnhancedVault.FundRecord) storage pendingWithdrawRequestRecords,
        mapping(uint256 => uint256) storage pendingWithdrawRequestIndex,
        uint256[] storage pendingWithdrawIds,
        mapping(uint256 => EnhancedVault.FundRecord) storage pendingWithdrawRecords,
        mapping(uint256 => uint256) storage pendingWithdrawIndex,
        mapping(bytes32 => mapping(address => EnhancedVault.UserFund)) storage userFunds,
        mapping(bytes32 => EnhancedVault.VaultState) storage vaults,
        bytes32 vaultHash,
        address user,
        uint256 requestId,
        uint256 settledActive
    ) public {
        EnhancedVault.UserFund storage fund = userFunds[vaultHash][user];
        uint256 exitAmount =
            fund.stoppedPrincipal + settledActive + fund.pendingActivePrincipal + fund.systemPausedPrincipal;

        clearPendingWithdrawRequests(
            pendingWithdrawRequestIds, pendingWithdrawRequestIndex, pendingWithdrawRequestRecords
        );
        clearPendingWithdrawRequests(pendingWithdrawIds, pendingWithdrawIndex, pendingWithdrawRecords);
        markPendingDepositRecordsConverted(
            pendingDepositIds, pendingDepositRecords, pendingDepositIndex, vaultHash, user
        );

        if (exitAmount > 0) {
            uint256 withdrawId = addPendingWithdraw(
                userFunds,
                pendingWithdrawIds,
                pendingWithdrawRecords,
                pendingWithdrawIndex,
                vaults,
                vaultHash,
                user,
                exitAmount,
                true
            );
            fund.stoppedPrincipal = exitAmount;
            emit FundRecordConverted(vaultHash, user, requestId, withdrawId, exitAmount);
        } else {
            fund.stoppedPrincipal = 0;
            emit FundRecordConverted(vaultHash, user, requestId, 0, 0);
        }

        fund.activePrincipal = 0;
        fund.pendingActivePrincipal = 0;
        fund.pendingWithdrawAmount = 0;
        fund.systemPausedPrincipal = 0;
        fund.entryCumCollateral = 0;
        fund.entryCumPremium = 0;
        fund.initialAmountTotal = 0;
    }

    function convertWithdrawRequestRecordsToWithdraw(
        mapping(bytes32 => mapping(address => EnhancedVault.UserFund)) storage userFunds,
        uint256[] storage pendingWithdrawRequestIds,
        mapping(uint256 => EnhancedVault.FundRecord) storage pendingWithdrawRequestRecords,
        mapping(uint256 => uint256) storage pendingWithdrawRequestIndex,
        uint256[] storage pendingWithdrawIds,
        mapping(uint256 => EnhancedVault.FundRecord) storage pendingWithdrawRecords,
        mapping(uint256 => uint256) storage pendingWithdrawIndex,
        mapping(bytes32 => EnhancedVault.VaultState) storage vaults,
        bytes32 vaultHash,
        address user,
        uint256 settledActive
    ) public returns (uint256 stopAmount) {
        EnhancedVault.UserFund storage fund = userFunds[vaultHash][user];
        uint256 totalRequested = fund.pendingWithdrawAmount;
        uint256 stopBudget = totalRequested > settledActive ? settledActive : totalRequested;

        uint256[] memory records = copyIds(pendingWithdrawRequestIds);
        uint256 len = records.length;

        if (stopBudget == totalRequested) {
            uint256 consumed;
            for (uint256 i; i < len && consumed < stopBudget;) {
                unchecked {
                    consumed += convertSingleWithdrawRequestRecord(
                        pendingWithdrawRequestRecords,
                        pendingWithdrawRequestIndex,
                        pendingWithdrawRequestIds,
                        pendingWithdrawRecords,
                        pendingWithdrawIndex,
                        pendingWithdrawIds,
                        userFunds,
                        vaults,
                        vaultHash,
                        user,
                        records[i],
                        stopBudget - consumed
                    );
                    ++i;
                }
            }
            for (uint256 i; i < len;) {
                convertSingleWithdrawRequestRecord(
                    pendingWithdrawRequestRecords,
                    pendingWithdrawRequestIndex,
                    pendingWithdrawRequestIds,
                    pendingWithdrawRecords,
                    pendingWithdrawIndex,
                    pendingWithdrawIds,
                    userFunds,
                    vaults,
                    vaultHash,
                    user,
                    records[i],
                    0
                );
                unchecked {
                    ++i;
                }
            }
        } else {
            uint256 consumed;
            for (uint256 i; i < len;) {
                uint256 prorated;
                if (i == len - 1) {
                    prorated = stopBudget - consumed;
                } else {
                    prorated = pendingWithdrawRequestRecords[records[i]].amount * stopBudget / totalRequested;
                }
                unchecked {
                    consumed += convertSingleWithdrawRequestRecord(
                        pendingWithdrawRequestRecords,
                        pendingWithdrawRequestIndex,
                        pendingWithdrawRequestIds,
                        pendingWithdrawRecords,
                        pendingWithdrawIndex,
                        pendingWithdrawIds,
                        userFunds,
                        vaults,
                        vaultHash,
                        user,
                        records[i],
                        prorated
                    );
                    ++i;
                }
            }
        }

        return stopBudget;
    }

    function convertSingleWithdrawRequestRecord(
        mapping(uint256 => EnhancedVault.FundRecord) storage pendingWithdrawRequestRecords,
        mapping(uint256 => uint256) storage pendingWithdrawRequestIndex,
        uint256[] storage pendingWithdrawRequestIds,
        mapping(uint256 => EnhancedVault.FundRecord) storage pendingWithdrawRecords,
        mapping(uint256 => uint256) storage pendingWithdrawIndex,
        uint256[] storage pendingWithdrawIds,
        mapping(bytes32 => mapping(address => EnhancedVault.UserFund)) storage userFunds,
        mapping(bytes32 => EnhancedVault.VaultState) storage vaults,
        bytes32 vaultHash,
        address user,
        uint256 withdrawRequestId,
        uint256 available
    ) public returns (uint256 converted) {
        if (pendingWithdrawRequestIndex[withdrawRequestId] == 0) {
            return 0;
        }
        EnhancedVault.FundRecord storage withdrawRequestRec = pendingWithdrawRequestRecords[withdrawRequestId];

        converted = withdrawRequestRec.amount > available ? available : withdrawRequestRec.amount;
        removePendingRecord(
            pendingWithdrawRequestIds, pendingWithdrawRequestIndex, pendingWithdrawRequestRecords, withdrawRequestId
        );

        uint256 withdrawId;
        if (converted > 0) {
            withdrawId = addPendingWithdraw(
                userFunds,
                pendingWithdrawIds,
                pendingWithdrawRecords,
                pendingWithdrawIndex,
                vaults,
                vaultHash,
                user,
                converted,
                false
            );
        }
        emit FundRecordConverted(vaultHash, user, withdrawRequestId, withdrawId, converted);
    }

    function nextRecordId(
        mapping(bytes32 => mapping(address => EnhancedVault.UserFund)) storage userFunds,
        bytes32 vaultHash,
        address user
    ) public returns (uint256 recordId) {
        EnhancedVault.UserFund storage fund = userFunds[vaultHash][user];
        unchecked {
            return ++fund.nextRecordId;
        }
    }

    function addPendingDeposit(
        mapping(bytes32 => mapping(address => EnhancedVault.UserFund)) storage userFunds,
        uint256[] storage ids,
        mapping(uint256 => EnhancedVault.FundRecord) storage records,
        mapping(uint256 => uint256) storage indexes,
        mapping(bytes32 => EnhancedVault.VaultState) storage vaults,
        bytes32 vaultHash,
        address user,
        uint256 amount
    ) public returns (uint256 recordId) {
        if (ids.length >= MAX_PENDING_DEPOSITS_PER_USER) revert PendingRecordLimitExceeded();
        recordId = nextRecordId(userFunds, vaultHash, user);
        records[recordId] = EnhancedVault.FundRecord({
            id: recordId,
            vaultHash: vaultHash,
            user: user,
            recordType: EnhancedVault.FundRecordType.DEPOSIT,
            amount: amount,
            createdCycleId: vaults[vaultHash].currentCycleId,
            isExitAll: false
        });
        ids.push(recordId);
        indexes[recordId] = ids.length;
        emit FundRecordCreated(vaultHash, user, recordId, EnhancedVault.FundRecordType.DEPOSIT, amount);
    }

    function addPendingWithdrawRequest(
        mapping(bytes32 => mapping(address => EnhancedVault.UserFund)) storage userFunds,
        uint256[] storage ids,
        mapping(uint256 => EnhancedVault.FundRecord) storage records,
        mapping(uint256 => uint256) storage indexes,
        uint256[] storage pendingWithdrawIds,
        mapping(bytes32 => EnhancedVault.VaultState) storage vaults,
        bytes32 vaultHash,
        address user,
        uint256 amount,
        bool isExitAll
    ) public returns (uint256 recordId) {
        uint256 exitCount = ids.length + pendingWithdrawIds.length;
        if (exitCount >= MAX_PENDING_EXIT_RECORDS_PER_USER) revert PendingRecordLimitExceeded();
        recordId = nextRecordId(userFunds, vaultHash, user);
        records[recordId] = EnhancedVault.FundRecord({
            id: recordId,
            vaultHash: vaultHash,
            user: user,
            recordType: EnhancedVault.FundRecordType.WITHDRAW_REQUEST,
            amount: amount,
            createdCycleId: vaults[vaultHash].currentCycleId,
            isExitAll: isExitAll
        });
        ids.push(recordId);
        indexes[recordId] = ids.length;
        emit FundRecordCreated(vaultHash, user, recordId, EnhancedVault.FundRecordType.WITHDRAW_REQUEST, amount);
    }

    function addPendingWithdraw(
        mapping(bytes32 => mapping(address => EnhancedVault.UserFund)) storage userFunds,
        uint256[] storage ids,
        mapping(uint256 => EnhancedVault.FundRecord) storage records,
        mapping(uint256 => uint256) storage indexes,
        mapping(bytes32 => EnhancedVault.VaultState) storage vaults,
        bytes32 vaultHash,
        address user,
        uint256 amount,
        bool isExitAll
    ) public returns (uint256 recordId) {
        recordId = nextRecordId(userFunds, vaultHash, user);
        records[recordId] = EnhancedVault.FundRecord({
            id: recordId,
            vaultHash: vaultHash,
            user: user,
            recordType: EnhancedVault.FundRecordType.WITHDRAW,
            amount: amount,
            createdCycleId: vaults[vaultHash].currentCycleId,
            isExitAll: isExitAll
        });
        ids.push(recordId);
        indexes[recordId] = ids.length;
        emit FundRecordCreated(vaultHash, user, recordId, EnhancedVault.FundRecordType.WITHDRAW, amount);
    }

    function removePendingRecord(
        uint256[] storage ids,
        mapping(uint256 => uint256) storage indexMap,
        mapping(uint256 => EnhancedVault.FundRecord) storage recordMap,
        uint256 recordId
    ) public {
        uint256 idxPlusOne = indexMap[recordId];
        if (idxPlusOne == 0) revert RecordNotPending();
        uint256 idx = idxPlusOne - 1;
        uint256 lastIdx = ids.length - 1;
        uint256 lastId = ids[lastIdx];
        if (idx != lastIdx) {
            ids[idx] = lastId;
            indexMap[lastId] = idx + 1;
        }
        ids.pop();
        delete indexMap[recordId];
        delete recordMap[recordId];
    }

    function clearPendingWithdrawRequests(
        uint256[] storage ids,
        mapping(uint256 => uint256) storage indexMap,
        mapping(uint256 => EnhancedVault.FundRecord) storage recordMap
    ) public {
        while (ids.length != 0) {
            uint256 recordId = ids[ids.length - 1];
            ids.pop();
            delete indexMap[recordId];
            delete recordMap[recordId];
        }
    }

    function getPendingRecord(
        mapping(uint256 => EnhancedVault.FundRecord) storage records,
        mapping(uint256 => uint256) storage indexes,
        uint256 recordId,
        EnhancedVault.FundRecordType expectedType
    ) public view returns (EnhancedVault.FundRecord memory rec) {
        rec = records[recordId];
        if (rec.user == address(0)) revert RecordNotFound();
        if (rec.recordType != expectedType) revert RecordTypeMismatch();
        if (indexes[recordId] == 0) revert RecordNotPending();
    }

    function copyIds(uint256[] storage ids) public view returns (uint256[] memory out) {
        uint256 len = ids.length;
        out = new uint256[](len);
        for (uint256 i; i < len;) {
            out[i] = ids[i];
            unchecked {
                ++i;
            }
        }
    }

    function buildPendingRecords(uint256[] storage ids, mapping(uint256 => EnhancedVault.FundRecord) storage records)
        public
        view
        returns (EnhancedVault.FundRecord[] memory out)
    {
        uint256 len = ids.length;
        out = new EnhancedVault.FundRecord[](len);
        for (uint256 i; i < len;) {
            out[i] = records[ids[i]];
            unchecked {
                ++i;
            }
        }
    }
}

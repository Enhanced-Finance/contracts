// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IEnhancedVault {
    enum CyclePhase {
        OPEN,
        SETTLED,
        PROCESSING_DONE,
        ENDED
    }

    struct UserFund {
        uint256 activePrincipal;
        uint256 pendingActivePrincipal;
        uint256 pendingWithdrawAmount;
        uint256 stoppedPrincipal;
        uint256 systemPausedPrincipal;
        uint256 materializedPremium;
        uint256 entryCumCollateral;
        uint256 entryCumPremium;
        uint256 initialAmountTotal;
        uint256 nextRecordId;
        bool buybackEnabled;
    }

    struct UserPosition {
        uint256 activeBalance;
        uint256 pendingDeposit;
        uint256 pendingWithdrawAmount;
        uint256 claimableWithdraw;
        uint256 claimableSystemPaused;
        uint256 claimablePremium;
        uint256 projectedPremium;
    }

    enum FundRecordType {
        DEPOSIT,
        WITHDRAW_REQUEST,
        WITHDRAW
    }

    struct FundRecord {
        uint256 id;
        bytes32 vaultHash;
        address user;
        FundRecordType recordType;
        uint256 amount;
        uint256 createdCycleId;
    }

    function setVaultPaused(bytes32 vaultHash, bool paused) external;
    function setVaultEnd(bytes32 vaultHash, bool isEnd) external;
    function pauseVault(bytes32 vaultHash) external;
    function withdraw(bytes32 vaultHash, uint256 amount) external;
    function cancelDeposit(bytes32 vaultHash, uint256 recordId) external;
    function cancelWithdraw(bytes32 vaultHash, uint256 recordId) external;
    function claimWithdraw(bytes32 vaultHash, uint256 recordId) external;
    function claimPremium(bytes32 vaultHash, uint256 amount) external;
    function claimActive(bytes32 vaultHash) external;
    function setBuybackEnabled(bytes32 vaultHash, bool enabled) external;
    function endVault(bytes32 vaultHash) external;
    function getMyPosition(bytes32 vaultHash, address user) external view returns (UserPosition memory);
    function getPendingDeposits(bytes32 vaultHash, address user) external view returns (FundRecord[] memory);
    function getPendingWithdrawRequests(bytes32 vaultHash, address user) external view returns (FundRecord[] memory);
    function getPendingWithdraws(bytes32 vaultHash, address user) external view returns (FundRecord[] memory);
    function systemPauseFunds(bytes32 vaultHash, address[] calldata users) external;
    function getQueueProgress(bytes32 vaultHash)
        external
        view
        returns (CyclePhase phase, uint256 queueLen, uint256 processedCount, uint256 remaining, bool canStartNextCycle);
    function getQueueUsers(bytes32 vaultHash, uint256 offset, uint256 limit) external view returns (address[] memory);
}

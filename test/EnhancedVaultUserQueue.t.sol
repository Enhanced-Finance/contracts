// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";
import {EnhancedVault} from "../src/periphery/vault/EnhancedVault.sol";
import {EnhancedVaultRecordsLib} from "../src/periphery/vault/libs/EnhancedVaultRecordsLib.sol";
import {IEnhancedOptions} from "../src/core/interfaces/IEnhancedOptions.sol";
import {ISwapRouter} from "../src/core/interfaces/ISwapRouter.sol";
import {EnhancedVaultLinkedLibraries} from "./helpers/EnhancedVaultLinkedLibraries.sol";

contract MockERC20ForVaultQueue is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_, 18) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MockSwapRouterForVaultQueue is ISwapRouter {
    uint256 public immutable amountOut;

    constructor(uint256 amountOut_) {
        amountOut = amountOut_;
    }

    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256) {
        params;
        MockERC20ForVaultQueue(params.tokenOut).mint(params.recipient, amountOut);
        return amountOut;
    }

    function exactInput(ExactInputParams calldata) external payable returns (uint256) {
        revert("not implemented");
    }

    function exactOutputSingle(ExactOutputSingleParams calldata) external payable returns (uint256) {
        revert("not implemented");
    }

    function exactOutput(ExactOutputParams calldata) external payable returns (uint256) {
        revert("not implemented");
    }
}

contract EnhancedVaultQueueHarness is EnhancedVault {
    function seedOwner(address newOwner) external {
        _transferOwnership(newOwner);
    }

    function seedCore(address enhancedOptionsAddr, address operatorAddr, address vaultSignerAddr) external {
        enhancedOptions = IEnhancedOptions(enhancedOptionsAddr);
        operator = operatorAddr;
        vaultSigner = vaultSignerAddr;
    }

    function seedVault(
        bytes32 vaultHash,
        address collateralAsset,
        address strikeAsset,
        uint256 minInvestmentAmount,
        uint256 capacity,
        int256 strikePriceBps,
        uint256 minPrincipalRatio,
        int256 buybackPriceRatio,
        bool isActive,
        uint256 currentCycleId
    ) external {
        VaultState storage st = vaults[vaultHash];
        st.params.cycleDuration = 1 days;
        st.params.collateralAsset = collateralAsset;
        st.params.strikeAsset = strikeAsset;
        st.params.minInvestmentAmount = minInvestmentAmount;
        st.params.capacity = capacity;
        st.params.startTime = 1;
        st.params.strikePriceBps = strikePriceBps;
        st.params.minPrincipalRatio = minPrincipalRatio;
        st.params.buybackPriceRatio = buybackPriceRatio;
        st.isActive = isActive;
        st.isPaused = false;
        st.isEnd = false;
        st.currentCycleId = currentCycleId;
        st.currentCycleStart = 1;
        vaultPhases[vaultHash] = CyclePhase.OPEN;
        cumCollateral[vaultHash][0] = 1e18;
        cumPremium[vaultHash][0] = 0;
    }

    function seedSwapRouter(address router) external {
        swapRouter = router;
    }

    function seedMaterializedPremium(bytes32 vaultHash, address user, uint256 premium) external {
        UserFund storage fund = userFunds[vaultHash][user];
        fund.materializedPremium = premium;
        fund.exists = true;
    }

    function seedActiveUserFund(
        bytes32 vaultHash,
        address user,
        uint256 activePrincipal,
        uint256 entryCumCollateral,
        uint256 entryCumPremium
    ) external {
        UserFund storage fund = userFunds[vaultHash][user];
        fund.activePrincipal = activePrincipal;
        fund.entryCumCollateral = entryCumCollateral;
        fund.entryCumPremium = entryCumPremium;
        fund.exists = true;
    }

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
}

contract EnhancedVaultUserQueueTest is EnhancedVaultLinkedLibraries {
    bytes32 internal constant VAULT_HASH = keccak256("task1-2-vault");

    uint256 internal constant OWNER_PK = 0xA11CE;
    uint256 internal constant OPERATOR_PK = 0xB0B;
    uint256 internal constant USER_PK = 0xCAFE;
    uint256 internal constant USER2_PK = 0xD00D;
    uint256 internal constant USER3_PK = 0xD0D0;

    EnhancedVaultQueueHarness internal vault;
    MockERC20ForVaultQueue internal collateral;
    MockERC20ForVaultQueue internal strike;

    address internal owner;
    address internal operator;
    address internal user;

    function setUp() external {
        _etchEnhancedVaultLibraries();

        owner = vm.addr(OWNER_PK);
        operator = vm.addr(OPERATOR_PK);
        user = vm.addr(USER_PK);

        vault = new EnhancedVaultQueueHarness();
        vault.seedOwner(owner);
        vault.seedCore(address(0x1111), operator, address(0x2222));
        assertEq(vault.operator(), operator, "operator seed mismatch");

        collateral = new MockERC20ForVaultQueue("Collateral", "COL");
        strike = new MockERC20ForVaultQueue("Strike", "USD");

        vault.seedVault(VAULT_HASH, address(collateral), address(strike), 1, type(uint256).max, 0, 0, 0, true, 1);

        collateral.mint(user, 1_000_000 ether);
        collateral.mint(address(vault), 1_000_000 ether);
        vm.prank(user);
        collateral.approve(address(vault), type(uint256).max);

        strike.mint(address(vault), 1_000_000 ether);
    }

    function _userFund(bytes32 vaultHash, address targetUser)
        internal
        view
        returns (EnhancedVault.UserFund memory fund)
    {
        (
            fund.activePrincipal,
            fund.pendingActivePrincipal,
            fund.pendingWithdrawAmount,
            fund.stoppedPrincipal,
            fund.systemPausedPrincipal,
            fund.materializedPremium,
            fund.entryCumCollateral,
            fund.entryCumPremium,
            fund.initialAmountTotal,
            fund.nextRecordId,
            fund.buybackEnabled,
        ) = vault.userFunds(vaultHash, targetUser);
    }

    function _enableBuyback(bytes32 vaultHash, address targetUser) internal {
        vm.prank(targetUser);
        vault.setBuybackEnabled(vaultHash, true);
    }

    function _vaultState(bytes32 vaultHash) internal view returns (EnhancedVault.VaultState memory st) {
        (
            EnhancedVault.VaultParams memory params,
            bool isActive,
            uint256 currentCycleId,
            uint256 currentCycleStart,
            uint256 totalDeposited,
            bool isPaused,
            bool isEnd
        ) = vault.vaults(vaultHash);

        st = EnhancedVault.VaultState({
            params: params,
            isActive: isActive,
            currentCycleId: currentCycleId,
            currentCycleStart: currentCycleStart,
            totalDeposited: totalDeposited,
            isPaused: isPaused,
            isEnd: isEnd
        });
    }

    function _currentCycleId(bytes32 vaultHash) internal view returns (uint256 currentCycleId) {
        (,, currentCycleId,,,,) = vault.vaults(vaultHash);
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
        ) = vault.cycleRecords(vaultHash, cycleId);
    }

    function testGetUserFund_DefaultZeroState() external view {
        EnhancedVault.UserFund memory fund = _userFund(VAULT_HASH, user);
        assertEq(fund.activePrincipal, 0);
        assertEq(fund.pendingActivePrincipal, 0);
        assertEq(fund.nextRecordId, 0);
        assertEq(fund.stoppedPrincipal, 0);
        assertFalse(fund.buybackEnabled);
    }

    function testGetVault_ShouldExposeReservedBuybackParams() external {
        bytes32 customHash = keccak256("reserved-buyback-params");
        vault.seedVault(customHash, address(collateral), address(strike), 5 ether, 500 ether, 0, 8000, -2000, true, 3);

        EnhancedVault.VaultState memory st = _vaultState(customHash);
        assertEq(st.params.minPrincipalRatio, 8000);
        assertEq(st.params.buybackPriceRatio, -2000);
    }

    function testDeposit_ShouldCreateRecordIdFromZero_OnFirstDeposit() external {
        bytes32 customHash = keccak256("first-deposit-copy-fields");
        vault.seedVault(customHash, address(collateral), address(strike), 1, type(uint256).max, 0, 9000, -1000, true, 1);

        _depositAs(user, customHash, 10 ether);

        EnhancedVault.UserFund memory fund = _userFund(customHash, user);
        assertEq(fund.pendingActivePrincipal, 10 ether, "first deposit should increase pending active");
        assertEq(fund.nextRecordId, 1, "first deposit should allocate the first record id");
    }

    function testDeposit_ShouldKeepIncrementingRecordIds_AfterFirstDeposit() external {
        bytes32 customHash = keccak256("first-deposit-no-overwrite-fields");
        vault.seedVault(customHash, address(collateral), address(strike), 1, type(uint256).max, 0, 9000, -1000, true, 1);

        _depositAs(user, customHash, 10 ether);

        vault.seedVault(customHash, address(collateral), address(strike), 1, type(uint256).max, 0, 5000, 2000, true, 1);

        _depositAs(user, customHash, 20 ether);

        EnhancedVault.UserFund memory fund = _userFund(customHash, user);
        assertEq(fund.pendingActivePrincipal, 30 ether, "later deposits should keep accumulating pending active");
        assertEq(fund.nextRecordId, 2, "later deposits should keep incrementing record ids");
    }

    function testGetPendingDeposits_ReturnsFundRecordArrayWithId() external view {
        EnhancedVault.FundRecord[] memory deposits = vault.getPendingDeposits(VAULT_HASH, user);
        assertEq(deposits.length, 0);
    }

    function testClaimWithdraw_UsesVaultHashAndUintRecordId() external {
        vm.prank(user);
        vm.expectRevert(EnhancedVaultRecordsLib.RecordNotFound.selector);
        vault.claimWithdraw(VAULT_HASH, 1);
    }

    function testDeposit_ShouldMergeIntoPendingActive() external {
        uint256 amount1 = 200 ether;
        uint256 amount2 = 350 ether;

        _depositAs(user, VAULT_HASH, amount1);
        _depositAs(user, VAULT_HASH, amount2);

        EnhancedVault.UserFund memory fund = _userFund(VAULT_HASH, user);
        assertEq(fund.pendingActivePrincipal, amount1 + amount2, "pending active should merge");
        assertEq(fund.initialAmountTotal, amount1 + amount2, "initial total should accumulate");
    }

    function testDeposit_ShouldAllowSameParamsAcrossRepeatedUserCalls() external {
        uint256 amount = 100 ether;

        _depositAs(user, VAULT_HASH, amount);
        _depositAs(user, VAULT_HASH, amount);

        EnhancedVault.UserFund memory fund = _userFund(VAULT_HASH, user);
        assertEq(fund.pendingActivePrincipal, 200 ether, "same params should be allowed for direct user deposits");
    }

    function testDeposit_ShouldCreateMultiplePendingDepositRecords() external {
        _depositAs(user, VAULT_HASH, 10 ether);
        _depositAs(user, VAULT_HASH, 20 ether);

        EnhancedVault.FundRecord[] memory deposits = vault.getPendingDeposits(VAULT_HASH, user);
        assertEq(deposits.length, 2);
        assertEq(deposits[0].amount, 10 ether);
        assertEq(deposits[1].amount, 20 ether);
        assertEq(deposits[0].id, 1);
        assertEq(deposits[1].id, 2);
    }

    function testDeposit_ShouldActivateOnNextCycle() external {
        uint256 amount = 200 ether;
        _depositAs(user, VAULT_HASH, amount);

        vm.warp(2 days);
        vm.prank(operator);
        vault.nextCycle(VAULT_HASH);

        EnhancedVault.UserFund memory fund = _userFund(VAULT_HASH, user);
        assertEq(fund.pendingActivePrincipal, 0, "pending should be consumed at cycle transition");
        assertEq(fund.activePrincipal, amount, "deposit should become active in next cycle");
    }

    function testDepositRecord_ShouldCreateAndCancel_RollbackPending() external {
        uint256 amount = 75 ether;
        uint256 balanceBefore = collateral.balanceOf(user);
        _depositAs(user, VAULT_HASH, amount);

        EnhancedVault.FundRecord[] memory deposits = vault.getPendingDeposits(VAULT_HASH, user);
        assertEq(deposits.length, 1);
        uint256 recordId = deposits[0].id;
        EnhancedVault.UserFund memory afterDeposit = _userFund(VAULT_HASH, user);
        assertEq(afterDeposit.pendingActivePrincipal, amount, "pending active should increase");

        vm.prank(user);
        vault.cancelDeposit(VAULT_HASH, recordId);

        EnhancedVault.UserFund memory afterCancel = _userFund(VAULT_HASH, user);
        assertEq(afterCancel.pendingActivePrincipal, 0, "cancel should rollback pending active");
        assertEq(collateral.balanceOf(user), balanceBefore, "cancel should refund collateral");
        deposits = vault.getPendingDeposits(VAULT_HASH, user);
        assertEq(deposits.length, 0, "pending deposit list should be empty");
    }

    function testCancelDeposit_ShouldRemoveSelectedPendingRecord_AndRefund() external {
        uint256 balanceBefore = collateral.balanceOf(user);
        _depositAs(user, VAULT_HASH, 75 ether);
        _depositAs(user, VAULT_HASH, 25 ether);

        EnhancedVault.FundRecord[] memory deposits = vault.getPendingDeposits(VAULT_HASH, user);
        uint256 recordId = deposits[0].id;

        vm.prank(user);
        vault.cancelDeposit(VAULT_HASH, recordId);

        deposits = vault.getPendingDeposits(VAULT_HASH, user);
        assertEq(deposits.length, 1);
        assertEq(deposits[0].amount, 25 ether);
        assertEq(collateral.balanceOf(user), balanceBefore - 25 ether);
    }

    function testCancelDeposit_ShouldHandleTailThenHeadThenRemaining_WithConsistentState() external {
        uint256 balanceBefore = collateral.balanceOf(user);
        _depositAs(user, VAULT_HASH, 10 ether); // id 1
        _depositAs(user, VAULT_HASH, 20 ether); // id 2
        _depositAs(user, VAULT_HASH, 30 ether); // id 3

        EnhancedVault.UserFund memory fund = _userFund(VAULT_HASH, user);
        assertEq(fund.pendingActivePrincipal, 60 ether, "pending active should equal total deposits");
        assertEq(fund.initialAmountTotal, 60 ether, "initial total should equal total deposits");

        // Remove tail (covers idx == lastIdx path).
        vm.prank(user);
        vault.cancelDeposit(VAULT_HASH, 3);
        EnhancedVault.FundRecord[] memory deposits = vault.getPendingDeposits(VAULT_HASH, user);
        assertEq(deposits.length, 2, "tail removal should keep 2 records");
        fund = _userFund(VAULT_HASH, user);
        assertEq(fund.pendingActivePrincipal, 30 ether, "pending active should shrink after tail cancel");
        assertEq(fund.initialAmountTotal, 30 ether, "initial total should shrink after tail cancel");
        assertEq(collateral.balanceOf(user), balanceBefore - 30 ether, "tail cancel should refund exact amount");

        // Remove head next (covers non-tail swap path after prior tail removal).
        vm.prank(user);
        vault.cancelDeposit(VAULT_HASH, 1);
        deposits = vault.getPendingDeposits(VAULT_HASH, user);
        assertEq(deposits.length, 1, "head removal should keep one record");
        assertEq(deposits[0].id, 2, "record id 2 should remain");
        assertEq(deposits[0].amount, 20 ether, "remaining amount should be intact");
        fund = _userFund(VAULT_HASH, user);
        assertEq(fund.pendingActivePrincipal, 20 ether, "pending active should track remaining record");
        assertEq(fund.initialAmountTotal, 20 ether, "initial total should track remaining record");
        assertEq(collateral.balanceOf(user), balanceBefore - 20 ether, "head cancel should refund exact amount");

        // Remove final remaining record to ensure indices are still valid.
        vm.prank(user);
        vault.cancelDeposit(VAULT_HASH, 2);
        deposits = vault.getPendingDeposits(VAULT_HASH, user);
        assertEq(deposits.length, 0, "all pending records should be removable");
        fund = _userFund(VAULT_HASH, user);
        assertEq(fund.pendingActivePrincipal, 0, "pending active should be zero after all cancels");
        assertEq(fund.initialAmountTotal, 0, "initial total should be zero after all cancels");
        assertEq(collateral.balanceOf(user), balanceBefore, "all deposits should be fully refunded");
    }

    function testPause_ShouldAccumulatePendingStop_WithTruncationAtProcessTime() external {
        vault.seedActiveUserFund(VAULT_HASH, user, 200 ether, 1e18, 0);

        vm.prank(user);
        vault.withdraw(VAULT_HASH, 40 ether);

        vm.prank(user);
        vault.withdraw(VAULT_HASH, 80 ether);

        EnhancedVault.UserFund memory fund = _userFund(VAULT_HASH, user);
        assertEq(fund.pendingWithdrawAmount, 120 ether, "withdraw requests should accumulate before process");
    }

    function testPause_ShouldCreateMultiplePendingPauseRecords() external {
        vault.seedActiveUserFund(VAULT_HASH, user, 200 ether, 1e18, 0);
        vm.prank(user);
        vault.withdraw(VAULT_HASH, 40 ether);
        vm.prank(user);
        vault.withdraw(VAULT_HASH, 80 ether);

        EnhancedVault.FundRecord[] memory pauses = vault.getPendingWithdrawRequests(VAULT_HASH, user);
        assertEq(pauses.length, 2);
        assertEq(pauses[0].amount, 40 ether);
        assertEq(pauses[1].amount, 80 ether);
    }

    function testPause_ShouldRevert_WhenUserHasNoActive_AndNotPolluteQueue() external {
        vm.prank(user);
        vm.expectRevert(EnhancedVault.NotActive.selector);
        vault.withdraw(VAULT_HASH, 1 ether);

        (EnhancedVault.CyclePhase phase, uint256 queueLen, uint256 processedCount, uint256 remaining, bool canStart) =
            vault.getQueueProgress(VAULT_HASH);
        assertEq(uint256(phase), uint256(EnhancedVault.CyclePhase.OPEN));
        assertEq(queueLen, 0, "reverted withdraw request should not enqueue user");
        assertEq(processedCount, 0);
        assertEq(remaining, 0);
        assertFalse(canStart);
    }

    function testPause_ShouldApplyOnNextCycle() external {
        vault.seedActiveUserFund(VAULT_HASH, user, 100 ether, 1e18, 0);
        vault.seedCycleRecord(VAULT_HASH, 1, 100 ether, 100 ether);

        vm.prank(user);
        vault.withdraw(VAULT_HASH, 40 ether);

        vm.warp(2 days);
        vm.prank(operator);
        vault.nextCycle(VAULT_HASH);

        EnhancedVault.UserFund memory fund = _userFund(VAULT_HASH, user);
        assertEq(fund.activePrincipal, 60 ether, "withdraw amount should be removed from active");
        assertEq(fund.stoppedPrincipal, 40 ether, "paused amount should move to stopped");
        assertEq(fund.pendingWithdrawAmount, 0, "pending stop should be consumed");
    }

    function testProcess_ShouldConvertPauseIntoPendingWithdrawRecord() external {
        vault.seedActiveUserFund(VAULT_HASH, user, 100 ether, 1e18, 0);
        vault.seedCycleRecord(VAULT_HASH, 1, 100 ether, 100 ether);
        vm.prank(user);
        vault.withdraw(VAULT_HASH, 40 ether);

        vm.warp(2 days);
        vm.prank(operator);
        vault.nextCycle(VAULT_HASH);

        EnhancedVault.FundRecord[] memory pauses = vault.getPendingWithdrawRequests(VAULT_HASH, user);
        EnhancedVault.FundRecord[] memory withdraws = vault.getPendingWithdraws(VAULT_HASH, user);
        assertEq(pauses.length, 0);
        assertEq(withdraws.length, 1);
        assertEq(withdraws[0].amount, 40 ether);
    }

    function testProcess_ShouldConsumeMultiplePauseRecordsWithoutSkipping() external {
        vault.seedActiveUserFund(VAULT_HASH, user, 300 ether, 1e18, 0);
        vault.seedCycleRecord(VAULT_HASH, 1, 300 ether, 300 ether);

        vm.prank(user);
        vault.withdraw(VAULT_HASH, 40 ether);
        vm.prank(user);
        vault.withdraw(VAULT_HASH, 80 ether);
        vm.prank(user);
        vault.withdraw(VAULT_HASH, 50 ether);

        vm.warp(2 days);
        vm.prank(operator);
        vault.nextCycle(VAULT_HASH);

        EnhancedVault.FundRecord[] memory pauses = vault.getPendingWithdrawRequests(VAULT_HASH, user);
        EnhancedVault.FundRecord[] memory withdraws = vault.getPendingWithdraws(VAULT_HASH, user);
        EnhancedVault.UserFund memory fund = _userFund(VAULT_HASH, user);
        assertEq(pauses.length, 0, "all withdraw request records should be consumed");
        assertEq(withdraws.length, 3, "all withdraw request records should convert");
        assertEq(withdraws[0].amount + withdraws[1].amount + withdraws[2].amount, 170 ether, "converted sum mismatch");
        assertEq(fund.stoppedPrincipal, 170 ether);
        assertEq(fund.activePrincipal, 130 ether);
    }

    function testPauseRecord_ShouldCreateAndCancel_RollbackPendingStop() external {
        vault.seedActiveUserFund(VAULT_HASH, user, 200 ether, 1e18, 0);

        vm.prank(user);
        vault.withdraw(VAULT_HASH, 80 ether);
        EnhancedVault.FundRecord[] memory pauses = vault.getPendingWithdrawRequests(VAULT_HASH, user);
        assertEq(pauses.length, 1, "withdraw request record should be created");
        uint256 pauseRecordId = pauses[0].id;
        EnhancedVault.UserFund memory afterPause = _userFund(VAULT_HASH, user);
        assertEq(afterPause.pendingWithdrawAmount, 80 ether, "pending stop should increase");

        vm.prank(user);
        vault.cancelWithdraw(VAULT_HASH, pauseRecordId);

        EnhancedVault.UserFund memory afterCancel = _userFund(VAULT_HASH, user);
        assertEq(afterCancel.pendingWithdrawAmount, 0, "cancel should rollback pending stop");
        pauses = vault.getPendingWithdrawRequests(VAULT_HASH, user);
        assertEq(pauses.length, 0, "withdraw-request list should clear after cancel");
    }

    function testPause_ShouldOnlyFreeCapacityOnWithdraw_NotOnQueueProcess() external {
        vault.seedVault(VAULT_HASH, address(collateral), address(strike), 1, 100 ether, 0, 0, 0, true, 1);

        address user2 = vm.addr(USER2_PK);
        collateral.mint(user2, 1_000_000 ether);
        vm.prank(user2);
        collateral.approve(address(vault), type(uint256).max);

        _depositAs(user, VAULT_HASH, 100 ether);

        vm.warp(2 days);
        vm.prank(operator);
        vault.nextCycle(VAULT_HASH);

        vm.prank(user);
        vault.withdraw(VAULT_HASH, 100 ether);

        vm.warp(3 days);
        vm.prank(operator);
        vault.nextCycle(VAULT_HASH);

        vm.prank(user2);
        vm.expectRevert(EnhancedVault.CapacityExceeded.selector);
        vault.deposit(VAULT_HASH, 100 ether);

        EnhancedVault.FundRecord[] memory withdraws = vault.getPendingWithdraws(VAULT_HASH, user);
        uint256 withdrawRecordId = withdraws[0].id;
        vm.prank(user);
        vault.claimWithdraw(VAULT_HASH, withdrawRecordId);

        _depositAs(user2, VAULT_HASH, 100 ether);
    }

    function testProcess_ShouldApplySettledScale_BeforeStopAndActivate() external {
        vault.seedActiveUserFund(VAULT_HASH, user, 100 ether, 1e18, 0);
        vault.seedCycleRecord(VAULT_HASH, 1, 100 ether, 80 ether);

        vm.prank(user);
        vault.withdraw(VAULT_HASH, 70 ether);

        _depositAs(user, VAULT_HASH, 20 ether);

        vm.warp(2 days);
        vm.prank(operator);
        vault.nextCycle(VAULT_HASH);

        EnhancedVault.UserFund memory fund = _userFund(VAULT_HASH, user);
        assertEq(fund.stoppedPrincipal, 70 ether, "stop should apply on settled active");
        assertEq(fund.activePrincipal, 30 ether, "pending active should merge only after stop");
        assertEq(fund.pendingWithdrawAmount, 0, "pending stop should be cleared");
        assertEq(fund.pendingActivePrincipal, 0, "pending active should be consumed");
    }

    function testProcess_ShouldConsumeAllPendingDepositRecords() external {
        _depositAs(user, VAULT_HASH, 20 ether);
        _depositAs(user, VAULT_HASH, 30 ether);

        vm.warp(2 days);
        vm.prank(operator);
        vault.nextCycle(VAULT_HASH);

        EnhancedVault.FundRecord[] memory deposits = vault.getPendingDeposits(VAULT_HASH, user);
        EnhancedVault.UserFund memory fund = _userFund(VAULT_HASH, user);
        assertEq(deposits.length, 0);
        assertEq(fund.activePrincipal, 50 ether);
    }

    function testPauseAmount_ShouldClampToSettledActive() external {
        vault.seedActiveUserFund(VAULT_HASH, user, 100 ether, 1e18, 0);
        vault.seedCycleRecord(VAULT_HASH, 1, 100 ether, 50 ether);

        vm.prank(user);
        vault.withdraw(VAULT_HASH, 80 ether);

        vm.warp(2 days);
        vm.prank(operator);
        vault.nextCycle(VAULT_HASH);

        EnhancedVault.UserFund memory fund = _userFund(VAULT_HASH, user);
        assertEq(fund.stoppedPrincipal, 50 ether, "withdraw amount should clamp to settled active");
        assertEq(fund.activePrincipal, 0, "all settled active should be stopped");
        assertEq(fund.pendingWithdrawAmount, 0, "pending stop should be consumed");

        EnhancedVault.FundRecord[] memory pauses = vault.getPendingWithdrawRequests(VAULT_HASH, user);
        assertEq(pauses.length, 0, "withdraw request records should be consumed");
        EnhancedVault.FundRecord[] memory withdraws = vault.getPendingWithdraws(VAULT_HASH, user);
        assertEq(withdraws.length, 1, "should create a withdraw record");
        assertEq(
            uint256(withdraws[0].recordType),
            uint256(EnhancedVault.FundRecordType.WITHDRAW),
            "converted record type mismatch"
        );
        assertEq(withdraws[0].amount, 50 ether, "converted amount should clamp to settled active");
    }

    function testNextCycle_ShouldNotDoubleCount_WhenActiveUserDeposits() external {
        vault.seedActiveUserFund(VAULT_HASH, user, 100 ether, 1e18, 0);
        vault.seedCycleRecord(VAULT_HASH, 1, 100 ether, 100 ether);

        _depositAs(user, VAULT_HASH, 50 ether);

        vm.warp(2 days);
        vm.prank(operator);
        vault.nextCycle(VAULT_HASH);

        EnhancedVault.CycleRecord memory nextRec = _cycleRecord(VAULT_HASH, 2);
        EnhancedVault.UserFund memory fund = _userFund(VAULT_HASH, user);
        assertEq(nextRec.totalActiveCollateral, 150 ether, "next cycle active should not double count");
        assertEq(fund.activePrincipal, 150 ether, "user active should include only single deposit increment");
    }

    function testNextCycle_ShouldNotDoubleCountReduction_WhenActiveUserPauses() external {
        vault.seedActiveUserFund(VAULT_HASH, user, 100 ether, 1e18, 0);
        vault.seedCycleRecord(VAULT_HASH, 1, 100 ether, 100 ether);

        vm.prank(user);
        vault.withdraw(VAULT_HASH, 40 ether);

        vm.warp(2 days);
        vm.prank(operator);
        vault.nextCycle(VAULT_HASH);

        EnhancedVault.CycleRecord memory nextRec = _cycleRecord(VAULT_HASH, 2);
        EnhancedVault.UserFund memory fund = _userFund(VAULT_HASH, user);
        assertEq(nextRec.totalActiveCollateral, 60 ether, "next cycle active should only reduce once");
        assertEq(fund.activePrincipal, 60 ether, "user active should reflect single pause reduction");
    }

    function testClaimWithdraw_ShouldOnlyUseWithdrawRecordState() external {
        vault.seedActiveUserFund(VAULT_HASH, user, 150 ether, 1e18, 0);
        vault.seedCycleRecord(VAULT_HASH, 1, 150 ether, 123 ether);
        vm.prank(user);
        vault.withdraw(VAULT_HASH, 123 ether);

        vm.warp(2 days);
        vm.prank(operator);
        vault.nextCycle(VAULT_HASH);
        EnhancedVault.FundRecord[] memory withdraws = vault.getPendingWithdraws(VAULT_HASH, user);
        uint256 withdrawRecordId = withdraws[0].id;

        uint256 userCollateralBefore = collateral.balanceOf(user);
        uint256 userStrikeBefore = strike.balanceOf(user);

        vm.prank(user);
        vault.claimWithdraw(VAULT_HASH, withdrawRecordId);

        uint256 userCollateralAfter = collateral.balanceOf(user);
        uint256 userStrikeAfter = strike.balanceOf(user);

        assertEq(userCollateralAfter - userCollateralBefore, 123 ether, "claim should pay stopped principal");
        assertEq(userStrikeAfter - userStrikeBefore, 0, "claimWithdraw should not transfer strike premium");

        EnhancedVault.UserFund memory fund = _userFund(VAULT_HASH, user);
        assertEq(fund.stoppedPrincipal, 0, "stopped principal should be consumed");
        assertEq(fund.materializedPremium, 0, "premium remains unchanged in this flow");
    }

    function testGetPendingWithdraws_ShouldReturnCurrentPendingOnly() external {
        vault.seedActiveUserFund(VAULT_HASH, user, 150 ether, 1e18, 0);
        vault.seedCycleRecord(VAULT_HASH, 1, 150 ether, 123 ether);
        vm.prank(user);
        vault.withdraw(VAULT_HASH, 123 ether);
        vm.warp(2 days);
        vm.prank(operator);
        vault.nextCycle(VAULT_HASH);

        EnhancedVault.FundRecord[] memory withdraws = vault.getPendingWithdraws(VAULT_HASH, user);
        assertEq(withdraws.length, 1);
        vm.prank(user);
        vault.claimWithdraw(VAULT_HASH, withdraws[0].id);
        withdraws = vault.getPendingWithdraws(VAULT_HASH, user);
        assertEq(withdraws.length, 0);
    }

    function testBuyback_ShouldAllocateToPendingActive_ByUser() external {
        address user2 = vm.addr(0xD00D);
        vault.seedMaterializedPremium(VAULT_HASH, user, 120 ether);
        vault.seedMaterializedPremium(VAULT_HASH, user2, 80 ether);

        MockSwapRouterForVaultQueue router = new MockSwapRouterForVaultQueue(100 ether);
        vault.seedSwapRouter(address(router));

        address[] memory users = new address[](2);
        users[0] = user;
        users[1] = user2;

        _enableBuyback(VAULT_HASH, user);
        _enableBuyback(VAULT_HASH, user2);

        vm.prank(operator);
        vault.buyback(
            VAULT_HASH,
            users,
            EnhancedVault.SwapParams({
                amountIn: 100 ether, amountOutMinimum: 0, deadline: block.timestamp + 1 hours, fee: 3000
            })
        );

        EnhancedVault.UserFund memory fund1 = _userFund(VAULT_HASH, user);
        EnhancedVault.UserFund memory fund2 = _userFund(VAULT_HASH, user2);
        assertEq(fund1.pendingActivePrincipal, 60 ether, "user1 should receive proportional buyback collateral");
        assertEq(fund2.pendingActivePrincipal, 40 ether, "user2 should receive proportional buyback collateral");
    }

    function testBuyback_ShouldRevert_WhenVaultPaused() external {
        vault.seedMaterializedPremium(VAULT_HASH, user, 120 ether);

        MockSwapRouterForVaultQueue router = new MockSwapRouterForVaultQueue(50 ether);
        vault.seedSwapRouter(address(router));

        vm.prank(owner);
        vault.setVaultPaused(VAULT_HASH, true);

        address[] memory users = new address[](1);
        users[0] = user;

        vm.prank(operator);
        vm.expectRevert(EnhancedVault.VaultPaused.selector);
        vault.buyback(
            VAULT_HASH,
            users,
            EnhancedVault.SwapParams({
                amountIn: 50 ether, amountOutMinimum: 0, deadline: block.timestamp + 1 hours, fee: 3000
            })
        );
    }

    function testBuyback_ShouldStillWork_WhenVaultIsEnding() external {
        vault.seedMaterializedPremium(VAULT_HASH, user, 120 ether);

        MockSwapRouterForVaultQueue router = new MockSwapRouterForVaultQueue(50 ether);
        vault.seedSwapRouter(address(router));

        vm.prank(owner);
        vault.setVaultEnd(VAULT_HASH, true);

        address[] memory users = new address[](1);
        users[0] = user;

        _enableBuyback(VAULT_HASH, user);

        vm.prank(operator);
        vault.buyback(
            VAULT_HASH,
            users,
            EnhancedVault.SwapParams({
                amountIn: 50 ether, amountOutMinimum: 0, deadline: block.timestamp + 1 hours, fee: 3000
            })
        );

        EnhancedVault.UserFund memory fund = _userFund(VAULT_HASH, user);
        assertEq(fund.pendingActivePrincipal, 50 ether, "winding-down vault should still allow operator buyback");
    }

    function testBuyback_ShouldActivatePendingOnNextCycle() external {
        address user2 = vm.addr(0xD00D);
        vault.seedMaterializedPremium(VAULT_HASH, user, 120 ether);
        vault.seedMaterializedPremium(VAULT_HASH, user2, 80 ether);

        MockSwapRouterForVaultQueue router = new MockSwapRouterForVaultQueue(100 ether);
        vault.seedSwapRouter(address(router));

        address[] memory users = new address[](2);
        users[0] = user;
        users[1] = user2;

        _enableBuyback(VAULT_HASH, user);
        _enableBuyback(VAULT_HASH, user2);

        vm.prank(operator);
        vault.buyback(
            VAULT_HASH,
            users,
            EnhancedVault.SwapParams({
                amountIn: 100 ether, amountOutMinimum: 0, deadline: block.timestamp + 1 hours, fee: 3000
            })
        );

        vm.warp(2 days);
        vm.prank(operator);
        vault.nextCycle(VAULT_HASH);

        EnhancedVault.UserFund memory fund1 = _userFund(VAULT_HASH, user);
        EnhancedVault.UserFund memory fund2 = _userFund(VAULT_HASH, user2);
        assertEq(fund1.pendingActivePrincipal, 0, "user1 pending should be consumed");
        assertEq(fund2.pendingActivePrincipal, 0, "user2 pending should be consumed");
        assertEq(fund1.activePrincipal, 60 ether, "user1 buyback collateral should be active");
        assertEq(fund2.activePrincipal, 40 ether, "user2 buyback collateral should be active");
    }

    function testBuybackCollateral_ShouldActivateFromPendingActiveOnly() external {
        vault.seedActiveUserFund(VAULT_HASH, user, 100 ether, 1e18, 0);
        vault.seedCycleRecord(VAULT_HASH, 1, 100 ether, 100 ether);
        vault.seedMaterializedPremium(VAULT_HASH, user, 100 ether);

        MockSwapRouterForVaultQueue router = new MockSwapRouterForVaultQueue(30 ether);
        vault.seedSwapRouter(address(router));

        address[] memory users = new address[](1);
        users[0] = user;

        _enableBuyback(VAULT_HASH, user);

        vm.prank(operator);
        vault.buyback(
            VAULT_HASH,
            users,
            EnhancedVault.SwapParams({
                amountIn: 30 ether, amountOutMinimum: 0, deadline: block.timestamp + 1 hours, fee: 3000
            })
        );

        EnhancedVault.UserFund memory beforeCycle = _userFund(VAULT_HASH, user);
        assertEq(beforeCycle.activePrincipal, 100 ether, "buyback should not change active immediately");
        assertEq(beforeCycle.pendingActivePrincipal, 30 ether, "buyback collateral should go to pending");

        vm.warp(2 days);
        vm.prank(operator);
        vault.nextCycle(VAULT_HASH);

        EnhancedVault.UserFund memory afterCycle = _userFund(VAULT_HASH, user);
        assertEq(afterCycle.pendingActivePrincipal, 0, "pending buyback should be consumed on process");
        assertEq(afterCycle.activePrincipal, 130 ether, "buyback collateral should activate via pending path");
    }

    function testLegacyInvestmentIdEntrypoints_ShouldBeUnavailable() external {
        bytes32[] memory ids = new bytes32[](1);
        ids[0] = bytes32(uint256(1));

        // These legacy investment-id entrypoints were removed entirely, so calls to their old
        // selectors must now fail at dispatch time instead of succeeding through a compatibility shim.
        vm.prank(operator);
        (bool pauseOk,) = address(vault).call(abi.encodeWithSignature("forcePauseFunds(bytes32[])", ids));
        assertFalse(pauseOk, "legacy forcePauseFunds selector should be unavailable");

        vm.prank(user);
        (bool clearOk,) = address(vault).call(abi.encodeWithSignature("clearForceExit(bytes32)", ids[0]));
        assertFalse(clearOk, "legacy clearForceExit selector should be unavailable");
    }

    function testDeposit_ShouldRevert_WhenPendingDepositCapExceeded() external {
        for (uint256 i; i < 64; i++) {
            _depositAs(user, VAULT_HASH, 1 ether);
        }
        vm.prank(user);
        vm.expectRevert(EnhancedVaultRecordsLib.PendingRecordLimitExceeded.selector);
        vault.deposit(VAULT_HASH, 1 ether);
    }

    function testPause_ShouldRevert_WhenSharedExitPendingCapExceeded() external {
        vault.seedActiveUserFund(VAULT_HASH, user, 200 ether, 1e18, 0);
        for (uint256 i; i < 64; i++) {
            vm.prank(user);
            vault.withdraw(VAULT_HASH, 1 ether);
        }
        vm.prank(user);
        vm.expectRevert(EnhancedVaultRecordsLib.PendingRecordLimitExceeded.selector);
        vault.withdraw(VAULT_HASH, 1 ether);
    }

    function testPauseToWithdraw_ShouldNotIncreaseSharedExitCount() external {
        vault.seedActiveUserFund(VAULT_HASH, user, 200 ether, 1e18, 0);
        vault.seedCycleRecord(VAULT_HASH, 1, 200 ether, 200 ether);
        for (uint256 i; i < 64; i++) {
            vm.prank(user);
            vault.withdraw(VAULT_HASH, 1 ether);
        }

        vm.warp(2 days);
        vm.prank(operator);
        vault.nextCycle(VAULT_HASH);

        EnhancedVault.FundRecord[] memory pauses = vault.getPendingWithdrawRequests(VAULT_HASH, user);
        EnhancedVault.FundRecord[] memory withdraws = vault.getPendingWithdraws(VAULT_HASH, user);
        assertEq(pauses.length, 0);
        assertEq(withdraws.length, 64);
    }

    function testCancelDeposit_ShouldRevert_WhenCallerIsNotRecordOwner() external {
        address user2 = vm.addr(USER2_PK);
        _depositAs(user, VAULT_HASH, 10 ether);
        uint256 recordId = vault.getPendingDeposits(VAULT_HASH, user)[0].id;
        vm.prank(user2);
        vm.expectRevert(EnhancedVaultRecordsLib.RecordNotFound.selector);
        vault.cancelDeposit(VAULT_HASH, recordId);
    }

    function testCancelPause_ShouldRevert_WhenCallerIsNotRecordOwner() external {
        address user2 = vm.addr(USER2_PK);
        vault.seedActiveUserFund(VAULT_HASH, user, 100 ether, 1e18, 0);
        vm.prank(user);
        vault.withdraw(VAULT_HASH, 10 ether);
        uint256 recordId = vault.getPendingWithdrawRequests(VAULT_HASH, user)[0].id;
        vm.prank(user2);
        vm.expectRevert(EnhancedVaultRecordsLib.RecordNotFound.selector);
        vault.cancelWithdraw(VAULT_HASH, recordId);
    }

    function testClaimWithdraw_ShouldRevert_WhenCallerIsNotRecordOwner() external {
        address user2 = vm.addr(USER2_PK);
        vault.seedActiveUserFund(VAULT_HASH, user, 100 ether, 1e18, 0);
        vault.seedCycleRecord(VAULT_HASH, 1, 100 ether, 100 ether);
        vm.prank(user);
        vault.withdraw(VAULT_HASH, 10 ether);
        vm.warp(2 days);
        vm.prank(operator);
        vault.nextCycle(VAULT_HASH);
        uint256 recordId = vault.getPendingWithdraws(VAULT_HASH, user)[0].id;
        vm.prank(user2);
        vm.expectRevert(EnhancedVaultRecordsLib.RecordNotFound.selector);
        vault.claimWithdraw(VAULT_HASH, recordId);
    }

    function testCancelDeposit_ShouldRevert_WhenRecordDoesNotExist() external {
        vm.prank(user);
        vm.expectRevert(EnhancedVaultRecordsLib.RecordNotFound.selector);
        vault.cancelDeposit(VAULT_HASH, 1);
    }

    function testCancelPause_ShouldRevert_WhenRecordDoesNotExist() external {
        vm.prank(user);
        vm.expectRevert(EnhancedVaultRecordsLib.RecordNotFound.selector);
        vault.cancelWithdraw(VAULT_HASH, 1);
    }

    function testCancelDeposit_ShouldRevert_AfterCycleAdvances() external {
        _depositAs(user, VAULT_HASH, 10 ether);
        uint256 recordId = vault.getPendingDeposits(VAULT_HASH, user)[0].id;

        vm.warp(2 days);
        vm.prank(operator);
        vault.nextCycle(VAULT_HASH);

        vm.prank(user);
        vm.expectRevert(EnhancedVaultRecordsLib.RecordNotFound.selector);
        vault.cancelDeposit(VAULT_HASH, recordId);
    }

    function testCancelPause_ShouldRevert_AfterCycleAdvances() external {
        vault.seedActiveUserFund(VAULT_HASH, user, 100 ether, 1e18, 0);
        vault.seedCycleRecord(VAULT_HASH, 1, 100 ether, 100 ether);
        vm.prank(user);
        vault.withdraw(VAULT_HASH, 10 ether);
        uint256 recordId = vault.getPendingWithdrawRequests(VAULT_HASH, user)[0].id;

        vm.warp(2 days);
        vm.prank(operator);
        vault.nextCycle(VAULT_HASH);

        vm.prank(user);
        vm.expectRevert(EnhancedVaultRecordsLib.RecordNotFound.selector);
        vault.cancelWithdraw(VAULT_HASH, recordId);
    }

    function testClaimWithdraw_ShouldSucceedOnce_AndSecondClaimFail() external {
        vault.seedActiveUserFund(VAULT_HASH, user, 100 ether, 1e18, 0);
        vault.seedCycleRecord(VAULT_HASH, 1, 100 ether, 50 ether);

        vm.prank(user);
        vault.withdraw(VAULT_HASH, 80 ether);

        vm.warp(2 days);
        vm.prank(operator);
        vault.nextCycle(VAULT_HASH);

        EnhancedVault.FundRecord[] memory withdraws = vault.getPendingWithdraws(VAULT_HASH, user);
        assertEq(withdraws.length, 1, "withdraw record should exist");
        uint256 withdrawRecordId = withdraws[0].id;

        uint256 beforeBal = collateral.balanceOf(user);
        vm.prank(user);
        vault.claimWithdraw(VAULT_HASH, withdrawRecordId);
        uint256 afterBal = collateral.balanceOf(user);
        assertEq(afterBal - beforeBal, 50 ether, "claim amount mismatch");
        withdraws = vault.getPendingWithdraws(VAULT_HASH, user);
        assertEq(withdraws.length, 0, "record should be removed after claim");

        vm.prank(user);
        vm.expectRevert(EnhancedVaultRecordsLib.RecordNotFound.selector);
        vault.claimWithdraw(VAULT_HASH, withdrawRecordId);
    }

    function testThreeStep_ShouldProcessQueueByPages_AndGateStart() external {
        address user2 = vm.addr(0xD00D);
        collateral.mint(user2, 1_000_000 ether);
        vm.prank(user2);
        collateral.approve(address(vault), type(uint256).max);

        _depositAs(user, VAULT_HASH, 100 ether);
        _depositAs(user2, VAULT_HASH, 50 ether);

        vm.warp(2 days);
        vm.prank(operator);
        vault.settlePreviousCycle(VAULT_HASH);

        (EnhancedVault.CyclePhase phase0, uint256 queueLen0, uint256 processed0, uint256 remaining0, bool canStart0) =
            vault.getQueueProgress(VAULT_HASH);
        assertEq(uint256(phase0), uint256(EnhancedVault.CyclePhase.SETTLED));
        assertEq(queueLen0, 2);
        assertEq(processed0, 0);
        assertEq(remaining0, 2);
        assertFalse(canStart0);

        vm.prank(operator);
        vault.processQueuedUsers(VAULT_HASH, 0, 1);
        vm.prank(operator);
        vm.expectRevert(EnhancedVault.InvalidCyclePhase.selector);
        vault.startNextCycle(VAULT_HASH);

        vm.prank(operator);
        vault.processQueuedUsers(VAULT_HASH, 1, 1);
        (EnhancedVault.CyclePhase phase1, uint256 queueLen1, uint256 processed1, uint256 remaining1, bool canStart1) =
            vault.getQueueProgress(VAULT_HASH);
        assertEq(uint256(phase1), uint256(EnhancedVault.CyclePhase.PROCESSING_DONE));
        assertEq(queueLen1, 2);
        assertEq(processed1, 2);
        assertEq(remaining1, 0);
        assertTrue(canStart1);

        vm.prank(operator);
        vault.startNextCycle(VAULT_HASH);
        assertEq(_currentCycleId(VAULT_HASH), 2);
    }

    function testSystemPauseFunds_ShouldInlineSettleUser_AndWithdrawShouldConvertToClaimableRecord() external {
        vault.seedVault(VAULT_HASH, address(collateral), address(strike), 1, type(uint256).max, 0, 0, 0, true, 1);

        address user2 = vm.addr(0xD00D);
        collateral.mint(user2, 1_000_000 ether);
        vm.prank(user2);
        collateral.approve(address(vault), type(uint256).max);

        _depositAs(user, VAULT_HASH, 100 ether);
        _depositAs(user2, VAULT_HASH, 50 ether);

        vm.warp(2 days);
        vm.prank(operator);
        vault.nextCycle(VAULT_HASH);

        vault.seedVault(VAULT_HASH, address(collateral), address(strike), 1, type(uint256).max, 0, 20_000, 0, true, 2);

        _depositAs(user, VAULT_HASH, 1 ether);

        vm.warp(3 days);
        vm.prank(operator);
        vault.settlePreviousCycle(VAULT_HASH);

        address[] memory users = new address[](1);
        users[0] = user;
        vm.prank(operator);
        vault.systemPauseFunds(VAULT_HASH, users);

        EnhancedVault.UserFund memory afterPause = _userFund(VAULT_HASH, user);
        assertEq(afterPause.activePrincipal, 0, "system pause should inline-settle active principal");
        assertEq(afterPause.pendingActivePrincipal, 0, "system pause should absorb pending deposits");
        assertEq(afterPause.systemPausedPrincipal, 101 ether, "system pause should stage the full force-exit amount");

        vm.prank(user);
        vault.withdraw(VAULT_HASH, 1 ether);

        EnhancedVault.FundRecord[] memory withdraws = vault.getPendingWithdraws(VAULT_HASH, user);
        assertEq(withdraws.length, 1, "system-pause self-settle should create one pending withdraw record");
        assertEq(withdraws[0].amount, 1 ether, "withdraw should convert the requested system-paused amount");

        afterPause = _userFund(VAULT_HASH, user);
        assertEq(
            afterPause.systemPausedPrincipal, 100 ether, "withdraw should decrement staged system-paused principal"
        );
        assertEq(
            afterPause.stoppedPrincipal,
            1 ether,
            "withdraw should move the requested amount into claimable stopped principal"
        );

        uint256 balanceBefore = collateral.balanceOf(user);
        vm.prank(user);
        vault.claimWithdraw(VAULT_HASH, withdraws[0].id);
        uint256 balanceAfter = collateral.balanceOf(user);
        assertEq(balanceAfter - balanceBefore, 1 ether, "claim should transfer only the converted amount");

        vm.prank(operator);
        vault.processQueuedUsers(VAULT_HASH, 0, 2);

        EnhancedVault.CycleRecord memory nextCycleAfterQueue = _cycleRecord(VAULT_HASH, 3);
        assertEq(
            nextCycleAfterQueue.totalActiveCollateral,
            50 ether,
            "system-paused user should be removed from next-cycle active"
        );
        assertEq(
            nextCycleAfterQueue.remainingActiveCollateral, 50 ether, "remaining active should shrink by paused amount"
        );

        EnhancedVault.UserFund memory fundBeforeStart = _userFund(VAULT_HASH, user);
        assertEq(fundBeforeStart.activePrincipal, 0, "user active should be zeroed in processing window");
        assertEq(fundBeforeStart.stoppedPrincipal, 0, "claim should consume stopped principal");
        assertEq(
            fundBeforeStart.systemPausedPrincipal, 100 ether, "unwithdrawn system-paused principal should remain staged"
        );
        assertEq(
            vault.getPendingWithdraws(VAULT_HASH, user).length, 0, "claim should clear the pending withdraw record"
        );

        vm.prank(operator);
        vault.startNextCycle(VAULT_HASH);

        EnhancedVault.UserFund memory fund = _userFund(VAULT_HASH, user);
        assertEq(fund.activePrincipal, 0, "system-paused user should not join next cycle active");
        assertEq(fund.stoppedPrincipal, 0, "claimed principal should stay cleared after cycle start");
        assertEq(
            fund.systemPausedPrincipal, 100 ether, "staged system-paused principal should persist across cycle start"
        );

        MockSwapRouterForVaultQueue router = new MockSwapRouterForVaultQueue(12 ether);
        vault.seedSwapRouter(address(router));
        vault.seedMaterializedPremium(VAULT_HASH, user, 20 ether);

        _enableBuyback(VAULT_HASH, user);

        vm.prank(operator);
        vault.buyback(
            VAULT_HASH,
            users,
            EnhancedVault.SwapParams({
                amountIn: 10 ether, amountOutMinimum: 0, deadline: block.timestamp + 1 hours, fee: 3000
            })
        );

        fund = _userFund(VAULT_HASH, user);
        assertEq(fund.pendingActivePrincipal, 12 ether, "system-paused user should still receive buyback collateral");
    }

    function testSystemPauseFunds_ShouldConvertWithdrawRequestsBeforePausingRemainingFunds() external {
        vault.seedVault(VAULT_HASH, address(collateral), address(strike), 1, type(uint256).max, 0, 0, 0, true, 1);

        address user2 = vm.addr(0xD00D);
        collateral.mint(user2, 1_000_000 ether);
        vm.prank(user2);
        collateral.approve(address(vault), type(uint256).max);

        _depositAs(user, VAULT_HASH, 100 ether);
        _depositAs(user2, VAULT_HASH, 50 ether);

        vm.warp(2 days);
        vm.prank(operator);
        vault.nextCycle(VAULT_HASH);

        vault.seedVault(VAULT_HASH, address(collateral), address(strike), 1, type(uint256).max, 0, 20_000, 0, true, 2);

        _depositAs(user, VAULT_HASH, 1 ether);

        vm.prank(user);
        vault.withdraw(VAULT_HASH, 40 ether);

        vm.warp(3 days);
        vm.prank(operator);
        vault.settlePreviousCycle(VAULT_HASH);

        address[] memory users = new address[](1);
        users[0] = user;
        vm.prank(operator);
        vault.systemPauseFunds(VAULT_HASH, users);

        EnhancedVault.UserFund memory fundAfterPause = _userFund(VAULT_HASH, user);
        assertEq(fundAfterPause.pendingWithdrawAmount, 0, "system pause should consume withdraw requests immediately");
        assertEq(fundAfterPause.stoppedPrincipal, 40 ether, "withdraw request should become claimable immediately");
        assertEq(
            fundAfterPause.systemPausedPrincipal,
            61 ether,
            "only non-withdrawing active plus pending deposit should enter system pause"
        );

        EnhancedVault.FundRecord[] memory withdrawRequests = vault.getPendingWithdrawRequests(VAULT_HASH, user);
        EnhancedVault.FundRecord[] memory withdraws = vault.getPendingWithdraws(VAULT_HASH, user);
        assertEq(withdrawRequests.length, 0, "withdraw request records should be deleted during system pause");
        assertEq(withdraws.length, 1, "system pause should create one withdraw record");
        assertEq(withdraws[0].amount, 40 ether, "withdraw record amount mismatch");
    }

    function testSystemPauseFunds_ShouldConvertMultipleWithdrawRequestsProRata_WhenSettledActiveIsInsufficient()
        external
    {
        vault.seedVault(VAULT_HASH, address(collateral), address(strike), 1, type(uint256).max, 0, 0, 0, true, 1);

        _depositAs(user, VAULT_HASH, 100 ether);

        vm.warp(2 days);
        vm.prank(operator);
        vault.nextCycle(VAULT_HASH);

        vault.seedVault(VAULT_HASH, address(collateral), address(strike), 1, type(uint256).max, 0, 20_000, 0, true, 2);

        vm.prank(user);
        vault.withdraw(VAULT_HASH, 40 ether);
        vm.prank(user);
        vault.withdraw(VAULT_HASH, 80 ether);

        vault.seedCycleRecord(VAULT_HASH, 2, 100 ether, 60 ether);

        vm.warp(3 days);
        vm.prank(operator);
        vault.settlePreviousCycle(VAULT_HASH);

        address[] memory users = new address[](1);
        users[0] = user;
        vm.prank(operator);
        vault.systemPauseFunds(VAULT_HASH, users);

        EnhancedVault.UserFund memory fundAfterPause = _userFund(VAULT_HASH, user);
        assertEq(fundAfterPause.pendingWithdrawAmount, 0, "system pause should fully consume queued withdraw amount");
        assertEq(fundAfterPause.stoppedPrincipal, 60 ether, "stopped principal should clamp to settled active");
        assertEq(fundAfterPause.systemPausedPrincipal, 0, "no active funds should remain for system pause");

        EnhancedVault.FundRecord[] memory withdrawRequests = vault.getPendingWithdrawRequests(VAULT_HASH, user);
        EnhancedVault.FundRecord[] memory withdraws = vault.getPendingWithdraws(VAULT_HASH, user);
        assertEq(withdrawRequests.length, 0, "all withdraw request records should be consumed");
        assertEq(withdraws.length, 2, "each request should become a withdraw record");
        assertEq(withdraws[0].amount + withdraws[1].amount, 60 ether, "pro-rata converted sum mismatch");
        assertEq(withdraws[0].amount, 20 ether, "first request should receive pro-rata share");
        assertEq(withdraws[1].amount, 40 ether, "second request should receive pro-rata share");
    }

    function testSystemPauseFunds_ShouldRevert_WhenPhaseIsNotSettled() external {
        address[] memory users = new address[](1);
        users[0] = user;
        vm.prank(operator);
        vm.expectRevert(EnhancedVault.InvalidCyclePhase.selector);
        vault.systemPauseFunds(VAULT_HASH, users);
    }

    function testSystemPauseFunds_ShouldRevert_WhenUserNotBelowMinPrincipalRatio() external {
        vault.seedVault(VAULT_HASH, address(collateral), address(strike), 1, type(uint256).max, 0, 0, 0, true, 1);

        _depositAs(user, VAULT_HASH, 100 ether);

        vm.warp(2 days);
        vm.prank(operator);
        vault.settlePreviousCycle(VAULT_HASH);

        address[] memory users = new address[](1);
        users[0] = user;
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(EnhancedVault.UserNotBelowMinPrincipalRatio.selector, user));
        vault.systemPauseFunds(VAULT_HASH, users);
    }

    function testProcessQueuedUsers_ShouldBeIdempotent_WithOverlappingPages() external {
        address user2 = vm.addr(0xD00D);
        address user3 = vm.addr(USER3_PK);
        collateral.mint(user2, 1_000_000 ether);
        collateral.mint(user3, 1_000_000 ether);
        vm.prank(user2);
        collateral.approve(address(vault), type(uint256).max);
        vm.prank(user3);
        collateral.approve(address(vault), type(uint256).max);

        _depositAs(user, VAULT_HASH, 100 ether);
        _depositAs(user2, VAULT_HASH, 50 ether);
        _depositAs(user3, VAULT_HASH, 25 ether);

        vm.warp(2 days);
        vm.prank(operator);
        vault.settlePreviousCycle(VAULT_HASH);

        vm.prank(operator);
        vault.processQueuedUsers(VAULT_HASH, 0, 2);

        (EnhancedVault.CyclePhase phase1, uint256 queueLen1, uint256 processed1,,) = vault.getQueueProgress(VAULT_HASH);
        assertEq(uint256(phase1), uint256(EnhancedVault.CyclePhase.SETTLED));
        assertEq(queueLen1, 3);
        assertEq(processed1, 2, "first page should process two users");

        vm.prank(operator);
        vault.processQueuedUsers(VAULT_HASH, 1, 2);

        (EnhancedVault.CyclePhase phase2, uint256 queueLen2, uint256 processed2,,) = vault.getQueueProgress(VAULT_HASH);
        assertEq(uint256(phase2), uint256(EnhancedVault.CyclePhase.PROCESSING_DONE));
        assertEq(queueLen2, 3);
        assertEq(processed2, 3, "overlapping page should only process newly uncovered user once");

        vm.prank(operator);
        vault.startNextCycle(VAULT_HASH);

        EnhancedVault.CycleRecord memory nextRec = _cycleRecord(VAULT_HASH, 2);
        assertEq(nextRec.totalActiveCollateral, 175 ether, "overlapping pagination must not double apply user deltas");
    }

    function testProcessQueuedUsers_PauseConversionShouldBeIdempotent_WithOverlappingPages() external {
        address user2 = vm.addr(0xD00D);
        address user3 = vm.addr(USER3_PK);
        collateral.mint(user2, 1_000_000 ether);
        collateral.mint(user3, 1_000_000 ether);
        vm.prank(user2);
        collateral.approve(address(vault), type(uint256).max);
        vm.prank(user3);
        collateral.approve(address(vault), type(uint256).max);

        _depositAs(user, VAULT_HASH, 100 ether);
        _depositAs(user2, VAULT_HASH, 50 ether);
        _depositAs(user3, VAULT_HASH, 25 ether);

        vm.warp(2 days);
        vm.prank(operator);
        vault.nextCycle(VAULT_HASH);

        vm.prank(user);
        vault.withdraw(VAULT_HASH, 40 ether);
        vm.prank(user2);
        vault.withdraw(VAULT_HASH, 10 ether);
        vm.prank(user3);
        vault.withdraw(VAULT_HASH, 5 ether);

        vm.warp(3 days);
        vm.prank(operator);
        vault.settlePreviousCycle(VAULT_HASH);

        vm.prank(operator);
        vault.processQueuedUsers(VAULT_HASH, 0, 2);
        vm.prank(operator);
        vault.processQueuedUsers(VAULT_HASH, 1, 2);

        EnhancedVault.FundRecord[] memory userWithdraws = vault.getPendingWithdraws(VAULT_HASH, user);
        assertEq(userWithdraws.length, 1, "withdraw request should convert to one withdraw");
        assertEq(userWithdraws[0].amount, 40 ether, "withdraw-request conversion should happen once");
    }

    function testSettleToStartWindow_ShouldFreezeWriteEntrypointsExceptWithdraw() external {
        _depositAs(user, VAULT_HASH, 100 ether);
        vault.seedActiveUserFund(VAULT_HASH, user, 10 ether, 1e18, 0);

        vm.warp(2 days);
        vm.prank(operator);
        vault.settlePreviousCycle(VAULT_HASH);

        vm.prank(user);
        vm.expectRevert(EnhancedVault.CycleProcessingLocked.selector);
        vault.deposit(VAULT_HASH, 1 ether);

        vm.prank(user);
        vault.withdraw(VAULT_HASH, 1 ether);
        EnhancedVault.FundRecord[] memory withdrawRequests = vault.getPendingWithdrawRequests(VAULT_HASH, user);
        assertEq(withdrawRequests.length, 1, "withdraw should be allowed outside OPEN when vault active");

        address[] memory users = new address[](1);
        users[0] = user;
        vm.prank(operator);
        vm.expectRevert(EnhancedVault.CycleProcessingLocked.selector);
        vault.buyback(
            VAULT_HASH,
            users,
            EnhancedVault.SwapParams({
                amountIn: 1 ether, amountOutMinimum: 0, deadline: block.timestamp + 1 hours, fee: 3000
            })
        );
    }

    function testSetVaultPaused_ShouldToggleByOwner() external {
        EnhancedVault.VaultState memory beforeSet = _vaultState(VAULT_HASH);
        assertFalse(beforeSet.isPaused, "default should be unpaused");

        vm.prank(owner);
        vault.setVaultPaused(VAULT_HASH, true);
        EnhancedVault.VaultState memory afterPause = _vaultState(VAULT_HASH);
        assertTrue(afterPause.isPaused, "owner should be able to pause");

        vm.prank(owner);
        vault.setVaultPaused(VAULT_HASH, false);
        EnhancedVault.VaultState memory afterUnpause = _vaultState(VAULT_HASH);
        assertFalse(afterUnpause.isPaused, "owner should be able to unpause");
    }

    function testPauseVault_ShouldAllowOperatorPauseOnly() external {
        vm.prank(operator);
        vault.pauseVault(VAULT_HASH);
        EnhancedVault.VaultState memory afterPause = _vaultState(VAULT_HASH);
        assertTrue(afterPause.isPaused, "operator should be able to pause");

        vm.prank(operator);
        vm.expectRevert();
        vault.setVaultPaused(VAULT_HASH, false);
    }

    function testWithdraw_ShouldRevert_WhenVaultPaused() external {
        vault.seedActiveUserFund(VAULT_HASH, user, 100 ether, 1e18, 0);
        vm.prank(owner);
        vault.setVaultPaused(VAULT_HASH, true);

        vm.prank(user);
        vm.expectRevert(EnhancedVault.VaultPaused.selector);
        vault.withdraw(VAULT_HASH, 10 ether);
    }

    function testNextCycle_ShouldRevert_WhenVaultInactive() external {
        vm.prank(owner);
        vault.setVaultActive(VAULT_HASH, false);

        vm.warp(2 days);
        vm.prank(operator);
        vm.expectRevert(EnhancedVault.VaultNotActive.selector);
        vault.nextCycle(VAULT_HASH);
    }

    function testSetVaultEnd_ShouldToggleByOwner() external {
        EnhancedVault.VaultState memory beforeSet = _vaultState(VAULT_HASH);
        assertFalse(beforeSet.isEnd, "default should be not ended");

        vm.prank(owner);
        vault.setVaultEnd(VAULT_HASH, true);
        EnhancedVault.VaultState memory afterEnd = _vaultState(VAULT_HASH);
        assertTrue(afterEnd.isEnd, "owner should be able to set end");

        vm.prank(owner);
        vault.setVaultEnd(VAULT_HASH, false);
        EnhancedVault.VaultState memory afterResume = _vaultState(VAULT_HASH);
        assertFalse(afterResume.isEnd, "owner should be able to unset end");
    }

    function testEndState_ShouldBlockNonWithdrawClaimSettleOps() external {
        vm.prank(owner);
        vault.setVaultEnd(VAULT_HASH, true);

        vm.prank(user);
        vm.expectRevert(EnhancedVault.VaultEnded.selector);
        vault.deposit(VAULT_HASH, 1 ether);

        vm.prank(operator);
        vm.expectRevert(EnhancedVault.VaultEnded.selector);
        vault.nextCycle(VAULT_HASH);

        vm.prank(operator);
        vm.expectRevert(EnhancedVault.VaultEnded.selector);
        vault.startNextCycle(VAULT_HASH);
    }

    function testEndState_ShouldAllowWithdrawClaimAndTerminalExitPipeline() external {
        vault.seedActiveUserFund(VAULT_HASH, user, 100 ether, 1e18, 0);
        vault.seedCycleRecord(VAULT_HASH, 1, 100 ether, 100 ether);

        vm.prank(owner);
        vault.setVaultEnd(VAULT_HASH, true);

        vm.prank(user);
        vault.withdraw(VAULT_HASH, 40 ether);

        vm.warp(2 days);
        vm.prank(operator);
        vault.settlePreviousCycle(VAULT_HASH);

        vm.prank(operator);
        vault.processQueuedUsers(VAULT_HASH, 0, 1);

        EnhancedVault.FundRecord[] memory withdraws = vault.getPendingWithdraws(VAULT_HASH, user);
        assertEq(withdraws.length, 1, "withdraw should still be processed in end state");
        uint256 beforeBal = collateral.balanceOf(user);
        vm.prank(user);
        vault.claimWithdraw(VAULT_HASH, withdraws[0].id);
        uint256 afterBal = collateral.balanceOf(user);
        assertEq(afterBal - beforeBal, 40 ether, "claim should remain available in end state");

        vm.prank(operator);
        vault.endVault(VAULT_HASH);

        (
            EnhancedVault.CyclePhase phase,
            uint256 queueLen,
            uint256 processedCount,
            uint256 remaining,
            bool canStartNextCycle
        ) = vault.getQueueProgress(VAULT_HASH);
        assertEq(uint256(phase), uint256(EnhancedVault.CyclePhase.ENDED), "vault should enter ENDED phase");
        assertEq(queueLen, 0, "queue snapshot should be cleared");
        assertEq(processedCount, 0, "processed count should reset");
        assertEq(remaining, 0, "remaining queue length should reset");
        assertFalse(canStartNextCycle, "ENDED phase cannot start a new cycle");

        beforeBal = collateral.balanceOf(user);
        vm.prank(user);
        vault.claimActive(VAULT_HASH);
        afterBal = collateral.balanceOf(user);
        assertEq(afterBal - beforeBal, 60 ether, "claimActive should return the remaining active principal");

        EnhancedVault.UserFund memory fund = _userFund(VAULT_HASH, user);
        assertEq(fund.activePrincipal, 0, "claimActive should clear active principal");
        assertEq(fund.pendingActivePrincipal, 0, "claimActive should clear pending principal");
    }

    function testProcessQueuedUser_ShouldRefundPendingDeposit_WhenCumCollateralHitsZero() external {
        vault.seedActiveUserFund(VAULT_HASH, user, 100 ether, 1e18, 0);
        vault.seedCycleRecord(VAULT_HASH, 1, 100 ether, 0);
        _depositAs(user, VAULT_HASH, 20 ether);

        vm.warp(2 days);
        vm.prank(operator);
        vault.nextCycle(VAULT_HASH);

        EnhancedVault.UserFund memory fund = _userFund(VAULT_HASH, user);
        assertEq(fund.activePrincipal, 0, "full-loss cycle should not keep pending deposit as active principal");
        assertEq(fund.stoppedPrincipal, 20 ether, "pending deposit should be refunded into stopped principal");
        assertEq(fund.pendingActivePrincipal, 0, "pending deposit should be consumed during queue processing");

        EnhancedVault.FundRecord[] memory withdraws = vault.getPendingWithdraws(VAULT_HASH, user);
        assertEq(withdraws.length, 1, "pending deposit refund should create a claimable withdraw record");
        assertEq(withdraws[0].amount, 20 ether, "withdraw record should match refunded pending deposit");

        uint256 balanceBefore = collateral.balanceOf(user);
        vm.prank(user);
        vault.claimWithdraw(VAULT_HASH, withdraws[0].id);
        uint256 balanceAfter = collateral.balanceOf(user);
        assertEq(balanceAfter - balanceBefore, 20 ether, "claim should return refunded pending deposit");
    }

    function _depositAs(address depositor, bytes32 vaultHash, uint256 amount) internal {
        vm.prank(depositor);
        vault.deposit(vaultHash, amount);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Vm} from "forge-std/Vm.sol";
import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";
import {EnhancedVault} from "../src/periphery/vault/EnhancedVault.sol";
import {EnhancedVaultRecordsLib} from "../src/periphery/vault/libs/EnhancedVaultRecordsLib.sol";
import {IEnhancedOptions} from "../src/core/interfaces/IEnhancedOptions.sol";
import {ISwapRouter} from "../src/core/interfaces/ISwapRouter.sol";
import {EnhancedVaultLinkedLibraries} from "./helpers/EnhancedVaultLinkedLibraries.sol";

contract MockERC20ForVaultUnit is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_, 18) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MockSwapRouterForVaultUnit is ISwapRouter {
    uint256 public immutable amountOut;

    constructor(uint256 amountOut_) {
        amountOut = amountOut_;
    }

    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256) {
        params;
        MockERC20ForVaultUnit(params.tokenOut).mint(params.recipient, amountOut);
        return amountOut;
    }

    function exactInput(ExactInputParams calldata) external payable returns (uint256) {
        revert("UNSUPPORTED");
    }

    function exactOutputSingle(ExactOutputSingleParams calldata) external payable returns (uint256) {
        revert("UNSUPPORTED");
    }

    function exactOutput(ExactOutputParams calldata) external payable returns (uint256) {
        revert("UNSUPPORTED");
    }
}

contract MockEnhancedOptionsForVaultUnit {
    address public marginPool;

    function setMarginPool(address newMarginPool) external {
        marginPool = newMarginPool;
    }
}

contract EnhancedVaultUnitHarness is EnhancedVault {
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
        uint256 currentCycleId,
        uint256 protocolFeeRate
    ) external {
        VaultState storage st = vaults[vaultHash];
        st.params.cycleDuration = 1 days;
        st.params.underlyingAsset = collateralAsset;
        st.params.collateralAsset = collateralAsset;
        st.params.strikeAsset = strikeAsset;
        st.params.minInvestmentAmount = minInvestmentAmount;
        st.params.capacity = capacity;
        st.params.startTime = 1;
        st.params.strikePriceBps = strikePriceBps;
        st.params.minPrincipalRatio = minPrincipalRatio;
        st.params.buybackPriceRatio = buybackPriceRatio;
        st.protocolFeeRate = protocolFeeRate;
        st.isActive = isActive;
        st.isPaused = false;
        st.isEnd = false;
        st.currentCycleId = currentCycleId;
        st.currentCycleStart = 1;
        vaultPhases[vaultHash] = CyclePhase.OPEN;
        cumCollateral[vaultHash][0] = 1e18;
        cumPremium[vaultHash][0] = 0;
    }

    function seedPhase(bytes32 vaultHash, CyclePhase phase) external {
        vaultPhases[vaultHash] = phase;
    }

    function seedUserFundState(
        bytes32 vaultHash,
        address user,
        uint256 activePrincipal,
        uint256 initialAmountTotal,
        uint256 entryCumCollateral,
        uint256 entryCumPremium
    ) external {
        UserFund storage fund = userFunds[vaultHash][user];
        fund.activePrincipal = activePrincipal;
        fund.initialAmountTotal = initialAmountTotal;
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

    function seedSystemPausedPrincipalWithBasis(bytes32 vaultHash, address user, uint256 amount, uint256 basis)
        external
    {
        UserFund storage fund = userFunds[vaultHash][user];
        fund.systemPausedPrincipal = amount;
        fund.initialAmountTotal = basis;
        fund.exists = true;
    }

    function seedMaterializedPremium(bytes32 vaultHash, address user, uint256 premium) external {
        UserFund storage fund = userFunds[vaultHash][user];
        fund.materializedPremium = premium;
        fund.exists = true;
    }

    function seedSystemPausedPrincipal(bytes32 vaultHash, address user, uint256 amount) external {
        userFunds[vaultHash][user].systemPausedPrincipal = amount;
        userFunds[vaultHash][user].initialAmountTotal = amount;
    }

    function seedSwapRouter(address router) external {
        swapRouter = router;
    }

    function seedCumCollateral(bytes32 vaultHash, uint256 cycleId, uint256 value) external {
        cumCollateral[vaultHash][cycleId] = value;
    }

    function seedCumPremium(bytes32 vaultHash, uint256 cycleId, uint256 value) external {
        cumPremium[vaultHash][cycleId] = value;
    }

    function seedCurrentCycleId(bytes32 vaultHash, uint256 cycleId) external {
        vaults[vaultHash].currentCycleId = cycleId;
    }

    function seedProtocolFeeRate(bytes32 vaultHash, uint256 protocolFeeRate) external {
        vaults[vaultHash].protocolFeeRate = protocolFeeRate;
    }
}

contract EnhancedVaultUnitTest is EnhancedVaultLinkedLibraries {
    bytes32 internal constant VAULT_HASH = keccak256("vault-unit");
    bytes32 internal constant DEPOSITED_EVENT = keccak256("Deposited(bytes32,address,uint256,uint256)");
    bytes32 internal constant WITHDRAW_REQUESTED_EVENT =
        keccak256("WithdrawRequested(bytes32,address,uint256,uint256)");
    bytes32 internal constant AUTO_BUY_ENABLED_SET_EVENT = keccak256("AutoBuyEnabledSet(bytes32,address,bool)");
    bytes4 internal constant BUYBACK_DISABLED_SELECTOR = bytes4(keccak256("BuybackDisabled(address)"));

    uint256 internal constant OWNER_PK = 0xA11CE;
    uint256 internal constant OPERATOR_PK = 0xB0B;
    uint256 internal constant USER_PK = 0xCAFE;
    uint256 internal constant HEALTHY_USER_PK = 0xD00D;
    uint256 internal constant VIOLATING_USER_PK = 0xD0D0;

    EnhancedVaultUnitHarness internal vault;
    MockERC20ForVaultUnit internal collateral;
    MockERC20ForVaultUnit internal strike;

    address internal owner;
    address internal operator;
    address internal user;
    address internal healthyUser;
    address internal violatingUser;

    function setUp() external {
        _etchEnhancedVaultLibraries();

        owner = vm.addr(OWNER_PK);
        operator = vm.addr(OPERATOR_PK);
        user = vm.addr(USER_PK);
        healthyUser = vm.addr(HEALTHY_USER_PK);
        violatingUser = vm.addr(VIOLATING_USER_PK);

        vault = new EnhancedVaultUnitHarness();
        vault.seedOwner(owner);
        vault.seedCore(address(0x1111), operator, address(0x2222));

        collateral = new MockERC20ForVaultUnit("Collateral", "COL");
        strike = new MockERC20ForVaultUnit("Strike", "USD");

        vault.seedVault(
            VAULT_HASH, address(collateral), address(strike), 1, type(uint256).max, 0, 8_000, -1_250, true, 1, 0
        );

        collateral.mint(user, 1_000_000 ether);
        collateral.mint(healthyUser, 1_000_000 ether);
        collateral.mint(violatingUser, 1_000_000 ether);
        collateral.mint(address(vault), 1_000_000 ether);
        strike.mint(address(vault), 1_000_000 ether);

        vm.prank(user);
        collateral.approve(address(vault), type(uint256).max);
        vm.prank(healthyUser);
        collateral.approve(address(vault), type(uint256).max);
        vm.prank(violatingUser);
        collateral.approve(address(vault), type(uint256).max);
    }

    function _userFund(address targetUser) internal view returns (EnhancedVault.UserFund memory fund) {
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
            fund.exists,
            fund.autoBuyEnabled,
            fund.exitAllRequested,
            fund.exitAllRequestedCycleId
        ) = vault.userFunds(VAULT_HASH, targetUser);
    }

    function _vaultState() internal view returns (EnhancedVault.VaultState memory st) {
        (
            EnhancedVault.VaultParams memory params,
            bool isActive,
            uint256 currentCycleId,
            uint256 currentCycleStart,
            uint256 totalDeposited,
            bool isPaused,
            bool isEnd,
            uint256 protocolFeeRate
        ) = vault.vaults(VAULT_HASH);

        st = EnhancedVault.VaultState({
            params: params,
            isActive: isActive,
            currentCycleId: currentCycleId,
            currentCycleStart: currentCycleStart,
            totalDeposited: totalDeposited,
            isPaused: isPaused,
            isEnd: isEnd,
            protocolFeeRate: protocolFeeRate
        });
    }

    function _cycleRecord(uint256 cycleId) internal view returns (EnhancedVault.CycleRecord memory rec) {
        (
            rec.totalActiveCollateral,
            rec.remainingActiveCollateral,
            rec.totalPremium,
            rec.collateralRatio,
            rec.premiumRatio
        ) = vault.cycleRecords(VAULT_HASH, cycleId);
    }

    function testWithdraw_ShouldRevertWhenPendingExitRecordLimitIsReached() external {
        vault.seedUserFundState(VAULT_HASH, user, 200 ether, 200 ether, 1e18, 0);
        vault.seedCycleRecord(VAULT_HASH, 1, 200 ether, 200 ether);

        // Build 32 withdraw requests in cycle 1, convert them to 32 withdraw records,
        // then add 32 new requests in cycle 2 so the shared exit cap reaches 64.
        for (uint256 i; i < 32; i++) {
            vm.prank(user);
            vault.withdraw(VAULT_HASH, 1 ether);
        }

        vm.warp(2 days);
        vm.prank(operator);
        vault.nextCycle(VAULT_HASH);

        vault.seedCycleRecord(VAULT_HASH, 2, 168 ether, 168 ether);
        for (uint256 i; i < 32; i++) {
            vm.prank(user);
            vault.withdraw(VAULT_HASH, 1 ether);
        }

        vm.prank(user);
        vm.expectRevert(EnhancedVaultRecordsLib.PendingRecordLimitExceeded.selector);
        vault.withdraw(VAULT_HASH, 1 ether);
    }

    function testProtocolFeeRate_ShouldDefaultToZeroInVaultState() external {
        assertEq(_vaultState().protocolFeeRate, 0, "new vault should default protocol fee rate to zero");
    }

    function testProtocolFeeRecipient_ShouldBeQueryableAfterOwnerUpdate() external {
        vm.prank(owner);
        vault.setProtocolFeeRecipient(healthyUser);

        assertEq(vault.protocolFeeRecipient(), healthyUser, "recipient should be publicly queryable");
    }

    function testProtocolFee_ShouldReduceCollateralRatioAndNextActiveCollateral() external {
        vault.seedProtocolFeeRate(VAULT_HASH, 100_000);
        _depositAs(user, 100 ether);

        vm.warp(2 days);
        vm.prank(operator);
        vault.nextCycle(VAULT_HASH);

        vm.warp(3 days);
        vm.prank(operator);
        vault.nextCycle(VAULT_HASH);

        EnhancedVault.CycleRecord memory settled = _cycleRecord(2);
        EnhancedVault.CycleRecord memory nextRec = _cycleRecord(3);
        EnhancedVault.UserPosition memory pos = vault.getMyPosition(VAULT_HASH, user);

        assertEq(vault.protocolFeeAccrued(VAULT_HASH), 1 ether, "fee should accrue from cycle-start active TVL");
        assertEq(settled.collateralRatio, 99e16, "fee should reduce user collateral ratio");
        assertEq(nextRec.totalActiveCollateral, 99 ether, "next active should use net collateral after fee");
        assertEq(nextRec.remainingActiveCollateral, 99 ether, "next remaining should use net collateral after fee");
        assertEq(pos.activeBalance, 99 ether, "projected active balance should reflect protocol fee");
        assertEq(_vaultState().totalDeposited, 99 ether, "capacity accounting should remove fee from user TVL");
    }

    function testProtocolFee_ShouldCapAtGrossCollateralAfterSettle() external {
        vault.seedProtocolFeeRate(VAULT_HASH, 10_000_000);
        vault.seedCycleRecord(VAULT_HASH, 1, 100 ether, 5 ether / 10);

        vm.warp(2 days);
        vm.prank(operator);
        vault.nextCycle(VAULT_HASH);

        EnhancedVault.CycleRecord memory settled = _cycleRecord(1);
        EnhancedVault.CycleRecord memory nextRec = _cycleRecord(2);

        assertEq(vault.protocolFeeAccrued(VAULT_HASH), 5 ether / 10, "fee should cap at gross collateral");
        assertEq(settled.collateralRatio, 0, "capped fee can reduce collateral ratio to zero");
        assertEq(nextRec.totalActiveCollateral, 0, "no user principal should remain after capped fee");
    }

    function testClaimProtocolFees_ShouldTransferAccruedCollateralWithoutReducingTotalDepositedAgain() external {
        vault.seedProtocolFeeRate(VAULT_HASH, 100_000);
        _depositAs(user, 100 ether);

        vm.prank(owner);
        vault.setProtocolFeeRecipient(healthyUser);

        vm.warp(2 days);
        vm.prank(operator);
        vault.nextCycle(VAULT_HASH);

        vm.warp(3 days);
        vm.prank(operator);
        vault.nextCycle(VAULT_HASH);

        uint256 totalDepositedBeforeClaim = _vaultState().totalDeposited;
        uint256 recipientBefore = collateral.balanceOf(healthyUser);

        vm.prank(healthyUser);
        vault.claimProtocolFees(VAULT_HASH);

        assertEq(collateral.balanceOf(healthyUser) - recipientBefore, 1 ether, "recipient should receive accrued fee");
        assertEq(vault.protocolFeeAccrued(VAULT_HASH), 0, "claim should clear accrued fee");
        assertEq(_vaultState().totalDeposited, totalDepositedBeforeClaim, "claim should not reduce TVL twice");
    }

    function testBuyback_ShouldIncreaseTotalDepositedEvenWhenCapacityIsExceeded() external {
        MockSwapRouterForVaultUnit router = new MockSwapRouterForVaultUnit(2 ether);
        vault.seedSwapRouter(address(router));
        _depositAs(user, 1 ether);
        vault.seedMaterializedPremium(VAULT_HASH, user, 2 ether);

        vault.seedVault(VAULT_HASH, address(collateral), address(strike), 1, 1 ether, 0, 8_000, -1_250, true, 1, 0);
        vm.prank(user);
        vault.setBuybackEnabled(VAULT_HASH, true);

        vm.prank(operator);
        vault.buyback(VAULT_HASH, _users(user), _swapParams(1 ether));

        (,,,, uint256 totalDeposited,,,) = vault.vaults(VAULT_HASH);
        EnhancedVault.UserFund memory fund = _userFund(user);
        assertEq(totalDeposited, 3 ether, "buyback output should increase total deposited beyond capacity");
        assertEq(fund.initialAmountTotal, 1 ether, "buyback should not increase the user's initial principal basis");
    }

    function testClaimProtocolFees_ShouldRevertForUnauthorizedCaller() external {
        vm.prank(user);
        vm.expectRevert();
        vault.claimProtocolFees(VAULT_HASH);
    }

    function testDeposit_ShouldCreateFirstPendingDepositRecord() external {
        _depositAs(user, 10 ether);

        EnhancedVault.UserFund memory fund = _userFund(user);
        assertEq(fund.pendingActivePrincipal, 10 ether, "first deposit should increase pending active");
        assertEq(fund.nextRecordId, 1, "first deposit should allocate record id 1");
    }

    function testDeposit_ShouldIncrementRecordCounterOnLaterDeposits() external {
        _depositAs(user, 10 ether);
        _depositAs(user, 5 ether);

        EnhancedVault.UserFund memory fund = _userFund(user);
        assertEq(fund.pendingActivePrincipal, 15 ether, "later deposits should continue accumulating pending active");
        assertEq(fund.nextRecordId, 2, "later deposits should keep incrementing record ids");
    }

    function testWithdraw_ShouldRevertInSettledPhase() external {
        vault.seedUserFundState(VAULT_HASH, user, 10 ether, 10 ether, 1e18, 0);
        vault.seedCycleRecord(VAULT_HASH, 1, 10 ether, 10 ether);

        vm.warp(2 days);
        vm.prank(operator);
        vault.settlePreviousCycle(VAULT_HASH);

        vault.seedPhase(VAULT_HASH, EnhancedVault.CyclePhase.SETTLED);

        vm.prank(user);
        vm.expectRevert(EnhancedVault.CycleProcessingLocked.selector);
        vault.withdraw(VAULT_HASH, 1 ether);
    }

    function testWithdraw_ShouldRevertInProcessingDonePhase() external {
        vault.seedUserFundState(VAULT_HASH, user, 10 ether, 10 ether, 1e18, 0);
        vault.seedCycleRecord(VAULT_HASH, 1, 10 ether, 10 ether);

        vm.warp(2 days);
        vm.prank(operator);
        vault.settlePreviousCycle(VAULT_HASH);

        vm.prank(user);
        vm.expectRevert(EnhancedVault.CycleProcessingLocked.selector);
        vault.withdraw(VAULT_HASH, 1 ether);
    }

    function testSystemPauseFunds_ShouldRevertForHealthyUser() external {
        vault.seedUserFundState(VAULT_HASH, healthyUser, 10 ether, 10 ether, 1e18, 0);
        vault.seedCycleRecord(VAULT_HASH, 1, 10 ether, 10 ether);

        vm.warp(2 days);
        vm.prank(operator);
        vault.settlePreviousCycle(VAULT_HASH);
        vault.seedPhase(VAULT_HASH, EnhancedVault.CyclePhase.SETTLED);

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(EnhancedVault.UserNotBelowMinPrincipalRatio.selector, healthyUser));
        vault.systemPauseFunds(VAULT_HASH, _users(healthyUser));
    }

    function testSystemPauseFunds_ShouldInlineSettleViolatingUser() external {
        vault.seedUserFundState(VAULT_HASH, healthyUser, 10 ether, 7 ether, 1e18, 0);
        vault.seedUserFundState(VAULT_HASH, violatingUser, 7 ether, 10 ether, 1e18, 0);
        vault.seedCycleRecord(VAULT_HASH, 1, 17 ether, 17 ether);

        vm.warp(2 days);
        vm.prank(operator);
        vault.settlePreviousCycle(VAULT_HASH);
        vault.seedPhase(VAULT_HASH, EnhancedVault.CyclePhase.SETTLED);

        vm.prank(operator);
        vault.systemPauseFunds(VAULT_HASH, _users(violatingUser));

        EnhancedVault.UserFund memory violatingFund = _userFund(violatingUser);
        EnhancedVault.UserFund memory healthyFund = _userFund(healthyUser);
        assertEq(violatingFund.activePrincipal, 0, "violating user active should be settled inline");
        assertEq(
            violatingFund.systemPausedPrincipal,
            7 ether,
            "violating user system-paused principal should hold the force-exit amount"
        );
        assertEq(healthyFund.stoppedPrincipal, 0, "healthy user state should remain untouched before processing");
    }

    function testBuyback_ShouldMoveSpentPremiumIntoPendingActivePrincipal() external {
        MockSwapRouterForVaultUnit router = new MockSwapRouterForVaultUnit(1 ether);
        vault.seedSwapRouter(address(router));
        _depositAs(user, 1 ether);
        vault.seedMaterializedPremium(VAULT_HASH, user, 2 ether);

        vm.prank(user);
        vault.setBuybackEnabled(VAULT_HASH, true);

        vm.prank(operator);
        vault.buyback(VAULT_HASH, _users(user), _swapParams(1 ether));

        EnhancedVault.UserFund memory fund = _userFund(user);
        assertEq(fund.materializedPremium, 1 ether, "buyback should deduct spent premium");
        assertEq(fund.pendingActivePrincipal, 2 ether, "buyback output should add to pending active");
        assertEq(vault.getQueueUsers(VAULT_HASH, 0, 10)[0], user, "buyback user should be queued");
    }

    function testBuyback_ShouldMaterializeProjectedPremiumBeforeAvailabilityCheck() external {
        MockSwapRouterForVaultUnit router = new MockSwapRouterForVaultUnit(1 ether);
        vault.seedSwapRouter(address(router));
        vault.seedCurrentCycleId(VAULT_HASH, 2);
        vault.seedUserFundState(VAULT_HASH, user, 100 ether, 100 ether, 1e18, 1e16);
        vault.seedCumPremium(VAULT_HASH, 1, 3e16);

        vm.prank(user);
        vault.setBuybackEnabled(VAULT_HASH, true);

        vm.prank(operator);
        vault.buyback(VAULT_HASH, _users(user), _swapParams(1 ether));

        EnhancedVault.UserFund memory fund = _userFund(user);
        assertEq(fund.materializedPremium, 1 ether, "buyback should materialize projected premium then spend");
        assertEq(fund.entryCumPremium, 3e16, "buyback should advance premium checkpoint after materializing");
        assertEq(fund.pendingActivePrincipal, 1 ether, "buyback output should land in pending active");
    }

    function testDeposit_ShouldDefaultNewUserFundToManualBuybackDisabledAndAutoBuyEnabled() external {
        _depositAs(user, 1 ether);

        EnhancedVault.UserFund memory fund = _userFund(user);
        assertFalse(fund.buybackEnabled, "first fund creation should default manual buyback off");
        assertTrue(fund.autoBuyEnabled, "first fund creation should default auto-buy on");
    }

    function testDeposit_ShouldNotOverrideExplicitBuybackOptOut() external {
        _depositAs(user, 1 ether);

        vm.prank(user);
        vault.setBuybackEnabled(VAULT_HASH, false);

        _depositAs(user, 1 ether);

        EnhancedVault.UserFund memory fund = _userFund(user);
        assertFalse(fund.buybackEnabled, "deposit should preserve explicit opt-out");
        assertEq(fund.pendingActivePrincipal, 2 ether, "second deposit should still be accepted");
    }

    function testBuyback_ShouldRevert_WhenUserHasNotEnabledBuyback() external {
        MockSwapRouterForVaultUnit router = new MockSwapRouterForVaultUnit(1 ether);
        vault.seedSwapRouter(address(router));
        vault.seedMaterializedPremium(VAULT_HASH, user, 2 ether);

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(BUYBACK_DISABLED_SELECTOR, user));
        vault.buyback(VAULT_HASH, _users(user), _swapParams(1 ether));
    }

    function testSetAutoBuyEnabled_ShouldRevertWhenFundMissing() external {
        vm.prank(user);
        vm.expectRevert(EnhancedVault.FundNotFound.selector);
        vault.setAutoBuyEnabled(VAULT_HASH, true);
    }

    function testSetAutoBuyEnabled_ShouldAllowUserToToggleAndEmitEvent() external {
        _depositAs(user, 1 ether);

        vm.recordLogs();
        vm.prank(user);
        vault.setAutoBuyEnabled(VAULT_HASH, true);

        Vm.Log memory log = _findLog(vm.getRecordedLogs(), AUTO_BUY_ENABLED_SET_EVENT);
        assertEq(log.emitter, address(vault), "unexpected auto-buy event emitter");
        assertEq(log.topics.length, 3, "auto-buy event topic count mismatch");
        assertEq(log.topics[1], VAULT_HASH, "auto-buy event vaultHash mismatch");
        assertEq(address(uint160(uint256(log.topics[2]))), user, "auto-buy event user mismatch");
        bool enabled = abi.decode(log.data, (bool));
        assertTrue(enabled, "auto-buy event enabled mismatch");

        EnhancedVault.UserFund memory fund = _userFund(user);
        assertFalse(fund.buybackEnabled, "auto-buy should not mutate manual buyback");
        assertTrue(fund.autoBuyEnabled, "auto-buy should be enabled");

        vm.prank(user);
        vault.setAutoBuyEnabled(VAULT_HASH, false);

        fund = _userFund(user);
        assertFalse(fund.buybackEnabled, "auto-buy disable should not mutate manual buyback");
        assertFalse(fund.autoBuyEnabled, "auto-buy should be disabled");
    }

    function testBuyback_ShouldAllowAutoBuyWhenManualBuybackDisabled() external {
        MockSwapRouterForVaultUnit router = new MockSwapRouterForVaultUnit(1 ether);
        vault.seedSwapRouter(address(router));
        vault.seedMaterializedPremium(VAULT_HASH, user, 2 ether);

        vm.prank(user);
        vault.setAutoBuyEnabled(VAULT_HASH, true);

        vm.prank(operator);
        vault.buyback(VAULT_HASH, _users(user), _swapParams(1 ether));

        EnhancedVault.UserFund memory fund = _userFund(user);
        assertFalse(fund.buybackEnabled, "manual buyback should remain disabled");
        assertTrue(fund.autoBuyEnabled, "auto-buy should remain enabled");
        assertEq(fund.materializedPremium, 1 ether, "auto-buy should deduct spent premium");
        assertEq(fund.pendingActivePrincipal, 1 ether, "auto-buy output should land in pending active");
    }

    function testSetBuybackEnabled_ShouldAllowUserToOptInBeforeOperatorBuyback() external {
        MockSwapRouterForVaultUnit router = new MockSwapRouterForVaultUnit(1 ether);
        vault.seedSwapRouter(address(router));
        vault.seedMaterializedPremium(VAULT_HASH, user, 2 ether);

        vm.prank(user);
        vault.setBuybackEnabled(VAULT_HASH, true);

        vm.prank(operator);
        vault.buyback(VAULT_HASH, _users(user), _swapParams(1 ether));

        EnhancedVault.UserFund memory fund = _userFund(user);
        assertEq(fund.materializedPremium, 1 ether, "buyback should deduct spent premium after opt-in");
        assertEq(fund.pendingActivePrincipal, 1 ether, "buyback output should land in pending active after opt-in");
    }

    function testSetBuybackEnabled_ShouldAllowUserToOptOutAgain() external {
        MockSwapRouterForVaultUnit router = new MockSwapRouterForVaultUnit(1 ether);
        vault.seedSwapRouter(address(router));
        vault.seedMaterializedPremium(VAULT_HASH, user, 2 ether);

        vm.startPrank(user);
        vault.setBuybackEnabled(VAULT_HASH, true);
        vault.setBuybackEnabled(VAULT_HASH, false);
        vm.stopPrank();

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(BUYBACK_DISABLED_SELECTOR, user));
        vault.buyback(VAULT_HASH, _users(user), _swapParams(1 ether));
    }

    function testWithdraw_ShouldAllowRequest_WhenAutoBuyIsEnabled() external {
        vault.seedUserFundState(VAULT_HASH, user, 20 ether, 20 ether, 1e18, 0);

        vm.prank(user);
        vault.setAutoBuyEnabled(VAULT_HASH, true);

        vm.prank(user);
        vault.withdraw(VAULT_HASH, 7 ether);

        EnhancedVault.UserFund memory fund = _userFund(user);
        EnhancedVault.FundRecord[] memory withdraws = vault.getPendingWithdrawRequests(VAULT_HASH, user);
        assertEq(fund.pendingWithdrawAmount, 7 ether, "auto-buy should not block principal withdraw requests");
        assertEq(withdraws.length, 1, "withdraw request should be recorded");
        assertEq(withdraws[0].amount, 7 ether, "withdraw request amount mismatch");
    }

    function testClaimWithdraw_ShouldAllowPrincipalClaim_WhenAutoBuyIsEnabled() external {
        vault.seedUserFundState(VAULT_HASH, user, 20 ether, 20 ether, 1e18, 0);
        vault.seedCycleRecord(VAULT_HASH, 1, 20 ether, 20 ether);

        vm.prank(user);
        vault.setAutoBuyEnabled(VAULT_HASH, true);

        vm.prank(user);
        vault.withdraw(VAULT_HASH, 7 ether);

        vm.warp(2 days);
        vm.prank(operator);
        vault.nextCycle(VAULT_HASH);

        EnhancedVault.FundRecord[] memory withdraws = vault.getPendingWithdraws(VAULT_HASH, user);
        assertEq(withdraws.length, 1, "withdraw request should convert into one claimable record");

        uint256 balanceBefore = collateral.balanceOf(user);
        vm.prank(user);
        vault.claimWithdraw(VAULT_HASH, withdraws[0].id);

        uint256 balanceAfter = collateral.balanceOf(user);
        EnhancedVault.UserFund memory fund = _userFund(user);
        assertEq(balanceAfter - balanceBefore, 7 ether, "claim should transfer collateral");
        assertEq(fund.stoppedPrincipal, 0, "claim should consume stopped principal");
        assertEq(
            vault.getPendingWithdraws(VAULT_HASH, user).length, 0, "claim should remove the pending withdraw record"
        );
    }

    function testSystemPausedWithdrawAfterLoss_ShouldReduceBasisProportionallyAndClearOnFullExit() external {
        vault.seedSystemPausedPrincipalWithBasis(VAULT_HASH, user, 60 ether, 100 ether);

        vm.prank(user);
        vault.withdraw(VAULT_HASH, 30 ether);

        EnhancedVault.UserFund memory fund = _userFund(user);
        assertEq(fund.systemPausedPrincipal, 30 ether, "half of the paused collateral should remain");
        assertEq(fund.initialAmountTotal, 50 ether, "half of the cost basis should remain");

        vm.prank(user);
        vault.withdraw(VAULT_HASH, 30 ether);

        fund = _userFund(user);
        assertEq(fund.systemPausedPrincipal, 0, "the final paused withdrawal should clear collateral");
        assertEq(fund.initialAmountTotal, 0, "the final paused withdrawal should clear the cost basis");
    }

    function testClaimActiveAfterLoss_ShouldClearInitialAmountTotal() external {
        vault.seedUserFundState(VAULT_HASH, user, 100 ether, 100 ether, 1e18, 0);
        vault.seedCurrentCycleId(VAULT_HASH, 1);
        vault.seedCumCollateral(VAULT_HASH, 1, 6e17);
        vault.seedPhase(VAULT_HASH, EnhancedVault.CyclePhase.ENDED);

        uint256 balanceBefore = collateral.balanceOf(user);
        vm.prank(user);
        vault.claimActive(VAULT_HASH);
        uint256 balanceAfter = collateral.balanceOf(user);

        EnhancedVault.UserFund memory fund = _userFund(user);
        assertEq(balanceAfter - balanceBefore, 60 ether, "claim should return the loss-adjusted collateral");
        assertEq(fund.activePrincipal, 0, "claim should clear active principal");
        assertEq(fund.initialAmountTotal, 0, "claiming the full position should clear the cost basis");
    }

    function testCancelWithdraw_ShouldRemovePendingRequestAndReducePendingAmount() external {
        vault.seedUserFundState(VAULT_HASH, user, 20 ether, 20 ether, 1e18, 0);

        vm.prank(user);
        vault.withdraw(VAULT_HASH, 5 ether);

        vm.prank(user);
        vault.cancelWithdraw(VAULT_HASH, 1);

        EnhancedVault.UserFund memory fund = _userFund(user);
        assertEq(fund.pendingWithdrawAmount, 0, "cancel should rollback pending withdraw amount");
        assertEq(
            vault.getPendingWithdrawRequests(VAULT_HASH, user).length, 0, "cancel should remove the pending request"
        );
    }

    function testCancelDeposit_ShouldRemovePendingDepositAndRefundUser() external {
        _depositAs(user, 9 ether);

        uint256 balanceBefore = collateral.balanceOf(user);
        vm.prank(user);
        vault.cancelDeposit(VAULT_HASH, 1);

        uint256 balanceAfter = collateral.balanceOf(user);
        EnhancedVault.UserFund memory fund = _userFund(user);
        assertEq(balanceAfter - balanceBefore, 9 ether, "cancel should refund the pending deposit");
        assertEq(fund.pendingActivePrincipal, 0, "cancel should rollback pending active principal");
        assertEq(
            vault.getPendingDeposits(VAULT_HASH, user).length, 0, "cancel should remove the pending deposit record"
        );
    }

    function testDepositAndWithdrawEvents_ShouldMatchPendingRecordIds() external {
        vault.seedUserFundState(VAULT_HASH, user, 20 ether, 20 ether, 1e18, 0);

        vm.recordLogs();
        _depositAs(user, 10 ether);
        vm.prank(user);
        vault.withdraw(VAULT_HASH, 3 ether);

        EnhancedVault.FundRecord[] memory deposits = vault.getPendingDeposits(VAULT_HASH, user);
        EnhancedVault.FundRecord[] memory withdraws = vault.getPendingWithdrawRequests(VAULT_HASH, user);
        assertEq(deposits.length, 1, "deposit record should exist");
        assertEq(withdraws.length, 1, "withdraw request record should exist");
        assertEq(deposits[0].id, 1, "deposit record id mismatch");
        assertEq(withdraws[0].id, 2, "withdraw record id mismatch");

        Vm.Log[] memory logs = vm.getRecordedLogs();
        Vm.Log memory depositedLog = _findLog(logs, DEPOSITED_EVENT);
        Vm.Log memory withdrawLog = _findLog(logs, WITHDRAW_REQUESTED_EVENT);

        (uint256 depositedRecordId, uint256 depositedAmount) = abi.decode(depositedLog.data, (uint256, uint256));
        (uint256 withdrawRecordId, uint256 withdrawAmount) = abi.decode(withdrawLog.data, (uint256, uint256));

        assertEq(depositedRecordId, deposits[0].id, "deposit event record id should match stored record");
        assertEq(withdrawRecordId, withdraws[0].id, "withdraw event record id should match stored record");
        assertEq(depositedAmount, 10 ether, "deposit event amount mismatch");
        assertEq(withdrawAmount, 3 ether, "withdraw event amount mismatch");
    }

    function testGetMyPosition_ShouldProjectActiveBalanceAgainstLastCompletedCycle() external {
        vault.seedUserFundState(VAULT_HASH, user, 100 ether, 100 ether, 1e18, 0);
        vault.seedCurrentCycleId(VAULT_HASH, 2);
        vault.seedCumCollateral(VAULT_HASH, 1, 8e17);

        EnhancedVault.UserPosition memory pos = vault.getMyPosition(VAULT_HASH, user);
        assertEq(pos.activeBalance, 80 ether, "active balance should use the last completed cycle");
    }

    function testSettledCycleId_ShouldUseCurrentCycleAccumulator_InSettledAndProcessingDone() external {
        vault.seedUserFundState(VAULT_HASH, user, 100 ether, 100 ether, 1e18, 1e16);
        vault.seedCurrentCycleId(VAULT_HASH, 2);
        vault.seedCumCollateral(VAULT_HASH, 1, 8e17);
        vault.seedCumCollateral(VAULT_HASH, 2, 6e17);
        vault.seedCumPremium(VAULT_HASH, 1, 2e16);
        vault.seedCumPremium(VAULT_HASH, 2, 5e16);

        vault.seedPhase(VAULT_HASH, EnhancedVault.CyclePhase.SETTLED);
        uint256 balanceBefore = strike.balanceOf(user);
        vm.prank(user);
        vault.claimPremium(VAULT_HASH, 4 ether);
        uint256 balanceAfter = strike.balanceOf(user);
        assertEq(balanceAfter - balanceBefore, 4 ether, "SETTLED should use currentCycle accumulators");

        vault.seedUserFundState(VAULT_HASH, user, 100 ether, 100 ether, 1e18, 1e16);
        vault.seedMaterializedPremium(VAULT_HASH, user, 0);
        vault.seedPhase(VAULT_HASH, EnhancedVault.CyclePhase.PROCESSING_DONE);

        EnhancedVault.UserPosition memory pos = vault.getMyPosition(VAULT_HASH, user);
        assertEq(pos.activeBalance, 60 ether, "PROCESSING_DONE should read currentCycle collateral accumulator");
        assertEq(pos.projectedPremium, 4 ether, "PROCESSING_DONE should read currentCycle premium accumulator");
    }

    function testClaimPremium_ShouldReduceMaterializedPremiumAndTransferStrikeAsset() external {
        vault.seedMaterializedPremium(VAULT_HASH, user, 5 ether);

        uint256 balanceBefore = strike.balanceOf(user);
        vm.prank(user);
        vault.claimPremium(VAULT_HASH, 3 ether);

        uint256 balanceAfter = strike.balanceOf(user);
        EnhancedVault.UserFund memory fund = _userFund(user);
        assertEq(balanceAfter - balanceBefore, 3 ether, "claim should transfer strike asset");
        assertEq(fund.materializedPremium, 2 ether, "claim should reduce materialized premium");
    }

    function testClaimPremium_ShouldRevert_WhenAutoBuyIsEnabled() external {
        vault.seedMaterializedPremium(VAULT_HASH, user, 5 ether);

        vm.prank(user);
        vault.setAutoBuyEnabled(VAULT_HASH, true);

        vm.prank(user);
        vm.expectRevert(EnhancedVault.AutoBuyPremiumClaimDisabled.selector);
        vault.claimPremium(VAULT_HASH, 3 ether);
    }

    function testClaimPremium_ShouldMaterializeProjectedPremiumBeforeTransfer() external {
        vault.seedUserFundState(VAULT_HASH, user, 100 ether, 100 ether, 1e18, 1e16);
        vault.seedMaterializedPremium(VAULT_HASH, user, 1 ether);
        vault.seedCurrentCycleId(VAULT_HASH, 2);
        vault.seedCumPremium(VAULT_HASH, 1, 3e16);

        uint256 balanceBefore = strike.balanceOf(user);
        vm.prank(user);
        vault.claimPremium(VAULT_HASH, 3 ether);

        uint256 balanceAfter = strike.balanceOf(user);
        EnhancedVault.UserFund memory fund = _userFund(user);
        assertEq(balanceAfter - balanceBefore, 3 ether, "claim should transfer projected premium");
        assertEq(fund.materializedPremium, 0, "claim should consume newly materialized premium");
        assertEq(fund.entryCumPremium, 3e16, "claim should advance entry premium checkpoint");
    }

    function testClaimActive_ShouldPreserveProjectedPremiumForLaterClaim() external {
        vault.seedUserFundState(VAULT_HASH, user, 100 ether, 100 ether, 1e18, 1e16);
        vault.seedCurrentCycleId(VAULT_HASH, 1);
        vault.seedCumCollateral(VAULT_HASH, 1, 1e18);
        vault.seedCumPremium(VAULT_HASH, 1, 3e16);
        vault.seedPhase(VAULT_HASH, EnhancedVault.CyclePhase.ENDED);

        vm.prank(user);
        vault.claimActive(VAULT_HASH);

        uint256 premiumBalanceBefore = strike.balanceOf(user);
        vm.prank(user);
        vault.claimPremium(VAULT_HASH, 2 ether);
        uint256 premiumBalanceAfter = strike.balanceOf(user);

        EnhancedVault.UserFund memory fund = _userFund(user);
        assertEq(
            premiumBalanceAfter - premiumBalanceBefore, 2 ether, "claimActive should not discard projected premium"
        );
        assertEq(fund.materializedPremium, 0, "claimPremium should consume the final-cycle premium");
    }

    function testClaimActive_ShouldReturnSystemPausedPrincipalWhenEnded() external {
        vault.seedSystemPausedPrincipal(VAULT_HASH, user, 12 ether);
        vault.seedPhase(VAULT_HASH, EnhancedVault.CyclePhase.ENDED);

        uint256 beforeBal = collateral.balanceOf(user);
        vm.prank(user);
        vault.claimActive(VAULT_HASH);
        uint256 afterBal = collateral.balanceOf(user);

        assertEq(afterBal - beforeBal, 12 ether, "claimActive should release system-paused principal");

        EnhancedVault.UserFund memory fund = _userFund(user);
        assertEq(fund.systemPausedPrincipal, 0, "claimActive should clear system-paused principal");
    }

    function testSetAssetApprovalSwapRouter_ShouldPersistConfiguredRouterApproval() external {
        address oldRouter = address(0x1111);
        address newRouter = address(0x2222);

        vm.startPrank(owner);
        vault.setSwapRouter(oldRouter);
        vault.setAssetApprovalSwapRouter(address(strike), true);
        assertEq(strike.allowance(address(vault), oldRouter), type(uint256).max, "router approval should persist");

        vault.setSwapRouter(newRouter);
        vm.stopPrank();

        assertEq(
            strike.allowance(address(vault), oldRouter), type(uint256).max, "old router approval remains until revoked"
        );
    }

    function testMarginPool_ShouldReadEnhancedOptionsMarginPool() external {
        MockEnhancedOptionsForVaultUnit options = new MockEnhancedOptionsForVaultUnit();
        address newMarginPool = address(0xABCD);
        options.setMarginPool(newMarginPool);
        vault.seedCore(address(options), operator, address(0x2222));

        assertEq(vault.marginPool(), newMarginPool, "Vault should read EnhancedOptions marginPool");
    }

    function testSetAssetApprovalMarginPool_ShouldApproveEnhancedOptionsMarginPool() external {
        MockEnhancedOptionsForVaultUnit options = new MockEnhancedOptionsForVaultUnit();
        address newMarginPool = address(0xABCD);
        options.setMarginPool(newMarginPool);
        vault.seedCore(address(options), operator, address(0x2222));

        vm.prank(owner);
        vault.setAssetApprovalMarginPool(address(collateral), true);

        assertEq(
            collateral.allowance(address(vault), newMarginPool),
            type(uint256).max,
            "Vault should approve EnhancedOptions marginPool"
        );
    }

    function _depositAs(address depositor, uint256 amount) internal {
        vm.prank(depositor);
        vault.deposit(VAULT_HASH, amount);
    }

    function _users(address onlyUser) internal pure returns (address[] memory users) {
        users = new address[](1);
        users[0] = onlyUser;
    }

    function _swapParams(uint256 amountIn) internal view returns (EnhancedVault.SwapParams memory) {
        return EnhancedVault.SwapParams({
            amountIn: amountIn, amountOutMinimum: 0, deadline: block.timestamp + 1 hours, fee: 3_000
        });
    }

    function _findLog(Vm.Log[] memory logs, bytes32 signature) internal pure returns (Vm.Log memory) {
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].topics.length != 0 && logs[i].topics[0] == signature) {
                return logs[i];
            }
        }
        revert("event not found");
    }
}

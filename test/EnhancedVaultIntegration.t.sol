// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {EnhancedVaultIntegrationBase} from "./helpers/EnhancedVaultIntegrationBase.sol";
import {EnhancedVault} from "../src/periphery/vault/EnhancedVault.sol";

contract EnhancedVaultIntegrationTest is EnhancedVaultIntegrationBase {
    // This smoke test is run with --offline and currently needs:
    // --skip test/EnhancedVaultUserQueue.t.sol
    // --skip test/EnhancedVaultAdvanceCycleState.t.sol
    function testFixture_ShouldCreateVaultAndSeedSpotPrice() external {
        assertTrue(vaultHash != bytes32(0), "vault hash should be non-zero");
        assertFalse(defaultVaultParams.isPut, "default vault should be call");
        assertEq(address(vault.enhancedOptions()), address(enhancedOptions), "vault enhanced options mismatch");
        assertEq(vault.protocolFeeRecipient(), owner, "vault protocol fee recipient mismatch");
        assertEq(_currentCycleId(vaultHash), 1, "vault current cycle should start at one");
        assertEq(
            oracle.getPrice(address(underlying)),
            SEEDED_UNDERLYING_PRICE,
            "underlying spot price should match seeded value"
        );
    }

    function testPayloadBuilders_ShouldMatchExpectedLengths() external {
        TransferConfig memory transferCfg = _defaultTransferConfig();
        bytes memory transferPayload = _buildSignedTransferPayload(transferCfg);
        assertEq(transferPayload.length, 130);

        OrderConfig memory orderCfg = _createDefaultOrder(_defaultOrderOverrides());
        bytes memory orderPayload = _buildSignedOrderPayload(orderCfg);
        assertEq(orderPayload.length, 377);
    }

    function testIntegration_Setup_ShouldCreateVaultFundMakerAndOpenVault() external {
        _depositAs(user, 10 ether);
        _warpToCycleEnd();
        _settleAndProcessInSingleBatch(vaultHash);
        _makerDepositStrikeToMMarket(1_000 ether);

        uint256 vaultId = _createOrderAsOperator(vaultHash, _defaultOrderOverrides());
        uint256 activeCycleId = _currentCycleId(vaultHash);
        uint256[] memory vaultIds = vault.getVaultIds(vaultHash, activeCycleId);
        EnhancedVault.VaultState memory st = _vaultState(vaultHash);
        EnhancedVault.CycleRecord memory rec = _cycleRecord(vaultHash, activeCycleId);

        assertGt(vaultId, 0, "vault id should be created");
        assertEq(vaultIds.length, 1, "active cycle should track exactly one opened vault");
        assertEq(vaultIds[0], vaultId, "stored vault id mismatch");
        assertEq(st.currentCycleId, 2, "deposit activation should advance the vault to cycle 2");
        assertEq(rec.totalActiveCollateral, 10 ether, "user deposit should become active collateral");
        assertEq(
            rec.remainingActiveCollateral, 9 ether, "one unit of collateral should be consumed by the opened vault"
        );
    }

    function testIntegration_OTMFullCycle_ShouldSettlePremiumAndAllowWithdrawClaim() external {
        _depositAs(user, 10 ether);
        _warpToCycleEnd();
        _settleAndProcessInSingleBatch(vaultHash);
        _makerDepositStrikeToMMarket(1_000 ether);
        _createOrderAsOperator(vaultHash, _defaultOrderOverrides());

        uint256 cycleTwoExpiry = _currentCycleExpiry();
        _setExpiryPrice(cycleTwoExpiry, 1_500e8);
        vm.warp(cycleTwoExpiry + 2);

        vm.prank(operator);
        vault.nextCycle(vaultHash);

        EnhancedVault.VaultState memory afterOtmSettlement = _vaultState(vaultHash);
        EnhancedVault.CycleRecord memory cycleThreeRecord = _cycleRecord(vaultHash, afterOtmSettlement.currentCycleId);
        assertEq(afterOtmSettlement.currentCycleId, 3, "OTM settlement should advance into cycle 3");
        assertEq(
            cycleThreeRecord.totalActiveCollateral, 10 ether, "full collateral should remain active after OTM expiry"
        );

        vm.prank(user);
        vault.withdraw(vaultHash, 4 ether);

        _warpToCycleEnd();
        vm.prank(operator);
        vault.nextCycle(vaultHash);

        EnhancedVault.UserFund memory fundAfterProcess = _userFund(vaultHash, user);
        EnhancedVault.FundRecord[] memory withdraws = vault.getPendingWithdraws(vaultHash, user);
        assertEq(withdraws.length, 1, "withdraw request should convert into one claimable record");
        assertEq(withdraws[0].amount, 4 ether, "claimable amount should match the requested withdraw");
        assertEq(fundAfterProcess.activePrincipal, 6 ether, "remaining collateral should stay active");
        assertEq(
            fundAfterProcess.materializedPremium,
            1 ether,
            "OTM cycle premium should materialize on the next queued user action"
        );

        uint256 balanceBeforeClaim = underlying.balanceOf(user);
        vm.prank(user);
        vault.claimWithdraw(vaultHash, withdraws[0].id);
        uint256 balanceAfterClaim = underlying.balanceOf(user);

        assertEq(balanceAfterClaim - balanceBeforeClaim, 4 ether, "claim should transfer withdrawn collateral");
        assertEq(vault.getPendingWithdraws(vaultHash, user).length, 0, "claim should clear the withdraw record");
    }

    function testIntegration_ShortCallITMExpiry_FullCycle_LossIsRealized() external {
        uint256 otmCollateral = _runExpiryScenario(1_500e8);
        uint256 itmCollateral = _runExpiryScenario(3_000e8);

        assertLt(itmCollateral, otmCollateral, "ITM settlement should leave less active collateral than OTM");
    }

    function testIntegration_UserDepositsAgainAndPartialWithdraw_AcrossMultipleCycles() external {
        _activateUsers(user, maker, owner);
        _finishCycleInBatchesAtPrice(1_900e8, 1);

        _depositAs(user, 3 ether);
        vm.prank(user);
        vault.withdraw(vaultHash, 2 ether);

        _finishCycleInBatchesAtPrice(2_000e8, 1);

        EnhancedVault.UserFund memory fund = _userFund(vaultHash, user);
        assertGt(fund.activePrincipal, 0, "user should still have active principal after partial withdraw");
        assertGt(fund.entryCumCollateral, 0, "next cycle entry collateral checkpoint should refresh");
        assertGt(fund.entryCumPremium, 0, "premium checkpoint should reflect prior realized premium");
        assertEq(fund.pendingWithdrawAmount, 0, "queued withdraw should be consumed during cycle processing");
        assertEq(_currentCycleId(vaultHash), 4, "two extra cycle transitions should land in cycle 4");
    }

    function testIntegration_SystemPauseThenBuyback_UserReactivates() external {
        _configureMinPrincipalRatioVault(9_800);
        _activateUserPosition(user, 10 ether);
        _depositAs(user, 1 ether);
        _finishCycleAtPrice(3_000e8);

        address[] memory users = _users(user);
        vm.prank(operator);
        vault.systemPauseFunds(vaultHash, users);

        EnhancedVault.UserFund memory pausedFund = _userFund(vaultHash, user);
        uint256 premiumBefore = pausedFund.materializedPremium;
        assertGt(
            pausedFund.systemPausedPrincipal, 0, "ITM loss should move the user into staged system-paused principal"
        );
        assertEq(
            vault.getPendingWithdraws(vaultHash, user).length, 0, "system pause should not create a withdraw record"
        );

        _processCurrentSettledQueue(users.length);

        vm.prank(operator);
        vault.startNextCycle(vaultHash);

        vm.prank(user);
        vault.withdraw(vaultHash, pausedFund.systemPausedPrincipal);

        EnhancedVault.FundRecord[] memory withdraws = vault.getPendingWithdraws(vaultHash, user);
        assertEq(withdraws.length, 1, "withdraw should convert staged system-paused funds into a claimable record");
        assertEq(
            withdraws[0].amount,
            pausedFund.systemPausedPrincipal,
            "claimable record should match withdrawn system-paused principal"
        );

        vm.prank(user);
        vault.setBuybackEnabled(vaultHash, true);

        vm.prank(operator);
        vault.buyback(vaultHash, users, _defaultSwapParams(1 ether));

        EnhancedVault.UserFund memory afterBuyback = _userFund(vaultHash, user);
        assertLt(afterBuyback.materializedPremium, premiumBefore, "buyback should spend part of the realized premium");
        assertGt(afterBuyback.pendingActivePrincipal, 0, "buyback output should become pending active collateral");

        _openNextCycleWithoutOrder();
        EnhancedVault.UserFund memory reactivated = _userFund(vaultHash, user);
        assertGt(reactivated.activePrincipal, 0, "buyback collateral should reactivate in the next cycle");
    }

    function _runExpiryScenario(uint256 expiryPrice) internal returns (uint256 settledCollateralAfterCycle) {
        uint256 snapshotId = vm.snapshot();

        _depositAs(user, 10 ether);
        _warpToCycleEnd();
        _settleAndProcessInSingleBatch(vaultHash);
        _makerDepositStrikeToMMarket(1_000 ether);

        uint256 vaultId = _createOrderAsOperator(vaultHash, _defaultOrderOverrides());
        uint256 cycleTwoExpiry = _currentCycleExpiry();
        _setExpiryPrice(cycleTwoExpiry, expiryPrice);
        vm.warp(cycleTwoExpiry + 2);

        vm.prank(operator);
        vault.nextCycle(vaultHash);

        EnhancedVault.UserFund memory fund = _userFund(vaultHash, user);
        EnhancedVault.CycleRecord memory settled = _cycleRecord(vaultHash, _currentCycleId(vaultHash) - 1);
        EnhancedVault.CycleRecord memory nextCycleRecord = _cycleRecord(vaultHash, _currentCycleId(vaultHash));
        assertGt(vaultId, 0, "scenario should open one vault");
        assertGt(
            fund.activePrincipal + fund.pendingActivePrincipal + fund.materializedPremium,
            0,
            "scenario should leave observable user state"
        );
        assertEq(_currentCycleId(vaultHash), 3, "scenario should always advance exactly one active option cycle");
        assertGt(settled.premiumRatio, 0, "opened short call should always realize premium");
        if (expiryPrice > SEEDED_UNDERLYING_PRICE) {
            assertLt(settled.collateralRatio, 1e18, "ITM settlement should scale collateral down");
        }

        settledCollateralAfterCycle = nextCycleRecord.totalActiveCollateral;
        vm.revertTo(snapshotId);
    }
}

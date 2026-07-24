// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {Actions} from "../../../core/libs/Actions.sol";
import {Parser} from "../../../core/libs/Parser.sol";
import {IEnhancedOptions} from "../../../core/interfaces/IEnhancedOptions.sol";
import {EnhancedVault} from "../EnhancedVault.sol";

library EnhancedVaultCycleLib {
    uint256 internal constant PRECISION = 1e18;
    uint256 internal constant PROTOCOL_FEE_RATE_BASE = 10_000_000;

    error ExpiryInPast();
    error MustBeCashSettled();
    error WrongCollateral();
    error WrongExpiry();
    error WrongOptionType();
    error WrongStrikeAsset();
    error WrongTaker();
    error WrongUnderlying();

    function settleCycleAndUpdateAccumulators(
        IEnhancedOptions enhancedOptions,
        mapping(bytes32 => mapping(uint256 => uint256[])) storage vaultIdsByCycle,
        mapping(bytes32 => uint256) storage cyclePremium,
        mapping(bytes32 => mapping(uint256 => EnhancedVault.CycleRecord)) storage cycleRecords,
        mapping(bytes32 => mapping(uint256 => uint256)) storage cumCollateral,
        mapping(bytes32 => mapping(uint256 => uint256)) storage cumPremium,
        mapping(bytes32 => uint256) storage protocolFeeAccrued,
        bytes32 vaultHash,
        uint256 cycleId,
        EnhancedVault.VaultState storage st
    ) public returns (EnhancedVault.CycleSettlement memory settled) {
        address taker = address(this);
        uint256[] storage vaultIds = vaultIdsByCycle[vaultHash][cycleId];
        uint256 len = vaultIds.length;
        if (len > 0) {
            Actions.ActionArgs[] memory settleActions = new Actions.ActionArgs[](len);
            for (uint256 i; i < len;) {
                settleActions[i] = Actions.ActionArgs({
                    actionType: Actions.ActionType.SettleVault,
                    owner: taker,
                    secondAddress: taker,
                    asset: address(0),
                    vaultId: vaultIds[i],
                    amount: 0,
                    index: 0,
                    data: ""
                });
                unchecked {
                    ++i;
                }
            }

            uint256 balBefore = IERC20(st.params.collateralAsset).balanceOf(taker);
            enhancedOptions.ingressoSettle(settleActions);
            uint256 balAfter = IERC20(st.params.collateralAsset).balanceOf(taker);
            settled.totalReturned = balAfter > balBefore ? balAfter - balBefore : 0;
        }

        settled.totalPremium = cyclePremium[vaultHash];
        delete cyclePremium[vaultHash];

        EnhancedVault.CycleRecord storage rec = cycleRecords[vaultHash][cycleId];
        settled.activeCol = rec.totalActiveCollateral;
        uint256 grossCollateralAfterSettle = rec.remainingActiveCollateral + settled.totalReturned;

        if (settled.activeCol > 0) {
            settled.protocolFee = settled.activeCol * st.protocolFeeRate / PROTOCOL_FEE_RATE_BASE;
            if (settled.protocolFee > grossCollateralAfterSettle) {
                settled.protocolFee = grossCollateralAfterSettle;
            }
            settled.netActiveCollateral = grossCollateralAfterSettle - settled.protocolFee;
            if (settled.protocolFee > 0) {
                protocolFeeAccrued[vaultHash] += settled.protocolFee;
            }

            rec.collateralRatio = settled.netActiveCollateral * PRECISION / settled.activeCol;
            rec.premiumRatio = settled.totalPremium * PRECISION / settled.activeCol;
        } else {
            settled.netActiveCollateral = 0;
            rec.collateralRatio = PRECISION;
            rec.premiumRatio = 0;
        }
        rec.totalPremium = settled.totalPremium;

        cumCollateral[vaultHash][cycleId] = cumCollateral[vaultHash][cycleId - 1] * rec.collateralRatio / PRECISION;
        cumPremium[vaultHash][cycleId] =
            cumPremium[vaultHash][cycleId - 1] + rec.premiumRatio * cumCollateral[vaultHash][cycleId - 1] / PRECISION;
    }

    function advanceCycleState(
        mapping(bytes32 => mapping(uint256 => EnhancedVault.CycleRecord)) storage cycleRecords,
        bytes32 vaultHash,
        uint256,
        uint256 nextId,
        uint256 activeCol,
        uint256 netActiveCollateral
    ) public returns (uint256 capReduction) {
        EnhancedVault.CycleRecord storage nextRec = cycleRecords[vaultHash][nextId];
        nextRec.totalActiveCollateral = netActiveCollateral;
        nextRec.remainingActiveCollateral = nextRec.totalActiveCollateral;

        capReduction = activeCol > netActiveCollateral ? activeCol - netActiveCollateral : 0;
    }

    function validateOrder(
        EnhancedVault.VaultParams storage params,
        bytes calldata payload,
        uint256 currentCycleStart,
        address taker
    ) public view returns (uint256 orderCollateral) {
        (
            /* Quote */,
            Parser.Confirmation memory conf,
            /* quoteSig */,
            /* confSig */,
            /* fee1 */,
            /* fee2 */
        ) = Parser.parseQuoteAndConfirmation(payload);

        if (uint256(conf.expiry) < block.timestamp) revert ExpiryInPast();
        if (conf.taker != taker) revert WrongTaker();
        if (uint256(conf.expiry) != currentCycleStart + params.cycleDuration) revert WrongExpiry();
        if (conf.isPhysicallySettled) revert MustBeCashSettled();
        if (conf.assetAddress != params.underlyingAsset) revert WrongUnderlying();
        if (conf.collateralAsset != params.collateralAsset) revert WrongCollateral();
        if (conf.usd != params.strikeAsset) revert WrongStrikeAsset();
        if (conf.isPut != params.isPut) revert WrongOptionType();

        return conf.collateralAmount;
    }
}

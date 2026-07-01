// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {EnhancedOptions} from "src/core/EnhancedOptions.sol";
import {EnhancedVaultIntegrationBase} from "./helpers/EnhancedVaultIntegrationBase.sol";

contract EnhancedOptionsRegressionTest is EnhancedVaultIntegrationBase {
    function test_newPositionRejectsMakerWithoutWhitelistReceiver() external {
        vm.startPrank(owner);
        _setMakerWhitelistAsOwner(maker, address(0));
        vm.stopPrank();

        OrderOverrides memory overrides = _defaultOrderOverrides();
        overrides.quoteNonce = 701;
        overrides.confirmationNonce = 701;

        OrderConfig memory cfg = _createDefaultOrder(overrides);
        bytes memory payload = _buildSignedOrderPayload(cfg);

        underlying.mint(address(vault), 1e18);
        _makerDepositStrikeToMMarket(10e18);

        vm.prank(address(vault));
        vm.expectRevert(abi.encodeWithSignature("MakerWhitelistRequired(address)", maker));
        enhancedOptions.ingressoNewTrustedTakerPosition(payload);
    }

    function test_newPositionRejectsQuoteAfterValidUntil() external {
        vm.warp(1_000);

        OrderOverrides memory overrides = _defaultOrderOverrides();
        overrides.quoteNonce = 601;
        overrides.confirmationNonce = 601;
        overrides.validUntil = 999;

        OrderConfig memory cfg = _createDefaultOrder(overrides);
        bytes memory payload = _buildSignedOrderPayload(cfg);

        underlying.mint(address(vault), 1e18);
        _makerDepositStrikeToMMarket(10e18);

        vm.prank(address(vault));
        vm.expectRevert(EnhancedOptions.QuoteAuthorizationExpired.selector);
        enhancedOptions.ingressoNewTrustedTakerPosition(payload);
    }

    function test_newPositionAllowsQuoteAtValidUntil() external {
        vm.warp(1_000);

        OrderOverrides memory overrides = _defaultOrderOverrides();
        overrides.quoteNonce = 602;
        overrides.confirmationNonce = 602;
        overrides.validUntil = 1_000;

        OrderConfig memory cfg = _createDefaultOrder(overrides);
        bytes memory payload = _buildSignedOrderPayload(cfg);

        underlying.mint(address(vault), 1e18);
        _makerDepositStrikeToMMarket(10e18);

        vm.prank(address(vault));
        (uint256 vaultId, uint256 premium) = enhancedOptions.ingressoNewTrustedTakerPosition(payload);

        assertGt(vaultId, 0);
        assertEq(premium, 1e18);
    }

    function test_newPositionAllowsQuoteBeforeValidUntil() external {
        vm.warp(1_000);

        OrderOverrides memory overrides = _defaultOrderOverrides();
        overrides.quoteNonce = 603;
        overrides.confirmationNonce = 603;
        overrides.validUntil = 1_001;

        OrderConfig memory cfg = _createDefaultOrder(overrides);
        bytes memory payload = _buildSignedOrderPayload(cfg);

        underlying.mint(address(vault), 1e18);
        _makerDepositStrikeToMMarket(10e18);

        vm.prank(address(vault));
        (uint256 vaultId, uint256 premium) = enhancedOptions.ingressoNewTrustedTakerPosition(payload);

        assertGt(vaultId, 0);
        assertEq(premium, 1e18);
    }

    function test_trustedTakerAndMakerOrderAcceptsInvalidSignaturesWhenMakerIsTrusted() external {
        OrderOverrides memory overrides = _defaultOrderOverrides();
        overrides.quoteNonce = 301;
        overrides.confirmationNonce = 301;

        OrderConfig memory cfg = _createDefaultOrder(overrides);
        bytes memory payload = _withInvalidQuoteSignature(_buildSignedOrderPayload(cfg));

        underlying.mint(address(vault), 1e18);
        _makerDepositStrikeToMMarket(10e18);

        vm.prank(address(vault));
        (uint256 vaultId, uint256 premium) = enhancedOptions.ingressoNewTrustedTakerAndMakerPosition(payload);

        assertGt(vaultId, 0);
        assertEq(premium, 1e18);
    }

    function test_vaultCreateOrderAcceptsInvalidMakerQuoteSignatureWhenMakerIsTrusted() external {
        _depositAs(user, 10 ether);
        _warpToCycleEnd();
        _settleAndProcessInSingleBatch(vaultHash);
        _makerDepositStrikeToMMarket(1_000 ether);

        OrderOverrides memory overrides = _defaultOrderOverrides();
        overrides.quoteNonce = 302;
        overrides.confirmationNonce = 302;

        OrderConfig memory cfg = _createDefaultOrder(overrides);
        cfg.expiry = _currentCycleExpiry();
        bytes memory payload = _withInvalidQuoteSignature(_buildSignedOrderPayload(cfg));
        bytes memory vaultSig = _signVaultOrder(payload);

        vm.prank(operator);
        vault.createOrder(vaultHash, payload, vaultSig, true);

        uint256[] memory vaultIds = vault.getVaultIds(vaultHash, _currentCycleId(vaultHash));
        assertEq(vaultIds.length, 1);
    }

    function test_trustedTakerOrderRejectsConfirmationQuantityAboveQuoteQuantity() external {
        OrderOverrides memory overrides = _defaultOrderOverrides();
        overrides.quoteQuantity = 1e18;
        overrides.quantity = 2e18;
        overrides.collateralAmount = 2e18;
        overrides.quoteNonce = 101;
        overrides.confirmationNonce = 101;

        OrderConfig memory cfg = _createDefaultOrder(overrides);
        bytes memory payload = _buildSignedOrderPayload(cfg);

        underlying.mint(address(vault), 2e18);
        _makerDepositStrikeToMMarket(10e18);

        vm.prank(address(vault));
        vm.expectRevert(EnhancedOptions.QuantityExceedsQuote.selector);
        enhancedOptions.ingressoNewTrustedTakerPosition(payload);
    }

    function test_trustedTakerAndMakerOrderDeductsMakerFeeFromPremiumAndPaysCombinedFee() external {
        address feeRecipient = bot;
        vm.prank(owner);
        enhancedOptions.setFeeRecipient(feeRecipient);

        OrderOverrides memory overrides = _defaultOrderOverrides();
        overrides.quoteNonce = 401;
        overrides.confirmationNonce = 401;
        overrides.protocolFee = 0.02e18;
        overrides.makerFee = 0.03e18;

        OrderConfig memory cfg = _createDefaultOrder(overrides);
        bytes memory payload = _buildSignedOrderPayload(cfg);

        underlying.mint(address(vault), 1e18);
        _makerDepositStrikeToMMarket(10e18);

        uint256 feeRecipientBalanceBefore = strike.balanceOf(feeRecipient);

        vm.prank(address(vault));
        (, uint256 premium) = enhancedOptions.ingressoNewTrustedTakerAndMakerPosition(payload);

        assertEq(premium, 0.97e18);
        assertEq(strike.balanceOf(address(vault)), 0.97e18);
        assertEq(strike.balanceOf(feeRecipient) - feeRecipientBalanceBefore, 0.05e18);
    }

    function test_depositAndOpenRejectsWithdrawTransferPayload() external {
        vm.prank(user);
        underlying.approve(address(mmarket), type(uint256).max);

        TransferConfig memory depositCfg = _defaultTransferConfig();
        depositCfg.amount = 1e18;
        depositCfg.isDeposit = true;
        depositCfg.nonce = 201;

        bytes memory depositPayload = _buildSignedTransferPayload(depositCfg);
        vm.prank(operator);
        enhancedOptions.ingressoTransferAsset(depositPayload);

        TransferConfig memory withdrawCfg = depositCfg;
        withdrawCfg.isDeposit = false;
        withdrawCfg.nonce = 202;

        bytes memory withdrawPayload = _buildSignedTransferPayload(withdrawCfg);

        vm.prank(operator);
        vm.expectRevert(EnhancedOptions.InvalidTransferIsDeposit.selector);
        enhancedOptions.ingressoDepositAndOpen(withdrawPayload, "");
    }

    function _withInvalidQuoteSignature(bytes memory payload) internal pure returns (bytes memory) {
        for (uint256 i = 114; i < 179; i++) {
            payload[i] = 0;
        }
        return payload;
    }
}

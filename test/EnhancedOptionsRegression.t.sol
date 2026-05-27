// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {EnhancedOptions} from "src/core/EnhancedOptions.sol";
import {EnhancedVaultIntegrationBase} from "./helpers/EnhancedVaultIntegrationBase.sol";

contract EnhancedOptionsRegressionTest is EnhancedVaultIntegrationBase {
    function test_trustedTakerAndMakerOrderAcceptsInvalidSignaturesWhenMakerIsTrusted() external {
        vm.prank(owner);
        enhancedOptions.setTrustedMaker(maker, true);

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

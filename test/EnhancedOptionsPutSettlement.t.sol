// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Actions} from "src/core/libs/Actions.sol";
import {MMarketOperations} from "src/core/libs/MMarketOperations.sol";
import {EnhancedVaultIntegrationBase, EnhancedVaultFixtureERC20} from "./helpers/EnhancedVaultIntegrationBase.sol";

contract EnhancedOptionsPutSettlementTest is EnhancedVaultIntegrationBase {
    uint256 internal constant PUT_STRIKE_PRICE = 4_000e8;
    uint256 internal constant PUT_QUANTITY = 10e18;
    uint256 internal constant PUT_OTOKEN_AMOUNT = 10e8;
    uint256 internal constant PUT_PREMIUM_PRICE = 100e18;
    uint256 internal constant PUT_TOTAL_PREMIUM = 1_000e6;
    uint256 internal constant PUT_COLLATERAL = 40_000e6;

    function _deployTokens() internal override {
        underlying = new EnhancedVaultFixtureERC20("Fixture Underlying", "fUND", 18);
        strike = new EnhancedVaultFixtureERC20("Fixture Strike", "fUSD", 6);

        underlying.mint(user, INITIAL_USER_BALANCE);
        underlying.mint(maker, INITIAL_MAKER_BALANCE);
        strike.mint(maker, INITIAL_MAKER_BALANCE);
        strike.mint(user, PUT_COLLATERAL);
    }

    function test_cashPutRedeemPaysStrikeAssetWhenUnderlyingExpiresBelowStrikeWithSixDecimalStrike() external {
        address otoken = _openCashPut();
        uint256 makerStrikeBefore = strike.balanceOf(maker);

        _finalizeExpiryPrice(3_500e8);
        _redeemMakerOtokens(otoken);

        assertEq(strike.balanceOf(maker) - makerStrikeBefore, 5_000e6, "ITM put should pay strike difference");
        assertEq(mmarket.userBalances(maker, otoken), 0, "redeemed otokens should leave maker balance");
    }

    function test_cashPutRedeemPaysNothingWhenUnderlyingExpiresAboveStrike() external {
        address otoken = _openCashPut();
        uint256 makerStrikeBefore = strike.balanceOf(maker);

        _finalizeExpiryPrice(4_386_875e5);
        _redeemMakerOtokens(otoken);

        assertEq(strike.balanceOf(maker), makerStrikeBefore, "OTM put should not pay strike asset");
        assertEq(mmarket.userBalances(maker, otoken), 0, "redeemed OTM otokens should still burn");
    }

    function _openCashPut() internal returns (address otoken) {
        vm.startPrank(owner);
        whitelist.whitelistCollateral(address(strike));
        whitelist.whitelistCoveredCollateral(address(strike), address(underlying), true);
        whitelist.whitelistProduct(address(underlying), address(strike), address(strike), true);
        enhancedOptions.setTrustedTaker(user, true);
        vm.stopPrank();

        vm.prank(user);
        strike.approve(address(marginPool), type(uint256).max);
        _makerDepositStrikeToMMarket(PUT_TOTAL_PREMIUM);

        OrderOverrides memory overrides = _defaultOrderOverrides();
        overrides.strikePrice = PUT_STRIKE_PRICE;
        overrides.premiumPrice = PUT_PREMIUM_PRICE;
        overrides.quoteQuantity = PUT_QUANTITY;
        overrides.quantity = PUT_QUANTITY;
        overrides.collateralAmount = PUT_COLLATERAL;
        overrides.quoteNonce = 501;
        overrides.confirmationNonce = 501;
        overrides.validUntil = uint64(block.timestamp + 1 days);
        overrides.taker = user;
        overrides.collateralAsset = address(strike);
        overrides.hasIsPut = true;
        overrides.isPut = true;

        OrderConfig memory cfg = _createDefaultOrder(overrides);
        bytes memory payload = _buildSignedOrderPayload(cfg);

        vm.prank(user);
        enhancedOptions.ingressoNewTrustedTakerAndMakerPosition(payload);

        otoken = factory.getOtoken(
            address(underlying), address(strike), address(strike), PUT_STRIKE_PRICE, cfg.expiry, true, false, user
        );
        assertEq(mmarket.userBalances(maker, otoken), PUT_OTOKEN_AMOUNT, "maker should hold put otokens in MMarket");
    }

    function _finalizeExpiryPrice(uint256 underlyingExpiryPrice) internal {
        uint256 expiry = _currentCycleExpiry();
        vm.warp(expiry + 1);
        vm.prank(bot);
        manualPricer.setExpiryPriceInOracle(expiry, underlyingExpiryPrice);
        vm.warp(expiry + 2);
    }

    function _redeemMakerOtokens(address otoken) internal {
        MMarketOperations.Operation[] memory operations = new MMarketOperations.Operation[](1);
        operations[0] = MMarketOperations.Operation({
            operationType: MMarketOperations.OperationType.Withdraw,
            user1: maker,
            user2: address(enhancedOptions),
            asset1: otoken,
            asset2: address(0),
            amount1: PUT_OTOKEN_AMOUNT,
            amount2: 0,
            data: bytes("")
        });

        Actions.ActionArgs[] memory actions = new Actions.ActionArgs[](1);
        actions[0] = Actions.ActionArgs({
            actionType: Actions.ActionType.Redeem,
            owner: address(0),
            secondAddress: maker,
            asset: otoken,
            vaultId: 0,
            amount: PUT_OTOKEN_AMOUNT,
            index: 0,
            data: bytes("")
        });

        vm.prank(operator);
        enhancedOptions.ingressoRedeem(operations, actions);
    }
}

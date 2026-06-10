// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Actions} from "src/core/libs/Actions.sol";
import {MarginVault} from "src/core/libs/MarginVault.sol";
import {EnhancedVaultFixtureERC20, EnhancedVaultIntegrationBase} from "./helpers/EnhancedVaultIntegrationBase.sol";

contract ControllerPhysicalSettlementTest is EnhancedVaultIntegrationBase {
    uint256 internal constant STRIKE_PRICE = 1_000e8;
    uint256 internal constant EXPIRY_PRICE = 2_000e8;
    uint256 internal constant WRITER_AMOUNT = 5e8;
    uint256 internal constant REDEEM_AMOUNT = 4e8;
    uint256 internal constant WRITER_COLLATERAL = 5e18;
    address internal constant LINKED_MARGIN_VAULT_LIBRARY = 0x48CCcDd73BD72b87eB0FEf42141f329E9512feeB;

    address internal writerA;
    address internal writerB;
    address internal exerciser;
    EnhancedVaultFixtureERC20 internal physicalUnderlying;

    function setUp() public override {
        super.setUp();
        vm.etch(LINKED_MARGIN_VAULT_LIBRARY, type(MarginVault).runtimeCode);

        writerA = user;
        writerB = maker;
        exerciser = bot;

        physicalUnderlying = new EnhancedVaultFixtureERC20("Physical Underlying", "pUND", 18);
        physicalUnderlying.mint(writerA, INITIAL_USER_BALANCE);
        physicalUnderlying.mint(writerB, INITIAL_MAKER_BALANCE);
        strike.mint(exerciser, 10_000e18);

        vm.startPrank(owner);
        whitelist.whitelistCollateral(address(physicalUnderlying));
        whitelist.whitelistCoveredCollateral(address(physicalUnderlying), address(physicalUnderlying), false);
        whitelist.whitelistProduct(address(physicalUnderlying), address(strike), address(physicalUnderlying), false);
        oracle.setStablePrice(address(physicalUnderlying), EXPIRY_PRICE);
        vm.stopPrank();

        vm.prank(writerA);
        physicalUnderlying.approve(address(marginPool), type(uint256).max);
        vm.prank(writerB);
        physicalUnderlying.approve(address(marginPool), type(uint256).max);
        vm.prank(exerciser);
        strike.approve(address(marginPool), type(uint256).max);
    }

    function testPhysicalSettlementDistributesRemainingBalancesProRata() external {
        uint256 expiry = block.timestamp + 7 days;
        address otoken = factory.createOtoken(
            address(physicalUnderlying), address(strike), address(physicalUnderlying), STRIKE_PRICE, expiry, false, true
        );

        uint256 vaultA = _openPhysicalCallVault(writerA, otoken);
        uint256 vaultB = _openPhysicalCallVault(writerB, otoken);

        _settleExpiryAndRedeemPartial(otoken, expiry);

        uint256 writerAUnderlyingBefore = physicalUnderlying.balanceOf(writerA);
        uint256 writerAStrikeBefore = strike.balanceOf(writerA);

        _settleVault(writerA, vaultA);

        assertEq(physicalUnderlying.balanceOf(writerA) - writerAUnderlyingBefore, 3e18, "writer A collateral share");
        assertEq(strike.balanceOf(writerA) - writerAStrikeBefore, 2_000e18, "writer A receiving share");

        uint256 writerBUnderlyingBefore = physicalUnderlying.balanceOf(writerB);
        uint256 writerBStrikeBefore = strike.balanceOf(writerB);

        _settleVault(writerB, vaultB);

        assertEq(physicalUnderlying.balanceOf(writerB) - writerBUnderlyingBefore, 3e18, "writer B collateral share");
        assertEq(strike.balanceOf(writerB) - writerBStrikeBefore, 2_000e18, "writer B receiving share");
    }

    function _openPhysicalCallVault(address writer, address otoken) internal returns (uint256 vaultId) {
        vaultId = controller.getAccountVaultCounter(writer) + 1;

        Actions.ActionArgs[] memory actions = new Actions.ActionArgs[](3);
        actions[0] = Actions.ActionArgs({
            actionType: Actions.ActionType.OpenVault,
            owner: writer,
            secondAddress: address(0),
            asset: address(0),
            vaultId: vaultId,
            amount: 0,
            index: 0,
            data: abi.encode(uint256(2))
        });
        actions[1] = Actions.ActionArgs({
            actionType: Actions.ActionType.DepositCollateral,
            owner: writer,
            secondAddress: writer,
            asset: address(physicalUnderlying),
            vaultId: vaultId,
            amount: WRITER_COLLATERAL,
            index: 0,
            data: bytes("")
        });
        actions[2] = Actions.ActionArgs({
            actionType: Actions.ActionType.MintShortOption,
            owner: writer,
            secondAddress: address(enhancedOptions),
            asset: otoken,
            vaultId: vaultId,
            amount: WRITER_AMOUNT,
            index: 0,
            data: bytes("")
        });

        vm.prank(address(enhancedOptions));
        controller.operate(actions);
    }

    function _settleExpiryAndRedeemPartial(address otoken, uint256 expiry) internal {
        vm.warp(expiry + 1);

        Actions.ActionArgs[] memory actions = new Actions.ActionArgs[](1);
        actions[0] = Actions.ActionArgs({
            actionType: Actions.ActionType.Redeem,
            owner: address(0),
            secondAddress: exerciser,
            asset: otoken,
            vaultId: 0,
            amount: REDEEM_AMOUNT,
            index: 0,
            data: bytes("")
        });

        vm.prank(address(enhancedOptions));
        controller.operate(actions);

        vm.warp(expiry + controllerLogic.redeemTimePeriod());
    }

    function _settleVault(address writer, uint256 vaultId) internal {
        Actions.ActionArgs[] memory actions = new Actions.ActionArgs[](1);
        actions[0] = Actions.ActionArgs({
            actionType: Actions.ActionType.SettleVault,
            owner: writer,
            secondAddress: writer,
            asset: address(0),
            vaultId: vaultId,
            amount: 0,
            index: 0,
            data: bytes("")
        });

        vm.prank(address(enhancedOptions));
        controller.operate(actions);
    }
}

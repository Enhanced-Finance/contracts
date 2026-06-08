// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {EnhancedVaultIntegrationBase} from "./helpers/EnhancedVaultIntegrationBase.sol";
import {Actions} from "src/core/libs/Actions.sol";
import {stdStorage, StdStorage} from "forge-std/StdStorage.sol";

contract ControllerSecurityTest is EnhancedVaultIntegrationBase {
    using stdStorage for StdStorage;

    function testOwnerCannotEnableOperators() public {
        vm.prank(owner);
        vm.expectRevert("operators cannot be enabled");
        controller.setOperatorsEnabled(true);
    }

    function testVaultOwnerCannotOperateWhenDeprecatedOperatorsFlagIsForcedOn() public {
        stdstore.target(address(controller)).sig(controller.operatorsEnabled.selector).enable_packed_slots()
            .checked_write(true);

        Actions.ActionArgs[] memory actions = new Actions.ActionArgs[](1);
        actions[0] = Actions.ActionArgs({
            actionType: Actions.ActionType.OpenVault,
            owner: user,
            secondAddress: address(0),
            asset: address(0),
            vaultId: controller.getAccountVaultCounter(user) + 1,
            amount: 0,
            index: 0,
            data: abi.encode(uint256(0))
        });

        vm.prank(user);
        vm.expectRevert(bytes("C6"));
        controller.operate(actions);
    }

    function testCustodyVaultCollateralRevertsWhenFullyPaused() public {
        vm.prank(owner);
        controller.setFullPauser(owner);
        vm.prank(owner);
        controller.setSystemFullyPaused(true);

        vm.prank(address(enhancedOptions));
        vm.expectRevert(bytes("C5"));
        controller.releaseVaultCollateralToCustody(address(underlying), user, 1);
    }
}

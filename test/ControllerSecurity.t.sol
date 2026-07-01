// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {EnhancedVaultIntegrationBase} from "./helpers/EnhancedVaultIntegrationBase.sol";

contract ControllerSecurityTest is EnhancedVaultIntegrationBase {
    function testOwnerCannotEnableOperators() public {
        vm.prank(owner);
        vm.expectRevert("operators cannot be enabled");
        controller.setOperatorsEnabled(true);
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

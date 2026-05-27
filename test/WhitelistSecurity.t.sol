// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {EnhancedVaultIntegrationBase} from "./helpers/EnhancedVaultIntegrationBase.sol";
import {MockERC20} from "src/core/mocks/MockERC20.sol";

contract WhitelistSecurityTest is EnhancedVaultIntegrationBase {
    function testCoveredCallCollateralMustBeUnderlying() public {
        MockERC20 otherCollateral = new MockERC20("Other Collateral", "OC", 18);

        vm.prank(owner);
        vm.expectRevert("Whitelist: covered call collateral must be underlying");
        whitelist.whitelistCoveredCollateral(address(otherCollateral), address(underlying), false);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {EnhancedVaultIntegrationBase} from "./helpers/EnhancedVaultIntegrationBase.sol";

contract OtokenFactorySecurityTest is EnhancedVaultIntegrationBase {
    function testCannotCreateZeroStrikePhysicalCall() public {
        vm.expectRevert("OtokenFactory: Can't create a $0 strike physical call option");
        factory.createOtoken(
            address(underlying),
            address(strike),
            address(underlying),
            0,
            block.timestamp + 7 days,
            false,
            true
        );
    }
}

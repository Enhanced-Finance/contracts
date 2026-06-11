// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {OtokenInterface} from "src/core/interfaces/OtokenInterface.sol";
import {EnhancedVaultIntegrationBase} from "./helpers/EnhancedVaultIntegrationBase.sol";

contract OtokenFactorySecurityTest is EnhancedVaultIntegrationBase {
    function testCannotCreateZeroStrikePhysicalCall() public {
        vm.expectRevert("OtokenFactory: Can't create a $0 strike physical call option");
        factory.createOtoken(
            address(underlying), address(strike), address(underlying), 0, block.timestamp + 7 days, false, true, user
        );
    }

    function testCannotCreateOtokenForZeroVaultOwner() public {
        vm.expectRevert("OtokenFactory: Vault owner is zero");
        factory.createOtoken(
            address(underlying),
            address(strike),
            address(underlying),
            1_000e8,
            block.timestamp + 7 days,
            false,
            true,
            address(0)
        );
    }

    function testCreatesDistinctOtokensForDifferentVaultOwners() public {
        uint256 expiry = block.timestamp + 7 days;

        address firstOtoken = factory.createOtoken(
            address(underlying), address(strike), address(underlying), 1_000e8, expiry, false, true, user
        );
        address secondOtoken = factory.createOtoken(
            address(underlying), address(strike), address(underlying), 1_000e8, expiry, false, true, maker
        );

        assertTrue(firstOtoken != secondOtoken, "distinct vault owners should not share otoken");
        assertEq(OtokenInterface(firstOtoken).vaultOwner(), user, "first vault owner");
        assertEq(OtokenInterface(secondOtoken).vaultOwner(), maker, "second vault owner");
        assertEq(
            factory.getOtoken(
                address(underlying), address(strike), address(underlying), 1_000e8, expiry, false, true, user
            ),
            firstOtoken,
            "first vault owner lookup"
        );
        assertEq(
            factory.getOtoken(
                address(underlying), address(strike), address(underlying), 1_000e8, expiry, false, true, maker
            ),
            secondOtoken,
            "second vault owner lookup"
        );
    }
}

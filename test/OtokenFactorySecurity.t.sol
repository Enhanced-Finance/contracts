// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {OtokenInterface} from "src/core/interfaces/OtokenInterface.sol";
import {EnhancedVaultIntegrationBase} from "./helpers/EnhancedVaultIntegrationBase.sol";

contract OtokenFactorySecurityTest is EnhancedVaultIntegrationBase {
    function testCannotCreateZeroStrikePhysicalCall() public {
        vm.expectRevert("OtokenFactory: Can't create a $0 strike physical call option");
        factory.createOtoken(
            address(underlying), address(strike), address(underlying), 0, block.timestamp + 7 days, false, true, user, 1
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
            address(0),
            1
        );
    }

    function testCannotCreateOtokenForZeroVaultId() public {
        vm.expectRevert("OtokenFactory: Vault id is zero");
        factory.createOtoken(
            address(underlying),
            address(strike),
            address(underlying),
            1_000e8,
            block.timestamp + 7 days,
            false,
            true,
            user,
            0
        );
    }

    function testCreatesDistinctPhysicalOtokensForDifferentVaults() public {
        uint256 expiry = block.timestamp + 7 days;

        address firstOtoken = factory.createOtoken(
            address(underlying), address(strike), address(underlying), 1_000e8, expiry, false, true, user, uint256(1)
        );
        address secondOtoken = factory.createOtoken(
            address(underlying), address(strike), address(underlying), 1_000e8, expiry, false, true, maker, uint256(1)
        );

        assertTrue(firstOtoken != secondOtoken, "distinct vaults should not share otoken");
        assertEq(OtokenInterface(firstOtoken).vaultOwner(), user, "first vault owner");
        assertEq(OtokenInterface(firstOtoken).vaultId(), 1, "first vault id");
        assertEq(OtokenInterface(secondOtoken).vaultOwner(), maker, "second vault owner");
        assertEq(OtokenInterface(secondOtoken).vaultId(), 1, "second vault id");
        assertEq(
            factory.getOtoken(
                address(underlying), address(strike), address(underlying), 1_000e8, expiry, false, true, user, 1
            ),
            firstOtoken,
            "first vault lookup"
        );
        assertEq(
            factory.getOtoken(
                address(underlying), address(strike), address(underlying), 1_000e8, expiry, false, true, maker, 1
            ),
            secondOtoken,
            "second vault lookup"
        );
    }

    function testCreatesDistinctPhysicalOtokensForSameOwnerDifferentVaultIds() public {
        uint256 expiry = block.timestamp + 7 days;

        address firstOtoken = factory.createOtoken(
            address(underlying), address(strike), address(underlying), 1_000e8, expiry, false, true, user, uint256(1)
        );
        address secondOtoken = factory.createOtoken(
            address(underlying), address(strike), address(underlying), 1_000e8, expiry, false, true, user, uint256(2)
        );

        assertTrue(firstOtoken != secondOtoken, "distinct vault ids should not share otoken");
        assertEq(OtokenInterface(secondOtoken).vaultOwner(), user, "second vault owner");
        assertEq(OtokenInterface(secondOtoken).vaultId(), 2, "second vault id");
    }
}

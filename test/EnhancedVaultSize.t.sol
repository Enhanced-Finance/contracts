// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {EnhancedVault} from "../src/periphery/vault/EnhancedVault.sol";

contract EnhancedVaultSizeTest is Test {
    uint256 internal constant EIP_170_LIMIT = 24_576;
    uint256 internal constant REQUIRED_RUNTIME_HEADROOM = 128;

    function testRuntimeCodeSize_ShouldStayWithinEip170Limit() external {
        EnhancedVault vault = new EnhancedVault();
        assertLe(address(vault).code.length, EIP_170_LIMIT, "EnhancedVault runtime size exceeds EIP-170");
    }

    function testRuntimeCodeSize_ShouldKeepSafetyHeadroom() external {
        EnhancedVault vault = new EnhancedVault();
        assertLe(
            address(vault).code.length,
            EIP_170_LIMIT - REQUIRED_RUNTIME_HEADROOM,
            "EnhancedVault runtime size has less than the configured headroom"
        );
    }
}

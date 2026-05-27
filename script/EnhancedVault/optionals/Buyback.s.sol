// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console} from "forge-std/Script.sol";
import {EnhancedVault} from "src/periphery/vault/EnhancedVault.sol";
import {BaseEnhancedVaultScript} from "./BaseEnhancedVaultScript.s.sol";

contract Buyback is BaseEnhancedVaultScript {
    // --- Vault/user configuration (hard-coded) ---
    bytes32 constant VAULT_HASH = 0x9832d172f61a4ac7cca7bad266a425d65bcb8fb83a3d195c378972572c5f2c3b;
    address constant USER_1 = 0x56E49A068e368F2D40FFE9314033671CF3402eC1;
    bool constant INCLUDE_SECOND_USER = false;
    address constant USER_2 = 0x0000000000000000000000000000000000000002;

    // --- Swap parameters ---
    uint256 constant AMOUNT_IN = 216313819891201749540;
    uint256 constant AMOUNT_OUT_MINIMUM = 4654377225398997506033;
    // uint256 constant DEADLINE = 1774317981;
    uint256 constant DEADLINE = 1800000000;
    uint24 constant FEE = 3000;
    // -----------------------------------------------

    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        (EnhancedVault vault, address vaultAddr) = _loadVault();
        (,, uint256 currentCycleId,,,,) = vault.vaults(VAULT_HASH);

        address[] memory users = _buildUsers();
        EnhancedVault.SwapParams memory swapParams = _buildSwapParams();

        console.log("EnhancedVault:", vaultAddr);
        console.log("currentCycleId:", currentCycleId);
        console.log("vaultHash:", vm.toString(VAULT_HASH));
        console.log("users.length:", users.length);
        for (uint256 i = 0; i < users.length; i++) {
            console.log("user:", users[i]);
        }
        console.log("swap.amountIn:", swapParams.amountIn);
        console.log("swap.amountOutMinimum:", swapParams.amountOutMinimum);
        console.log("swap.deadline:", swapParams.deadline);
        console.log("swap.fee:", swapParams.fee);

        vm.startBroadcast(privateKey);
        vault.buyback(VAULT_HASH, users, swapParams);
        vm.stopBroadcast();
    }

    function _buildUsers() internal pure returns (address[] memory users) {
        if (INCLUDE_SECOND_USER) {
            users = new address[](2);
            users[0] = USER_1;
            users[1] = USER_2;
            return users;
        }

        users = new address[](1);
        users[0] = USER_1;
    }

    function _buildSwapParams() internal pure returns (EnhancedVault.SwapParams memory swapParams) {
        swapParams = EnhancedVault.SwapParams({
            amountIn: AMOUNT_IN, amountOutMinimum: AMOUNT_OUT_MINIMUM, deadline: DEADLINE, fee: FEE
        });
    }
}

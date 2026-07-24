// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console} from "forge-std/Script.sol";
import {EnhancedVault} from "src/periphery/vault/EnhancedVault.sol";
import {BaseEnhancedVaultScript} from "./BaseEnhancedVaultScript.s.sol";

contract Buyback is BaseEnhancedVaultScript {
    // --- Swap parameters ---
    uint256 constant AMOUNT_IN = 216313819891201749540;
    uint256 constant AMOUNT_OUT_MINIMUM = 4654377225398997506033;
    // uint256 constant DEADLINE = 1774317981;
    uint256 constant DEADLINE = 1800000000;
    uint24 constant FEE = 3000;
    // -----------------------------------------------

    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        bytes32 vaultHash = vm.envBytes32("VAULT_HASH");
        (EnhancedVault vault, address vaultAddr) = _loadVault();
        (,, uint256 currentCycleId,,,,,) = vault.vaults(vaultHash);

        address[] memory users = vm.envAddress("USERS", ",");
        EnhancedVault.SwapParams memory swapParams = _buildSwapParams();

        console.log("EnhancedVault:", vaultAddr);
        console.log("currentCycleId:", currentCycleId);
        console.log("vaultHash:", vm.toString(vaultHash));
        console.log("users.length:", users.length);
        for (uint256 i = 0; i < users.length; i++) {
            console.log("user:", users[i]);
        }
        console.log("swap.amountIn:", swapParams.amountIn);
        console.log("swap.amountOutMinimum:", swapParams.amountOutMinimum);
        console.log("swap.deadline:", swapParams.deadline);
        console.log("swap.fee:", swapParams.fee);

        vm.startBroadcast(privateKey);
        vault.buyback(vaultHash, users, swapParams);
        vm.stopBroadcast();
    }

    function _buildSwapParams() internal pure returns (EnhancedVault.SwapParams memory swapParams) {
        swapParams = EnhancedVault.SwapParams({
            amountIn: AMOUNT_IN, amountOutMinimum: AMOUNT_OUT_MINIMUM, deadline: DEADLINE, fee: FEE
        });
    }
}

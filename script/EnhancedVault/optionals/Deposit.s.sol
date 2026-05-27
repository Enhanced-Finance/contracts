// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console} from "forge-std/Script.sol";
import {EnhancedVault} from "src/periphery/vault/EnhancedVault.sol";
import {BaseEnhancedVaultScript} from "./BaseEnhancedVaultScript.s.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract Deposit is BaseEnhancedVaultScript {
    bytes32 constant VAULT_HASH = 0x9832d172f61a4ac7cca7bad266a425d65bcb8fb83a3d195c378972572c5f2c3b;
    uint256 constant AMOUNT = 10_000e18;

    function run() public {
        uint256 takerPrivateKey = vm.envUint("TAKER_PRIVATE_KEY");
        address user = vm.addr(takerPrivateKey);
        (EnhancedVault vault, address vaultAddr) = _loadVault();
        (EnhancedVault.VaultParams memory params, , , , , ,) = vault.vaults(VAULT_HASH);
        IERC20 collateral = IERC20(params.collateralAsset);

        console.log("EnhancedVault:", vaultAddr);
        console.log("vaultHash:", vm.toString(VAULT_HASH));
        console.log("user:", user);

        uint256 allowance = collateral.allowance(user, vaultAddr);
        if (allowance < AMOUNT) {
            console.log("Approving collateral to vault...");
            vm.startBroadcast(takerPrivateKey);
            collateral.approve(vaultAddr, type(uint256).max);
            vm.stopBroadcast();
        }

        vm.startBroadcast(takerPrivateKey);
        vault.deposit(VAULT_HASH, AMOUNT);
        vm.stopBroadcast();
    }
}

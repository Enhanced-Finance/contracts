// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console} from "forge-std/Script.sol";
import {EnhancedVault} from "src/periphery/vault/EnhancedVault.sol";
import {BaseEnhancedVaultScript} from "./BaseEnhancedVaultScript.s.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract Deposit is BaseEnhancedVaultScript {
    uint256 constant AMOUNT = 10_000e18;

    function run() public {
        uint256 takerPrivateKey = vm.envUint("TAKER_PRIVATE_KEY");
        bytes32 vaultHash = vm.envBytes32("VAULT_HASH");
        address user = vm.addr(takerPrivateKey);
        (EnhancedVault vault, address vaultAddr) = _loadVault();
        (EnhancedVault.VaultParams memory params,,,,,,,) = vault.vaults(vaultHash);
        IERC20 collateral = IERC20(params.collateralAsset);

        console.log("EnhancedVault:", vaultAddr);
        console.log("vaultHash:", vm.toString(vaultHash));
        console.log("user:", user);

        uint256 allowance = collateral.allowance(user, vaultAddr);
        if (allowance < AMOUNT) {
            console.log("Approving collateral to vault...");
            vm.startBroadcast(takerPrivateKey);
            collateral.approve(vaultAddr, type(uint256).max);
            vm.stopBroadcast();
        }

        vm.startBroadcast(takerPrivateKey);
        vault.deposit(vaultHash, AMOUNT);
        vm.stopBroadcast();
    }
}

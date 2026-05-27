// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {EnhancedOptions} from "src/core/EnhancedOptions.sol";
import {Actions} from "src/core/libs/Actions.sol";
import {stdJson} from "lib/forge-std/src/StdJson.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract IngressoSettle is Script {
    using stdJson for string;

    // --- Configuration: Set these values before running ---
    uint256 constant VAULT_ID = 6; // Vault ID to settle
    // ----------------------------------------------------

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // Vault Owner
        uint256 ownerPrivateKey = vm.envUint("TAKER_PRIVATE_KEY"); // Using Taker as Vault Owner usually
        address owner = vm.addr(ownerPrivateKey);

        uint256 chainId = block.chainid;
        string memory chainIdStr = vm.toString(chainId);
        string memory deployPath = string.concat(vm.projectRoot(), "/.deploy/", chainIdStr, ".json");

        require(vm.isFile(deployPath), "Deploy file not found");
        string memory deployJson = vm.readFile(deployPath);
        address enhancedOptionsAddr = deployJson.readAddress(".EnhancedOptions.proxyAddress");
        require(enhancedOptionsAddr != address(0), "EnhancedOptions proxy not found");

        console.log("Executing IngressoSettle on:", enhancedOptionsAddr);
        console.log("Caller (Operator):", deployer);
        console.log("Vault Owner:", owner);
        console.log("Vault ID:", VAULT_ID);

        // 1. Prepare Actions (Settle Vault in Controller)
        Actions.ActionArgs[] memory actions = new Actions.ActionArgs[](1);
        actions[0] = Actions.ActionArgs({
            actionType: Actions.ActionType.SettleVault,
            owner: owner, // vault owner
            secondAddress: owner, // collateral receiver (must be owner)
            asset: address(0), // not used
            vaultId: VAULT_ID, // vault ID
            amount: 0, // not used
            index: 0, // not used
            data: bytes("")
        });

        // 2. Execute Transaction
        // ingressoSettle checks _checkOperator(), so Deployer must call it.
        vm.startBroadcast(deployerPrivateKey);
        EnhancedOptions(enhancedOptionsAddr).ingressoSettle(actions);
        vm.stopBroadcast();

        console.log("IngressoSettle executed successfully");
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {EnhancedOptions} from "src/core/EnhancedOptions.sol";
import {Actions} from "src/core/libs/Actions.sol";
import {MMarketOperations} from "src/core/libs/MMarketOperations.sol";
import {stdJson} from "lib/forge-std/src/StdJson.sol";

contract IngressoRedeem is Script {
    using stdJson for string;

    uint256 constant AMOUNT = 6000000000; // Amount to redeem

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // Maker holds Otokens in MMarket and pays any physical settlement exercise assets.
        address user = vm.envAddress("MAKER");
        address receiver = vm.envAddress("RECEIVER");
        address otoken = vm.envAddress("OTOKEN");

        uint256 chainId = block.chainid;
        string memory chainIdStr = vm.toString(chainId);
        string memory deployPath = string.concat(vm.projectRoot(), "/.deploy/", chainIdStr, ".json");

        require(vm.isFile(deployPath), "Deploy file not found");
        string memory deployJson = vm.readFile(deployPath);
        address enhancedOptionsAddr = deployJson.readAddress(".EnhancedOptions.proxyAddress");
        require(enhancedOptionsAddr != address(0), "EnhancedOptions proxy not found");

        console.log("Executing IngressoRedeem on:", enhancedOptionsAddr);
        console.log("Caller (Operator):", deployer);
        console.log("Maker / Payer:", user);
        console.log("Receiver:", receiver);
        console.log("Otoken:", otoken);

        // 1. Prepare Operations (Withdraw from MMarket)
        MMarketOperations.Operation[] memory operations = new MMarketOperations.Operation[](1);
        operations[0] = MMarketOperations.Operation({
            operationType: MMarketOperations.OperationType.Withdraw,
            user1: user, // maker to withdraw otokens from
            user2: enhancedOptionsAddr, // This field is checked in EnhancedOptions to be address(this) inside the contract logic?
            // Wait, let's check EnhancedOptions.sol:168:
            // require(operations[0].user2 == address(this), "invalid withdraw recipient");
            // So we must pass address(EnhancedOptions) here?
            // Actually, in the solidity script we are constructing the calldata.
            // EnhancedOptions checks `operations[0].user2`.
            // So we should set it to enhancedOptionsAddr.
            asset1: otoken, // asset to withdraw
            asset2: address(0), // not used
            amount1: AMOUNT, // amount
            amount2: 0, // not used
            data: bytes("")
        });
        // Fix user2 to be enhancedOptionsAddr based on check in contract
        operations[0].user2 = enhancedOptionsAddr;

        // 2. Prepare Actions (Redeem in Controller)
        Actions.ActionArgs[] memory actions = new Actions.ActionArgs[](1);
        actions[0] = Actions.ActionArgs({
            actionType: Actions.ActionType.Redeem,
            owner: user, // payer/maker; must match operations[0].user1
            secondAddress: receiver, // redeem receiver; must match makerWhitelist[user]
            asset: otoken, // otoken
            vaultId: 0, // not used
            amount: AMOUNT, // amount
            index: 0, // not used
            data: bytes("")
        });

        // 3. Execute Transaction
        // ingressRedeem is nonReentrant and checks _checkOperator().
        // So it must be called by the Operator (Deployer).
        // But it operates on User's MMarket balance.
        // Does it require User signature?
        // EnhancedOptions.sol:155 `ingressoRedeem` takes structs directly, NO signature verification inside.
        // It just calls `mmarket.operate(operations)`.
        // MMarket.operate likely checks msg.sender is a valid operator (EnhancedOptions).
        // But does MMarket check if `user1` authorized this withdrawal?
        // If EnhancedOptions is the operator of MMarket, it can move funds.
        // But `ingressoRedeem` has `_checkOperator()`, so only `EnhancedOptions.operator` can call it.
        // So the `Deployer` (Operator) must call this.
        // This implies the User must have requested this off-chain or via another mechanism?
        // Or this is an admin function?
        // The function name `ingresso...` usually implies entry point.
        // Since there is no signature check in `ingressoRedeem`, the Operator holds full custody/power here.

        vm.startBroadcast(deployerPrivateKey);
        EnhancedOptions(enhancedOptionsAddr).ingressoRedeem(operations, actions);
        vm.stopBroadcast();

        console.log("IngressoRedeem executed successfully");
    }
}

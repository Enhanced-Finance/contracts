// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {EnhancedOptions} from "src/core/EnhancedOptions.sol";
import {Actions} from "src/core/libs/Actions.sol";
import {MMarketOperations} from "src/core/libs/MMarketOperations.sol";
import {stdJson} from "lib/forge-std/src/StdJson.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Otoken} from "src/core/Otoken.sol";

contract IngressoRedeem is Script {
    using stdJson for string;

    // --- Configuration: Set these values before running ---
    // Otoken to redeem
    address constant OTOKEN_ADDRESS = 0x31b6A5Ec6D21697934f3Dd2B81a897DA8d17896c; // Replace with actual Otoken address
    address constant USER_ADDRESS = 0x56E49A068e368F2D40FFE9314033671CF3402eC1; // Replace with actual Otoken address
    uint256 constant AMOUNT = 1 * 1e8; // Amount to redeem
    // ----------------------------------------------------

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // User who holds Otokens in MMarket and wants to redeem
        address user = USER_ADDRESS;

        uint256 chainId = block.chainid;
        string memory chainIdStr = vm.toString(chainId);
        string memory deployPath = string.concat(vm.projectRoot(), "/.deploy/", chainIdStr, ".json");

        require(vm.isFile(deployPath), "Deploy file not found");
        string memory deployJson = vm.readFile(deployPath);
        address enhancedOptionsAddr = deployJson.readAddress(".EnhancedOptions.proxyAddress");
        require(enhancedOptionsAddr != address(0), "EnhancedOptions proxy not found");

        console.log("Executing IngressoRedeem on:", enhancedOptionsAddr);
        console.log("Caller (Operator):", deployer);
        console.log("User (Redeemer):", user);
        console.log("Otoken:", OTOKEN_ADDRESS);
        // Otoken otoken = Otoken(OTOKEN_ADDRESS);
        // if (AMOUNT > 0) {
        //     address marginPoolAddr = deployJson.readAddress(".MarginPool.proxyAddress");
        //     require(marginPoolAddr != address(0), "MarginPool proxy not found");

        //     console.log("Checking allowance for User -> MarginPool...");
        //     vm.startBroadcast(userPrivateKey);
        //     IERC20 asset = IERC20(otoken.strikeAsset());
        //     uint256 allowance = asset.allowance(user, marginPoolAddr);
        //     if (allowance < AMOUNT) {
        //         console.log("Approving token...");
        //         asset.approve(marginPoolAddr, type(uint256).max);
        //     }
        //     vm.stopBroadcast();
        // }
        // 1. Prepare Operations (Withdraw from MMarket)
        MMarketOperations.Operation[] memory operations = new MMarketOperations.Operation[](1);
        operations[0] = MMarketOperations.Operation({
            operationType: MMarketOperations.OperationType.Withdraw,
            user1: user, // user to withdraw from
            user2: enhancedOptionsAddr, // This field is checked in EnhancedOptions to be address(this) inside the contract logic?
            // Wait, let's check EnhancedOptions.sol:168:
            // require(operations[0].user2 == address(this), "invalid withdraw recipient");
            // So we must pass address(EnhancedOptions) here?
            // Actually, in the solidity script we are constructing the calldata.
            // EnhancedOptions checks `operations[0].user2`.
            // So we should set it to enhancedOptionsAddr.
            asset1: OTOKEN_ADDRESS, // asset to withdraw
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
            owner: address(0), // not used for Redeem
            secondAddress: user, // redeem receiver (must be otoken owner/user1 from op)
            asset: OTOKEN_ADDRESS, // otoken
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

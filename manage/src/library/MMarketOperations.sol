/**
 * SPDX-License-Identifier: UNLICENSED
 */
pragma solidity ^0.8.22;

library MMarketOperations {
    // possible actions that can be performed
    enum OperationType {
        Deposit,
        Withdraw,
        ConductTrade
    }

    struct Operation {
        OperationType operationType;
        address user_1;
        address user_2;
        address asset_1;
        address asset_2;
        uint256 amount_1;
        uint256 amount_2;
        bytes data;
    }

    function parseDepositArgs(Operation memory _args) internal pure returns (Operation memory) {
        require((_args.operationType == OperationType.Deposit), "Deposit: bad operation type");
        require(_args.user_1 != address(0), "Deposit: bad user_1");
        require(_args.user_2 != address(0), "Deposit: bad user_2");
        require(_args.asset_1 != address(0), "Deposit: bad asset_1");
        return _args;
    }

    function parseWithdrawArgs(Operation memory _args) internal pure returns (Operation memory) {
        require((_args.operationType == OperationType.Withdraw), "Withdraw: bad operation type");
        require(_args.user_1 != address(0), "Withdraw: bad user_1");
        require(_args.user_2 != address(0), "Withdraw: bad user_2");
        require(_args.asset_1 != address(0), "Withdraw: bad asset_1");
        return _args;
    }

    function parseConductTradeArgs(Operation memory _args) internal pure returns (Operation memory) {
        require((_args.operationType == OperationType.ConductTrade), "ConductTrade: bad operation type");
        require(_args.user_1 != address(0), "ConductTrade: bad user_1");
        require(_args.asset_1 != address(0), "ConductTrade: bad asset_1");
        require(_args.user_2 != address(0), "ConductTrade: bad user_2");
        require(_args.asset_2 != address(0), "ConductTrade: bad asset_2");
        return _args;
    }
}

/**
 * SPDX-License-Identifier: MIT
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
        address user1;
        address user2;
        address asset1;
        address asset2;
        uint256 amount1;
        uint256 amount2;
        bytes data;
    }

    function parseDepositArgs(Operation memory _args) internal pure returns (Operation memory) {
        require((_args.operationType == OperationType.Deposit), "Deposit: bad operation type");
        require(_args.user1 != address(0), "Deposit: bad user1");
        require(_args.user2 != address(0), "Deposit: bad user2");
        require(_args.asset1 != address(0), "Deposit: bad asset1");
        return _args;
    }

    function parseWithdrawArgs(Operation memory _args) internal pure returns (Operation memory) {
        require((_args.operationType == OperationType.Withdraw), "Withdraw: bad operation type");
        require(_args.user1 != address(0), "Withdraw: bad user1");
        require(_args.user2 != address(0), "Withdraw: bad user2");
        require(_args.asset1 != address(0), "Withdraw: bad asset1");
        return _args;
    }

    function parseConductTradeArgs(Operation memory _args) internal pure returns (Operation memory) {
        require((_args.operationType == OperationType.ConductTrade), "ConductTrade: bad operation type");
        require(_args.user1 != address(0), "ConductTrade: bad user1");
        require(_args.asset1 != address(0), "ConductTrade: bad asset1");
        require(_args.user2 != address(0), "ConductTrade: bad user2");
        require(_args.asset2 != address(0), "ConductTrade: bad asset2");
        return _args;
    }
}

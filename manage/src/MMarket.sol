/**
 * SPDX-License-Identifier: UNLICENSED
 */
pragma solidity ^0.8.22;

import "./library/MMarketOperations.sol";

import "lib/solmate/src/tokens/ERC20.sol";
import "lib/solmate/src/utils/SafeTransferLib.sol";

import "lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/utils/cryptography/EIP712Upgradeable.sol";

/**
 * @title MMarket
 */
contract MMarket is EIP712Upgradeable, OwnableUpgradeable, ReentrancyGuard {
    /// @dev operator
    address operator;
    /// @dev mapping between user and an asset and the amount of the asset in the pool
    mapping(address => mapping(address => uint256)) public userBalances;

    /// @notice emits an event when MMarket receive funds from controller
    event TransferToPool(address indexed asset, address indexed account, address indexed source, uint256 amount);
    /// @notice emits an event when MMarket transfer funds to controller
    event TransferToUser(address indexed asset, address indexed account, address indexed recipient, uint256 amount);
    /// @notice emits an event when mmarket transfers funds between accounts
    event InternalTransferIncrease(address indexed asset, address indexed user, uint256 amount);
    /// @notice emits an event when mmarket transfers funds between accounts
    event InternalTransferDecrease(address indexed asset, address indexed user, uint256 amount);
    /// @notice emits an event when there is a change in operator
    event OperatorChanged(address newOperator, address oldOperator);

    function initialize() external initializer {
        __EIP712_init("mmarket", "0.0.0");
        __Ownable_init(msg.sender);
        // __ReentrancyGuard_init();
    }

    function setOperator(address _operator) external {
        _checkOwner();
        emit OperatorChanged(_operator, operator);
        operator = _operator;
    }

    function _checkOperator() internal view {
        if (operator != _msgSender()) revert("bad operator");
    }

    function operate(MMarketOperations.Operation[] memory operations) external nonReentrant {
        _checkOperator();
        for (uint256 i = 0; i < operations.length; i++) {
            MMarketOperations.Operation memory operation = operations[i];
            MMarketOperations.OperationType operationType = operation.operationType;

            if (operationType == MMarketOperations.OperationType.Deposit) {
                deposit(MMarketOperations.parseDepositArgs(operation));
            } else if (operationType == MMarketOperations.OperationType.Withdraw) {
                withdraw(MMarketOperations.parseWithdrawArgs(operation));
            } else if (operationType == MMarketOperations.OperationType.ConductTrade) {
                conductTrade(MMarketOperations.parseConductTradeArgs(operation));
            } else {
                revert("invalid operation");
            }
        }
    }

    function deposit(MMarketOperations.Operation memory _deposit) internal {
        transferToPool(_deposit.asset_1, _deposit.user_1, _deposit.user_2, _deposit.amount_1);
    }

    function withdraw(MMarketOperations.Operation memory _withdraw) internal {
        transferToUser(_withdraw.asset_1, _withdraw.user_1, _withdraw.user_2, _withdraw.amount_1);
    }

    function conductTrade(MMarketOperations.Operation memory _conductTrade) internal {
        transferBetweenUsers(
            _conductTrade.asset_1,
            _conductTrade.asset_2,
            _conductTrade.user_1,
            _conductTrade.user_2,
            _conductTrade.amount_1,
            _conductTrade.amount_2
        );
    }

    /**
     * @notice transfers an asset from a user to the pool
     * @param _asset address of the asset to transfer
     * @param _user_1 address of the user to change internal balances for
     * @param _user_2 address of the user who will have the funds transferred from
     * @param _amount amount of the token to transfer from _user
     */
    function transferToPool(address _asset, address _user_1, address _user_2, uint256 _amount) internal {
        require(_amount > 0, "MMarket: transferToPool amount is equal to 0");
        require(_user_1 != address(0), "MMarket: cannot have zero address as account");
        require(_user_1 != address(this), "MMarket: cannot transfer assets to oneself");
        require(_user_2 != address(this), "MMarket: cannot transfer assets to oneself");
        require(_user_2 != address(0), "MMarket: cannot have zero address as source");
        userBalances[_user_1][_asset] += _amount;
        // transfer _asset _amount from _user to pool
        SafeTransferLib.safeTransferFrom(ERC20(_asset), _user_2, address(this), _amount);
        emit TransferToPool(_asset, _user_1, _user_2, _amount);
    }

    /**
     * @notice transfers an asset from the pool to a user
     * @param _asset address of the asset to transfer
     * @param _user_1 address of the user to change internal balances for
     * @param _user_2 address of the user who will have the funds transferred to
     * @param _amount amount of the token to transfer to _user
     */
    function transferToUser(address _asset, address _user_1, address _user_2, uint256 _amount) internal {
        require(_amount > 0, "MMarket: transferToUser amount is equal to 0");
        require(_user_1 != address(0), "MMarket: cannot have zero address as account");
        require(_user_1 != address(this), "MMarket: cannot transfer assets to oneself");
        require(_user_2 != address(this), "MMarket: cannot transfer assets to oneself");
        require(_user_2 != address(0), "MMarket: cannot have zero address as recipient");
        userBalances[_user_1][_asset] -= _amount;
        // transfer _asset _amount from pool to _user
        SafeTransferLib.safeTransfer(ERC20(_asset), _user_2, _amount);
        emit TransferToUser(_asset, _user_1, _user_2, _amount);
    }

    // we transfer asset 1 and amount 1 to user 2 and asset 2 and amount 2 to user 1
    function transferBetweenUsers(
        address asset_1,
        address asset_2,
        address user_1,
        address user_2,
        uint256 amount_1,
        uint256 amount_2
    ) internal {
        require(user_1 != address(this), "MMarket: user_1 cannot transfer assets to oneself");
        require(user_2 != address(this), "MMarket: user_2 cannot transfer assets to oneself");
        userBalances[user_1][asset_1] -= amount_1;
        userBalances[user_2][asset_1] += amount_1;
        userBalances[user_1][asset_2] += amount_2;
        userBalances[user_2][asset_2] -= amount_2;
        emit InternalTransferIncrease(asset_1, user_2, amount_1);
        emit InternalTransferIncrease(asset_2, user_1, amount_2);
        emit InternalTransferDecrease(asset_1, user_1, amount_1);
        emit InternalTransferDecrease(asset_2, user_2, amount_2);
    }
}

/**
 * SPDX-License-Identifier: MIT
 */
pragma solidity ^0.8.28;

import {MMarketOperations} from "./libs/MMarketOperations.sol";

import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "lib/solmate/src/utils/SafeTransferLib.sol";

import {OwnableUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {ReentrancyGuardTransient} from "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuardTransient.sol";
import {
    EIP712Upgradeable
} from "lib/openzeppelin-contracts-upgradeable/contracts/utils/cryptography/EIP712Upgradeable.sol";
import {UUPSUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title MMarket
 * @dev ReentrancyGuardTransient requires EIP-1153 (Cancun-compatible EVM).
 */
contract MMarket is EIP712Upgradeable, OwnableUpgradeable, ReentrancyGuardTransient, UUPSUpgradeable {
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

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() external initializer {
        __EIP712_init("mmarket", "0.0.0");
        __Ownable_init(msg.sender);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function setOperator(address _operator) external {
        _checkOwner();
        require(_operator != address(0), "zero address");
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

    function deposit(MMarketOperations.Operation memory operation) internal {
        transferToPool(operation.asset1, operation.user1, operation.user2, operation.amount1);
    }

    function withdraw(MMarketOperations.Operation memory operation) internal {
        transferToUser(operation.asset1, operation.user1, operation.user2, operation.amount1);
    }

    function conductTrade(MMarketOperations.Operation memory operation) internal {
        transferBetweenUsers(
            operation.asset1, operation.asset2, operation.user1, operation.user2, operation.amount1, operation.amount2
        );
    }

    /**
     * @notice transfers an asset from a user to the pool
     * @param _asset address of the asset to transfer
     * @param _user1 address of the user to change internal balances for
     * @param _user2 address of the user who will have the funds transferred from
     * @param _amount amount of the token to transfer from _user
     */
    function transferToPool(address _asset, address _user1, address _user2, uint256 _amount) internal {
        require(_amount > 0, "MMarket: transferToPool amount is equal to 0");
        require(_user1 != address(0), "MMarket: cannot have zero address as account");
        require(_user1 != address(this), "MMarket: cannot transfer assets to oneself");
        require(_user2 != address(this), "MMarket: cannot transfer assets to oneself");
        require(_user2 != address(0), "MMarket: cannot have zero address as source");
        userBalances[_user1][_asset] += _amount;
        SafeTransferLib.safeTransferFrom(ERC20(_asset), _user2, address(this), _amount);

        emit TransferToPool(_asset, _user1, _user2, _amount);
    }

    /**
     * @notice transfers an asset from the pool to a user
     * @param _asset address of the asset to transfer
     * @param _user1 address of the user to change internal balances for
     * @param _user2 address of the user who will have the funds transferred to
     * @param _amount amount of the token to transfer to _user
     */
    function transferToUser(address _asset, address _user1, address _user2, uint256 _amount) internal {
        require(_amount > 0, "MMarket: transferToUser amount is equal to 0");
        require(_user1 != address(0), "MMarket: cannot have zero address as account");
        require(_user1 != address(this), "MMarket: cannot transfer assets to oneself");
        require(_user2 != address(this), "MMarket: cannot transfer assets to oneself");
        require(_user2 != address(0), "MMarket: cannot have zero address as destination");
        userBalances[_user1][_asset] -= _amount;
        SafeTransferLib.safeTransfer(ERC20(_asset), _user2, _amount);

        emit TransferToUser(_asset, _user1, _user2, _amount);
    }

    /**
     * @notice transfers an asset between users within the pool
     * @param _asset1 address of the asset to transfer
     * @param _asset2 address of the asset to transfer
     * @param _user1 address of the user to change internal balances for
     * @param _user2 address of the user who will have the funds transferred to
     * @param _amount1 amount of the token to transfer to _user
     * @param _amount2 amount of the token to transfer to _user
     */
    function transferBetweenUsers(
        address _asset1,
        address _asset2,
        address _user1,
        address _user2,
        uint256 _amount1,
        uint256 _amount2
    ) internal {
        require(_user1 != address(this), "MMarket: user1 cannot transfer assets to oneself");
        require(_user2 != address(this), "MMarket: user_2 cannot transfer assets to oneself");
        userBalances[_user1][_asset1] -= _amount1;
        userBalances[_user2][_asset1] += _amount1;
        userBalances[_user1][_asset2] += _amount2;
        userBalances[_user2][_asset2] -= _amount2;
        emit InternalTransferIncrease(_asset1, _user2, _amount1);
        emit InternalTransferIncrease(_asset2, _user1, _amount2);
        emit InternalTransferDecrease(_asset1, _user1, _amount1);
        emit InternalTransferDecrease(_asset2, _user2, _amount2);
    }
}

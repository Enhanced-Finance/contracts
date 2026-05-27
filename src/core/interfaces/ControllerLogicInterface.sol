// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

pragma experimental ABIEncoderV2;

import {Actions} from "../libs/Actions.sol";

interface ControllerLogicInterface {
    function handleDepositLong(Actions.DepositArgs memory _args) external;

    function handleWithdrawLong(Actions.WithdrawArgs memory _args) external;

    function handleDepositCollateral(Actions.DepositArgs memory _args) external;

    function handleWithdrawCollateral(Actions.WithdrawArgs memory _args) external;

    function handleMintOtoken(Actions.MintArgs memory _args, uint256 vaultType) external;

    function handleBurnOtoken(Actions.BurnArgs memory _args, uint256 vaultType) external;

    function handleRedeem(Actions.RedeemArgs memory _args, address) external;

    function handleSettle(Actions.SettleVaultArgs memory _args) external;

    function redeemTimePeriod() external view returns (uint256);
}

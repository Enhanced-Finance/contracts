// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "../library/Actions.sol";

interface IController {
    function operate(Actions.ActionArgs[] memory _actions) external;
    function setManager(address _manager) external;
    function getAccountVaultCounter(address _accountOwner) external view returns (uint256);
}

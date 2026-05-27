// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Actions} from "../libs/Actions.sol";
import {MarginVault} from "../libs/MarginVault.sol";

interface IController {
    function donate(address _asset, uint256 _amount) external;
    function releaseVaultCollateralToCustody(address _asset, address _receiver, uint256 _amount) external;
    function operate(Actions.ActionArgs[] memory _actions) external;
    function setManager(address _manager) external;
    function systemFullyPaused() external view returns (bool);
    function getConfiguration() external view returns (address, address, address, address);
    function getAccountVaultCounter(address _accountOwner) external view returns (uint256);
    function getVaultWithDetails(address _owner, uint256 _vaultId)
        external
        view
        returns (MarginVault.Vault memory, uint256, uint256);
}

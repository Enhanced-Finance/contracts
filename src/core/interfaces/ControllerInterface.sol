// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {MarginVault} from "../libs/MarginVault.sol";

interface ControllerInterface {
    function getNakedCap(address _asset) external view returns (uint256);

    function getNakedPoolBalance(address _asset) external view returns (uint256);

    function getVaultWithDetails(address, uint256) external view returns (MarginVault.Vault memory, uint256, uint256);

    function canSettleAssets(address _underlying, address _strike, address _collateral, uint256 _expiry)
        external
        view
        returns (bool);

    function removeVaultCollateral(address _owner, uint256 _vaultId, address _asset, uint256 _amount) external;

    function updateVault(uint8 _action, address _owner, uint256 _vaultId, address _asset, uint256 _amount) external;

    function increaseNakedPoolBalance(address _asset, uint256 _amount) external;

    function reduceNakedPoolBalance(address _asset, uint256 _amount) external;

    function deleteVault(address, uint256) external;

    function redeemTimePeriod() external view returns (uint256);
}

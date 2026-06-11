// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

interface IOtoken {
    function init(
        address _addressBook,
        address _underlyingAsset,
        address _strikeAsset,
        address _collateralAsset,
        uint256 _strikePrice,
        uint256 _expiry,
        bool _isPut,
        bool _isPhysicallySettled
    ) external;

    function getOtokenDetails() external view returns (address, address, address, uint256, uint256, bool, bool);

    function collateralAsset() external view returns (address);
    function expiryTimestamp() external view returns (uint256);
}

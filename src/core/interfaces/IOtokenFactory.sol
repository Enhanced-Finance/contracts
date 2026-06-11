// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

interface IOtokenFactory {
    function getOtoken(
        address _underlyingAsset,
        address _strikeAsset,
        address _collateralAsset,
        uint256 _strikePrice,
        uint256 _expiry,
        bool _isPut,
        bool _isPhysicallySettled,
        address _vaultOwner
    ) external view returns (address);

    function createOtoken(
        address _underlyingAsset,
        address _strikeAsset,
        address _collateralAsset,
        uint256 _strikePrice,
        uint256 _expiry,
        bool _isPut,
        bool _isPhysicallySettled,
        address _vaultOwner
    ) external returns (address);

    function getTargetOtokenAddress(
        address _underlyingAsset,
        address _strikeAsset,
        address _collateralAsset,
        uint256 _strikePrice,
        uint256 _expiry,
        bool _isPut,
        bool _isPhysicallySettled,
        address _vaultOwner
    ) external view returns (address);

    event OtokenCreated(
        address tokenAddress,
        address creator,
        address vaultOwner,
        address indexed underlying,
        address indexed strike,
        address indexed collateral,
        uint256 strikePrice,
        uint256 expiry,
        bool isPut,
        bool _isPhysicallySettled
    );
}

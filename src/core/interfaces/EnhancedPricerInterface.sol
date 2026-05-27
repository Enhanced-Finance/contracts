// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface EnhancedPricerInterface {
    function getPrice() external view returns (uint256);

    function getHistoricalPrice(uint80 _roundId) external view returns (uint256, uint256);
}

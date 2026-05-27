// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

contract ClearForceExit {
    function run() public pure {
        revert("LEGACY_ONLY: ClearForceExit(investmentId) is deprecated in user-fund flow");
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

contract ForcePauseFunds {
    function run() public pure {
        revert("LEGACY_ONLY: ForcePauseFunds(investmentIds) is deprecated in user-fund flow");
    }
}

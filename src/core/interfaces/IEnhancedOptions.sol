// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Actions} from "../libs/Actions.sol";
import {MMarketOperations} from "../libs/MMarketOperations.sol";

interface IEnhancedOptions {
    struct CustodyReleaseRequest {
        address owner;
        uint256 vaultId;
        address asset;
        uint256 amount;
    }

    struct CustodyRelease {
        address custodian;
        address asset;
        uint256 releasedAmount;
        uint256 outstandingAmount;
    }

    function ingressoNewTrustedTakerPosition(bytes calldata payload)
        external
        returns (uint256 vaultId, uint256 totalPremium);

    function ingressoNewTrustedMakerPosition(bytes calldata payload)
        external
        returns (uint256 vaultId, uint256 totalPremium);

    function ingressoNewTrustedTakerAndMakerPosition(bytes calldata payload)
        external
        returns (uint256 vaultId, uint256 totalPremium);

    function ingressoSettle(Actions.ActionArgs[] memory actions) external;

    function ingressoDepositAndOpen(bytes calldata transferPayload, bytes calldata orderPayload) external;

    function ingressoReleaseCollateralToCustody(
        address maker,
        address receiver,
        uint64 nonce,
        uint64 validUntil,
        CustodyReleaseRequest[] calldata requests,
        bytes calldata signature
    ) external;

    function setMakerCustodyLimitBps(address maker, address receiver, uint256 bps) external;

    function makerCustodyLimitBps(address maker, address receiver) external view returns (uint256);

    function marginPool() external view returns (address);

    function ingressoReturnFromCustody(address owner, uint256[] calldata vaultIds, uint256[] calldata amounts) external;
}

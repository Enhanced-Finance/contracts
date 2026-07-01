// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Actions} from "../libs/Actions.sol";
import {IEnhancedOptionsTimelock} from "./IEnhancedOptionsTimelock.sol";

interface IEnhancedOptions is IEnhancedOptionsTimelock {
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

    event OperatorChanged(address newOperator, address oldOperator);
    event CustodyOperatorChanged(address newCustodyOperator, address oldCustodyOperator);

    error BadOperator();
    error BadCustodyOperator();
    error MakerWhitelistRequired(address maker);
    error RedeemPayerInvalid();

    function initialize(
        address[] calldata initialTrustedTakers,
        address[] calldata initialTrustedMakers,
        address initialOperator,
        address initialCustodyOperator
    ) external;

    function setOperator(address operator) external;

    function operator() external view returns (address);

    function setCustodyOperator(address custodyOperator) external;

    function custodyOperator() external view returns (address);

    function setTrustedTaker(address taker, bool trusted) external;

    function setTrustedMaker(address maker, bool trusted) external;

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

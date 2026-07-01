// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IEnhancedOptionsTimelock {
    enum TimelockConfigType {
        TrustedTaker,
        TrustedMaker,
        MakerWhitelist,
        MakerCustodyLimitBps
    }

    event TrustedTakerSet(address indexed taker, bool trusted);
    event TrustedMakerSet(address indexed maker, bool trusted);
    event MakerWhitelistSet(address indexed maker, address indexed receiver);
    event MakerCustodyLimitBpsSet(address indexed maker, address indexed custodian, uint256 bps);
    event TrustedTakerScheduled(address indexed taker, uint64 executeAfter);
    event TrustedTakerExecuted(address indexed taker);
    event TrustedTakerCancelled(address indexed taker);
    event TrustedMakerScheduled(address indexed maker, uint64 executeAfter);
    event TrustedMakerExecuted(address indexed maker);
    event TrustedMakerCancelled(address indexed maker);
    event MakerWhitelistScheduled(address indexed maker, address indexed receiver, uint64 executeAfter);
    event MakerWhitelistExecuted(address indexed maker, address indexed receiver);
    event MakerWhitelistCancelled(address indexed maker);
    event MakerCustodyLimitBpsScheduled(
        address indexed maker, address indexed custodian, uint256 bps, uint64 executeAfter
    );
    event MakerCustodyLimitBpsExecuted(address indexed maker, address indexed custodian, uint256 bps);
    event MakerCustodyLimitBpsCancelled(address indexed maker, address indexed custodian);

    error ZeroAddress();
    error ZeroMaker();
    error ZeroReceiver();
    error CustodyLimitTooHigh();
    error TimelockRequired();
    error PendingUpdateExists();
    error PendingUpdateNotFound();
    error TimelockNotReady(uint64 executeAfter);
    error NoConfigChange();

    function scheduleConfigUpdate(TimelockConfigType configType, bytes calldata data) external;

    function executeConfigUpdate(TimelockConfigType configType, bytes calldata key) external;

    function cancelConfigUpdate(TimelockConfigType configType, bytes calldata key) external;

    function pendingConfigUpdate(TimelockConfigType configType, bytes calldata key)
        external
        view
        returns (bytes memory data, uint64 executeAfter);
}

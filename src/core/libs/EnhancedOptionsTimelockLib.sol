// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IEnhancedOptionsTimelock as Timelock} from "../interfaces/IEnhancedOptionsTimelock.sol";

library EnhancedOptionsTimelockLib {
    struct PendingAddressUpdate {
        address value;
        uint64 executeAfter;
    }

    struct PendingUintUpdate {
        uint256 value;
        uint64 executeAfter;
    }

    uint256 internal constant CONFIG_TIMELOCK_DELAY = 48 hours;
    uint256 internal constant MAX_CUSTODY_LIMIT_BPS = 10_000;
    uint8 internal constant CONFIG_TRUSTED_TAKER = 0;
    uint8 internal constant CONFIG_TRUSTED_MAKER = 1;
    uint8 internal constant CONFIG_MAKER_WHITELIST = 2;
    uint8 internal constant CONFIG_MAKER_CUSTODY_LIMIT_BPS = 3;

    function initializeTrustedRoles(
        mapping(address => bool) storage trustedTakers,
        mapping(address => bool) storage trustedMakers,
        address[] calldata initialTrustedTakers,
        address[] calldata initialTrustedMakers
    ) external {
        for (uint256 i; i < initialTrustedTakers.length; i++) {
            address taker = initialTrustedTakers[i];
            if (taker == address(0)) revert Timelock.ZeroAddress();
            trustedTakers[taker] = true;
            emit Timelock.TrustedTakerSet(taker, true);
        }
        for (uint256 i; i < initialTrustedMakers.length; i++) {
            address maker = initialTrustedMakers[i];
            if (maker == address(0)) revert Timelock.ZeroAddress();
            trustedMakers[maker] = true;
            emit Timelock.TrustedMakerSet(maker, true);
        }
    }

    function revokeTrustedTaker(
        mapping(address => bool) storage trusted,
        mapping(address => uint64) storage pending,
        address taker,
        bool desired
    ) external {
        if (desired) revert Timelock.TimelockRequired();
        if (taker == address(0)) revert Timelock.ZeroAddress();
        if (pending[taker] != 0) emit Timelock.TrustedTakerCancelled(taker);
        delete pending[taker];
        trusted[taker] = false;
        emit Timelock.TrustedTakerSet(taker, false);
    }

    function revokeTrustedMaker(
        mapping(address => bool) storage trusted,
        mapping(address => uint64) storage pending,
        address maker,
        bool desired
    ) external {
        if (desired) revert Timelock.TimelockRequired();
        if (maker == address(0)) revert Timelock.ZeroMaker();
        if (pending[maker] != 0) emit Timelock.TrustedMakerCancelled(maker);
        delete pending[maker];
        trusted[maker] = false;
        emit Timelock.TrustedMakerSet(maker, false);
    }

    function scheduleConfigUpdate(
        uint8 configType,
        bytes calldata data,
        mapping(address => bool) storage trustedTakers,
        mapping(address => bool) storage trustedMakers,
        mapping(address => address) storage makerWhitelist,
        mapping(address => mapping(address => uint256)) storage makerCustodyLimitBps,
        mapping(address => uint64) storage pendingTrustedTakers,
        mapping(address => uint64) storage pendingTrustedMakers,
        mapping(address => PendingAddressUpdate) storage pendingMakerWhitelist,
        mapping(address => mapping(address => PendingUintUpdate)) storage pendingMakerCustodyLimitBps
    ) external {
        if (configType == CONFIG_TRUSTED_TAKER) {
            address taker = abi.decode(data, (address));
            _scheduleTrustedTaker(trustedTakers, pendingTrustedTakers, taker);
        } else if (configType == CONFIG_TRUSTED_MAKER) {
            address maker = abi.decode(data, (address));
            _scheduleTrustedMaker(trustedMakers, pendingTrustedMakers, maker);
        } else if (configType == CONFIG_MAKER_WHITELIST) {
            (address maker, address receiver) = abi.decode(data, (address, address));
            _scheduleMakerWhitelist(makerWhitelist, pendingMakerWhitelist, maker, receiver);
        } else if (configType == CONFIG_MAKER_CUSTODY_LIMIT_BPS) {
            (address maker, address receiver, uint256 bps) = abi.decode(data, (address, address, uint256));
            _scheduleMakerCustodyLimit(makerCustodyLimitBps, pendingMakerCustodyLimitBps, maker, receiver, bps);
        }
    }

    function executeConfigUpdate(
        uint8 configType,
        bytes calldata key,
        mapping(address => bool) storage trustedTakers,
        mapping(address => bool) storage trustedMakers,
        mapping(address => address) storage makerWhitelist,
        mapping(address => mapping(address => uint256)) storage makerCustodyLimitBps,
        mapping(address => uint64) storage pendingTrustedTakers,
        mapping(address => uint64) storage pendingTrustedMakers,
        mapping(address => PendingAddressUpdate) storage pendingMakerWhitelist,
        mapping(address => mapping(address => PendingUintUpdate)) storage pendingMakerCustodyLimitBps
    ) external {
        if (configType == CONFIG_TRUSTED_TAKER) {
            address taker = abi.decode(key, (address));
            _executeTrustedTaker(trustedTakers, pendingTrustedTakers, taker);
        } else if (configType == CONFIG_TRUSTED_MAKER) {
            address maker = abi.decode(key, (address));
            _executeTrustedMaker(trustedMakers, pendingTrustedMakers, maker);
        } else if (configType == CONFIG_MAKER_WHITELIST) {
            address maker = abi.decode(key, (address));
            _executeMakerWhitelist(makerWhitelist, pendingMakerWhitelist, maker);
        } else if (configType == CONFIG_MAKER_CUSTODY_LIMIT_BPS) {
            (address maker, address receiver) = abi.decode(key, (address, address));
            _executeMakerCustodyLimit(makerCustodyLimitBps, pendingMakerCustodyLimitBps, maker, receiver);
        }
    }

    function cancelConfigUpdate(
        uint8 configType,
        bytes calldata key,
        mapping(address => uint64) storage pendingTrustedTakers,
        mapping(address => uint64) storage pendingTrustedMakers,
        mapping(address => PendingAddressUpdate) storage pendingMakerWhitelist,
        mapping(address => mapping(address => PendingUintUpdate)) storage pendingMakerCustodyLimitBps
    ) external {
        if (configType == CONFIG_TRUSTED_TAKER) {
            address taker = abi.decode(key, (address));
            _cancelTrustedTaker(pendingTrustedTakers, taker);
        } else if (configType == CONFIG_TRUSTED_MAKER) {
            address maker = abi.decode(key, (address));
            _cancelTrustedMaker(pendingTrustedMakers, maker);
        } else if (configType == CONFIG_MAKER_WHITELIST) {
            address maker = abi.decode(key, (address));
            _cancelMakerWhitelist(pendingMakerWhitelist, maker);
        } else if (configType == CONFIG_MAKER_CUSTODY_LIMIT_BPS) {
            (address maker, address receiver) = abi.decode(key, (address, address));
            _cancelMakerCustodyLimit(pendingMakerCustodyLimitBps, maker, receiver);
        }
    }

    function pendingConfigUpdate(
        uint8 configType,
        bytes calldata key,
        mapping(address => uint64) storage pendingTrustedTakers,
        mapping(address => uint64) storage pendingTrustedMakers,
        mapping(address => PendingAddressUpdate) storage pendingMakerWhitelist,
        mapping(address => mapping(address => PendingUintUpdate)) storage pendingMakerCustodyLimitBps
    ) external view returns (bytes memory data, uint64 executeAfter) {
        if (configType == CONFIG_TRUSTED_TAKER) {
            address taker = abi.decode(key, (address));
            executeAfter = pendingTrustedTakers[taker];
            if (executeAfter != 0) data = abi.encode(taker);
        } else if (configType == CONFIG_TRUSTED_MAKER) {
            address maker = abi.decode(key, (address));
            executeAfter = pendingTrustedMakers[maker];
            if (executeAfter != 0) data = abi.encode(maker);
        } else if (configType == CONFIG_MAKER_WHITELIST) {
            address maker = abi.decode(key, (address));
            PendingAddressUpdate memory update = pendingMakerWhitelist[maker];
            executeAfter = update.executeAfter;
            if (executeAfter != 0) data = abi.encode(maker, update.value);
        } else if (configType == CONFIG_MAKER_CUSTODY_LIMIT_BPS) {
            (address maker, address receiver) = abi.decode(key, (address, address));
            PendingUintUpdate memory update = pendingMakerCustodyLimitBps[maker][receiver];
            executeAfter = update.executeAfter;
            if (executeAfter != 0) data = abi.encode(maker, receiver, update.value);
        }
    }

    function clearMakerCustodyLimit(
        mapping(address => mapping(address => uint256)) storage current,
        mapping(address => mapping(address => PendingUintUpdate)) storage pending,
        address maker,
        address receiver,
        uint256 bps
    ) external {
        if (maker == address(0)) revert Timelock.ZeroMaker();
        if (receiver == address(0)) revert Timelock.ZeroReceiver();
        if (bps != 0) revert Timelock.TimelockRequired();
        if (pending[maker][receiver].executeAfter != 0) {
            emit Timelock.MakerCustodyLimitBpsCancelled(maker, receiver);
        }
        delete pending[maker][receiver];
        current[maker][receiver] = 0;
        emit Timelock.MakerCustodyLimitBpsSet(maker, receiver, 0);
    }

    function _scheduleTrustedTaker(
        mapping(address => bool) storage trusted,
        mapping(address => uint64) storage pending,
        address taker
    ) private {
        if (taker == address(0)) revert Timelock.ZeroAddress();
        if (trusted[taker]) revert Timelock.NoConfigChange();
        if (pending[taker] != 0) revert Timelock.PendingUpdateExists();
        uint64 executeAfter = _executeAfter();
        pending[taker] = executeAfter;
        emit Timelock.TrustedTakerScheduled(taker, executeAfter);
    }

    function _executeTrustedTaker(
        mapping(address => bool) storage trusted,
        mapping(address => uint64) storage pending,
        address taker
    ) private {
        _requireReady(pending[taker]);
        delete pending[taker];
        trusted[taker] = true;
        emit Timelock.TrustedTakerExecuted(taker);
        emit Timelock.TrustedTakerSet(taker, true);
    }

    function _cancelTrustedTaker(mapping(address => uint64) storage pending, address taker) private {
        if (pending[taker] == 0) revert Timelock.PendingUpdateNotFound();
        delete pending[taker];
        emit Timelock.TrustedTakerCancelled(taker);
    }

    function _scheduleTrustedMaker(
        mapping(address => bool) storage trusted,
        mapping(address => uint64) storage pending,
        address maker
    ) private {
        if (maker == address(0)) revert Timelock.ZeroMaker();
        if (trusted[maker]) revert Timelock.NoConfigChange();
        if (pending[maker] != 0) revert Timelock.PendingUpdateExists();
        uint64 executeAfter = _executeAfter();
        pending[maker] = executeAfter;
        emit Timelock.TrustedMakerScheduled(maker, executeAfter);
    }

    function _executeTrustedMaker(
        mapping(address => bool) storage trusted,
        mapping(address => uint64) storage pending,
        address maker
    ) private {
        _requireReady(pending[maker]);
        delete pending[maker];
        trusted[maker] = true;
        emit Timelock.TrustedMakerExecuted(maker);
        emit Timelock.TrustedMakerSet(maker, true);
    }

    function _cancelTrustedMaker(mapping(address => uint64) storage pending, address maker) private {
        if (pending[maker] == 0) revert Timelock.PendingUpdateNotFound();
        delete pending[maker];
        emit Timelock.TrustedMakerCancelled(maker);
    }

    function _scheduleMakerWhitelist(
        mapping(address => address) storage current,
        mapping(address => PendingAddressUpdate) storage pending,
        address maker,
        address receiver
    ) private {
        if (maker == address(0)) revert Timelock.ZeroMaker();
        if (current[maker] == receiver) revert Timelock.NoConfigChange();
        if (pending[maker].executeAfter != 0) revert Timelock.PendingUpdateExists();
        uint64 executeAfter = _executeAfter();
        pending[maker] = PendingAddressUpdate({value: receiver, executeAfter: executeAfter});
        emit Timelock.MakerWhitelistScheduled(maker, receiver, executeAfter);
    }

    function _executeMakerWhitelist(
        mapping(address => address) storage current,
        mapping(address => PendingAddressUpdate) storage pending,
        address maker
    ) private {
        PendingAddressUpdate memory update = pending[maker];
        _requireReady(update.executeAfter);
        delete pending[maker];
        current[maker] = update.value;
        emit Timelock.MakerWhitelistExecuted(maker, update.value);
        emit Timelock.MakerWhitelistSet(maker, update.value);
    }

    function _cancelMakerWhitelist(mapping(address => PendingAddressUpdate) storage pending, address maker) private {
        if (pending[maker].executeAfter == 0) revert Timelock.PendingUpdateNotFound();
        delete pending[maker];
        emit Timelock.MakerWhitelistCancelled(maker);
    }

    function _scheduleMakerCustodyLimit(
        mapping(address => mapping(address => uint256)) storage current,
        mapping(address => mapping(address => PendingUintUpdate)) storage pending,
        address maker,
        address receiver,
        uint256 bps
    ) private {
        if (maker == address(0)) revert Timelock.ZeroMaker();
        if (receiver == address(0)) revert Timelock.ZeroReceiver();
        if (bps == 0) revert Timelock.TimelockRequired();
        if (bps > MAX_CUSTODY_LIMIT_BPS) revert Timelock.CustodyLimitTooHigh();
        if (current[maker][receiver] == bps) revert Timelock.NoConfigChange();
        if (pending[maker][receiver].executeAfter != 0) revert Timelock.PendingUpdateExists();
        uint64 executeAfter = _executeAfter();
        pending[maker][receiver] = PendingUintUpdate({value: bps, executeAfter: executeAfter});
        emit Timelock.MakerCustodyLimitBpsScheduled(maker, receiver, bps, executeAfter);
    }

    function _executeMakerCustodyLimit(
        mapping(address => mapping(address => uint256)) storage current,
        mapping(address => mapping(address => PendingUintUpdate)) storage pending,
        address maker,
        address receiver
    ) private {
        PendingUintUpdate memory update = pending[maker][receiver];
        _requireReady(update.executeAfter);
        delete pending[maker][receiver];
        current[maker][receiver] = update.value;
        emit Timelock.MakerCustodyLimitBpsExecuted(maker, receiver, update.value);
        emit Timelock.MakerCustodyLimitBpsSet(maker, receiver, update.value);
    }

    function _cancelMakerCustodyLimit(
        mapping(address => mapping(address => PendingUintUpdate)) storage pending,
        address maker,
        address receiver
    ) private {
        if (pending[maker][receiver].executeAfter == 0) revert Timelock.PendingUpdateNotFound();
        delete pending[maker][receiver];
        emit Timelock.MakerCustodyLimitBpsCancelled(maker, receiver);
    }

    function _executeAfter() private view returns (uint64) {
        return uint64(block.timestamp + CONFIG_TIMELOCK_DELAY);
    }

    function _requireReady(uint64 executeAfter) private view {
        if (executeAfter == 0) revert Timelock.PendingUpdateNotFound();
        if (block.timestamp < executeAfter) revert Timelock.TimelockNotReady(executeAfter);
    }
}

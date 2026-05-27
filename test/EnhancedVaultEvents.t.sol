// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Vm} from "forge-std/Vm.sol";
import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";
import {EnhancedVault} from "../src/periphery/vault/EnhancedVault.sol";
import {EnhancedVaultLinkedLibraries} from "./helpers/EnhancedVaultLinkedLibraries.sol";

contract MockERC20ForVaultEvents is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_, 18) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract EnhancedVaultEventHarness is EnhancedVault {
    function seedOwner(address newOwner) external {
        _transferOwnership(newOwner);
    }

    function seedOperator(address newOperator) external {
        operator = newOperator;
    }

    function seedActivePrincipal(bytes32 vaultHash, address user, uint256 activePrincipal) external {
        userFunds[vaultHash][user].activePrincipal = activePrincipal;
    }
}

contract EnhancedVaultEventsTest is EnhancedVaultLinkedLibraries {
    bytes32 internal constant VAULT_CREATED_EVENT = keccak256(
        "VaultCreated(bytes32,uint256,address,address,address,bool,uint256,uint256,uint256,int256,uint256,int256)"
    );
    bytes32 internal constant DEPOSITED_EVENT = keccak256("Deposited(bytes32,address,uint256,uint256)");
    bytes32 internal constant WITHDRAW_REQUESTED_EVENT =
        keccak256("WithdrawRequested(bytes32,address,uint256,uint256)");
    bytes32 internal constant CYCLE_SETTLED_EVENT =
        keccak256("CycleSettled(bytes32,uint256,uint256,uint256,uint256,uint256)");
    bytes32 internal constant CYCLE_STARTED_EVENT = keccak256("CycleStarted(bytes32,uint256,uint256,uint256,uint256)");

    uint256 internal constant OWNER_PK = 0xA11CE;
    uint256 internal constant OPERATOR_PK = 0xB0B;
    uint256 internal constant USER_PK = 0xBEEF;

    EnhancedVaultEventHarness internal vault;
    MockERC20ForVaultEvents internal collateral;

    address internal owner;
    address internal operator;
    address internal user;

    function setUp() external {
        _etchEnhancedVaultLibraries();

        owner = vm.addr(OWNER_PK);
        operator = vm.addr(OPERATOR_PK);
        user = vm.addr(USER_PK);

        vault = new EnhancedVaultEventHarness();
        vault.seedOwner(owner);
        vault.seedOperator(operator);

        collateral = new MockERC20ForVaultEvents("Collateral", "COL");
        collateral.mint(user, 1_000_000 ether);
        vm.prank(user);
        collateral.approve(address(vault), type(uint256).max);
    }

    function _vaultState(bytes32 vaultHash) internal view returns (EnhancedVault.VaultState memory st) {
        (
            EnhancedVault.VaultParams memory params,
            bool isActive,
            uint256 currentCycleId,
            uint256 currentCycleStart,
            uint256 totalDeposited,
            bool isPaused,
            bool isEnd
        ) = vault.vaults(vaultHash);

        st = EnhancedVault.VaultState({
            params: params,
            isActive: isActive,
            currentCycleId: currentCycleId,
            currentCycleStart: currentCycleStart,
            totalDeposited: totalDeposited,
            isPaused: isPaused,
            isEnd: isEnd
        });
    }

    function testCreateVault_ShouldEmitFullParamsAndInitialState() external {
        EnhancedVault.VaultParams memory params = _vaultParams();
        bytes32 expectedHash = keccak256(abi.encode(params));

        vm.recordLogs();
        vm.prank(owner);
        bytes32 vaultHash = vault.createVault(params);

        assertEq(vaultHash, expectedHash, "vault hash mismatch");

        Vm.Log memory log = _findLog(vm.getRecordedLogs(), VAULT_CREATED_EVENT);
        assertEq(log.emitter, address(vault), "unexpected event emitter");
        assertEq(log.topics.length, 2, "topic count mismatch");
        assertEq(log.topics[1], expectedHash, "indexed vaultHash mismatch");

        (
            uint256 cycleDuration,
            address underlyingAsset,
            address collateralAsset,
            address strikeAsset,
            bool isPut,
            uint256 capacity,
            uint256 minInvestmentAmount,
            uint256 startTime,
            int256 strikePriceBps,
            uint256 minPrincipalRatio,
            int256 buybackPriceRatio
        ) = abi.decode(
            log.data, (uint256, address, address, address, bool, uint256, uint256, uint256, int256, uint256, int256)
        );

        assertEq(cycleDuration, params.cycleDuration, "cycleDuration mismatch");
        assertEq(underlyingAsset, params.underlyingAsset, "underlyingAsset mismatch");
        assertEq(collateralAsset, params.collateralAsset, "collateralAsset mismatch");
        assertEq(strikeAsset, params.strikeAsset, "strikeAsset mismatch");
        assertEq(isPut, params.isPut, "isPut mismatch");
        assertEq(capacity, params.capacity, "capacity mismatch");
        assertEq(minInvestmentAmount, params.minInvestmentAmount, "minInvestmentAmount mismatch");
        assertEq(startTime, params.startTime, "startTime mismatch");
        assertEq(strikePriceBps, params.strikePriceBps, "strikePriceBps mismatch");
        assertEq(minPrincipalRatio, params.minPrincipalRatio, "minPrincipalRatio mismatch");
        assertEq(buybackPriceRatio, params.buybackPriceRatio, "buybackPriceRatio mismatch");

        EnhancedVault.VaultState memory st = _vaultState(vaultHash);
        assertTrue(st.isActive, "vault should start active");
        assertEq(st.currentCycleId, 1, "currentCycleId mismatch");
        assertEq(st.currentCycleStart, params.startTime, "currentCycleStart mismatch");
        assertEq(st.totalDeposited, 0, "totalDeposited mismatch");
        assertFalse(st.isPaused, "vault should not start paused");
        assertFalse(st.isEnd, "vault should not start ended");
    }

    function testDeposit_ShouldEmitRecordId() external {
        bytes32 vaultHash = _createVault();
        uint256 amount = 25 ether;

        vm.recordLogs();
        vm.prank(user);
        vault.deposit(vaultHash, amount);

        Vm.Log memory log = _findLog(vm.getRecordedLogs(), DEPOSITED_EVENT);
        assertEq(log.emitter, address(vault), "unexpected event emitter");
        assertEq(log.topics.length, 3, "topic count mismatch");
        assertEq(log.topics[1], vaultHash, "indexed vaultHash mismatch");
        assertEq(address(uint160(uint256(log.topics[2]))), user, "indexed user mismatch");

        (uint256 recordId, uint256 loggedAmount) = abi.decode(log.data, (uint256, uint256));
        assertEq(recordId, 1, "deposit recordId mismatch");
        assertEq(loggedAmount, amount, "deposit amount mismatch");
    }

    function testWithdraw_ShouldEmitRecordId() external {
        bytes32 vaultHash = _createVault();
        uint256 amount = 7 ether;

        vault.seedActivePrincipal(vaultHash, user, 100 ether);

        vm.recordLogs();
        vm.prank(user);
        vault.withdraw(vaultHash, amount);

        Vm.Log memory log = _findLog(vm.getRecordedLogs(), WITHDRAW_REQUESTED_EVENT);
        assertEq(log.emitter, address(vault), "unexpected event emitter");
        assertEq(log.topics.length, 3, "topic count mismatch");
        assertEq(log.topics[1], vaultHash, "indexed vaultHash mismatch");
        assertEq(address(uint160(uint256(log.topics[2]))), user, "indexed user mismatch");

        (uint256 recordId, uint256 loggedAmount) = abi.decode(log.data, (uint256, uint256));
        assertEq(recordId, 1, "withdraw recordId mismatch");
        assertEq(loggedAmount, amount, "withdraw amount mismatch");
    }

    function testNextCycle_ShouldEmitCycleSettledAndCycleStarted() external {
        bytes32 vaultHash = _createVault();
        uint256 depositAmount = 25 ether;

        vm.prank(user);
        vault.deposit(vaultHash, depositAmount);

        vm.warp(block.timestamp + 8 days);

        vm.recordLogs();
        vm.prank(operator);
        vault.nextCycle(vaultHash);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        Vm.Log memory settledLog = _findLog(logs, CYCLE_SETTLED_EVENT);
        assertEq(settledLog.emitter, address(vault), "unexpected CycleSettled emitter");
        assertEq(settledLog.topics.length, 3, "CycleSettled topic count mismatch");
        assertEq(settledLog.topics[1], vaultHash, "CycleSettled vaultHash mismatch");
        assertEq(uint256(settledLog.topics[2]), 1, "CycleSettled settledCycleId mismatch");

        (uint256 totalActiveCollateral, uint256 allocatedCollateral, uint256 totalReturned, uint256 totalPremium) =
            abi.decode(settledLog.data, (uint256, uint256, uint256, uint256));
        assertEq(totalActiveCollateral, 0, "CycleSettled totalActiveCollateral mismatch");
        assertEq(allocatedCollateral, 0, "CycleSettled allocatedCollateral mismatch");
        assertEq(totalReturned, 0, "CycleSettled totalReturned mismatch");
        assertEq(totalPremium, 0, "CycleSettled totalPremium mismatch");

        Vm.Log memory startedLog = _findLog(logs, CYCLE_STARTED_EVENT);
        assertEq(startedLog.emitter, address(vault), "unexpected CycleStarted emitter");
        assertEq(startedLog.topics.length, 3, "CycleStarted topic count mismatch");
        assertEq(startedLog.topics[1], vaultHash, "CycleStarted vaultHash mismatch");
        assertEq(uint256(startedLog.topics[2]), 2, "CycleStarted newCycleId mismatch");

        EnhancedVault.VaultState memory st = _vaultState(vaultHash);
        (uint256 startedActiveCollateral, uint256 cycleStart, uint256 cycleEnd) =
            abi.decode(startedLog.data, (uint256, uint256, uint256));
        assertEq(startedActiveCollateral, depositAmount, "CycleStarted totalActiveCollateral mismatch");
        assertEq(cycleStart, st.currentCycleStart, "CycleStarted start mismatch");
        assertEq(cycleEnd, st.currentCycleStart + st.params.cycleDuration, "CycleStarted end mismatch");
    }

    function testCreateVaultHash_ShouldChangeWhenStrikePriceBpsChanges() external {
        EnhancedVault.VaultParams memory lowBps = _vaultParams();
        EnhancedVault.VaultParams memory highBps = _vaultParams();
        highBps.strikePriceBps = lowBps.strikePriceBps - 250;

        assertNotEq(
            keccak256(abi.encode(lowBps)), keccak256(abi.encode(highBps)), "vault hash should include strikePriceBps"
        );
    }

    function testCreateVault_ShouldRevertWhenStrikePriceBpsIsOutOfRange() external {
        EnhancedVault.VaultParams memory params = _vaultParams();
        params.strikePriceBps = 10_001;

        vm.prank(owner);
        vm.expectRevert();
        vault.createVault(params);
    }

    function testCreateVault_ShouldRevertWhenBuybackPriceRatioIsOutOfRange() external {
        EnhancedVault.VaultParams memory params = _vaultParams();
        params.buybackPriceRatio = -10_001;

        vm.prank(owner);
        vm.expectRevert();
        vault.createVault(params);
    }

    function _createVault() internal returns (bytes32 vaultHash) {
        EnhancedVault.VaultParams memory params = _vaultParams();
        vm.prank(owner);
        vaultHash = vault.createVault(params);
    }

    function _vaultParams() internal view returns (EnhancedVault.VaultParams memory params) {
        params = EnhancedVault.VaultParams({
            cycleDuration: 7 days,
            underlyingAsset: address(0x1001),
            collateralAsset: address(collateral),
            strikeAsset: address(0x1002),
            isPut: true,
            capacity: 1_000_000 ether,
            minInvestmentAmount: 1 ether,
            startTime: block.timestamp + 1 days,
            strikePriceBps: 500,
            minPrincipalRatio: 8_500,
            buybackPriceRatio: -1_250
        });
    }

    function _findLog(Vm.Log[] memory logs, bytes32 signature) internal pure returns (Vm.Log memory) {
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].topics.length != 0 && logs[i].topics[0] == signature) {
                return logs[i];
            }
        }
        revert("event not found");
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {ConfigureEnhancedVault, IEnhancedVaultConfigTarget} from "../script/EnhancedVault/ConfigureEnhancedVault.s.sol";

contract MockEnhancedVaultConfigTarget is IEnhancedVaultConfigTarget {
    address public operator;
    address public vaultSigner;
    address public swapRouter;

    address[] internal _marginPoolAssets;
    bool[] internal _marginPoolApprovals;
    address[] internal _swapRouterAssets;
    bool[] internal _swapRouterApprovals;

    function setOperator(address newOperator) external {
        operator = newOperator;
    }

    function setVaultSigner(address newSigner) external {
        vaultSigner = newSigner;
    }

    function setSwapRouter(address newSwapRouter) external {
        swapRouter = newSwapRouter;
    }

    function setAssetApprovalMarginPool(address asset, bool approval) external {
        _marginPoolAssets.push(asset);
        _marginPoolApprovals.push(approval);
    }

    function setAssetApprovalSwapRouter(address asset, bool approval) external {
        _swapRouterAssets.push(asset);
        _swapRouterApprovals.push(approval);
    }

    function marginPoolCallCount() external view returns (uint256) {
        return _marginPoolAssets.length;
    }

    function swapRouterCallCount() external view returns (uint256) {
        return _swapRouterAssets.length;
    }

    function marginPoolCall(uint256 index) external view returns (address asset, bool approval) {
        return (_marginPoolAssets[index], _marginPoolApprovals[index]);
    }

    function swapRouterCall(uint256 index) external view returns (address asset, bool approval) {
        return (_swapRouterAssets[index], _swapRouterApprovals[index]);
    }
}

contract ConfigureEnhancedVaultHarness is ConfigureEnhancedVault {
    function exposedReadApprovals(string memory configJson, string memory key)
        external
        view
        returns (ApprovalConfig[] memory)
    {
        return _readApprovals(configJson, key);
    }

    function exposedApplyMarginPoolApprovals(IEnhancedVaultConfigTarget vault, ApprovalConfig[] memory approvals)
        external
    {
        _applyMarginPoolApprovals(vault, approvals);
    }

    function exposedApplySwapRouterApprovals(IEnhancedVaultConfigTarget vault, ApprovalConfig[] memory approvals)
        external
    {
        _applySwapRouterApprovals(vault, approvals);
    }
}

contract ConfigureEnhancedVaultScriptTest is Test {
    ConfigureEnhancedVaultHarness internal harness;
    MockEnhancedVaultConfigTarget internal target;

    function setUp() external {
        harness = new ConfigureEnhancedVaultHarness();
        target = new MockEnhancedVaultConfigTarget();
    }

    function testReadApprovals_ShouldDecodeSeparateLists() external view {
        string memory configJson = string.concat(
            '{"EnhancedVault":{"marginPoolApprovals":[',
            '{"asset":"0x0000000000000000000000000000000000000011","approval":true},',
            '{"asset":"0x0000000000000000000000000000000000000022","approval":false}',
            '],"swapRouterApprovals":[',
            '{"asset":"0x00000000000000000000000000000000000000AA","approval":true}',
            "]}}"
        );

        ConfigureEnhancedVault.ApprovalConfig[] memory marginPoolApprovals =
            harness.exposedReadApprovals(configJson, ".EnhancedVault.marginPoolApprovals");
        ConfigureEnhancedVault.ApprovalConfig[] memory swapRouterApprovals =
            harness.exposedReadApprovals(configJson, ".EnhancedVault.swapRouterApprovals");

        assertEq(marginPoolApprovals.length, 2, "marginPool approvals length mismatch");
        assertEq(marginPoolApprovals[0].asset, address(0x11), "first marginPool asset mismatch");
        assertTrue(marginPoolApprovals[0].approval, "first marginPool approval mismatch");
        assertEq(marginPoolApprovals[1].asset, address(0x22), "second marginPool asset mismatch");
        assertFalse(marginPoolApprovals[1].approval, "second marginPool approval mismatch");

        assertEq(swapRouterApprovals.length, 1, "swapRouter approvals length mismatch");
        assertEq(swapRouterApprovals[0].asset, address(0xAA), "swapRouter asset mismatch");
        assertTrue(swapRouterApprovals[0].approval, "swapRouter approval mismatch");
    }

    function testReadApprovals_ShouldDecodeRealConfigFile() external view {
        string memory configPath = string.concat(vm.projectRoot(), "/config/1328.json");
        string memory configJson = vm.readFile(configPath);

        ConfigureEnhancedVault.ApprovalConfig[] memory marginPoolApprovals =
            harness.exposedReadApprovals(configJson, ".EnhancedVault.marginPoolApprovals");
        ConfigureEnhancedVault.ApprovalConfig[] memory swapRouterApprovals =
            harness.exposedReadApprovals(configJson, ".EnhancedVault.swapRouterApprovals");

        assertEq(marginPoolApprovals.length, 1, "real config marginPool approvals length mismatch");
        assertEq(
            marginPoolApprovals[0].asset,
            0xb4720E4467aCe9D54da0ee10365e5594A10F9fE2,
            "real config marginPool asset mismatch"
        );
        assertTrue(marginPoolApprovals[0].approval, "real config marginPool approval mismatch");

        assertEq(swapRouterApprovals.length, 1, "real config swapRouter approvals length mismatch");
        assertEq(
            swapRouterApprovals[0].asset,
            0x134b5f74d65a34eb6F9CdaD5eD664b45A167cC43,
            "real config swapRouter asset mismatch"
        );
        assertTrue(swapRouterApprovals[0].approval, "real config swapRouter approval mismatch");
    }

    function testApplyMarginPoolApprovals_ShouldOnlyCallMarginPoolSetter() external {
        ConfigureEnhancedVault.ApprovalConfig[] memory approvals = new ConfigureEnhancedVault.ApprovalConfig[](3);
        approvals[0] = ConfigureEnhancedVault.ApprovalConfig({asset: address(0x11), approval: true});
        approvals[1] = ConfigureEnhancedVault.ApprovalConfig({asset: address(0), approval: true});
        approvals[2] = ConfigureEnhancedVault.ApprovalConfig({asset: address(0x22), approval: false});

        harness.exposedApplyMarginPoolApprovals(target, approvals);

        assertEq(target.marginPoolCallCount(), 2, "marginPool approval call count mismatch");
        assertEq(target.swapRouterCallCount(), 0, "swapRouter approvals should not be called");

        (address firstAsset, bool firstApproval) = target.marginPoolCall(0);
        assertEq(firstAsset, address(0x11), "first marginPool approval asset mismatch");
        assertTrue(firstApproval, "first marginPool approval flag mismatch");

        (address secondAsset, bool secondApproval) = target.marginPoolCall(1);
        assertEq(secondAsset, address(0x22), "second marginPool approval asset mismatch");
        assertFalse(secondApproval, "second marginPool approval flag mismatch");
    }

    function testApplySwapRouterApprovals_ShouldOnlyCallSwapRouterSetter() external {
        ConfigureEnhancedVault.ApprovalConfig[] memory approvals = new ConfigureEnhancedVault.ApprovalConfig[](3);
        approvals[0] = ConfigureEnhancedVault.ApprovalConfig({asset: address(0xAA), approval: true});
        approvals[1] = ConfigureEnhancedVault.ApprovalConfig({asset: address(0), approval: false});
        approvals[2] = ConfigureEnhancedVault.ApprovalConfig({asset: address(0xBB), approval: false});

        harness.exposedApplySwapRouterApprovals(target, approvals);

        assertEq(target.swapRouterCallCount(), 2, "swapRouter approval call count mismatch");
        assertEq(target.marginPoolCallCount(), 0, "marginPool approvals should not be called");

        (address firstAsset, bool firstApproval) = target.swapRouterCall(0);
        assertEq(firstAsset, address(0xAA), "first swapRouter approval asset mismatch");
        assertTrue(firstApproval, "first swapRouter approval flag mismatch");

        (address secondAsset, bool secondApproval) = target.swapRouterCall(1);
        assertEq(secondAsset, address(0xBB), "second swapRouter approval asset mismatch");
        assertFalse(secondApproval, "second swapRouter approval flag mismatch");
    }
}

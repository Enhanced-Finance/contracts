// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

interface IEnhancedVaultConfigTarget {
    function operator() external view returns (address);
    function vaultSigner() external view returns (address);
    function protocolFeeRecipient() external view returns (address);
    function swapRouter() external view returns (address);
    function setOperator(address newOperator) external;
    function setVaultSigner(address newSigner) external;
    function setProtocolFeeRecipient(address newRecipient) external;
    function setSwapRouter(address newSwapRouter) external;
    function setAssetApprovalMarginPool(address asset, bool approval) external;
    function setAssetApprovalSwapRouter(address asset, bool approval) external;
}

/**
 * @notice Configure EnhancedVault from config/<chainId>.json.
 *
 * Supported config keys under ".EnhancedVault":
 *   operator             (address)   — setOperator
 *   vaultSigner          (address)   — setVaultSigner
 *   protocolFeeRecipient (address)   — setProtocolFeeRecipient
 *   swapRouter           (address)   — setSwapRouter
 *   marginPoolApprovals  (array)     — setAssetApprovalMarginPool
 *   swapRouterApprovals  (array)     — setAssetApprovalSwapRouter
 *
 * Vault creation via ".EnhancedVault.vaults[]":
 *   Each entry may contain:
 *     cycleDuration       (uint256) seconds
 *     underlyingAsset     (address)
 *     collateralAsset     (address)
 *     strikeAsset         (address)
 *     isPut               (bool)
 *     capacity            (uint256) in collateral decimals
 *     minInvestmentAmount (uint256) in collateral decimals
 *     startTime           (uint256) unix timestamp, 0 = now
 *     active              (bool)    setVaultActive after creation (default true)
 */
contract ConfigureEnhancedVault is Script {
    using stdJson for string;

    struct ApprovalConfig {
        address asset;
        bool approval;
    }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        uint256 chainId = block.chainid;
        string memory chainIdStr = vm.toString(chainId);
        string memory deployPath = string.concat(vm.projectRoot(), "/.deploy/", chainIdStr, ".json");
        string memory configPath = string.concat(vm.projectRoot(), "/config/", chainIdStr, ".json");

        require(vm.isFile(deployPath), "Deploy file not found");
        require(vm.isFile(configPath), "Config file not found");

        string memory deployJson = vm.readFile(deployPath);
        string memory configJson = vm.readFile(configPath);

        address vaultAddr = deployJson.readAddress(".EnhancedVault.proxyAddress");
        require(vaultAddr != address(0), "EnhancedVault proxy not found");

        IEnhancedVaultConfigTarget vault = IEnhancedVaultConfigTarget(vaultAddr);
        console.log("Configuring EnhancedVault at:", vaultAddr);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Operator
        if (vm.keyExists(configJson, ".EnhancedVault.operator")) {
            address desiredOperator = configJson.readAddress(".EnhancedVault.operator");
            if (desiredOperator != address(0) && vault.operator() != desiredOperator) {
                console.log("Updating Operator...");
                vault.setOperator(desiredOperator);
            }
        }

        // 2. VaultSigner
        if (vm.keyExists(configJson, ".EnhancedVault.vaultSigner")) {
            address desiredSigner = configJson.readAddress(".EnhancedVault.vaultSigner");
            if (desiredSigner != address(0) && vault.vaultSigner() != desiredSigner) {
                console.log("Updating VaultSigner...");
                vault.setVaultSigner(desiredSigner);
            }
        }

        // 3. ProtocolFeeRecipient
        if (vm.keyExists(configJson, ".EnhancedVault.protocolFeeRecipient")) {
            _applyProtocolFeeRecipient(vault, configJson.readAddress(".EnhancedVault.protocolFeeRecipient"));
        }

        // 4. SwapRouter
        if (vm.keyExists(configJson, ".EnhancedVault.swapRouter")) {
            address desiredRouter = configJson.readAddress(".EnhancedVault.swapRouter");
            if (desiredRouter != address(0) && vault.swapRouter() != desiredRouter) {
                console.log("Updating SwapRouter...");
                vault.setSwapRouter(desiredRouter);
            }
        }

        if (vm.keyExists(configJson, ".EnhancedVault.marginPoolApprovals")) {
            _applyMarginPoolApprovals(vault, _readApprovals(configJson, ".EnhancedVault.marginPoolApprovals"));
        }

        if (vm.keyExists(configJson, ".EnhancedVault.swapRouterApprovals")) {
            _applySwapRouterApprovals(vault, _readApprovals(configJson, ".EnhancedVault.swapRouterApprovals"));
        }

        vm.stopBroadcast();

        console.log("ConfigureEnhancedVault complete.");
    }

    function _readApprovals(string memory configJson, string memory key)
        internal
        view
        returns (ApprovalConfig[] memory approvals)
    {
        uint256 len = _countApprovals(configJson, key);
        approvals = new ApprovalConfig[](len);
        for (uint256 i; i < len; i++) {
            string memory baseKey = string.concat(key, "[", vm.toString(i), "]");
            approvals[i] = ApprovalConfig({
                asset: configJson.readAddress(string.concat(baseKey, ".asset")),
                approval: configJson.readBool(string.concat(baseKey, ".approval"))
            });
        }
    }

    function _countApprovals(string memory configJson, string memory key) internal view returns (uint256 len) {
        while (vm.keyExistsJson(configJson, string.concat(key, "[", vm.toString(len), "].asset"))) {
            len++;
        }
    }

    function _applyProtocolFeeRecipient(IEnhancedVaultConfigTarget vault, address desiredRecipient) internal {
        if (desiredRecipient != address(0) && vault.protocolFeeRecipient() != desiredRecipient) {
            console.log("Updating ProtocolFeeRecipient...");
            vault.setProtocolFeeRecipient(desiredRecipient);
        }
    }

    function _applyMarginPoolApprovals(IEnhancedVaultConfigTarget vault, ApprovalConfig[] memory approvals) internal {
        uint256 len = approvals.length;
        for (uint256 i; i < len; i++) {
            ApprovalConfig memory config = approvals[i];
            if (config.asset == address(0)) continue;
            console.log("Updating MarginPool asset approval...");
            vault.setAssetApprovalMarginPool(config.asset, config.approval);
        }
    }

    function _applySwapRouterApprovals(IEnhancedVaultConfigTarget vault, ApprovalConfig[] memory approvals) internal {
        uint256 len = approvals.length;
        for (uint256 i; i < len; i++) {
            ApprovalConfig memory config = approvals[i];
            if (config.asset == address(0)) continue;
            console.log("Updating SwapRouter asset approval...");
            vault.setAssetApprovalSwapRouter(config.asset, config.approval);
        }
    }
}

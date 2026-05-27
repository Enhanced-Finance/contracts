// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {EnhancedVault} from "src/periphery/vault/EnhancedVault.sol";
import {stdJson} from "forge-std/StdJson.sol";

/**
 * @notice Register a new vault on EnhancedVault.
 *
 * Required env vars:
 *   PRIVATE_KEY                   deployer (must be owner)
 *
 * Vault parameters are configured directly in this script via constants.
 */
contract CreateVault is Script {
    using stdJson for string;

    // --- Configuration: set these values directly before running ---
    uint256 constant VAULT_CYCLE_DURATION = 3600; // 1 hour
    address VAULT_UNDERLYING_ASSET = vm.envAddress("UNDERLYING");
    address VAULT_COLLATERAL_ASSET = vm.envAddress("UNDERLYING");
    address VAULT_STRIKE_ASSET = vm.envAddress("STRIKE");
    bool constant VAULT_IS_PUT = false; // true = put, false = call
    uint256 constant VAULT_CAPACITY = 1_000_000e18;
    uint256 constant VAULT_MIN_INVESTMENT = 1e16;
    uint256 constant VAULT_START_TIME = 1773280800; // > 0
    int256 constant VAULT_STRIKE_PRICE_BPS = 500; // precision: 10000 (e.g. 500 = +5%, -500 = -5%)
    uint256 constant VAULT_MIN_PRINCIPAL_RATIO = 9000; // precision: 10000 (e.g. 8000 = 80%)
    int256 constant VAULT_BUYBACK_PRICE_RATIO = -100; // precision: 10000 (can be negative)
    // --------------------------------------------------------------

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        uint256 chainId = block.chainid;
        string memory chainIdStr = vm.toString(chainId);
        string memory deployPath = string.concat(vm.projectRoot(), "/.deploy/", chainIdStr, ".json");

        require(vm.isFile(deployPath), "Deploy file not found");
        string memory deployJson = vm.readFile(deployPath);
        address vaultAddr = deployJson.readAddress(".EnhancedVault.proxyAddress");
        require(vaultAddr != address(0), "EnhancedVault proxy not found");

        EnhancedVault.VaultParams memory params = EnhancedVault.VaultParams({
            cycleDuration: VAULT_CYCLE_DURATION,
            underlyingAsset: VAULT_UNDERLYING_ASSET,
            collateralAsset: VAULT_COLLATERAL_ASSET,
            strikeAsset: VAULT_STRIKE_ASSET,
            isPut: VAULT_IS_PUT,
            capacity: VAULT_CAPACITY,
            minInvestmentAmount: VAULT_MIN_INVESTMENT,
            startTime: VAULT_START_TIME,
            strikePriceBps: VAULT_STRIKE_PRICE_BPS,
            minPrincipalRatio: VAULT_MIN_PRINCIPAL_RATIO,
            buybackPriceRatio: VAULT_BUYBACK_PRICE_RATIO
        });

        console.log("Creating vault on EnhancedVault:", vaultAddr);
        console.log("  cycleDuration:", params.cycleDuration);
        console.log("  underlyingAsset:", params.underlyingAsset);
        console.log("  collateralAsset:", params.collateralAsset);
        console.log("  strikeAsset:", params.strikeAsset);
        console.log("  isPut:", params.isPut);
        console.log("  capacity:", params.capacity);
        console.log("  minInvestmentAmount:", params.minInvestmentAmount);
        console.log("  startTime:", params.startTime);
        console.log("  strikePriceBps:", params.strikePriceBps);
        console.log("  minPrincipalRatio:", params.minPrincipalRatio);
        console.logInt(params.buybackPriceRatio);

        vm.startBroadcast(deployerPrivateKey);
        bytes32 vaultHash = EnhancedVault(vaultAddr).createVault(params);
        vm.stopBroadcast();

        console.log("Vault created. Hash:", vm.toString(vaultHash));
    }
}

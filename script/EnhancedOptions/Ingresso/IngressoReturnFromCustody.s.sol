// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {stdJson} from "lib/forge-std/src/StdJson.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {EnhancedOptions} from "src/core/EnhancedOptions.sol";

contract IngressoReturnFromCustody is Script {
    using stdJson for string;

    // --- Configuration: Set these values before running ---
    address constant OWNER = 0x0000000000000000000000000000000000000000; // maker
    uint256 constant VAULT_ID = 1;
    address constant ASSET = 0x0000000000000000000000000000000000000000;
    uint256 constant AMOUNT = 1e18;
    // ----------------------------------------------------

    function run() public {
        require(OWNER != address(0), "OWNER not set");
        require(ASSET != address(0), "ASSET not set");
        require(AMOUNT > 0, "AMOUNT not set");

        uint256 repayerPrivateKey = vm.envUint("REPAYER_PRIVATE_KEY");
        address repayer = vm.addr(repayerPrivateKey);

        address enhancedOptionsAddr = _loadEnhancedOptions();

        uint256[] memory vaultIds = new uint256[](1);
        vaultIds[0] = VAULT_ID;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = AMOUNT;

        console.log("Executing on:", enhancedOptionsAddr);
        console.log("Repayer:", repayer);
        console.log("owner:", OWNER);
        console.log("Vault ID:", VAULT_ID);
        console.log("Asset:", ASSET);
        console.log("Amount:", AMOUNT);

        vm.startBroadcast(repayerPrivateKey);
        IERC20 asset = IERC20(ASSET);
        uint256 allowance = asset.allowance(repayer, enhancedOptionsAddr);
        if (allowance < AMOUNT) {
            console.log("Approving token (repayer -> EnhancedOptions)...");
            asset.approve(enhancedOptionsAddr, type(uint256).max);
        }
        EnhancedOptions(enhancedOptionsAddr).ingressoReturnFromCustody(OWNER, vaultIds, amounts);
        vm.stopBroadcast();

        console.log("RepayBorrow executed successfully");
    }

    function _loadEnhancedOptions() internal view returns (address enhancedOptionsAddr) {
        uint256 chainId = block.chainid;
        string memory chainIdStr = vm.toString(chainId);
        string memory deployPath = string.concat(vm.projectRoot(), "/.deploy/", chainIdStr, ".json");

        require(vm.isFile(deployPath), "Deploy file not found");
        string memory deployJson = vm.readFile(deployPath);
        enhancedOptionsAddr = deployJson.readAddress(".EnhancedOptions.proxyAddress");
        require(enhancedOptionsAddr != address(0), "EnhancedOptions proxy not found");
    }
}

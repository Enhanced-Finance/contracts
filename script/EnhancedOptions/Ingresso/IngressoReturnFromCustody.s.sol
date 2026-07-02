// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {stdJson} from "lib/forge-std/src/StdJson.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {EnhancedOptions} from "src/core/EnhancedOptions.sol";

contract IngressoReturnFromCustody is Script {
    using stdJson for string;

    uint256 constant VAULT_ID = 1;
    uint256 constant AMOUNT = 1e18;

    function run() public {
        address owner = vm.envAddress("MAKER");
        address assetAddress = vm.envAddress("ASSET");
        require(owner != address(0), "MAKER not set");
        require(assetAddress != address(0), "ASSET not set");
        require(AMOUNT > 0, "AMOUNT not set");

        uint256 returnerPrivateKey = vm.envUint("RETURNER_PRIVATE_KEY");
        address returner = vm.addr(returnerPrivateKey);

        address enhancedOptionsAddr = _loadEnhancedOptions();

        uint256[] memory vaultIds = new uint256[](1);
        vaultIds[0] = VAULT_ID;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = AMOUNT;

        console.log("Executing on:", enhancedOptionsAddr);
        console.log("Returner:", returner);
        console.log("owner:", owner);
        console.log("Vault ID:", VAULT_ID);
        console.log("Asset:", assetAddress);
        console.log("Amount:", AMOUNT);

        vm.startBroadcast(returnerPrivateKey);
        IERC20 asset = IERC20(assetAddress);
        uint256 allowance = asset.allowance(returner, enhancedOptionsAddr);
        if (allowance < AMOUNT) {
            console.log("Approving token (returner -> EnhancedOptions)...");
            asset.approve(enhancedOptionsAddr, type(uint256).max);
        }
        EnhancedOptions(enhancedOptionsAddr).ingressoReturnFromCustody(owner, vaultIds, amounts);
        vm.stopBroadcast();

        console.log("IngressoReturnFromCustody executed successfully");
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

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {EnhancedOptions} from "src/core/EnhancedOptions.sol";
import {Parser} from "src/core/libs/Parser.sol";
import {stdJson} from "lib/forge-std/src/StdJson.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract IngressoTransferAsset is Script {
    using stdJson for string;

    // --- Configuration: Set these values before running ---
    // Example values provided
    address constant ASSET_ADDRESS = 0x134b5f74d65a34eb6F9CdaD5eD664b45A167cC43; // TUSDT
    uint256 constant CHAIN_ID = 1328;
    uint256 constant AMOUNT = 1000 * 1e18;
    bool constant IS_DEPOSIT = false;
    uint64 constant NONCE = 1;
    // ----------------------------------------------------

    bytes32 constant TRANSFER_TYPEHASH =
        keccak256("Transfer(address user,address asset,uint256 chainId,uint256 amount,bool isDeposit,uint64 nonce)");

    // Domain Separator components
    bytes32 constant EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 constant NAME_HASH = keccak256(bytes("enhanced"));
    bytes32 constant VERSION_HASH = keccak256(bytes("0.0.0"));

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        uint256 userPrivateKey = vm.envUint("USER_PRIVATE_KEY");
        address user = vm.addr(userPrivateKey);

        uint256 chainId = block.chainid;
        string memory chainIdStr = vm.toString(chainId);
        string memory deployPath = string.concat(vm.projectRoot(), "/.deploy/", chainIdStr, ".json");

        require(vm.isFile(deployPath), "Deploy file not found");
        string memory deployJson = vm.readFile(deployPath);
        address enhancedOptionsAddr = deployJson.readAddress(".EnhancedOptions.proxyAddress");
        require(enhancedOptionsAddr != address(0), "EnhancedOptions proxy not found");

        console.log("Executing IngressoTransferAsset on:", enhancedOptionsAddr);
        console.log("Caller (Operator):", deployer);
        console.log("User:", user);

        // 0. Approve Token (User -> MMarket)
        if (IS_DEPOSIT) {
            address mmarketAddr = deployJson.readAddress(".MMarket.proxyAddress");
            require(mmarketAddr != address(0), "MMarket proxy not found");

            console.log("Checking allowance for User -> MMarket...");
            vm.startBroadcast(userPrivateKey);
            IERC20 asset = IERC20(ASSET_ADDRESS);
            uint256 allowance = asset.allowance(user, mmarketAddr);
            if (allowance < AMOUNT) {
                console.log("Approving token...");
                asset.approve(mmarketAddr, type(uint256).max);
            }
            vm.stopBroadcast();
        }

        // 1. Prepare Struct
        Parser.Transfer memory transfer = Parser.Transfer({
            user: user, asset: ASSET_ADDRESS, chainId: CHAIN_ID, amount: AMOUNT, isDeposit: IS_DEPOSIT, nonce: NONCE, payer: address(0)
        });

        // 2. Sign Transfer (User)
        bytes32 domainSeparator = _buildDomainSeparator(enhancedOptionsAddr, chainId);
        bytes32 transferDigest = _getTransferDigest(transfer, domainSeparator);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, transferDigest);
        bytes memory sig = abi.encodePacked(r, s, v);

        // 3. Pack Payload
        // Manual packing to match Parser.sol expected layout (130 bytes)
        bytes memory payload = _packPayload(transfer, sig);

        // 4. Execute Transaction (Deployer/Operator)
        vm.startBroadcast(deployerPrivateKey);
        EnhancedOptions(enhancedOptionsAddr).ingressoTransferAsset(payload);
        vm.stopBroadcast();

        console.log("IngressoTransferAsset executed successfully");
    }

    function _buildDomainSeparator(address verifyingContract, uint256 chainId) internal pure returns (bytes32) {
        return keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, NAME_HASH, VERSION_HASH, chainId, verifyingContract));
    }

    function _getTransferDigest(Parser.Transfer memory t, bytes32 domainSeparator) internal pure returns (bytes32) {
        bytes32 structHash =
            keccak256(abi.encode(TRANSFER_TYPEHASH, t.user, t.asset, t.chainId, t.amount, t.isDeposit, t.nonce));
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }

    function _packPayload(Parser.Transfer memory t, bytes memory sig) internal pure returns (bytes memory) {
        // Based on Parser.sol assembly logic:
        // 0-20: asset
        // 20-36: amount
        // 36-37: isDeposit
        // 37-45: nonce
        // 45-110: sig (65 bytes)
        // 110-130: user

        return abi.encodePacked(
            t.asset, // 20
            uint128(t.amount), // 16
            bool(t.isDeposit), // 1
            uint64(t.nonce), // 8
            sig, // 65
            t.user // 20
        );
    }
}

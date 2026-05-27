// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {EnhancedOptions} from "src/core/EnhancedOptions.sol";
import {Parser} from "src/core/libs/Parser.sol";
import {stdJson} from "lib/forge-std/src/StdJson.sol";

contract IngressoOTCTrade is Script {
    using stdJson for string;

    // --- Configuration: Set these values before running ---
    // Example values provided
    address constant USER1 = 0x1234567890123456789012345678901234567890;
    address constant USER2 = 0x0987654321098765432109876543210987654321;
    address constant ASSET1 = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1; // WETH
    address constant ASSET2 = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8; // USDC
    uint256 constant CHAIN_ID = 42161;
    uint256 constant AMOUNT1 = 1e18;
    uint256 constant AMOUNT2 = 2000e6;
    uint64 constant NONCE = 1;
    // ----------------------------------------------------

    bytes32 constant OTC_TRADE_TYPEHASH = keccak256(
        "OtcTrade(uint256 chainId,address user1,address user2,address asset1,address asset2,uint256 amount1,uint256 amount2,uint64 nonce)"
    );

    // Domain Separator components
    bytes32 constant EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 constant NAME_HASH = keccak256(bytes("enhanced"));
    bytes32 constant VERSION_HASH = keccak256(bytes("0.0.0"));

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        uint256 chainId = block.chainid;
        string memory chainIdStr = vm.toString(chainId);
        string memory deployPath = string.concat(vm.projectRoot(), "/.deploy/", chainIdStr, ".json");

        require(vm.isFile(deployPath), "Deploy file not found");
        string memory deployJson = vm.readFile(deployPath);
        address enhancedOptionsAddr = deployJson.readAddress(".EnhancedOptions.proxyAddress");
        require(enhancedOptionsAddr != address(0), "EnhancedOptions proxy not found");

        console.log("Executing IngressoOTCTrade on:", enhancedOptionsAddr);
        console.log("Caller:", deployer);

        // 1. Prepare Struct
        Parser.OTCTrade memory otcTrade = Parser.OTCTrade({
            chainId: CHAIN_ID,
            user1: USER1,
            user2: USER2,
            asset1: ASSET1,
            asset2: ASSET2,
            amount1: AMOUNT1,
            amount2: AMOUNT2,
            nonce: NONCE
        });

        // 2. Sign OTC Trade (EnhancedSigner -> PRIVATE_KEY)
        bytes32 domainSeparator = _buildDomainSeparator(enhancedOptionsAddr, chainId);
        bytes32 otcDigest = _getOTCTradeDigest(otcTrade, domainSeparator);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(deployerPrivateKey, otcDigest);
        bytes memory sig = abi.encodePacked(r, s, v);

        // 3. Pack Payload
        // Manual packing to match Parser.sol expected layout (185 bytes)
        bytes memory payload = _packPayload(otcTrade, sig);

        // 4. Execute Transaction
        vm.startBroadcast(deployerPrivateKey);
        EnhancedOptions(enhancedOptionsAddr).ingressoOTCTrade(payload);
        vm.stopBroadcast();

        console.log("IngressoOTCTrade executed successfully");
    }

    function _buildDomainSeparator(address verifyingContract, uint256 chainId) internal pure returns (bytes32) {
        return keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, NAME_HASH, VERSION_HASH, chainId, verifyingContract));
    }

    function _getOTCTradeDigest(Parser.OTCTrade memory otc, bytes32 domainSeparator) internal pure returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(
                OTC_TRADE_TYPEHASH,
                otc.chainId,
                otc.user1,
                otc.user2,
                otc.asset1,
                otc.asset2,
                otc.amount1,
                otc.amount2,
                otc.nonce
            )
        );
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }

    function _packPayload(Parser.OTCTrade memory otc, bytes memory sig) internal pure returns (bytes memory) {
        // Based on Parser.sol assembly logic:
        // 0-20: user1
        // 20-40: user2
        // 40-60: asset1
        // 60-80: asset2
        // 80-96: amount1
        // 96-112: amount2
        // 112-120: nonce
        // 120-185: sig (65 bytes)

        return abi.encodePacked(
            otc.user1, // 20
            otc.user2, // 20
            otc.asset1, // 20
            otc.asset2, // 20
            uint128(otc.amount1), // 16
            uint128(otc.amount2), // 16
            uint64(otc.nonce), // 8
            sig // 65
        );
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {EnhancedOptions} from "src/core/EnhancedOptions.sol";
import {Parser} from "src/core/libs/Parser.sol";
import {stdJson} from "lib/forge-std/src/StdJson.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/// @notice Executes `ingressoMMarketDeposit`.
///
///         The payer signs the Transfer digest and funds the deposit.
///         When PAYER_ADDRESS is address(0), the user acts as their own payer
///         (falls back to USER_PRIVATE_KEY for signing and USER address for funding).
///
///         Payload layout (150 bytes with payer, 130 bytes without):
///           0–19   asset (20)
///          20–35   amount (16)
///             36   isDeposit (1)
///          37–44   nonce (8)
///          45–109  signature (65)
///         110–129  user (20)
///         130–149  payer (20, optional — omit to use 130-byte format with payer=address(0))
contract IngressoMMarketDeposit is Script {
    using stdJson for string;

    // --- Configuration: Set these values before running ---
    uint256 constant CHAIN_ID = 11155111;
    uint256 constant AMOUNT = 5000 * 1e6;
    uint64 constant NONCE = 6;
    // ----------------------------------------------------

    bytes32 constant TRANSFER_TYPEHASH =
        keccak256("Transfer(address user,address asset,uint256 chainId,uint256 amount,bool isDeposit,uint64 nonce)");

    bytes32 constant EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 constant NAME_HASH = keccak256(bytes("enhanced"));
    bytes32 constant VERSION_HASH = keccak256(bytes("0.0.0"));

    function run() public {
        address ASSET_ADDRESS = vm.envAddress("STRIKE"); // TUSDT
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        uint256 userPrivateKey = vm.envUint("USER_PRIVATE_KEY");
        address user = vm.addr(userPrivateKey);

        // Payer defaults to user when PAYER is not set.
        address payerAddress = vm.envOr("PAYER", address(0));
        bool hasDedicatedPayer = payerAddress != address(0);
        address payer = hasDedicatedPayer ? payerAddress : user;

        uint256 payerPrivateKey;
        if (hasDedicatedPayer) {
            payerPrivateKey = vm.envUint("PAYER_PRIVATE_KEY");
            require(vm.addr(payerPrivateKey) == payer, "PAYER_PRIVATE_KEY does not match PAYER_ADDRESS");
        } else {
            payerPrivateKey = userPrivateKey;
        }

        uint256 chainId = block.chainid;
        string memory chainIdStr = vm.toString(chainId);
        string memory deployPath = string.concat(vm.projectRoot(), "/.deploy/", chainIdStr, ".json");

        require(vm.isFile(deployPath), "Deploy file not found");
        string memory deployJson = vm.readFile(deployPath);
        address enhancedOptionsAddr = deployJson.readAddress(".EnhancedOptions.proxyAddress");
        require(enhancedOptionsAddr != address(0), "EnhancedOptions proxy not found");
        address mmarketAddr = deployJson.readAddress(".MMarket.proxyAddress");
        require(mmarketAddr != address(0), "MMarket proxy not found");

        console.log("Executing IngressoMMarketDeposit on:", enhancedOptionsAddr);
        console.log("Caller (Operator):", deployer);
        console.log("User:", user);
        console.log("Payer:", payer);

        // 0. Approve token: payer -> MMarket
        vm.startBroadcast(payerPrivateKey);
        IERC20 asset = IERC20(ASSET_ADDRESS);
        uint256 allowance = asset.allowance(payer, mmarketAddr);
        if (allowance < AMOUNT) {
            console.log("Approving token (payer -> MMarket)...");
            asset.approve(mmarketAddr, type(uint256).max);
        }
        vm.stopBroadcast();

        // 1. Prepare struct (isDeposit always true for ingressoMMarketDeposit)
        Parser.Transfer memory transfer = Parser.Transfer({
            user: user,
            asset: ASSET_ADDRESS,
            chainId: CHAIN_ID,
            amount: AMOUNT,
            isDeposit: true,
            nonce: NONCE,
            payer: hasDedicatedPayer ? payer : address(0)
        });

        // 2. Sign Transfer digest (payer signs)
        bytes32 domainSeparator = _buildDomainSeparator(enhancedOptionsAddr, chainId);
        bytes32 transferDigest = _getTransferDigest(transfer, domainSeparator);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(payerPrivateKey, transferDigest);
        bytes memory sig = abi.encodePacked(r, s, v);

        // 3. Pack payload
        bytes memory payload =
            hasDedicatedPayer ? _packPayloadWithPayer(transfer, sig, payer) : _packPayload(transfer, sig);

        // 4. Execute (operator)
        vm.startBroadcast(deployerPrivateKey);
        EnhancedOptions(enhancedOptionsAddr).ingressoMMarketDeposit(payload);
        vm.stopBroadcast();

        console.log("IngressoMMarketDeposit executed successfully");
    }

    function _buildDomainSeparator(address verifyingContract, uint256 chainId) internal pure returns (bytes32) {
        return keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, NAME_HASH, VERSION_HASH, chainId, verifyingContract));
    }

    function _getTransferDigest(Parser.Transfer memory t, bytes32 domainSeparator) internal pure returns (bytes32) {
        // payer is NOT included in the signed digest — it is operator-controlled routing metadata.
        bytes32 structHash =
            keccak256(abi.encode(TRANSFER_TYPEHASH, t.user, t.asset, t.chainId, t.amount, t.isDeposit, t.nonce));
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }

    /// @dev 130-byte payload (no payer). effectivePayer = user.
    function _packPayload(Parser.Transfer memory t, bytes memory sig) internal pure returns (bytes memory) {
        return abi.encodePacked(
            t.asset, // 20
            uint128(t.amount), // 16
            bool(t.isDeposit), // 1
            uint64(t.nonce), // 8
            sig, // 65
            t.user // 20
        );
    }

    /// @dev 150-byte payload (with payer appended). effectivePayer = payer.
    function _packPayloadWithPayer(Parser.Transfer memory t, bytes memory sig, address payer)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodePacked(
            t.asset, // 20
            uint128(t.amount), // 16
            bool(t.isDeposit), // 1
            uint64(t.nonce), // 8
            sig, // 65
            t.user, // 20
            payer // 20
        );
    }
}

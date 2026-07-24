// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console} from "forge-std/Script.sol";
import {EnhancedVault} from "src/periphery/vault/EnhancedVault.sol";
import {Parser} from "src/core/libs/Parser.sol";
import {BaseEnhancedVaultScript} from "./BaseEnhancedVaultScript.s.sol";

contract CreateOrder is BaseEnhancedVaultScript {
    address ASSET_ADDRESS = vm.envAddress("UNDERLYING");
    bool constant IS_PUT = false;
    bool constant IS_PHYSICALLY_SETTLED = false;
    uint256 constant STRIKE = 4601520;
    uint64 constant EXPIRY = 1775548800;
    uint64 constant NONCE = 6;
    uint256 constant PRICE = 100000000000000000;
    uint256 constant QUOTE_QUANTITY = 47000000000000000000000;
    uint256 constant QUANTITY = 47000000000000000000000;
    bool constant IS_TAKER_BUY = true;
    uint64 constant VALID_UNTIL = 1800000000;
    address USD = vm.envAddress("STRIKE");
    address COLLATERAL_ASSET = vm.envAddress("UNDERLYING");
    uint256 constant COLLATERAL_AMOUNT = 47000000000000000000000;
    uint256 constant MAKER_FEE = 0;
    uint256 constant TAKER_FEE = 0;
    // -----------------------------------------------------

    bytes32 constant QUOTE_TYPEHASH = keccak256(
        "Quote(address assetAddress,uint256 chainId,bool isPut,bool isPhysicallySettled,uint256 strike,uint64 expiry,address maker,uint64 nonce,uint256 price,uint256 quantity,bool isTakerBuy,uint64 validUntil,address usd,address collateralAsset)"
    );
    bytes32 constant VAULT_ORDER_TYPEHASH = keccak256("VaultOrder(bytes32 vaultHash,bytes32 payloadHash)");
    bytes32 constant EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 constant ENHANCED_NAME_HASH = keccak256(bytes("enhanced"));
    bytes32 constant ENHANCED_VERSION_HASH = keccak256(bytes("0.0.0"));
    bytes32 constant VAULT_NAME_HASH = keccak256(bytes("Vault"));
    bytes32 constant VAULT_VERSION_HASH = keccak256(bytes("0.0.0"));

    function run() public {
        // vaultSigner signature -> PRIVATE_KEY
        uint256 vaultSignerPrivateKey = vm.envUint("PRIVATE_KEY");
        uint256 operatorPrivateKey = vm.envOr("OPERATOR_PRIVATE_KEY", vaultSignerPrivateKey);
        bytes32 vaultHash = vm.envBytes32("VAULT_HASH");
        // maker quote signature -> MAKER_PRIVATE_KEY
        uint256 makerPrivateKey = vm.envUint("MAKER_PRIVATE_KEY");
        bool useTrustedMaker = vm.envOr("USE_TRUSTED_MAKER", true);
        address maker = vm.addr(makerPrivateKey);

        (EnhancedVault vault, address vaultAddr) = _loadVault();
        address enhancedOptionsAddr = address(vault.enhancedOptions());
        require(enhancedOptionsAddr != address(0), "EnhancedOptions not set");

        bytes memory payload = _buildPayload(enhancedOptionsAddr, makerPrivateKey, maker, vaultAddr);
        bytes memory vaultSig = _buildVaultSignature(vaultAddr, vaultSignerPrivateKey, vaultHash, payload);

        console.log("EnhancedVault:", vaultAddr);
        console.log("EnhancedOptions:", enhancedOptionsAddr);
        console.log("vaultHash:", vm.toString(vaultHash));
        console.log("maker:", maker);
        console.log("useTrustedMaker:", useTrustedMaker);
        console.log("vaultSig:", vm.toString(vaultSig));
        console.log("payload:", vm.toString(payload));
        console.log("payloadLength:", payload.length);

        vm.startBroadcast(operatorPrivateKey);
        vault.createOrder(vaultHash, payload, vaultSig, useTrustedMaker);
        vm.stopBroadcast();
    }

    function _buildPayload(address enhancedOptionsAddr, uint256 makerPrivateKey, address maker, address taker)
        internal
        view
        returns (bytes memory payload)
    {
        Parser.Quote memory quote = Parser.Quote({
            assetAddress: ASSET_ADDRESS,
            chainId: block.chainid,
            isPut: IS_PUT,
            isPhysicallySettled: IS_PHYSICALLY_SETTLED,
            strike: STRIKE,
            expiry: EXPIRY,
            maker: maker,
            nonce: NONCE,
            price: PRICE,
            quantity: QUOTE_QUANTITY,
            isTakerBuy: IS_TAKER_BUY,
            validUntil: VALID_UNTIL,
            usd: USD,
            collateralAsset: COLLATERAL_ASSET
        });

        Parser.Confirmation memory confirmation = Parser.Confirmation({
            maker: maker,
            assetAddress: ASSET_ADDRESS,
            chainId: block.chainid,
            expiry: EXPIRY,
            isPut: IS_PUT,
            isPhysicallySettled: IS_PHYSICALLY_SETTLED,
            nonce: NONCE,
            price: PRICE,
            quantity: QUANTITY,
            quoteNonce: NONCE,
            quoteSignature: bytes(""),
            strike: STRIKE,
            taker: taker,
            isTakerBuy: IS_TAKER_BUY,
            usd: USD,
            collateralAsset: COLLATERAL_ASSET,
            collateralAmount: COLLATERAL_AMOUNT
        });

        bytes32 enhancedDomainSeparator = keccak256(
            abi.encode(
                EIP712_DOMAIN_TYPEHASH, ENHANCED_NAME_HASH, ENHANCED_VERSION_HASH, block.chainid, enhancedOptionsAddr
            )
        );

        bytes32 quoteStructHash = keccak256(
            abi.encode(
                QUOTE_TYPEHASH,
                quote.assetAddress,
                quote.chainId,
                quote.isPut,
                quote.isPhysicallySettled,
                quote.strike,
                quote.expiry,
                quote.maker,
                quote.nonce,
                quote.price,
                quote.quantity,
                quote.isTakerBuy,
                quote.validUntil,
                quote.usd,
                quote.collateralAsset
            )
        );
        bytes32 quoteDigest = keccak256(abi.encodePacked("\x19\x01", enhancedDomainSeparator, quoteStructHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(makerPrivateKey, quoteDigest);
        bytes memory quoteSig = abi.encodePacked(r, s, v);
        bytes memory confSig = new bytes(65);

        console.log("quoteSig:", vm.toString(quoteSig));
        payload = abi.encodePacked(
            confirmation.maker,
            quote.assetAddress,
            uint64(quote.expiry),
            quote.isPut,
            quote.isPhysicallySettled,
            uint64(confirmation.nonce),
            uint128(quote.price),
            uint128(quote.quantity),
            uint128(confirmation.quantity),
            uint64(quote.nonce),
            quoteSig,
            confSig,
            uint128(quote.strike),
            confirmation.taker,
            quote.isTakerBuy,
            uint64(quote.validUntil),
            quote.usd,
            quote.collateralAsset,
            uint128(confirmation.collateralAmount),
            uint128(MAKER_FEE),
            uint128(TAKER_FEE)
        );
    }

    function _buildVaultSignature(
        address vaultAddr,
        uint256 vaultSignerPrivateKey,
        bytes32 vaultHash,
        bytes memory payload
    ) internal view returns (bytes memory vaultSig) {
        bytes32 vaultDomainSeparator = keccak256(
            abi.encode(EIP712_DOMAIN_TYPEHASH, VAULT_NAME_HASH, VAULT_VERSION_HASH, block.chainid, vaultAddr)
        );
        bytes32 orderStructHash = keccak256(abi.encode(VAULT_ORDER_TYPEHASH, vaultHash, keccak256(payload)));
        bytes32 orderDigest = keccak256(abi.encodePacked("\x19\x01", vaultDomainSeparator, orderStructHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(vaultSignerPrivateKey, orderDigest);
        vaultSig = abi.encodePacked(r, s, v);
    }
}

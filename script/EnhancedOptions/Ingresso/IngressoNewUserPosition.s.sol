// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {EnhancedOptions} from "src/core/EnhancedOptions.sol";
import {Parser} from "src/core/libs/Parser.sol";
import {stdJson} from "lib/forge-std/src/StdJson.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract IngressoNewUserPosition is Script {
    using stdJson for string;

    // --- Configuration: Set these values before running ---
    // Example values provided
    address ASSET_ADDRESS = vm.envAddress("UNDERLYING"); // Underlying asset address (e.g., TWSEI)
    uint256 constant CHAIN_ID = 1328; // Chain ID
    bool constant IS_PUT = false; // true = Put option, false = Call option
    bool constant IS_PHYSICALLY_SETTLED = false; // true = Physical settlement, false = Cash settlement
    uint256 constant STRIKE = 6670000; // 2000 * 1e8;  Strike price, fixed 8 decimals (e.g., 2000 USDC = 2000e8)
    uint64 constant EXPIRY = 1772792700; // Expiry timestamp (seconds)
    // address constant MAKER = ...; // Derived from MAKER_PRIVATE_KEY
    uint64 constant NONCE = 6; // Transaction Nonce to prevent replay attacks
    uint256 constant PRICE = 687e12; // Quote price (Option Premium), 18 decimals
    uint256 constant QUOTE_QUANTITY = 1000000 * 1e18; // Quoted size in the maker quote, 18 decimals
    uint256 constant QUANTITY = 1000000 * 1e18; // Purchase quantity, 18 decimals (1 unit = 1e18)
    bool constant IS_TAKER_BUY = true; // true = Taker buys (Maker sells), false = Taker sells (Maker buys)
    uint64 constant VALID_UNTIL = 1800000000; // Expiration timestamp for this quote
    address constant USD = 0x134b5f74d65a34eb6F9CdaD5eD664b45A167cC43; // Quote asset/Stablecoin address (e.g., TUSDT)
    address COLLATERAL_ASSET = vm.envAddress("UNDERLYING"); // Collateral asset address (usually Underlying for Call, Stablecoin for Put)
    uint256 constant COLLATERAL_AMOUNT = 1000000 * 1e18; // Collateral amount, decimals depend on the asset (e.g., 1 WETH = 1e18)
    uint256 constant FEE = 687e16; // Transaction fee (if any)
    // ----------------------------------------------------

    bytes32 constant QUOTE_TYPEHASH = keccak256(
        "Quote(address assetAddress,uint256 chainId,bool isPut,bool isPhysicallySettled,uint256 strike,uint64 expiry,address maker,uint64 nonce,uint256 price,uint256 quantity,bool isTakerBuy,uint64 validUntil,address usd,address collateralAsset)"
    );
    bytes32 constant CONFIRMATION_TYPEHASH = keccak256(
        "Confirmation(address maker,address assetAddress,uint256 chainId,uint64 expiry,bool isPut,bool isPhysicallySettled,uint64 nonce,uint256 price,uint256 quantity,uint64 quoteNonce,bytes quoteSignature,uint256 strike,address taker,bool isTakerBuy,address usd,address collateralAsset,uint256 collateralAmount)"
    );

    // Domain Separator components (must match deployed contract)
    bytes32 constant EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 constant NAME_HASH = keccak256(bytes("enhanced"));
    bytes32 constant VERSION_HASH = keccak256(bytes("0.0.0"));

    function run() public {
        // 1. Load Keys and Addresses
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        uint256 makerPrivateKey = vm.envUint("MAKER_PRIVATE_KEY");
        address maker = vm.addr(makerPrivateKey);

        uint256 takerPrivateKey = vm.envUint("TAKER_PRIVATE_KEY");
        address taker = vm.addr(takerPrivateKey);

        console.log("Deployer (Operator):", deployer);
        console.log("Maker:", maker);
        console.log("Taker:", taker);

        uint256 chainId = block.chainid;
        string memory chainIdStr = vm.toString(chainId);
        string memory deployPath = string.concat(vm.projectRoot(), "/.deploy/", chainIdStr, ".json");

        require(vm.isFile(deployPath), "Deploy file not found");
        string memory deployJson = vm.readFile(deployPath);
        address enhancedOptionsAddr = deployJson.readAddress(".EnhancedOptions.proxyAddress");
        require(enhancedOptionsAddr != address(0), "EnhancedOptions proxy not found");

        console.log("Executing IngressoNewUserPosition on:", enhancedOptionsAddr);

        // 0. Approve Token (Taker -> MarginPool)
        // If Taker is buying (IS_TAKER_BUY = true) and IS_PUT = false (Call), they might need to pay premium?
        // Logic depends on what Taker is transferring.
        // Assuming Taker provides Collateral or Premium.
        // For simplicity here, we approve COLLATERAL_ASSET if amount > 0
        if (COLLATERAL_AMOUNT > 0) {
            address marginPoolAddr = deployJson.readAddress(".MarginPool.proxyAddress");
            require(marginPoolAddr != address(0), "MarginPool proxy not found");

            console.log("Checking allowance for Taker -> MarginPool...");
            vm.startBroadcast(takerPrivateKey);
            IERC20 asset = IERC20(COLLATERAL_ASSET);
            uint256 allowance = asset.allowance(taker, marginPoolAddr);
            if (allowance < COLLATERAL_AMOUNT) {
                console.log("Approving token...");
                asset.approve(marginPoolAddr, type(uint256).max);
            }
            vm.stopBroadcast();
        }

        // 2. Prepare Structs
        Parser.Quote memory quote = Parser.Quote({
            assetAddress: ASSET_ADDRESS,
            chainId: CHAIN_ID,
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
            chainId: CHAIN_ID,
            expiry: EXPIRY,
            isPut: IS_PUT,
            isPhysicallySettled: IS_PHYSICALLY_SETTLED,
            nonce: NONCE, // confirmation nonce
            price: PRICE,
            quantity: QUANTITY,
            quoteNonce: NONCE, // same as quote nonce
            quoteSignature: bytes(""), // Placeholder, will be filled
            strike: STRIKE,
            taker: taker,
            isTakerBuy: IS_TAKER_BUY,
            usd: USD,
            collateralAsset: COLLATERAL_ASSET,
            collateralAmount: COLLATERAL_AMOUNT
        });

        // 3. Sign Quote (Maker)
        bytes32 domainSeparator = _buildDomainSeparator(enhancedOptionsAddr, chainId);

        bytes32 quoteDigest = _getQuoteDigest(quote, domainSeparator);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(makerPrivateKey, quoteDigest);
        bytes memory quoteSig = abi.encodePacked(r, s, v);

        // Fill confirmation with quote signature
        confirmation.quoteSignature = quoteSig;

        // 4. Sign Confirmation (Taker)
        bytes32 confDigest = _getConfirmationDigest(confirmation, domainSeparator);
        (v, r, s) = vm.sign(takerPrivateKey, confDigest);
        bytes memory confSig = abi.encodePacked(r, s, v);

        // 5. Pack Payload
        // Manual packing to match Parser.sol expected layout (361 bytes)
        bytes memory payload = _packPayload(quote, confirmation, quoteSig, confSig, FEE);

        // 6. Execute Transaction (Deployer/Operator)
        vm.startBroadcast(deployerPrivateKey);
        EnhancedOptions(enhancedOptionsAddr).ingressoNewUserPosition(payload);
        vm.stopBroadcast();

        console.log("IngressoNewUserPosition executed successfully");
    }

    function _buildDomainSeparator(address verifyingContract, uint256 chainId) internal pure returns (bytes32) {
        return keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, NAME_HASH, VERSION_HASH, chainId, verifyingContract));
    }

    function _getQuoteDigest(Parser.Quote memory q, bytes32 domainSeparator) internal pure returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(
                QUOTE_TYPEHASH,
                q.assetAddress,
                q.chainId,
                q.isPut,
                q.isPhysicallySettled,
                q.strike,
                q.expiry,
                q.maker,
                q.nonce,
                q.price,
                q.quantity,
                q.isTakerBuy,
                q.validUntil,
                q.usd,
                q.collateralAsset
            )
        );
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }

    function _getConfirmationDigest(Parser.Confirmation memory c, bytes32 domainSeparator)
        internal
        pure
        returns (bytes32)
    {
        bytes32 sigHash = keccak256(c.quoteSignature);
        bytes32 structHash = keccak256(
            abi.encodePacked(
                abi.encode(
                    CONFIRMATION_TYPEHASH,
                    c.maker,
                    c.assetAddress,
                    c.chainId,
                    c.expiry,
                    c.isPut,
                    c.isPhysicallySettled,
                    c.nonce,
                    c.price
                ),
                abi.encode(
                    c.quantity,
                    c.quoteNonce,
                    sigHash,
                    c.strike,
                    c.taker,
                    c.isTakerBuy,
                    c.usd,
                    c.collateralAsset,
                    c.collateralAmount
                )
            )
        );
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }

    function _packPayload(
        Parser.Quote memory q,
        Parser.Confirmation memory c,
        bytes memory quoteSig,
        bytes memory confSig,
        uint256 fee
    ) internal pure returns (bytes memory) {
        // Based on Parser.sol assembly logic:
        // 0-20: maker
        // 20-40: assetAddress
        // 40-48: expiry
        // 48-49: isPut
        // 49-50: isPhysicallySettled
        // 50-58: nonce (conf)
        // 58-74: price
        // 74-90: quoteQuantity
        // 90-106: confirmationQuantity
        // 106-114: quoteNonce
        // 114-179: quoteSig (65 bytes)
        // 179-244: confSig (65 bytes)
        // 244-260: strike
        // 260-280: taker
        // 280-281: isTakerBuy
        // 281-289: validUntil
        // 289-309: usd
        // 309-329: collateralAsset
        // 329-345: collateralAmount
        // 345-361: fee

        return abi.encodePacked(
            c.maker, // 20
            q.assetAddress, // 20
            uint64(q.expiry), // 8
            bool(q.isPut), // 1
            bool(q.isPhysicallySettled), // 1
            uint64(c.nonce), // 8
            uint128(q.price), // 16
            uint128(q.quantity), // 16
            uint128(c.quantity), // 16
            uint64(q.nonce), // 8
            quoteSig, // 65
            confSig, // 65
            uint128(q.strike), // 16
            c.taker, // 20
            bool(q.isTakerBuy), // 1
            uint64(q.validUntil), // 8
            q.usd, // 20
            q.collateralAsset, // 20
            uint128(c.collateralAmount), // 16
            uint128(fee) // 16
        );
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {stdJson} from "lib/forge-std/src/StdJson.sol";
import {EnhancedOptions} from "src/core/EnhancedOptions.sol";

contract IngressoReleaseCollateralToCustody is Script {
    using stdJson for string;

    // --- Configuration: Set these values before running ---
    address constant VAULT_OWNER = 0x56E49A068e368F2D40FFE9314033671CF3402eC1;
    address constant RECEIVER = 0xD157F637262B0E6Af035baa35a5475E56b100D1b;
    uint64 constant NONCE = 1777271783;
    uint64 constant VALID_UNTIL = 1877279100;

    uint256 constant VAULT_ID = 5;
    address constant ASSET = 0x5cc75d8c5D9A22AC35D7cb734159b2Da5554981f;
    uint256 constant AMOUNT = 5000000000000000000;
    // ----------------------------------------------------

    bytes32 constant CUSTODY_RELEASE_TYPEHASH = keccak256(
        "CustodyRelease(address maker,address receiver,uint256 chainId,uint64 nonce,uint64 validUntil,bytes32 requestsHash)"
    );
    bytes32 constant CUSTODY_RELEASE_REQUEST_TYPEHASH =
        keccak256("CustodyReleaseRequest(address owner,uint256 vaultId,address asset,uint256 amount)");

    bytes32 constant EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 constant NAME_HASH = keccak256(bytes("enhanced"));
    bytes32 constant VERSION_HASH = keccak256(bytes("0.0.0"));

    function run() public {
        require(RECEIVER != address(0), "RECEIVER not set");
        require(ASSET != address(0), "ASSET not set");
        require(AMOUNT > 0, "AMOUNT not set");

        uint256 operatorPrivateKey = vm.envUint("PRIVATE_KEY");
        address operator = vm.addr(operatorPrivateKey);

        uint256 makerPrivateKey = vm.envUint("MAKER_PRIVATE_KEY");
        address maker = vm.addr(makerPrivateKey);

        address enhancedOptionsAddr = _loadEnhancedOptions();

        EnhancedOptions.CustodyReleaseRequest[] memory requests = new EnhancedOptions.CustodyReleaseRequest[](1);
        requests[0] =
            EnhancedOptions.CustodyReleaseRequest({owner: VAULT_OWNER, vaultId: VAULT_ID, asset: ASSET, amount: AMOUNT});

        bytes32 domainSeparator = _buildDomainSeparator(enhancedOptionsAddr, block.chainid);
        bytes32 borrowDigest = _getBorrowDigest(maker, RECEIVER, NONCE, VALID_UNTIL, requests, domainSeparator);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(makerPrivateKey, borrowDigest);
        bytes memory signature = abi.encodePacked(r, s, v);

        console.log("Executing IngressoBorrowUnderlying on:", enhancedOptionsAddr);
        console.log("Caller (Operator):", operator);
        console.log("Maker:", maker);
        console.log("Receiver:", RECEIVER);
        console.log("Vault ID:", VAULT_ID);
        console.log("Asset:", ASSET);
        console.log("Amount:", AMOUNT);

        vm.startBroadcast(operatorPrivateKey);
        EnhancedOptions(enhancedOptionsAddr)
            .ingressoReleaseCollateralToCustody(maker, RECEIVER, NONCE, VALID_UNTIL, requests, signature);
        vm.stopBroadcast();

        console.log("IngressoBorrowUnderlying executed successfully");
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

    function _buildDomainSeparator(address verifyingContract, uint256 chainId) internal pure returns (bytes32) {
        return keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, NAME_HASH, VERSION_HASH, chainId, verifyingContract));
    }

    function _getBorrowDigest(
        address maker,
        address receiver,
        uint64 nonce,
        uint64 validUntil,
        EnhancedOptions.CustodyReleaseRequest[] memory requests,
        bytes32 domainSeparator
    ) internal view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(CUSTODY_RELEASE_TYPEHASH, maker, receiver, block.chainid, nonce, validUntil, _requestsHash(requests))
        );
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }

    function _requestsHash(EnhancedOptions.CustodyReleaseRequest[] memory requests) internal pure returns (bytes32) {
        bytes32[] memory hashes = new bytes32[](requests.length);
        for (uint256 i = 0; i < requests.length; i++) {
            hashes[i] = keccak256(
                abi.encode(
                    CUSTODY_RELEASE_REQUEST_TYPEHASH,
                    requests[i].owner,
                    requests[i].vaultId,
                    requests[i].asset,
                    requests[i].amount
                )
            );
        }
        return keccak256(abi.encodePacked(hashes));
    }
}

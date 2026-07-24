// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {stdJson} from "lib/forge-std/src/StdJson.sol";
import {EnhancedOptions} from "src/core/EnhancedOptions.sol";

contract IngressoReleaseCollateralToCustody is Script {
    using stdJson for string;

    uint64 constant NONCE = 1777271783;
    uint64 constant VALID_UNTIL = 1877279100;

    uint256 constant VAULT_ID = 5;
    uint256 constant AMOUNT = 5000000000000000000;

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
        address vaultOwner = vm.envAddress("VAULT_OWNER");
        address receiver = vm.envAddress("RECEIVER");
        address asset = vm.envAddress("ASSET");
        require(receiver != address(0), "RECEIVER not set");
        require(asset != address(0), "ASSET not set");
        require(AMOUNT > 0, "AMOUNT not set");

        uint256 custodyOperatorPrivateKey = vm.envOr("CUSTODY_OPERATOR_PRIVATE_KEY", uint256(0));
        if (custodyOperatorPrivateKey == 0) {
            custodyOperatorPrivateKey = vm.envUint("PRIVATE_KEY");
        }
        address custodyOperator = vm.addr(custodyOperatorPrivateKey);

        uint256 makerPrivateKey = vm.envUint("MAKER_PRIVATE_KEY");
        address maker = vm.addr(makerPrivateKey);

        address enhancedOptionsAddr = _loadEnhancedOptions();

        EnhancedOptions.CustodyReleaseRequest[] memory requests = new EnhancedOptions.CustodyReleaseRequest[](1);
        requests[0] =
            EnhancedOptions.CustodyReleaseRequest({owner: vaultOwner, vaultId: VAULT_ID, asset: asset, amount: AMOUNT});

        bytes32 domainSeparator = _buildDomainSeparator(enhancedOptionsAddr, block.chainid);
        bytes32 custodyReleaseDigest =
            _getCustodyReleaseDigest(maker, receiver, NONCE, VALID_UNTIL, requests, domainSeparator);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(makerPrivateKey, custodyReleaseDigest);
        bytes memory signature = abi.encodePacked(r, s, v);

        console.log("Executing IngressoReleaseCollateralToCustody on:", enhancedOptionsAddr);
        console.log("Caller (CustodyOperator):", custodyOperator);
        console.log("Maker:", maker);
        console.log("Receiver:", receiver);
        console.log("Vault ID:", VAULT_ID);
        console.log("Asset:", asset);
        console.log("Amount:", AMOUNT);

        vm.startBroadcast(custodyOperatorPrivateKey);
        EnhancedOptions(enhancedOptionsAddr)
            .ingressoReleaseCollateralToCustody(maker, receiver, NONCE, VALID_UNTIL, requests, signature);
        vm.stopBroadcast();

        console.log("IngressoReleaseCollateralToCustody executed successfully");
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

    function _getCustodyReleaseDigest(
        address maker,
        address receiver,
        uint64 nonce,
        uint64 validUntil,
        EnhancedOptions.CustodyReleaseRequest[] memory requests,
        bytes32 domainSeparator
    ) internal view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(
                CUSTODY_RELEASE_TYPEHASH, maker, receiver, block.chainid, nonce, validUntil, _requestsHash(requests)
            )
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

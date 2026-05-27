// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {ManualPricer} from "src/core/ManualPricer.sol";
import {Strings} from "lib/openzeppelin-contracts/contracts/utils/Strings.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {ERC1967Proxy} from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployManualPricerProxy is Script {
    using Strings for uint256;
    using Strings for address;
    using stdJson for string;

    struct AssetConfig {
        address assetAddress;       // JSON key: "address"
        address bot;                // JSON key: "bot"
        uint256 deviationMultiplier;// JSON key: "deviationMultiplier"
        address owner;              // JSON key: "owner"
        uint256 priceTimeValidity;  // JSON key: "priceTimeValidity"
        string symbol;              // JSON key: "symbol"
    }

    struct DeployContext {
        uint256 deployerPrivateKey;
        address implementation;
        string path;
        string chainIdStr;
        address oracleAddr;
        address addressBookAddr;
    }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        uint256 chainId = block.chainid;
        string memory chainIdStr = chainId.toString();

        string memory configPath = string.concat(vm.projectRoot(), "/config/", chainIdStr, ".json");
        require(vm.isFile(configPath), "Config file not found");
        string memory configJson = vm.readFile(configPath);

        // Read assets array - ensure struct fields are ALPHABETICALLY ordered by JSON key
        AssetConfig[] memory assets = abi.decode(configJson.parseRaw(".ManualPricer.assets"), (AssetConfig[]));
        require(assets.length > 0, "No assets found in config");

        string memory deployDir = string.concat(vm.projectRoot(), "/.deploy/");
        string memory path = string.concat(deployDir, chainIdStr, ".json");
        require(vm.isFile(path), "Deploy file not found");
        string memory existingDeployJson = vm.readFile(path);

        // Read Implementation address
        address implementation;
        if (vm.keyExists(existingDeployJson, ".ManualPricer_Implementation.implementationAddress")) {
            implementation = existingDeployJson.readAddress(".ManualPricer_Implementation.implementationAddress");
            console.log("Using existing ManualPricer Implementation at:", implementation);
        } else {
            revert("ManualPricer Implementation not found. Run DeployManualPricerImplementation.s.sol first.");
        }
        
        // Read common dependencies ONCE
        address oracleAddr = existingDeployJson.readAddress(".Oracle.proxyAddress");
        address addressBookAddr = existingDeployJson.readAddress(".AddressBook.proxyAddress");
        require(oracleAddr != address(0), "Oracle proxy not found");
        require(addressBookAddr != address(0), "AddressBook proxy not found");

        DeployContext memory context = DeployContext({
            deployerPrivateKey: deployerPrivateKey,
            implementation: implementation,
            path: path,
            chainIdStr: chainIdStr,
            oracleAddr: oracleAddr,
            addressBookAddr: addressBookAddr
        });

        // Loop through assets and deploy Proxy for each
        for (uint256 i = 0; i < assets.length; i++) {
            string memory symbol = assets[i].symbol;
            address assetAddr = assets[i].assetAddress;
            string memory key = string.concat("ManualPricer-", symbol);

            if (vm.keyExists(existingDeployJson, string.concat(".", key))) {
                console.log("Skipping existing ManualPricer for:", symbol);
                continue;
            }

            console.log("Deploying ManualPricer Proxy for:", symbol, assetAddr);

            _deployProxy(context, assets[i], key);
        }
    }

    function _deployProxy(
        DeployContext memory context,
        AssetConfig memory assetConfig,
        string memory key
    ) internal {
        address bot = assetConfig.bot;
        address owner = assetConfig.owner;
        address asset = assetConfig.assetAddress;

        require(bot != address(0), "Bot address not found in asset config");
        require(owner != address(0), "Owner address not found in asset config");

        // Prepare Init Data
        bytes memory initData =
            abi.encodeWithSelector(ManualPricer.initialize.selector, bot, asset, context.oracleAddr, context.addressBookAddr, owner);

        vm.startBroadcast(context.deployerPrivateKey);
        ERC1967Proxy proxy = new ERC1967Proxy(context.implementation, initData);
        vm.stopBroadcast();

        console.log("Proxy deployed at:", address(proxy));

        _writeDeploymentData(context, address(proxy), asset, initData, key);
    }

    function _writeDeploymentData(
        DeployContext memory context, 
        address proxy, 
        address asset, 
        bytes memory initData, 
        string memory key
    ) internal {
        string memory jsonObj = "deployment_data";
        vm.serializeString(jsonObj, "contractName", "ManualPricer");
        vm.serializeAddress(jsonObj, "implementationAddress", context.implementation);
        vm.serializeAddress(jsonObj, "asset", asset);
        vm.serializeAddress(jsonObj, "proxyAddress", proxy);
        vm.serializeUint(jsonObj, "blockNumber", block.number);

        string memory verifyProxyCmd = string.concat(
            "forge verify-contract --chain-id ",
            context.chainIdStr,
            " --num-of-optimizations 200 --watch ",
            Strings.toHexString(proxy),
            " lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy",
            " --constructor-args ",
            Strings.toHexString(abi.encode(context.implementation, initData))
        );
        string memory finalJson = vm.serializeString(jsonObj, "verifyProxyCommand", verifyProxyCmd);

        vm.writeJson(finalJson, context.path, string.concat(".", key));
    }
}

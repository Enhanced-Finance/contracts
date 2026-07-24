// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

interface IWhitelistProductTarget {
    function isWhitelistedCollateral(address collateral) external view returns (bool);
    function isWhitelistedProduct(address underlying, address strike, address collateral, bool isPut)
        external
        view
        returns (bool);
    function isCoveredWhitelistedCollateral(address collateral, address underlying, bool isPut)
        external
        view
        returns (bool);
    function whitelistCollateral(address collateral) external;
    function whitelistProduct(address underlying, address strike, address collateral, bool isPut) external;
    function whitelistCoveredCollateral(address collateral, address underlying, bool isPut) external;
}

contract WhitelistProduct is Script {
    using stdJson for string;

    // stdJson encodes object values in alphabetical key order.
    struct ProductConfig {
        address collateral;
        bool isPut;
        address strike;
        address underlying;
    }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        uint256 chainId = block.chainid;
        string memory chainIdStr = vm.toString(chainId);
        string memory deployPath = string.concat(vm.projectRoot(), "/.deploy/", chainIdStr, ".json");
        string memory configPath = string.concat(vm.projectRoot(), "/config/", chainIdStr, ".json");

        require(vm.isFile(deployPath), "Deploy file not found");
        require(vm.isFile(configPath), "Config file not found");

        string memory deployJson = vm.readFile(deployPath);
        string memory configJson = vm.readFile(configPath);
        address whitelistAddr = deployJson.readAddress(".Whitelist.proxyAddress");
        require(whitelistAddr != address(0), "Whitelist proxy not found");

        ProductConfig[] memory products = _readProducts(configJson);
        _validateProducts(products);

        console.log("Executing WhitelistProduct on:", whitelistAddr);
        console.log("Caller (Owner):", deployer);
        console.log("Product count:", products.length);

        vm.startBroadcast(deployerPrivateKey);

        IWhitelistProductTarget whitelist = IWhitelistProductTarget(whitelistAddr);
        for (uint256 i; i < products.length; i++) {
            console.log("Processing product:", i);
            _processProduct(whitelist, products[i]);
        }

        vm.stopBroadcast();

        console.log("WhitelistProduct execution complete.");
    }

    function _readProducts(string memory configJson) internal view returns (ProductConfig[] memory) {
        require(vm.keyExistsJson(configJson, ".Whitelist.products"), "Whitelist products config not found");
        return abi.decode(configJson.parseRaw(".Whitelist.products"), (ProductConfig[]));
    }

    function _validateProducts(ProductConfig[] memory products) internal pure {
        require(products.length > 0, "No products found in config");

        for (uint256 i; i < products.length; i++) {
            require(products[i].underlying != address(0), "Product underlying is zero");
            require(products[i].strike != address(0), "Product strike is zero");
            require(products[i].collateral != address(0), "Product collateral is zero");
        }
    }

    function _processProduct(IWhitelistProductTarget whitelist, ProductConfig memory product) internal {
        console.log("Underlying:", product.underlying);
        console.log("Strike:", product.strike);
        console.log("Collateral:", product.collateral);
        console.log("Is Put:", product.isPut);

        if (!whitelist.isWhitelistedCollateral(product.collateral)) {
            console.log("Collateral is NOT whitelisted. Whitelisting collateral...");
            whitelist.whitelistCollateral(product.collateral);
        } else {
            console.log("Collateral is already whitelisted.");
        }

        if (!whitelist.isWhitelistedProduct(product.underlying, product.strike, product.collateral, product.isPut)) {
            console.log("Product is NOT whitelisted. Whitelisting product...");
            whitelist.whitelistProduct(product.underlying, product.strike, product.collateral, product.isPut);
        } else {
            console.log("Product is already whitelisted.");
        }

        if (!product.isPut && product.collateral == product.underlying) {
            if (!whitelist.isCoveredWhitelistedCollateral(product.collateral, product.underlying, product.isPut)) {
                console.log("Whitelisting Covered Collateral...");
                whitelist.whitelistCoveredCollateral(product.collateral, product.underlying, product.isPut);
            }
        }

        if (product.isPut && product.collateral == product.strike) {
            if (!whitelist.isCoveredWhitelistedCollateral(product.collateral, product.underlying, product.isPut)) {
                console.log("Whitelisting Covered Collateral (Put)...");
                whitelist.whitelistCoveredCollateral(product.collateral, product.underlying, product.isPut);
            }
        }
    }
}

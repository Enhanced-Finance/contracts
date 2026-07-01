// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {IWhitelistProductTarget, WhitelistProduct} from "../script/Whitelist/WhitelistProduct.s.sol";

contract MockWhitelistProductTarget is IWhitelistProductTarget {
    mapping(address => bool) internal _collaterals;
    mapping(bytes32 => bool) internal _products;
    mapping(bytes32 => bool) internal _coveredCollaterals;

    uint256 public whitelistCollateralCalls;
    uint256 public whitelistProductCalls;
    uint256 public whitelistCoveredCollateralCalls;

    function isWhitelistedCollateral(address collateral) external view returns (bool) {
        return _collaterals[collateral];
    }

    function isWhitelistedProduct(address underlying, address strike, address collateral, bool isPut)
        external
        view
        returns (bool)
    {
        return _products[keccak256(abi.encode(underlying, strike, collateral, isPut))];
    }

    function isCoveredWhitelistedCollateral(address collateral, address underlying, bool isPut)
        external
        view
        returns (bool)
    {
        return _coveredCollaterals[keccak256(abi.encode(collateral, underlying, isPut))];
    }

    function whitelistCollateral(address collateral) external {
        whitelistCollateralCalls++;
        _collaterals[collateral] = true;
    }

    function whitelistProduct(address underlying, address strike, address collateral, bool isPut) external {
        whitelistProductCalls++;
        _products[keccak256(abi.encode(underlying, strike, collateral, isPut))] = true;
    }

    function whitelistCoveredCollateral(address collateral, address underlying, bool isPut) external {
        whitelistCoveredCollateralCalls++;
        _coveredCollaterals[keccak256(abi.encode(collateral, underlying, isPut))] = true;
    }
}

contract WhitelistProductHarness is WhitelistProduct {
    function exposedReadProducts(string memory configJson) external view returns (ProductConfig[] memory) {
        return _readProducts(configJson);
    }

    function exposedValidateProducts(ProductConfig[] memory products) external pure {
        _validateProducts(products);
    }

    function exposedProcessProduct(IWhitelistProductTarget whitelist, ProductConfig memory product) external {
        _processProduct(whitelist, product);
    }
}

contract WhitelistProductScriptTest is Test {
    WhitelistProductHarness internal harness;
    MockWhitelistProductTarget internal target;

    function setUp() external {
        harness = new WhitelistProductHarness();
        target = new MockWhitelistProductTarget();
    }

    function testReadProducts_ShouldDecodeMultipleProductsAndPreserveExplicitCollateral() external view {
        string memory configJson = string.concat(
            '{"Whitelist":{"products":[',
            '{"underlying":"0x0000000000000000000000000000000000000011",',
            '"strike":"0x0000000000000000000000000000000000000022",',
            '"collateral":"0x0000000000000000000000000000000000000033","isPut":false},',
            '{"underlying":"0x0000000000000000000000000000000000000044",',
            '"strike":"0x0000000000000000000000000000000000000055",',
            '"collateral":"0x0000000000000000000000000000000000000066","isPut":true}',
            "]}}"
        );

        WhitelistProduct.ProductConfig[] memory products = harness.exposedReadProducts(configJson);

        assertEq(products.length, 2, "product count mismatch");
        assertEq(products[0].underlying, address(0x11), "first underlying mismatch");
        assertEq(products[0].strike, address(0x22), "first strike mismatch");
        assertEq(products[0].collateral, address(0x33), "explicit call collateral mismatch");
        assertFalse(products[0].isPut, "first product should be call");
        assertEq(products[1].underlying, address(0x44), "second underlying mismatch");
        assertEq(products[1].strike, address(0x55), "second strike mismatch");
        assertEq(products[1].collateral, address(0x66), "explicit put collateral mismatch");
        assertTrue(products[1].isPut, "second product should be put");
    }

    function testReadProducts_ShouldDecodeRealChainConfig() external view {
        string memory configJson = vm.readFile(string.concat(vm.projectRoot(), "/config/1328.json"));

        WhitelistProduct.ProductConfig[] memory products = harness.exposedReadProducts(configJson);

        assertEq(products.length, 2, "real config product count mismatch");
        assertEq(products[0].underlying, 0xb4720E4467aCe9D54da0ee10365e5594A10F9fE2);
        assertEq(products[0].strike, 0x134b5f74d65a34eb6F9CdaD5eD664b45A167cC43);
        assertEq(products[0].collateral, 0xb4720E4467aCe9D54da0ee10365e5594A10F9fE2);
        assertFalse(products[0].isPut);
        assertEq(products[1].collateral, 0x134b5f74d65a34eb6F9CdaD5eD664b45A167cC43);
        assertTrue(products[1].isPut);
    }

    function testValidateProducts_ShouldRejectEmptyArray() external {
        WhitelistProduct.ProductConfig[] memory products = new WhitelistProduct.ProductConfig[](0);

        vm.expectRevert("No products found in config");
        harness.exposedValidateProducts(products);
    }

    function testValidateProducts_ShouldRejectZeroAddress() external {
        WhitelistProduct.ProductConfig[] memory products = new WhitelistProduct.ProductConfig[](1);
        products[0] = WhitelistProduct.ProductConfig({
            collateral: address(0x33), isPut: false, strike: address(0x22), underlying: address(0)
        });

        vm.expectRevert("Product underlying is zero");
        harness.exposedValidateProducts(products);
    }

    function testProcessProduct_ShouldApplyCoveredCallAndRemainIdempotent() external {
        WhitelistProduct.ProductConfig memory product = WhitelistProduct.ProductConfig({
            collateral: address(0x11), isPut: false, strike: address(0x22), underlying: address(0x11)
        });

        harness.exposedProcessProduct(target, product);
        harness.exposedProcessProduct(target, product);

        assertEq(target.whitelistCollateralCalls(), 1, "collateral should only be whitelisted once");
        assertEq(target.whitelistProductCalls(), 1, "product should only be whitelisted once");
        assertEq(target.whitelistCoveredCollateralCalls(), 1, "covered collateral should only be whitelisted once");
    }

    function testProcessProduct_ShouldApplyCoveredPut() external {
        WhitelistProduct.ProductConfig memory product = WhitelistProduct.ProductConfig({
            collateral: address(0x22), isPut: true, strike: address(0x22), underlying: address(0x11)
        });

        harness.exposedProcessProduct(target, product);

        assertEq(target.whitelistCoveredCollateralCalls(), 1, "covered put collateral was not whitelisted");
    }

    function testProcessProduct_ShouldNotInferCoveredCollateral() external {
        WhitelistProduct.ProductConfig memory product = WhitelistProduct.ProductConfig({
            collateral: address(0x33), isPut: true, strike: address(0x22), underlying: address(0x11)
        });

        harness.exposedProcessProduct(target, product);

        assertEq(target.whitelistCollateralCalls(), 1);
        assertEq(target.whitelistProductCalls(), 1);
        assertEq(target.whitelistCoveredCollateralCalls(), 0, "non-standard collateral must remain explicit");
    }
}

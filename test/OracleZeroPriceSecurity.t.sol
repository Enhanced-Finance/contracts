// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {ERC1967Proxy} from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {ManualPricer} from "src/core/ManualPricer.sol";
import {MarginCalculator} from "src/core/MarginCalculator.sol";
import {Oracle} from "src/core/Oracle.sol";
import {EnhancedPricerInterface} from "src/core/interfaces/EnhancedPricerInterface.sol";
import {FixedPointInt256 as FPI} from "src/core/libs/FixedPointInt256.sol";

contract ZeroPricer is EnhancedPricerInterface {
    function getPrice() external pure returns (uint256) {
        return 0;
    }

    function getHistoricalPrice(uint80) external view returns (uint256, uint256) {
        return (0, block.timestamp);
    }
}

contract FixedPointHarness {
    using FPI for FPI.FixedPointInt;

    function div(uint256 numerator, uint256 denominator) external pure returns (int256) {
        return FPI.fromScaledUint(numerator, 8).div(FPI.fromScaledUint(denominator, 8)).value;
    }
}

contract MarginCalculatorHarness is MarginCalculator {
    function makeShortScaledDetailsExternal(uint256 short, uint256 strike, uint256 underlying) external pure {
        makeShortScaledDetails(short, strike, underlying);
    }
}

contract OracleZeroPriceSecurityTest is Test {
    address private owner = address(0xA11CE);
    address private bot = address(0xB0B);
    address private disputer = address(0xD15);
    address private asset = address(0xA55E7);

    Oracle private oracle;
    ZeroPricer private zeroPricer;

    function setUp() public {
        vm.warp(1_000);
        Oracle oracleImpl = new Oracle();
        ERC1967Proxy oracleProxy = new ERC1967Proxy(address(oracleImpl), abi.encodeCall(Oracle.initialize, (owner)));
        oracle = Oracle(address(oracleProxy));
        zeroPricer = new ZeroPricer();
    }

    function testOracleRejectsZeroLivePriceFromDynamicPricer() public {
        vm.prank(owner);
        oracle.setAssetPricer(asset, address(zeroPricer));

        vm.expectRevert("Oracle: price cannot be 0");
        oracle.getPrice(asset);
    }

    function testManualPricerRejectsZeroPriceBeforeOracleWrite() public {
        ManualPricer manualPricer = _deployManualPricer();

        vm.prank(bot);
        vm.expectRevert("ManualPricer: price cannot be 0");
        manualPricer.setExpiryPriceInOracle(block.timestamp - 1, 0);
    }

    function testManualPricerRejectsSameExpiryTimestamp() public {
        ManualPricer manualPricer = _deployManualPricer();

        vm.prank(bot);
        manualPricer.setExpiryPriceInOracle(block.timestamp - 100, 100e8);

        vm.prank(bot);
        vm.expectRevert("ManualPricer: expiry timestamp must increase");
        manualPricer.setExpiryPriceInOracle(block.timestamp - 100, 101e8);
    }

    function testManualPricerRejectsEarlierUnregisteredExpiryTimestamp() public {
        ManualPricer manualPricer = _deployManualPricer();

        vm.prank(bot);
        manualPricer.setExpiryPriceInOracle(block.timestamp - 100, 100e8);

        vm.prank(bot);
        vm.expectRevert("ManualPricer: expiry timestamp must increase");
        manualPricer.setExpiryPriceInOracle(block.timestamp - 200, 101e8);
    }

    function testManualPricerAcceptsStrictlyIncreasingExpiryTimestamp() public {
        ManualPricer manualPricer = _deployManualPricer();

        vm.prank(bot);
        manualPricer.setExpiryPriceInOracle(block.timestamp - 200, 100e8);

        vm.prank(bot);
        manualPricer.setExpiryPriceInOracle(block.timestamp - 100, 101e8);

        assertEq(manualPricer.lastExpiryTimestamp(), block.timestamp - 100);
        assertEq(manualPricer.getPrice(), 101e8);
    }

    function testOracleSetExpiryPriceRejectsZeroPrice() public {
        vm.prank(owner);
        oracle.setAssetPricer(asset, address(zeroPricer));

        vm.prank(address(zeroPricer));
        vm.expectRevert("Oracle: price cannot be 0");
        oracle.setExpiryPrice(asset, block.timestamp - 1, 0);
    }

    function testOracleDisputeExpiryPriceRejectsZeroPrice() public {
        vm.prank(owner);
        oracle.setAssetPricer(asset, address(zeroPricer));

        vm.prank(address(zeroPricer));
        oracle.setExpiryPrice(asset, block.timestamp - 1, 1e8);

        vm.prank(owner);
        oracle.setDisputer(disputer);

        vm.prank(disputer);
        vm.expectRevert("Oracle: price cannot be 0");
        oracle.disputeExpiryPrice(asset, block.timestamp - 1, 0);
    }

    function testOracleMigrationRejectsZeroPrice() public {
        uint256[] memory expiries = new uint256[](1);
        uint256[] memory prices = new uint256[](1);
        expiries[0] = block.timestamp - 1;
        prices[0] = 0;

        vm.prank(owner);
        vm.expectRevert("Oracle: price cannot be 0");
        oracle.migrateOracle(asset, expiries, prices);
    }

    function testMarginCalculatorRejectsZeroShortUnderlyingPrice() public {
        MarginCalculatorHarness calculator = new MarginCalculatorHarness();

        vm.expectRevert("MarginCalculator: underlying price cannot be 0");
        calculator.makeShortScaledDetailsExternal(1e8, 1_000e8, 0);
    }

    function testFixedPointDivisionRejectsZeroDenominator() public {
        FixedPointHarness harness = new FixedPointHarness();

        vm.expectRevert("FixedPointInt256: division by zero");
        harness.div(1e8, 0);
    }

    function _deployManualPricer() private returns (ManualPricer manualPricer) {
        ManualPricer manualPricerImpl = new ManualPricer();
        ERC1967Proxy manualPricerProxy = new ERC1967Proxy(
            address(manualPricerImpl),
            abi.encodeCall(ManualPricer.initialize, (bot, asset, address(oracle), address(0xADD4E55B00), owner))
        );
        manualPricer = ManualPricer(address(manualPricerProxy));

        vm.startPrank(owner);
        oracle.setAssetPricer(asset, address(manualPricer));
        manualPricer.setPriceTimeValidity(1 days);
        manualPricer.setDeviationMultiplier(10_000);
        vm.stopPrank();
    }
}

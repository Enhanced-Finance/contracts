// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {ControllerLogic} from "src/core/ControllerLogic.sol";
import {MockERC20} from "src/core/mocks/MockERC20.sol";
import {Actions} from "src/core/libs/Actions.sol";

contract ControllerLogicAddressBookMock {
    address internal immutable WHITELIST;
    address internal immutable CONTROLLER;
    address internal immutable ORACLE;
    address internal immutable CALCULATOR;
    address internal immutable POOL;

    constructor(address whitelist_, address controller_, address oracle_, address calculator_, address pool_) {
        WHITELIST = whitelist_;
        CONTROLLER = controller_;
        ORACLE = oracle_;
        CALCULATOR = calculator_;
        POOL = pool_;
    }

    function getWhitelist() external view returns (address) {
        return WHITELIST;
    }

    function getController() external view returns (address) {
        return CONTROLLER;
    }

    function getOracle() external view returns (address) {
        return ORACLE;
    }

    function getMarginCalculator() external view returns (address) {
        return CALCULATOR;
    }

    function getMarginPool() external view returns (address) {
        return POOL;
    }
}

contract ControllerLogicWhitelistMock {
    function isWhitelistedOtoken(address) external pure returns (bool) {
        return true;
    }
}

contract ControllerLogicControllerMock {
    function canSettleAssets(address, address, address, uint256) external pure returns (bool) {
        return true;
    }
}

contract ControllerLogicOracleMock {
    uint256 internal immutable PRICE;

    constructor(uint256 price_) {
        PRICE = price_;
    }

    function getExpiryPrice(address, uint256) external view returns (uint256, bool) {
        return (PRICE, true);
    }
}

contract ControllerLogicCalculatorMock {
    uint256 internal immutable STRIKE_PAYMENT_AMOUNT;
    uint256 internal immutable EXPIRED_PAYOUT_RATE;

    constructor(uint256 strikePayment_, uint256 payoutRate_) {
        STRIKE_PAYMENT_AMOUNT = strikePayment_;
        EXPIRED_PAYOUT_RATE = payoutRate_;
    }

    function getStrikePaymentAmount(address, uint256) external view returns (uint256) {
        return STRIKE_PAYMENT_AMOUNT;
    }

    function getExpiredPayoutRate(address) external view returns (uint256) {
        return EXPIRED_PAYOUT_RATE;
    }
}

contract ControllerLogicPoolMock {
    address public lastTransferToPoolAsset;
    address public lastTransferToPoolUser;
    uint256 public lastTransferToPoolAmount;
    address public lastTransferToUserAsset;
    address public lastTransferToUserUser;
    uint256 public lastTransferToUserAmount;

    function transferToPool(address asset, address user, uint256 amount) external {
        lastTransferToPoolAsset = asset;
        lastTransferToPoolUser = user;
        lastTransferToPoolAmount = amount;
        require(IERC20(asset).transferFrom(user, address(this), amount));
    }

    function transferToUser(address asset, address user, uint256 amount) external {
        lastTransferToUserAsset = asset;
        lastTransferToUserUser = user;
        lastTransferToUserAmount = amount;
        require(IERC20(asset).transfer(user, amount));
    }

    function updateRedemptionBalance(address, int256, bool, int256) external {}

    function getRedemptionBalance(address) external pure returns (uint256, uint256, uint256) {
        return (0, 0, 0);
    }
}

contract ControllerLogicOtokenMock {
    address internal immutable UNDERLYING_ASSET;
    address internal immutable STRIKE_ASSET;
    address internal immutable COLLATERAL_ASSET;
    uint256 internal immutable STRIKE_PRICE;
    uint256 internal immutable EXPIRY_TIMESTAMP;
    bool internal immutable IS_PUT;
    bool internal immutable IS_PHYSICALLY_SETTLED;
    address public lastBurnAccount;
    uint256 public lastBurnAmount;

    constructor(
        address underlyingAsset_,
        address strikeAsset_,
        address collateralAsset_,
        uint256 strikePrice_,
        uint256 expiryTimestamp_,
        bool isPut_,
        bool isPhysicallySettled_
    ) {
        UNDERLYING_ASSET = underlyingAsset_;
        STRIKE_ASSET = strikeAsset_;
        COLLATERAL_ASSET = collateralAsset_;
        STRIKE_PRICE = strikePrice_;
        EXPIRY_TIMESTAMP = expiryTimestamp_;
        IS_PUT = isPut_;
        IS_PHYSICALLY_SETTLED = isPhysicallySettled_;
    }

    function underlyingAsset() external view returns (address) {
        return UNDERLYING_ASSET;
    }

    function strikeAsset() external view returns (address) {
        return STRIKE_ASSET;
    }

    function collateralAsset() external view returns (address) {
        return COLLATERAL_ASSET;
    }

    function strikePrice() external view returns (uint256) {
        return STRIKE_PRICE;
    }

    function expiryTimestamp() external view returns (uint256) {
        return EXPIRY_TIMESTAMP;
    }

    function isPut() external view returns (bool) {
        return IS_PUT;
    }

    function isPhysicallySettled() external view returns (bool) {
        return IS_PHYSICALLY_SETTLED;
    }

    function getOtokenDetails() external view returns (address, address, address, uint256, uint256, bool, bool) {
        return (
            COLLATERAL_ASSET,
            UNDERLYING_ASSET,
            STRIKE_ASSET,
            STRIKE_PRICE,
            EXPIRY_TIMESTAMP,
            IS_PUT,
            IS_PHYSICALLY_SETTLED
        );
    }

    function burnOtoken(address account, uint256 amount) external {
        lastBurnAccount = account;
        lastBurnAmount = amount;
    }
}

contract ControllerLogicRedeemTest is Test {
    uint256 internal constant OTOKEN_AMOUNT = 1e8;
    uint256 internal constant STRIKE_PAYMENT = 1_000e6;
    uint256 internal constant PAYOUT_RATE = 1e18;
    uint256 internal constant PAYOUT = 1e18;

    function test_physicalRedeemTakesExercisePaymentFromPayerAndPaysReceiver() external {
        address payer = address(0xA11CE);
        address receiver = address(0xBEEF);
        address otokenHolder = address(0xE0);
        address owner = address(0xABCD);

        MockERC20 underlying = new MockERC20("Underlying", "UND", 18);
        MockERC20 strike = new MockERC20("Strike", "USD", 6);
        ControllerLogicPoolMock pool = new ControllerLogicPoolMock();
        ControllerLogicOtokenMock otoken = new ControllerLogicOtokenMock(
            address(underlying), address(strike), address(underlying), 1_000e8, block.timestamp - 1, false, true
        );
        ControllerLogicControllerMock controller = new ControllerLogicControllerMock();
        ControllerLogicAddressBookMock addressBook = new ControllerLogicAddressBookMock(
            address(new ControllerLogicWhitelistMock()),
            address(controller),
            address(new ControllerLogicOracleMock(2_500e8)),
            address(new ControllerLogicCalculatorMock(STRIKE_PAYMENT, PAYOUT_RATE)),
            address(pool)
        );
        ControllerLogic logic = new ControllerLogic();
        _unlockInitializers(address(logic));
        logic.initialize(address(addressBook), owner);

        strike.mint(payer, STRIKE_PAYMENT);
        underlying.mint(address(pool), PAYOUT);
        vm.prank(payer);
        strike.approve(address(pool), STRIKE_PAYMENT);

        Actions.RedeemArgs memory args =
            Actions.RedeemArgs({payer: payer, receiver: receiver, otoken: address(otoken), amount: OTOKEN_AMOUNT});

        vm.prank(address(controller));
        logic.handleRedeem(args, otokenHolder);

        assertEq(pool.lastTransferToPoolAsset(), address(strike));
        assertEq(pool.lastTransferToPoolUser(), payer);
        assertEq(pool.lastTransferToPoolAmount(), STRIKE_PAYMENT);
        assertEq(strike.balanceOf(payer), 0);
        assertEq(pool.lastTransferToUserAsset(), address(underlying));
        assertEq(pool.lastTransferToUserUser(), receiver);
        assertEq(pool.lastTransferToUserAmount(), PAYOUT);
        assertEq(underlying.balanceOf(receiver), PAYOUT);
        assertEq(otoken.lastBurnAccount(), otokenHolder);
        assertEq(otoken.lastBurnAmount(), OTOKEN_AMOUNT);
    }

    function _unlockInitializers(address target) internal {
        bytes32 initializableStorageSlot = 0xf0c57e16840df040f15088dc2f81fe391c3923bec73e23a9662efc9c229c6a00;
        vm.store(target, initializableStorageSlot, bytes32(0));
    }
}

/**
 * SPDX-License-Identifier: MIT
 */
pragma solidity ^0.8.28;

import {OwnableUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {ReentrancyGuardTransient} from "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuardTransient.sol";
import {Initializable} from "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {IERC20Metadata} from "lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {MarginVault} from "./libs/MarginVault.sol";
import {Actions} from "./libs/Actions.sol";
import {AddressBookInterface} from "./interfaces/AddressBookInterface.sol";
import {OtokenInterface} from "./interfaces/OtokenInterface.sol";
import {MarginCalculatorInterface} from "./interfaces/MarginCalculatorInterface.sol";
import {OracleInterface} from "./interfaces/OracleInterface.sol";
import {WhitelistInterface} from "./interfaces/WhitelistInterface.sol";
import {MarginPoolInterface} from "./interfaces/MarginPoolInterface.sol";
import {ControllerInterface} from "./interfaces/ControllerInterface.sol";

/**
 * @title Settlement
 * @author Enhanced Finance
 * @notice Contract that handles logic for the Controller on a modified version of Opyn's Gamma protocol
 *         An extension of the Controller to avoid contract size issues. Error list can be found in Controller.sol
 *         Main functions callable by Controller
 */
contract ControllerLogic is Initializable, OwnableUpgradeable, ReentrancyGuardTransient, UUPSUpgradeable {
    using MarginVault for MarginVault.Vault;

    AddressBookInterface public addressbook;
    WhitelistInterface public whitelist;
    MarginCalculatorInterface public calculator;
    OracleInterface public oracle;
    ControllerInterface public controller;
    MarginPoolInterface public pool;

    ///@dev scale used in MarginCalculator
    uint256 internal constant BASE = 8;

    ///@dev the number of seconds an ITM option is redeemable for after its expiry before the vault is settleable and collateral claimable.
    uint256 public redeemTimePeriod;

    /// @notice emits an event when a long oToken is deposited into a vault
    event LongOtokenDeposited(
        address indexed otoken, address indexed accountOwner, address indexed from, uint256 vaultId, uint256 amount
    );
    /// @notice emits an event when a long oToken is withdrawn from a vault
    event LongOtokenWithdrawed(
        address indexed otoken, address indexed accountOwner, address indexed to, uint256 vaultId, uint256 amount
    );
    /// @notice emits an event when a collateral asset is deposited into a vault
    event CollateralAssetDeposited(
        address indexed asset, address indexed accountOwner, address indexed from, uint256 vaultId, uint256 amount
    );
    /// @notice emits an event when a collateral asset is withdrawn from a vault
    event CollateralAssetWithdrawed(
        address indexed asset, address indexed accountOwner, address indexed to, uint256 vaultId, uint256 amount
    );
    /// @notice emits an event when a short oToken is minted from a vault
    event ShortOtokenMinted(
        address indexed otoken, address indexed accountOwner, address indexed to, uint256 vaultId, uint256 amount
    );
    /// @notice emits an event when a short oToken is burned
    event ShortOtokenBurned(
        address indexed otoken, address indexed accountOwner, address indexed from, uint256 vaultId, uint256 amount
    );
    /// @notice emits an event when a vault is settled
    event VaultSettled(
        address indexed accountOwner,
        address indexed oTokenAddress,
        address to,
        uint256 payout,
        uint256 vaultId,
        uint256 indexed vaultType
    );
    /// @notice emits an event when an oToken is redeemed
    event Redeem(
        address indexed otoken,
        address indexed redeemer,
        address indexed receiver,
        address collateralAsset,
        uint256 otokenBurned,
        uint256 payout
    );

    struct SettleMem {
        address collateral;
        address underlying;
        address strike;
        uint256 expiry;
        uint256 collateralPayout;
        uint256 strikePayout;
        uint256 strikeCount;
        uint256 shortAmount;
        bool isValidVault;
        uint256 collateralRedemptionBalance;
        uint256 receivingAssetBalance;
        uint256 otokenQuantity;
        uint256 underlyingExpiryPrice;
        uint256 collateralExpiryPrice;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice check if the sender is the Controller module
     */
    modifier onlyController() {
        _onlyController();
        _;
    }

    function _onlyController() internal view {
        require(msg.sender == addressbook.getController(), "ControllerLogic: Sender is not Controller");
    }

    /**
     * @notice initalize the deployed contract
     * @param _addressbook addressbook module
     * @param _owner account owner address
     */
    function initialize(address _addressbook, address _owner) external initializer {
        require(_addressbook != address(0), "C7");
        require(_owner != address(0), "C8");

        __Ownable_init(_owner);
        addressbook = AddressBookInterface(_addressbook);
        redeemTimePeriod = 3600;
        _refreshConfigInternal();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @dev updates the configuration of the controller. can only be called by the owner
     */
    function refreshConfiguration() external onlyOwner {
        _refreshConfigInternal();
    }

    /**
     * @notice get an oToken's payout/cash value after expiry, in the collateral asset
     * @param _otoken oToken address
     * @param _amount amount of the oToken to calculate the payout for, always represented in 1e8
     * @return amount of collateral to pay out
     */
    function getPayout(address _otoken, uint256 _amount) public view returns (uint256) {
        return calculator.getExpiredPayoutRate(_otoken) * _amount / (10 ** BASE);
    }

    /**
     * @notice set ITM option redemption time period
     * @dev can only be called by owner
     * @param _redeemTimePeriod number of seconds an ITM option is redeemable for after its expiry
     */
    function setRedeemTimePeriod(uint256 _redeemTimePeriod) external onlyOwner {
        require(_redeemTimePeriod > 0, "C38");

        redeemTimePeriod = _redeemTimePeriod;
    }

    function handleDepositLong(Actions.DepositArgs memory _args) external onlyController {
        require(whitelist.isWhitelistedOtoken(_args.asset), "C17");

        OtokenInterface otoken = OtokenInterface(_args.asset);

        require(block.timestamp < otoken.expiryTimestamp(), "C18");
        // dont allow deposit longs for physically settled type 2 vaults and physically settled otokens
        require(!otoken.isPhysicallySettled(), "C43");
        (, uint256 typeVault,) = controller.getVaultWithDetails(_args.owner, _args.vaultId);
        require(typeVault != 2, "C43");

        controller.updateVault(2, _args.owner, _args.vaultId, _args.asset, _args.amount);

        pool.transferToPool(_args.asset, _args.from, _args.amount);

        emit LongOtokenDeposited(_args.asset, _args.owner, _args.from, _args.vaultId, _args.amount);
    }

    function handleWithdrawLong(Actions.WithdrawArgs memory _args) external onlyController {
        OtokenInterface otoken = OtokenInterface(_args.asset);

        require(block.timestamp < otoken.expiryTimestamp(), "C19");
        controller.updateVault(3, _args.owner, _args.vaultId, _args.asset, _args.amount);

        pool.transferToUser(_args.asset, _args.to, _args.amount);

        emit LongOtokenWithdrawed(_args.asset, _args.owner, _args.to, _args.vaultId, _args.amount);
    }

    function handleDepositCollateral(Actions.DepositArgs memory _args) external onlyController {
        require(whitelist.isWhitelistedCollateral(_args.asset), "C21");

        (, uint256 typeVault,) = controller.getVaultWithDetails(_args.owner, _args.vaultId);

        if (typeVault == 1) {
            controller.increaseNakedPoolBalance(_args.asset, _args.amount);

            require(controller.getNakedPoolBalance(_args.asset) <= controller.getNakedCap(_args.asset), "C37");
        }
        controller.updateVault(4, _args.owner, _args.vaultId, _args.asset, _args.amount);

        pool.transferToPool(_args.asset, _args.from, _args.amount);

        emit CollateralAssetDeposited(_args.asset, _args.owner, _args.from, _args.vaultId, _args.amount);
    }

    function handleWithdrawCollateral(Actions.WithdrawArgs memory _args) external onlyController {
        (MarginVault.Vault memory vault, uint256 typeVault,) =
            controller.getVaultWithDetails(_args.owner, _args.vaultId);

        if (_isNotEmpty(vault.shortOtokens)) {
            OtokenInterface otoken = OtokenInterface(vault.shortOtokens[0]);

            require(block.timestamp < otoken.expiryTimestamp(), "C22");
        }

        if (typeVault == 1) {
            controller.reduceNakedPoolBalance(_args.asset, _args.amount);
        }

        controller.updateVault(5, _args.owner, _args.vaultId, _args.asset, _args.amount);

        pool.transferToUser(_args.asset, _args.to, _args.amount);

        emit CollateralAssetWithdrawed(_args.asset, _args.owner, _args.to, _args.vaultId, _args.amount);
    }

    function handleMintOtoken(Actions.MintArgs memory _args, uint256 vaultType) external onlyController {
        require(whitelist.isWhitelistedOtoken(_args.otoken), "C23");

        OtokenInterface otoken = OtokenInterface(_args.otoken);

        require(block.timestamp < otoken.expiryTimestamp(), "C24");

        if (vaultType == 2) {
            // this is a physically settled vault
            require(otoken.isPhysicallySettled(), "C40");
            // increase oTokenQuantity by _args.amount
            if (otoken.isPut()) {
                // each put is collateralised with the strikePrice amount of collateral asset. so increase collateralBalance by strikePrice per oToken, scaled to collateral decimals
                // _args.amount is in e8, strikePrice is in e8, so multiply by collateral asset decimals and divide by e16 to convert to collateral asset decimals
                pool.updateRedemptionBalance(
                    _args.otoken,
                    int256(_args.amount),
                    false,
                    int256(
                        _args.amount * otoken.strikePrice()
                            * (10 ** uint256(IERC20Metadata(otoken.collateralAsset()).decimals())) / 1e16
                    )
                );
            } else {
                // each call is collateralised with 1 full collateral asset, so increase collateralBalance by 1 per oToken, scaled to collateral decimals
                // _args.amount is in e8, so multiply by collateral asset decimals and divide by e8 to convert to collateral asset decimals
                pool.updateRedemptionBalance(
                    _args.otoken,
                    int256(_args.amount),
                    false,
                    int256(_args.amount * (10 ** uint256(IERC20Metadata(otoken.collateralAsset()).decimals())) / 1e8)
                );
            }
        } else {
            // this is not a physically settled vault
            require(!otoken.isPhysicallySettled(), "C40");
        }

        controller.updateVault(0, _args.owner, _args.vaultId, _args.otoken, _args.amount);

        otoken.mintOtoken(_args.to, _args.amount);

        emit ShortOtokenMinted(_args.otoken, _args.owner, _args.to, _args.vaultId, _args.amount);
    }

    function handleBurnOtoken(Actions.BurnArgs memory _args, uint256 vaultType) external onlyController {
        OtokenInterface otoken = OtokenInterface(_args.otoken);

        // do not allow burning expired otoken
        require(block.timestamp < otoken.expiryTimestamp(), "C26");

        if (vaultType == 2) {
            // this is a physically settled vault
            require(otoken.isPhysicallySettled(), "C40");
            if (otoken.isPut()) {
                // decrease oTokenQuantity by number of otokens being burned
                // each put is collateralised with the strikePrice amount of collateral asset, so decrease collateralBalance by strikePrice per oToken, scaled to collateral decimals
                // _args.amount is in e8, strikePrice is in e8, so multiply by collateral asset decimals and divide by e16 to convert to collateral asset decimals
                pool.updateRedemptionBalance(
                    _args.otoken,
                    -int256(_args.amount),
                    false,
                    -int256(
                        _args.amount * otoken.strikePrice()
                            * (10 ** uint256(IERC20Metadata(otoken.collateralAsset()).decimals())) / 1e16
                    )
                );
            } else {
                // decrease oTokenQuantity by number of otokens being burned
                // each call is collateralised with 1 full collateral asset, so decrease collateralBalance by 1 per oToken, scaled to collateral decimals
                // _args.amount is in e8, so multiply by collateral asset decimals and divide by e8 to convert to collateral asset decimals
                pool.updateRedemptionBalance(
                    _args.otoken,
                    -int256(_args.amount),
                    false,
                    -int256(_args.amount * (10 ** uint256(IERC20Metadata(otoken.collateralAsset()).decimals())) / 1e8)
                );
            }
        } else {
            // this is not a physically settled vault
            require(!otoken.isPhysicallySettled(), "C40");
        }

        // remove otoken from vault
        controller.updateVault(1, _args.owner, _args.vaultId, _args.otoken, _args.amount);
        // burn otoken
        otoken.burnOtoken(_args.from, _args.amount);

        emit ShortOtokenBurned(_args.otoken, _args.owner, _args.from, _args.vaultId, _args.amount);
    }

    function handleRedeem(Actions.RedeemArgs memory _args, address sender) external onlyController {
        OtokenInterface otoken = OtokenInterface(_args.otoken);

        // check that otoken to redeem is whitelisted
        require(whitelist.isWhitelistedOtoken(_args.otoken), "C27");

        (address collateral, address underlying, address strike, uint256 expiry) = _getOtokenDetails(address(otoken));

        // only allow redeeming expired otoken
        require(block.timestamp >= expiry, "C28");

        require(controller.canSettleAssets(underlying, strike, collateral, expiry), "C29");

        if (otoken.isPhysicallySettled()) {
            // must be within the redeem time period
            require(block.timestamp < expiry + redeemTimePeriod, "C39");

            uint256 strikePrice = otoken.strikePrice();
            (uint256 underlyingExpiryPrice,) = oracle.getExpiryPrice(underlying, expiry);
            (uint256 collateralExpiryPrice,) = oracle.getExpiryPrice(collateral, expiry);

            // get the amount of capital needed to exercise.
            // for calls this is strikeAsset, for puts it is underlyingAsset
            uint256 strikePayment = calculator.getStrikePaymentAmount(_args.otoken, _args.amount);

            if (otoken.isPut()) {
                // check put is ITM
                require(underlyingExpiryPrice < strikePrice, "C45");
                // take the underlying asset payment
                _removeExcessCollateralFromRedemptionBalances(
                    otoken, strikePrice, underlyingExpiryPrice, collateralExpiryPrice
                );
                pool.transferToPool(otoken.underlyingAsset(), _args.receiver, strikePayment);
            } else {
                // check call is ITM
                require(underlyingExpiryPrice > strikePrice, "C45");

                _removeExcessCollateralFromRedemptionBalances(
                    otoken, strikePrice, underlyingExpiryPrice, collateralExpiryPrice
                );
                // take the strike asset payment
                pool.transferToPool(otoken.strikeAsset(), _args.receiver, strikePayment);
            }

            pool.updateRedemptionBalance(_args.otoken, 0, true, int256(strikePayment));
        }
        uint256 payout = getPayout(_args.otoken, _args.amount);
        otoken.burnOtoken(sender, _args.amount);

        pool.transferToUser(collateral, _args.receiver, payout);

        if (otoken.isPhysicallySettled()) {
            pool.updateRedemptionBalance(_args.otoken, 0, false, -int256(payout));
        }

        emit Redeem(_args.otoken, sender, _args.receiver, collateral, _args.amount, payout);
    }

    function handleSettle(Actions.SettleVaultArgs memory _args) external onlyController {
        (MarginVault.Vault memory vault, uint256 typeVault,) =
            controller.getVaultWithDetails(_args.owner, _args.vaultId);

        // check if there is short or long otoken in vault
        // do not allow settling vault that have no short or long otoken
        // if there is a long otoken, burn it
        // store otoken address outside of this scope

        bool hasShort = _isNotEmpty(vault.shortOtokens);
        bool hasLong = _isNotEmpty(vault.longOtokens);

        require(hasShort || hasLong, "C30");

        OtokenInterface otoken =
            hasShort ? OtokenInterface(vault.shortOtokens[0]) : OtokenInterface(vault.longOtokens[0]);

        if (hasLong) {
            OtokenInterface longOtoken = OtokenInterface(vault.longOtokens[0]);

            longOtoken.burnOtoken(address(pool), vault.longAmounts[0]);
        }

        SettleMem memory settleMem;
        (settleMem.collateral, settleMem.underlying, settleMem.strike, settleMem.expiry) =
            _getOtokenDetails(address(otoken));

        // do not allow settling vault with un-expired otoken
        if (typeVault == 2) {
            require(block.timestamp >= settleMem.expiry + redeemTimePeriod, "C41");
        } else {
            require(block.timestamp >= settleMem.expiry, "C31");
        }
        require(
            controller.canSettleAssets(settleMem.underlying, settleMem.strike, settleMem.collateral, settleMem.expiry),
            "C29"
        );

        // this returns any overcollateralisation in the ITM scenario (this includes any amount caused by "overcollateralised" collateral as well as more collateral than was needed
        // and returns the exact collateral amount in the case of OTM
        (settleMem.collateralPayout, settleMem.isValidVault) = calculator.getExcessCollateral(vault, typeVault);
        // require that vault is valid (has excess collateral) before settling
        // to avoid allowing settling undercollateralized naked margin vault
        // if physically settled vault past its redeem time period, no collateral is required because no more redeems can happen so vault is always valid
        // however if calculator.getExcessCollateral returns not valid, settleMem.collateralPayout will be equal to the collateral deficit in the vault
        // we do not want to add this to the payout of settlement since it is a deficit, not an excess, so set to zero.
        if (typeVault == 2 && !settleMem.isValidVault) {
            settleMem.isValidVault = true;
            settleMem.collateralPayout = 0;
        }
        require(settleMem.isValidVault, "C32");

        // for physically settled vaults, payout is calculated differently
        if (typeVault == 2) {
            uint256 strikePrice = otoken.strikePrice();
            (settleMem.underlyingExpiryPrice,) = oracle.getExpiryPrice(settleMem.underlying, settleMem.expiry);
            (settleMem.collateralExpiryPrice,) = oracle.getExpiryPrice(settleMem.collateral, settleMem.expiry);

            _removeExcessCollateralFromRedemptionBalances(
                otoken, strikePrice, settleMem.underlyingExpiryPrice, settleMem.collateralExpiryPrice
            );

            (settleMem.collateralRedemptionBalance, settleMem.receivingAssetBalance, settleMem.otokenQuantity) =
                pool.getRedemptionBalance(address(otoken));

            settleMem.shortAmount = vault.shortAmounts[0];

            // CALLS:
            // strike payment is number of options in vault * strike price, converted to strike decimals
            // strikePrice denominatd in e8, shortAmount denominated in e8
            // strikePrice * shortAmount * e2 = e18
            // divide by (18 - strike decimals) to convert to strike decimals
            // assumes strike asset decimals <= 18
            // PUTS:
            // strike payment is number of options in vault, converted to underying decimals
            // shortAmount * e10 = e18
            // divide by (18 - underlying decimals) to convert to underlying decimals
            settleMem.strikePayout = otoken.isPut()
                ? settleMem.shortAmount * 1e10 / (10 ** (18 - uint256(IERC20Metadata(settleMem.underlying).decimals())))
                : (strikePrice * settleMem.shortAmount * 1e2)
                    / (10 ** (18 - uint256(IERC20Metadata(settleMem.strike).decimals())));

            // From here there are three scenarios that can happen:
            // 0. (IF OTM) There is no strike asset in the pool. Meaning the user should receive their payment in collateral + any collateral they have from overcollateralisation
            // 1. (IF ITM and no strike asset in the pool) Meaning the user should receive their payment in collateral + any collateral they have from overcollateralisation
            // 2. (IF ITM not enough strike asset in the pool to pay the strike payment) Meaning the user should receive any remaining strike asset, their remaining payment in collateral + any collateral they have from overcollateralisation
            // 3. (IF ITM and there is enough strike asset in the pool to pay the strike payment) Meaning the user should receive their payment in strike + any collateral they have from overcollateralization
            if (settleMem.receivingAssetBalance == 0) {
                // this is scenario 0 or 1
                settleMem.strikePayout = 0;
                // each remaining otoken to settle gets an equal share of collateralRedemptionBalance, (for OTM options this is zero)
                uint256 vaultShareOfCollateralRedemptionBalance =
                    settleMem.collateralRedemptionBalance * settleMem.shortAmount / settleMem.otokenQuantity;
                settleMem.collateralPayout += vaultShareOfCollateralRedemptionBalance;

                pool.updateRedemptionBalance(
                    address(otoken),
                    -int256(settleMem.shortAmount),
                    false,
                    -int256(vaultShareOfCollateralRedemptionBalance)
                );
            } else if (settleMem.strikePayout > settleMem.receivingAssetBalance) {
                // this is scenario 2
                settleMem.strikePayout = settleMem.receivingAssetBalance;
                // find how many options worth of strike payment is in the pool
                // CALLS: get receivingAssetBalance and convert to e18 notation then divide by strikePrice * 1e2 (e10) to get e8 value.
                // PUTS: get receivingAssetBalance and convert to e8 notation
                // assumes strike asset decimals <= 18
                settleMem.strikeCount = otoken.isPut()
                    ? settleMem.receivingAssetBalance
                        * (10 ** (18 - uint256(IERC20Metadata(settleMem.underlying).decimals()))) / 1e10
                    : settleMem.receivingAssetBalance
                        * (10 ** (18 - uint256(IERC20Metadata(settleMem.strike).decimals()))) / (strikePrice * 1e2);
                // we can get the amount the user is owed in collateral asset by subtracting the strikeCount from the shortAmounts
                uint256 contractsLeft = settleMem.shortAmount - settleMem.strikeCount;
                // divide collateralRedemptionBalance by total number of options to split between (otokenQuantity - strikeCount) and multiply by contractsLeft
                uint256 vaultShareOfCollateralRedemptionBalance = settleMem.collateralRedemptionBalance * contractsLeft
                    / (settleMem.otokenQuantity - settleMem.strikeCount);
                // the collateral payout is whatever it already was + the share of the collateralRedemptionBalance
                settleMem.collateralPayout += vaultShareOfCollateralRedemptionBalance;
                pool.updateRedemptionBalance(
                    address(otoken), -int256(settleMem.strikeCount), true, -int256(settleMem.strikePayout)
                );
                pool.updateRedemptionBalance(
                    address(otoken), -int256(contractsLeft), false, -int256(vaultShareOfCollateralRedemptionBalance)
                );
            } else {
                // this is scenario 3
                pool.updateRedemptionBalance(
                    address(otoken), -int256(settleMem.shortAmount), true, -int256(settleMem.strikePayout)
                );
            }
        }

        controller.updateVault(6, _args.owner, _args.vaultId, address(0), 0);

        if (typeVault == 1) {
            controller.reduceNakedPoolBalance(settleMem.collateral, settleMem.collateralPayout);
        }

        pool.transferToUser(settleMem.collateral, _args.to, settleMem.collateralPayout);
        if (settleMem.strikePayout > 0) {
            pool.transferToUser(
                otoken.isPut() ? otoken.underlyingAsset() : otoken.strikeAsset(), _args.to, settleMem.strikePayout
            );
        }
        uint256 vaultId = _args.vaultId;
        address payoutRecipient = _args.to;

        emit VaultSettled(_args.owner, address(otoken), payoutRecipient, settleMem.collateralPayout, vaultId, typeVault);
    }

    function _removeExcessCollateralFromRedemptionBalances(
        OtokenInterface otoken,
        uint256 strikePrice,
        uint256 underlyingExpiryPrice,
        uint256 collateralExpiryPrice
    ) internal {
        // now that we know the expiry price of the collateral and underlying assets, we can remove excess collateralRedemptionBalance from the pool
        // this simplifies settlement calculations because whatever remains can be split equally between any options that are not able to receive strike asset settlement

        (uint256 collateralRedemptionBalance,, uint256 otokenQuantity) = pool.getRedemptionBalance(address(otoken));
        uint256 totalExcessInPool;

        if (
            otoken.isPut() && underlyingExpiryPrice >= strikePrice || !otoken.isPut()
                && underlyingExpiryPrice <= strikePrice
        ) {
            // options expired OTM
            // no receiving asset consideration, vaults receive all their collateral back
            // set collateralRedemptionBalance to 0 since calculator.getExcessCollateral handles this case (because short options are worthless)
            // return if already set to 0
            if (collateralRedemptionBalance == 0) return;

            totalExcessInPool = collateralRedemptionBalance;
        } else if (otoken.isPut()) {
            // dont need to handle ITM put cases because collateralAsset == strikeAsset, so fully collateralised with no excess.
            return;
        } else if (!otoken.isPut()) {
            // ITM calls
            // first, check to see if this has already been done. We only want to do it once, the first time a settle OR redeem is done.
            // if is has NOT been done, collateralRedemptionBalance == otokenQuantity (accounting for decimals).
            // so we can return if this is not the case because it has already been done

            uint256 otokenQuantityCollateralDecimals =
                otokenQuantity * (10 ** uint256(IERC20Metadata(otoken.collateralAsset()).decimals())) / 1e8;

            if (collateralRedemptionBalance != otokenQuantityCollateralDecimals) return;

            // calls expired ITM
            // excess collateral for each option in pool is 1 - underlyingPrice/collateralPrice
            // if underlyingPrice >= collateralPrice, there is no excess: set to 0
            totalExcessInPool = underlyingExpiryPrice < collateralExpiryPrice
                ? otokenQuantityCollateralDecimals
                    - (otokenQuantityCollateralDecimals * underlyingExpiryPrice / collateralExpiryPrice)
                : 0;
        }

        // reduce value in redemptionBalancePool
        pool.updateRedemptionBalance(address(otoken), 0, false, -int256(totalExcessInPool));
    }

    /**
     * @dev get otoken detail, from both otoken versions
     */
    function _getOtokenDetails(address _otoken) internal view returns (address, address, address, uint256) {
        OtokenInterface otoken = OtokenInterface(_otoken);
        try otoken.getOtokenDetails() returns (
            address collateral, address underlying, address strike, uint256, uint256 expiry, bool, bool
        ) {
            return (collateral, underlying, strike, expiry);
        } catch {
            return (otoken.collateralAsset(), otoken.underlyingAsset(), otoken.strikeAsset(), otoken.expiryTimestamp());
        }
    }

    function _isNotEmpty(address[] memory _array) internal pure returns (bool) {
        return (_array.length > 0) && (_array[0] != address(0));
    }

    /**
     * @dev updates the internal configuration of the controller
     */
    function _refreshConfigInternal() internal {
        whitelist = WhitelistInterface(addressbook.getWhitelist());
        controller = ControllerInterface(addressbook.getController());
        oracle = OracleInterface(addressbook.getOracle());
        calculator = MarginCalculatorInterface(addressbook.getMarginCalculator());
        pool = MarginPoolInterface(addressbook.getMarginPool());
    }
}

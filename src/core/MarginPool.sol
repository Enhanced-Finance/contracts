/**
 * SPDX-License-Identifier: MIT
 */
pragma solidity ^0.8.28;

import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {OwnableUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {AddressBookInterface} from "./interfaces/AddressBookInterface.sol";

/**
 * @author Opyn Team
 * @title MarginPool
 * @notice Contract that holds all protocol funds
 */
contract MarginPool is OwnableUpgradeable, UUPSUpgradeable {
    using SafeERC20 for IERC20;

    /*  This struct will be used to handle the return of funds to option writers for physically settled options.
        Because oTokens are not associated with individual vaults (and therefore short sellers), we need a way to
        fairly distribute the strike payments and unclaimed collateral across all users who wrote and sold those
        oTokens. As ITM options are exercised, the collateralBalance will decrease (as the collateral is used for
        payout) and the receivingAssetBalance will increase as exercisers pay the strike price for their underlying
        for calls, or one underlying asset for puts.
        otokenQuantity is the number of options that are outstanding that the balances are to be split between.
    */
    struct RedemptionBalances {
        uint256 collateralBalance; // calls: underlying / yield generating derivative asset, puts: strike asset
        uint256 receivingAssetBalance; // calls: strike asset / yield generating stablecoin , puts: underlying asset
        uint256 otokenQuantity;
    }

    /// @notice AddressBook module
    address public addressBook;
    /// @dev the address that has the ability to withdraw excess assets in the pool
    address public farmer;
    /// @dev mapping between an asset and the amount of the asset in the pool
    mapping(address => uint256) internal assetBalance;
    /// @dev mapping to track asset balances for each physically settled oToken
    mapping(address => RedemptionBalances) internal redemptionBalances;

    /// @notice emits an event when marginpool receive funds from controller
    event TransferToPool(address indexed asset, address indexed user, uint256 amount);
    /// @notice emits an event when marginpool transfer funds to controller
    event TransferToUser(address indexed asset, address indexed user, uint256 amount);
    /// @notice emit event after updating the farmer address
    event FarmerUpdated(address indexed oldAddress, address indexed newAddress);
    /// @notice emit event when an asset gets harvested from the pool
    event AssetFarmed(address indexed asset, address indexed receiver, uint256 amount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice initializer
     * @param _addressBook AddressBook module
     */
    function initialize(address _addressBook, address _owner) external initializer {
        require(_addressBook != address(0), "Invalid address book");
        __Ownable_init(_owner);
        addressBook = _addressBook;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @notice check if the sender is the Controller module
     */
    modifier onlyController() {
        _onlyController();
        _;
    }

    function _onlyController() internal view {
        require(
            msg.sender == AddressBookInterface(addressBook).getController()
                || msg.sender == AddressBookInterface(addressBook).getControllerLogic(),
            "MarginPool: Sender is not Controller"
        );
    }

    /**
     * @notice check if the sender is the farmer address
     */
    modifier onlyFarmer() {
        _onlyFarmer();
        _;
    }

    function _onlyFarmer() internal view {
        require(msg.sender == farmer, "MarginPool: Sender is not farmer");
    }

    /**
     * @notice transfers an asset from a user to the pool
     * @param _asset address of the asset to transfer
     * @param _user address of the user to transfer assets from
     * @param _amount amount of the token to transfer from _user
     */
    function transferToPool(address _asset, address _user, uint256 _amount) public onlyController {
        require(_amount > 0, "MarginPool: transferToPool amount is equal to 0");
        assetBalance[_asset] = assetBalance[_asset] + _amount;

        // transfer _asset _amount from _user to pool
        IERC20(_asset).safeTransferFrom(_user, address(this), _amount);
        emit TransferToPool(_asset, _user, _amount);
    }

    /**
     * @notice transfers an asset from the pool to a user
     * @param _asset address of the asset to transfer
     * @param _user address of the user to transfer assets to
     * @param _amount amount of the token to transfer to _user
     */
    function transferToUser(address _asset, address _user, uint256 _amount) public onlyController {
        require(_user != address(this), "MarginPool: cannot transfer assets to oneself");
        assetBalance[_asset] = assetBalance[_asset] - _amount;

        // transfer _asset _amount from pool to _user
        IERC20(_asset).safeTransfer(_user, _amount);
        emit TransferToUser(_asset, _user, _amount);
    }

    /**
     * @notice updates the RedemptionBalance values for an otoken
     * @param _otoken address of the otokon
     * @param _otokenAmount amount of otokens that have been minted or burned. negative for burn
     * @param _isReceivingAsset true if receiving asset, false if collateral asset
     * @param _assetAmount amount to increment/decrement strike or collateral asset by (negative for decrement)
     */
    function updateRedemptionBalance(address _otoken, int256 _otokenAmount, bool _isReceivingAsset, int256 _assetAmount)
        public
        onlyController
    {
        if (_isReceivingAsset) {
            _assetAmount >= 0
                ? redemptionBalances[_otoken].receivingAssetBalance =
                    redemptionBalances[_otoken].receivingAssetBalance + uint256(_assetAmount)
                : redemptionBalances[_otoken].receivingAssetBalance =
                    redemptionBalances[_otoken].receivingAssetBalance - uint256(-_assetAmount);
        } else {
            _assetAmount >= 0
                ? redemptionBalances[_otoken].collateralBalance =
                    redemptionBalances[_otoken].collateralBalance + uint256(_assetAmount)
                : redemptionBalances[_otoken].collateralBalance =
                    redemptionBalances[_otoken].collateralBalance - uint256(-_assetAmount);
        }

        _otokenAmount >= 0
            ? redemptionBalances[_otoken].otokenQuantity = redemptionBalances[_otoken].otokenQuantity
                + uint256(_otokenAmount)
            : redemptionBalances[_otoken].otokenQuantity =
                redemptionBalances[_otoken].otokenQuantity - uint256(-_otokenAmount);
    }

    /**
     * @notice get the stored balance of an asset
     * @param _asset asset address
     * @return asset balance
     */
    function getStoredBalance(address _asset) external view returns (uint256) {
        return assetBalance[_asset];
    }

    /**
     * @notice get the redemption balances of an oToken
     * @param _oToken oToken address
     * @return collateralBalance the balance of collateralAsset to be split between short sellers when they settle
     * @return receivingAssetBalance the balance of strikeAsset to be split between short sellers when they settle
     *
     */
    function getRedemptionBalance(address _oToken)
        external
        view
        returns (uint256 collateralBalance, uint256 receivingAssetBalance, uint256 otokenQuantity)
    {
        RedemptionBalances memory balance = redemptionBalances[_oToken];
        return (balance.collateralBalance, balance.receivingAssetBalance, balance.otokenQuantity);
    }

    /**
     * @notice transfers multiple assets from users to the pool
     * @param _asset addresses of the assets to transfer
     * @param _user addresses of the users to transfer assets to
     * @param _amount amount of each token to transfer to pool
     */
    function batchTransferToPool(address[] memory _asset, address[] memory _user, uint256[] memory _amount)
        external
        onlyController
    {
        require(
            _asset.length == _user.length && _user.length == _amount.length,
            "MarginPool: batchTransferToPool array lengths are not equal"
        );

        for (uint256 i = 0; i < _asset.length; i++) {
            // transfer _asset _amount from _user to pool
            transferToPool(_asset[i], _user[i], _amount[i]);
        }
    }

    /**
     * @notice transfers multiple assets from the pool to users
     * @param _asset addresses of the assets to transfer
     * @param _user addresses of the users to transfer assets to
     * @param _amount amount of each token to transfer to _user
     */
    function batchTransferToUser(address[] memory _asset, address[] memory _user, uint256[] memory _amount)
        external
        onlyController
    {
        require(
            _asset.length == _user.length && _user.length == _amount.length,
            "MarginPool: batchTransferToUser array lengths are not equal"
        );

        for (uint256 i = 0; i < _asset.length; i++) {
            // transfer _asset _amount from pool to _user
            transferToUser(_asset[i], _user[i], _amount[i]);
        }
    }

    /**
     * @notice function to collect the excess balance of a particular asset
     * @dev can only be called by the farmer address. Do not farm otokens.
     * @param _asset asset address
     * @param _receiver receiver address
     * @param _amount amount to remove from pool
     */
    function farm(address _asset, address _receiver, uint256 _amount) external onlyFarmer {
        require(_receiver != address(0), "MarginPool: invalid receiver address");

        uint256 externalBalance = IERC20(_asset).balanceOf(address(this));
        uint256 storedBalance = assetBalance[_asset];

        require(_amount <= externalBalance - storedBalance, "MarginPool: amount to farm exceeds limit");

        IERC20(_asset).safeTransfer(_receiver, _amount);

        emit AssetFarmed(_asset, _receiver, _amount);
    }

    /**
     * @notice function to set farmer address
     * @dev can only be called by MarginPool owner
     * @param _farmer farmer address
     */
    function setFarmer(address _farmer) external onlyOwner {
        emit FarmerUpdated(farmer, _farmer);

        farmer = _farmer;
    }
}

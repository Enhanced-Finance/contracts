/**
 * SPDX-License-Identifier: MIT
 */
pragma solidity ^0.8.28;

import {AddressBookInterface} from "./interfaces/AddressBookInterface.sol";
import {OwnableUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

/**
 * @author Opyn Team
 * @title Whitelist Module
 * @notice The whitelist module keeps track of all valid oToken addresses, product hashes, collateral addresses, and callee addresses.
 */
contract Whitelist is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    /// @notice AddressBook module address
    address public addressBook;
    /// @dev mapping to track whitelisted products
    mapping(bytes32 => bool) internal whitelistedProduct;
    /// @dev mapping to track whitelisted collateral
    mapping(address => bool) internal whitelistedCollateral;
    /// @dev mapping to mapping to track whitelisted collateral for covered calls or puts
    mapping(bytes32 => bool) internal coveredWhitelistedCollateral;
    /// @dev mapping to mapping to track whitelisted collateral for naked calls or puts
    mapping(bytes32 => bool) internal nakedWhitelistedCollateral;
    /// @dev mapping to track whitelisted oTokens
    mapping(address => bool) internal whitelistedOtoken;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice initializer
     * @param _addressBook AddressBook module address
     * @param _owner owner address
     */
    function initialize(address _addressBook, address _owner) external initializer {
        require(_addressBook != address(0), "Invalid address book");

        __Ownable_init(_owner);
        addressBook = _addressBook;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /// @notice emits an event a product is whitelisted by the owner address
    event ProductWhitelisted(
        bytes32 productHash, address indexed underlying, address indexed strike, address indexed collateral, bool isPut
    );
    /// @notice emits an event a product is blacklisted by the owner address
    event ProductBlacklisted(
        bytes32 productHash, address indexed underlying, address indexed strike, address indexed collateral, bool isPut
    );
    /// @notice emits an event when a collateral address is whitelisted by the owner address
    event CollateralWhitelisted(address indexed collateral);
    /// @notice emits an event when a collateral address for vault type 0 or 2 is whitelisted by the owner address
    event CoveredCollateralWhitelisted(address indexed collateral, address underlying, bool isPut);
    /// @notice emits an event when a collateral address for vault type 1 is whitelisted by the owner address
    event NakedCollateralWhitelisted(address indexed collateral, address underlying, bool isPut);
    /// @notice emits an event when a collateral address is blacklist by the owner address
    event CollateralBlacklisted(address indexed collateral);
    /// @notice emits an event when an oToken is whitelisted by the OtokenFactory module
    event OtokenWhitelisted(address indexed otoken);
    /// @notice emits an event when an oToken is blacklisted by the OtokenFactory module
    event OtokenBlacklisted(address indexed otoken);

    /**
     * @notice check if the sender is the oTokenFactory module
     */
    modifier onlyFactory() {
        _onlyFactory();
        _;
    }

    function _onlyFactory() internal view {
        require(
            msg.sender == AddressBookInterface(addressBook).getOtokenFactory(), "Whitelist: Sender is not OtokenFactory"
        );
    }

    /**
     * @notice check if a product is whitelisted
     * @dev product is the hash of underlying asset, strike asset, collateral asset, and isPut
     * @param _underlying asset that the option references
     * @param _strike asset that the strike price is denominated in
     * @param _collateral asset that is held as collateral against short/written options
     * @param _isPut True if a put option, False if a call option
     * @return boolean, True if product is whitelisted
     */
    function isWhitelistedProduct(address _underlying, address _strike, address _collateral, bool _isPut)
        external
        view
        returns (bool)
    {
        bytes32 productHash = keccak256(abi.encode(_underlying, _strike, _collateral, _isPut));

        return whitelistedProduct[productHash];
    }

    /**
     * @notice check if a collateral asset is whitelisted
     * @param _collateral asset that is held as collateral against short/written options
     * @return boolean, True if the collateral is whitelisted
     */
    function isWhitelistedCollateral(address _collateral) external view returns (bool) {
        return whitelistedCollateral[_collateral];
    }

    /**
     * @notice check if a collateral asset is whitelisted for vault type 0 or 2
     * @param _collateral asset that is held as collateral against short/written options
     * @param _underlying asset that is used as the underlying asset for the written options
     * @param _isPut bool for whether the collateral is to be checked for suitability on a call or put
     * @return boolean, True if the collateral is whitelisted for vault type 0 or 2
     */
    function isCoveredWhitelistedCollateral(address _collateral, address _underlying, bool _isPut)
        external
        view
        returns (bool)
    {
        bytes32 productHash = keccak256(abi.encode(_collateral, _underlying, _isPut));
        return coveredWhitelistedCollateral[productHash];
    }

    /**
     * @notice check if a collateral asset is whitelisted for vault type 1
     * @param _collateral asset that is held as collateral against short/written options
     * @param _underlying asset that is used as the underlying asset for the written options
     * @param _isPut bool for whether the collateral is to be checked for suitability on a call or put
     * @return boolean, True if the collateral is whitelisted for vault type 1
     */
    function isNakedWhitelistedCollateral(address _collateral, address _underlying, bool _isPut)
        external
        view
        returns (bool)
    {
        bytes32 productHash = keccak256(abi.encode(_collateral, _underlying, _isPut));
        return nakedWhitelistedCollateral[productHash];
    }

    /**
     * @notice check if an oToken is whitelisted
     * @param _otoken oToken address
     * @return boolean, True if the oToken is whitelisted
     */
    function isWhitelistedOtoken(address _otoken) external view returns (bool) {
        return whitelistedOtoken[_otoken];
    }

    /**
     * @notice allows the owner to whitelist a product
     * @dev product is the hash of underlying asset, strike asset, collateral asset, and isPut
     * can only be called from the owner address
     * @param _underlying asset that the option references
     * @param _strike asset that the strike price is denominated in
     * @param _collateral asset that is held as collateral against short/written options
     * @param _isPut True if a put option, False if a call option
     */
    function whitelistProduct(address _underlying, address _strike, address _collateral, bool _isPut)
        external
        onlyOwner
    {
        require(whitelistedCollateral[_collateral], "Whitelist: Collateral is not whitelisted");

        bytes32 productHash = keccak256(abi.encode(_underlying, _strike, _collateral, _isPut));

        whitelistedProduct[productHash] = true;

        emit ProductWhitelisted(productHash, _underlying, _strike, _collateral, _isPut);
    }

    /**
     * @notice allow the owner to blacklist a product
     * @dev product is the hash of underlying asset, strike asset, collateral asset, and isPut
     * can only be called from the owner address
     * @param _underlying asset that the option references
     * @param _strike asset that the strike price is denominated in
     * @param _collateral asset that is held as collateral against short/written options
     * @param _isPut True if a put option, False if a call option
     */
    function blacklistProduct(address _underlying, address _strike, address _collateral, bool _isPut)
        external
        onlyOwner
    {
        bytes32 productHash = keccak256(abi.encode(_underlying, _strike, _collateral, _isPut));

        whitelistedProduct[productHash] = false;

        emit ProductBlacklisted(productHash, _underlying, _strike, _collateral, _isPut);
    }

    /**
     * @notice allows the owner to whitelist a collateral address
     * @dev can only be called from the owner address. This function is used to whitelist any asset other than Otoken as collateral. WhitelistOtoken() is used to whitelist Otoken contracts.
     * @param _collateral collateral asset address
     */
    function whitelistCollateral(address _collateral) external onlyOwner {
        whitelistedCollateral[_collateral] = true;

        emit CollateralWhitelisted(_collateral);
    }

    /**
     * @notice allows the owner to whitelist a collateral address for vault type 0 or 2
     * @dev can only be called from the owner address. This function is used to whitelist any asset other than Otoken as collateral.
     * @param _collateral collateral asset address
     * @param _underlying underlying asset address
     * @param _isPut bool for whether the collateral is suitable for puts or calls
     */
    function whitelistCoveredCollateral(address _collateral, address _underlying, bool _isPut) external onlyOwner {
        require(_isPut || _collateral == _underlying, "Whitelist: covered call collateral must be underlying");
        bytes32 productHash = keccak256(abi.encode(_collateral, _underlying, _isPut));
        coveredWhitelistedCollateral[productHash] = true;
        emit CoveredCollateralWhitelisted(_collateral, _underlying, _isPut);
    }

    /**
     * @notice allows the owner to whitelist a collateral address for vault type 1
     * @dev can only be called from the owner address. This function is used to whitelist any asset other than Otoken as collateral.
     * @param _collateral collateral asset address
     * @param _underlying underlying asset address
     * @param _isPut bool for whether the collateral is suitable for puts or calls
     */
    function whitelistNakedCollateral(address _collateral, address _underlying, bool _isPut) external onlyOwner {
        bytes32 productHash = keccak256(abi.encode(_collateral, _underlying, _isPut));
        nakedWhitelistedCollateral[productHash] = true;
        emit NakedCollateralWhitelisted(_collateral, _underlying, _isPut);
    }

    /**
     * @notice allows the owner to blacklist a collateral address
     * @dev can only be called from the owner address
     * @param _collateral collateral asset address
     */
    function blacklistCollateral(address _collateral) external onlyOwner {
        whitelistedCollateral[_collateral] = false;

        emit CollateralBlacklisted(_collateral);
    }

    /**
     * @notice allows the OtokenFactory module to whitelist a new option
     * @dev can only be called from the OtokenFactory address
     * @param _otokenAddress oToken
     */
    function whitelistOtoken(address _otokenAddress) external onlyFactory {
        whitelistedOtoken[_otokenAddress] = true;

        emit OtokenWhitelisted(_otokenAddress);
    }

    /**
     * @notice allows the owner to blacklist an option
     * @dev can only be called from the owner address
     * @param _otokenAddress oToken
     */
    function blacklistOtoken(address _otokenAddress) external onlyOwner {
        whitelistedOtoken[_otokenAddress] = false;

        emit OtokenBlacklisted(_otokenAddress);
    }
}

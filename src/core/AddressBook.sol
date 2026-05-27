/**
 * SPDX-License-Identifier: MIT
 */
pragma solidity ^0.8.28;

import {OwnableUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {ERC1967Proxy} from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {UUPSUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

/**
 * @author Opyn Team
 * @title AddressBook Module
 */
contract AddressBook is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    /// @dev Otoken implementation key
    bytes32 private constant OTOKEN_IMPL = keccak256("OTOKEN_IMPL");
    /// @dev OtokenFactory key
    bytes32 private constant OTOKEN_FACTORY = keccak256("OTOKEN_FACTORY");
    /// @dev Whitelist key
    bytes32 private constant WHITELIST = keccak256("WHITELIST");
    /// @dev Controller key
    bytes32 private constant CONTROLLER = keccak256("CONTROLLER");
    /// @dev MarginPool key
    bytes32 private constant MARGIN_POOL = keccak256("MARGIN_POOL");
    /// @dev MarginCalculator key
    bytes32 private constant MARGIN_CALCULATOR = keccak256("MARGIN_CALCULATOR");
    /// @dev ControllerLogic key
    bytes32 private constant CONTROLLER_LOGIC = keccak256("CONTROLLER_LOGIC");
    /// @dev LiquidationManager key
    bytes32 private constant LIQUIDATION_MANAGER = keccak256("LIQUIDATION_MANAGER");
    /// @dev Oracle key
    bytes32 private constant ORACLE = keccak256("ORACLE");

    /// @dev mapping between key and address
    mapping(bytes32 => address) private addresses;

    /// @notice emits an event when a new proxy is created
    event ProxyCreated(bytes32 indexed id, address indexed proxy);
    /// @notice emits an event when a new address is added
    event AddressAdded(bytes32 indexed id, address indexed add);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice initializer
     * @param _owner owner address
     */
    function initialize(address _owner) external initializer {
        __Ownable_init(_owner);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @notice return Otoken implementation address
     * @return Otoken implementation address
     */
    function getOtokenImpl() external view returns (address) {
        return getAddress(OTOKEN_IMPL);
    }

    /**
     * @notice return oTokenFactory address
     * @return OtokenFactory address
     */
    function getOtokenFactory() external view returns (address) {
        return getAddress(OTOKEN_FACTORY);
    }

    /**
     * @notice return Whitelist address
     * @return Whitelist address
     */
    function getWhitelist() external view returns (address) {
        return getAddress(WHITELIST);
    }

    /**
     * @notice return Controller address
     * @return Controller address
     */
    function getController() external view returns (address) {
        return getAddress(CONTROLLER);
    }

    /**
     * @notice return MarginPool address
     * @return MarginPool address
     */
    function getMarginPool() external view returns (address) {
        return getAddress(MARGIN_POOL);
    }

    /**
     * @notice return MarginCalculator address
     * @return MarginCalculator address
     */
    function getMarginCalculator() external view returns (address) {
        return getAddress(MARGIN_CALCULATOR);
    }

    /**
     * @notice return ControllerLogic address
     * @return ControllerLogic address
     */
    function getControllerLogic() external view returns (address) {
        return getAddress(CONTROLLER_LOGIC);
    }

    /**
     * @notice return LiquidationManager address
     * @return LiquidationManager address
     */
    function getLiquidationManager() external view returns (address) {
        return getAddress(LIQUIDATION_MANAGER);
    }

    /**
     * @notice return Oracle address
     * @return Oracle address
     */
    function getOracle() external view returns (address) {
        return getAddress(ORACLE);
    }

    /**
     * @notice set Otoken implementation address
     * @dev can only be called by the addressbook owner
     * @param _otokenImpl Otoken implementation address
     */
    function setOtokenImpl(address _otokenImpl) external onlyOwner {
        setAddress(OTOKEN_IMPL, _otokenImpl);
    }

    /**
     * @notice set OtokenFactory address
     * @dev can only be called by the addressbook owner
     * @param _otokenFactory OtokenFactory address
     */
    function setOtokenFactory(address _otokenFactory) external onlyOwner {
        setAddress(OTOKEN_FACTORY, _otokenFactory);
    }

    /**
     * @notice set Whitelist address
     * @dev can only be called by the addressbook owner
     * @param _whitelist Whitelist address
     */
    function setWhitelist(address _whitelist) external onlyOwner {
        setAddress(WHITELIST, _whitelist);
    }

    /**
     * @notice set Controller address
     * @dev can only be called by the addressbook owner
     * @param _controller Controller address
     */
    function setController(address _controller) external onlyOwner {
        updateImpl(CONTROLLER, _controller);
    }

    /**
     * @notice set MarginPool address
     * @dev can only be called by the addressbook owner
     * @param _marginPool MarginPool address
     */
    function setMarginPool(address _marginPool) external onlyOwner {
        updateImpl(MARGIN_POOL, _marginPool);
    }

    /**
     * @notice set MarginCalculator address
     * @dev can only be called by the addressbook owner
     * @param _marginCalculator MarginCalculator address
     */
    function setMarginCalculator(address _marginCalculator) external onlyOwner {
        setAddress(MARGIN_CALCULATOR, _marginCalculator);
    }

    /**
     * @notice set ControllerLogic address
     * @dev can only be called by the addressbook owner
     * @param _controllerLogic ControllerLogic address
     */
    function setControllerLogic(address _controllerLogic) external onlyOwner {
        updateImpl(CONTROLLER_LOGIC, _controllerLogic);
    }

    /**
     * @notice set LiquidationManager address
     * @dev can only be called by the addressbook owner
     * @param _liquidationManager LiquidationManager address
     */
    function setLiquidationManager(address _liquidationManager) external onlyOwner {
        setAddress(LIQUIDATION_MANAGER, _liquidationManager);
    }

    /**
     * @notice set Oracle address
     * @dev can only be called by the addressbook owner
     * @param _oracle Oracle address
     */
    function setOracle(address _oracle) external onlyOwner {
        setAddress(ORACLE, _oracle);
    }

    /**
     * @notice return an address for specific key
     * @param _key key address
     * @return address
     */
    function getAddress(bytes32 _key) public view returns (address) {
        return addresses[_key];
    }

    /**
     * @notice set a specific address for a specific key
     * @dev can only be called by the addressbook owner
     * @param _key key
     * @param _address address
     */
    function setAddress(bytes32 _key, address _address) public onlyOwner {
        addresses[_key] = _address;

        emit AddressAdded(_key, _address);
    }

    /**
     * @dev function to update the implementation of a specific component of the protocol
     * @param _id id of the contract to be updated
     * @param _newAddress address of the new implementation
     *
     */
    function updateImpl(bytes32 _id, address _newAddress) public onlyOwner {
        address payable proxyAddress = payable(getAddress(_id));

        if (proxyAddress == address(0)) {
            // controller has 3 address params, controller logic and margin pool have 2
            // However, we updated ControllerLogic and MarginPool to use 2 params.
            // Check Controller.sol init params: initialize(address _addressBook, address _owner, address _manager) -> 3 params.
            bytes memory params;
            if (_id == CONTROLLER) {
                params = abi.encodeWithSignature(
                    "initialize(address,address,address)",
                    address(this),
                    owner(),
                    owner() // manager defaults to owner
                );
            } else {
                params = abi.encodeWithSignature("initialize(address,address)", address(this), owner());
            }

            ERC1967Proxy proxy = new ERC1967Proxy(_newAddress, params);
            setAddress(_id, address(proxy));
            emit ProxyCreated(_id, address(proxy));
        } else {
            revert("Proxy already exists. Upgrade manually via UUPS.");
        }
    }
}

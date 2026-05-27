// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {EnhancedOptions} from "src/core/EnhancedOptions.sol";
import {MMarket} from "src/core/MMarket.sol";
import {MockERC20} from "src/core/mocks/MockERC20.sol";
import {Actions} from "src/core/libs/Actions.sol";
import {MMarketOperations} from "src/core/libs/MMarketOperations.sol";
import {MarginVault} from "src/core/libs/MarginVault.sol";

contract EnhancedOptionsCustodyHarness is EnhancedOptions {
    function trackedReleaseVaultCount(address owner) external view returns (uint256) {
        return vaultsWithOutstandingRelease[owner].length;
    }

    function trackedReleaseVaultId(address owner, uint256 index) external view returns (uint256) {
        return vaultsWithOutstandingRelease[owner][index];
    }

    function isTrackedReleaseVault(address owner, uint256 vaultId) external view returns (bool) {
        return isVaultReleaseTracked[owner][vaultId];
    }
}

contract EnhancedOptionsCustodyControllerMock {
    Actions.ActionType public lastActionType;
    address public lastOwner;
    address public lastSecondAddress;
    address public lastAsset;
    uint256 public lastVaultId;
    uint256 public lastAmount;
    uint256 public operateCount;

    mapping(address => mapping(uint256 => MarginVault.Vault)) internal vaults;
    mapping(address => mapping(uint256 => uint256)) internal vaultTypes;
    address public marginCalculator;
    bool public systemFullyPaused;

    function setMarginCalculator(address calculator) external {
        marginCalculator = calculator;
    }

    function setSystemFullyPaused(bool paused) external {
        systemFullyPaused = paused;
    }

    function setVaultCollateral(address vaultOwner, uint256 vaultId, address asset, uint256 amount) external {
        MarginVault.Vault storage vault = vaults[vaultOwner][vaultId];
        delete vault.collateralAssets;
        delete vault.collateralAmounts;
        vault.collateralAssets.push(asset);
        vault.collateralAmounts.push(amount);
    }

    function setVaultShortOtoken(address vaultOwner, uint256 vaultId, address shortOtoken, uint256 amount) external {
        MarginVault.Vault storage vault = vaults[vaultOwner][vaultId];
        delete vault.shortOtokens;
        delete vault.shortAmounts;
        vault.shortOtokens.push(shortOtoken);
        vault.shortAmounts.push(amount);
    }

    function setVaultType(address vaultOwner, uint256 vaultId, uint256 vaultType) external {
        vaultTypes[vaultOwner][vaultId] = vaultType;
    }

    function getVaultWithDetails(address vaultOwner, uint256 vaultId)
        external
        view
        returns (MarginVault.Vault memory, uint256, uint256)
    {
        return (vaults[vaultOwner][vaultId], vaultTypes[vaultOwner][vaultId], 0);
    }

    function getConfiguration() external view returns (address, address, address, address) {
        return (address(0), address(0), marginCalculator, address(this));
    }

    function donate(address asset, uint256 amount) external {
        IERC20(asset).transferFrom(msg.sender, address(this), amount);
    }

    function releaseVaultCollateralToCustody(address asset, address receiver, uint256 amount) external {
        IERC20(asset).transfer(receiver, amount);
    }

    function setManager(address) external {}

    function getAccountVaultCounter(address) external pure returns (uint256) {
        return 0;
    }

    function operate(Actions.ActionArgs[] memory actions) external {
        operateCount += 1;

        for (uint256 i; i < actions.length; i++) {
            Actions.ActionArgs memory action = actions[i];
            lastActionType = action.actionType;
            lastOwner = action.owner;
            lastSecondAddress = action.secondAddress;
            lastAsset = action.asset;
            lastVaultId = action.vaultId;
            lastAmount = action.amount;

            if (action.actionType == Actions.ActionType.WithdrawCollateral) {
                IERC20(action.asset).transfer(action.secondAddress, action.amount);
            } else if (action.actionType == Actions.ActionType.DepositCollateral) {
                IERC20(action.asset).transferFrom(action.secondAddress, address(this), action.amount);
            }
        }
    }
}

contract EnhancedOptionsCustodyMarginCalculatorMock {
    uint256 public excessCollateral = type(uint256).max;
    bool public isExcess = true;

    function setExcessCollateral(uint256 amount, bool excess) external {
        excessCollateral = amount;
        isExcess = excess;
    }

    function getExcessCollateral(MarginVault.Vault calldata, uint256) external view returns (uint256, bool) {
        return (excessCollateral, isExcess);
    }
}

contract EnhancedOptionsCustodyOtokenMock {
    uint256 public immutable expiryTimestamp;

    constructor(uint256 expiry) {
        expiryTimestamp = expiry;
    }
}

contract EnhancedOptionsCustodyReleaseTest is Test {
    uint256 internal constant OWNER_PK = 0xA11CE;
    uint256 internal constant OPERATOR_PK = 0xB0B;
    uint256 internal constant MAKER_PK = 0xE11E;

    bytes32 internal constant EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 internal constant ENHANCED_NAME_HASH = keccak256(bytes("enhanced"));
    bytes32 internal constant ENHANCED_VERSION_HASH = keccak256(bytes("0.0.0"));
    bytes32 internal constant CUSTODY_RELEASE_TYPEHASH = keccak256(
        "CustodyRelease(address maker,address receiver,uint256 chainId,uint64 nonce,uint64 validUntil,bytes32 requestsHash)"
    );
    bytes32 internal constant CUSTODY_RELEASE_REQUEST_TYPEHASH =
        keccak256("CustodyReleaseRequest(address owner,uint256 vaultId,address asset,uint256 amount)");

    address internal owner;
    address internal operator;
    address internal maker;
    address internal receiver = address(0xBEEF);
    address internal returner = address(0xDAD);

    EnhancedOptionsCustodyHarness internal enhancedOptions;
    MMarket internal mmarket;
    EnhancedOptionsCustodyControllerMock internal controller;
    EnhancedOptionsCustodyMarginCalculatorMock internal marginCalculator;
    MockERC20 internal underlying;
    MockERC20 internal otoken;

    function setUp() external {
        owner = vm.addr(OWNER_PK);
        operator = vm.addr(OPERATOR_PK);
        maker = vm.addr(MAKER_PK);

        enhancedOptions = new EnhancedOptionsCustodyHarness();
        mmarket = new MMarket();
        controller = new EnhancedOptionsCustodyControllerMock();
        marginCalculator = new EnhancedOptionsCustodyMarginCalculatorMock();
        underlying = new MockERC20("Underlying", "UND", 18);
        otoken = new MockERC20("Otoken", "OTK", 18);
        controller.setMarginCalculator(address(marginCalculator));

        _unlockInitializers(address(enhancedOptions));
        _unlockInitializers(address(mmarket));

        vm.startPrank(owner);
        enhancedOptions.initialize();
        mmarket.initialize();
        enhancedOptions.setOperator(operator);
        enhancedOptions.setController(address(controller));
        enhancedOptions.setMMarket(address(mmarket));
        enhancedOptions.setMarginPool(address(controller));
        mmarket.setOperator(address(enhancedOptions));
        vm.stopPrank();
    }

    function test_ownerCanSetMakerCustodyLimitBps() external {
        vm.prank(owner);
        enhancedOptions.setMakerCustodyLimitBps(maker, receiver, 7000);

        assertEq(enhancedOptions.makerCustodyLimitBps(maker, receiver), 7000);

        vm.prank(owner);
        enhancedOptions.setMakerCustodyLimitBps(maker, receiver, 0);

        assertEq(enhancedOptions.makerCustodyLimitBps(maker, receiver), 0);
    }

    function test_operatorCanBatchReleaseCollateralWithMakerSignature() external {
        _setMakerCustodyLimitBps(maker, receiver, 10000);
        _setVaultCollateral(maker, 1, address(underlying), 1 ether);
        _setVaultCollateral(maker, 2, address(underlying), 2 ether);
        underlying.mint(address(controller), 10 ether);

        EnhancedOptions.CustodyReleaseRequest[] memory requests = _custodyReleaseRequests();
        bytes memory sig = _signCustodyRelease(maker, receiver, 1, uint64(block.timestamp + 1 days), requests);

        vm.prank(operator);
        enhancedOptions.ingressoReleaseCollateralToCustody(maker, receiver, 1, uint64(block.timestamp + 1 days), requests, sig);

        assertEq(underlying.balanceOf(receiver), 3 ether);

        (address recordedCustodian, address recordedAsset, uint256 releasedAmount, uint256 outstandingAmount) =
            enhancedOptions.vaultCustodyReleases(maker, 1);
        assertEq(recordedCustodian, receiver);
        assertEq(recordedAsset, address(underlying));
        assertEq(releasedAmount, 1 ether);
        assertEq(outstandingAmount, 1 ether);
    }

    function test_releaseRejectsUnauthorizedCustodian() external {
        EnhancedOptions.CustodyReleaseRequest[] memory requests = _custodyReleaseRequests();
        bytes memory sig = _signCustodyRelease(maker, receiver, 1, uint64(block.timestamp + 1 days), requests);

        vm.prank(operator);
        vm.expectRevert(EnhancedOptions.CustodianNotAuthorized.selector);
        enhancedOptions.ingressoReleaseCollateralToCustody(maker, receiver, 1, uint64(block.timestamp + 1 days), requests, sig);
    }

    function test_releaseRejectsAmountAboveVaultDeposit() external {
        _setMakerCustodyLimitBps(maker, receiver, 10000);
        _setVaultCollateral(maker, 1, address(underlying), 1 ether);
        underlying.mint(address(controller), 2 ether);

        EnhancedOptions.CustodyReleaseRequest[] memory requests = new EnhancedOptions.CustodyReleaseRequest[](1);
        requests[0] =
            EnhancedOptions.CustodyReleaseRequest({owner: maker, vaultId: 1, asset: address(underlying), amount: 1 ether + 1});
        bytes memory sig = _signCustodyRelease(maker, receiver, 2, uint64(block.timestamp + 1 days), requests);

        vm.prank(operator);
        vm.expectRevert(EnhancedOptions.ExceedsVaultDeposit.selector);
        enhancedOptions.ingressoReleaseCollateralToCustody(maker, receiver, 2, uint64(block.timestamp + 1 days), requests, sig);
    }

    function test_releaseRejectsAmountAboveMakerCustodyLimit() external {
        _setMakerCustodyLimitBps(maker, receiver, 7000);
        _setVaultCollateral(maker, 1, address(underlying), 10 ether);
        underlying.mint(address(controller), 10 ether);

        EnhancedOptions.CustodyReleaseRequest[] memory requests = new EnhancedOptions.CustodyReleaseRequest[](1);
        requests[0] =
            EnhancedOptions.CustodyReleaseRequest({owner: maker, vaultId: 1, asset: address(underlying), amount: 7 ether + 1});
        bytes memory sig = _signCustodyRelease(maker, receiver, 3, uint64(block.timestamp + 1 days), requests);

        vm.prank(operator);
        vm.expectRevert(EnhancedOptions.ExceedsMakerCustodyLimit.selector);
        enhancedOptions.ingressoReleaseCollateralToCustody(maker, receiver, 3, uint64(block.timestamp + 1 days), requests, sig);
    }

    function test_releaseAllowsAmountAtMakerCustodyLimit() external {
        _setMakerCustodyLimitBps(maker, receiver, 7000);
        _setVaultCollateral(maker, 1, address(underlying), 10 ether);
        underlying.mint(address(controller), 10 ether);

        EnhancedOptions.CustodyReleaseRequest[] memory requests = new EnhancedOptions.CustodyReleaseRequest[](1);
        requests[0] =
            EnhancedOptions.CustodyReleaseRequest({owner: maker, vaultId: 1, asset: address(underlying), amount: 7 ether});
        bytes memory sig = _signCustodyRelease(maker, receiver, 4, uint64(block.timestamp + 1 days), requests);

        vm.prank(operator);
        enhancedOptions.ingressoReleaseCollateralToCustody(maker, receiver, 4, uint64(block.timestamp + 1 days), requests, sig);

        assertEq(underlying.balanceOf(receiver), 7 ether);
        (,,, uint256 outstandingAmount) = enhancedOptions.vaultCustodyReleases(maker, 1);
        assertEq(outstandingAmount, 7 ether);
    }

    function test_releaseRejectsWhenControllerFullyPaused() external {
        _setMakerCustodyLimitBps(maker, receiver, 10000);
        _setVaultCollateral(maker, 1, address(underlying), 1 ether);
        controller.setSystemFullyPaused(true);

        EnhancedOptions.CustodyReleaseRequest[] memory requests = new EnhancedOptions.CustodyReleaseRequest[](1);
        requests[0] =
            EnhancedOptions.CustodyReleaseRequest({owner: maker, vaultId: 1, asset: address(underlying), amount: 1 ether});
        bytes memory sig = _signCustodyRelease(maker, receiver, 7, uint64(block.timestamp + 1 days), requests);

        vm.prank(operator);
        vm.expectRevert(EnhancedOptions.SystemFullyPaused.selector);
        enhancedOptions.ingressoReleaseCollateralToCustody(maker, receiver, 7, uint64(block.timestamp + 1 days), requests, sig);
    }

    function test_releaseRejectsExpiredVault() external {
        _setMakerCustodyLimitBps(maker, receiver, 10000);
        _setVaultCollateral(maker, 1, address(underlying), 10 ether);
        EnhancedOptionsCustodyOtokenMock expiredOtoken = new EnhancedOptionsCustodyOtokenMock(block.timestamp);
        controller.setVaultShortOtoken(maker, 1, address(expiredOtoken), 1 ether);
        underlying.mint(address(controller), 10 ether);

        EnhancedOptions.CustodyReleaseRequest[] memory requests = new EnhancedOptions.CustodyReleaseRequest[](1);
        requests[0] =
            EnhancedOptions.CustodyReleaseRequest({owner: maker, vaultId: 1, asset: address(underlying), amount: 1 ether});
        bytes memory sig = _signCustodyRelease(maker, receiver, 6, uint64(block.timestamp + 1 days), requests);

        vm.prank(operator);
        vm.expectRevert(EnhancedOptions.CannotReleaseFromExpiredVault.selector);
        enhancedOptions.ingressoReleaseCollateralToCustody(maker, receiver, 6, uint64(block.timestamp + 1 days), requests, sig);
    }

    function test_anyoneCanReturnFromCustody() external {
        _releaseOnce();
        underlying.mint(returner, 1 ether);

        uint256[] memory vaultIds = new uint256[](1);
        vaultIds[0] = 1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1 ether;

        vm.startPrank(returner);
        underlying.approve(address(enhancedOptions), 1 ether);
        enhancedOptions.ingressoReturnFromCustody(maker, vaultIds, amounts);
        vm.stopPrank();

        (,,, uint256 outstandingAmount) = enhancedOptions.vaultCustodyReleases(maker, 1);
        assertEq(outstandingAmount, 0);
        assertEq(underlying.balanceOf(address(controller)), 8 ether);
    }

    function test_returnRemovesFullyReturnedVaultsFromTracking() external {
        _releaseOnce();

        assertEq(enhancedOptions.trackedReleaseVaultCount(maker), 2);
        assertTrue(enhancedOptions.isTrackedReleaseVault(maker, 1));
        assertTrue(enhancedOptions.isTrackedReleaseVault(maker, 2));

        _returnOnce();

        assertEq(enhancedOptions.trackedReleaseVaultCount(maker), 0);
        assertFalse(enhancedOptions.isTrackedReleaseVault(maker, 1));
        assertFalse(enhancedOptions.isTrackedReleaseVault(maker, 2));
    }

    function test_redeemRevertsWhenMakerHasOutstandingCustodyRelease() external {
        _releaseOnce();
        _seedMMarketOtokenBalance();

        (MMarketOperations.Operation[] memory operations, Actions.ActionArgs[] memory actions) = _redeemArgs();

        vm.prank(operator);
        vm.expectRevert(EnhancedOptions.OutstandingCustodyRelease.selector);
        enhancedOptions.ingressoRedeem(operations, actions);
    }

    function test_redeemCanProceedAfterCustodyIsReturned() external {
        _releaseOnce();
        _returnOnce();
        _seedMMarketOtokenBalance();

        (MMarketOperations.Operation[] memory operations, Actions.ActionArgs[] memory actions) = _redeemArgs();

        vm.prank(operator);
        enhancedOptions.ingressoRedeem(operations, actions);

        assertEq(uint256(controller.lastActionType()), uint256(Actions.ActionType.Redeem));
    }

    function _releaseOnce() internal {
        _setMakerCustodyLimitBps(maker, receiver, 10000);
        _setVaultCollateral(maker, 1, address(underlying), 1 ether);
        _setVaultCollateral(maker, 2, address(underlying), 2 ether);
        underlying.mint(address(controller), 10 ether);

        EnhancedOptions.CustodyReleaseRequest[] memory requests = _custodyReleaseRequests();
        bytes memory sig = _signCustodyRelease(maker, receiver, 1, uint64(block.timestamp + 1 days), requests);

        vm.prank(operator);
        enhancedOptions.ingressoReleaseCollateralToCustody(maker, receiver, 1, uint64(block.timestamp + 1 days), requests, sig);
    }

    function _returnOnce() internal {
        underlying.mint(returner, 3 ether);

        uint256[] memory vaultIds = new uint256[](2);
        vaultIds[0] = 1;
        vaultIds[1] = 2;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1 ether;
        amounts[1] = 2 ether;

        vm.startPrank(returner);
        underlying.approve(address(enhancedOptions), 3 ether);
        enhancedOptions.ingressoReturnFromCustody(maker, vaultIds, amounts);
        vm.stopPrank();
    }

    function _custodyReleaseRequests() internal view returns (EnhancedOptions.CustodyReleaseRequest[] memory requests) {
        requests = new EnhancedOptions.CustodyReleaseRequest[](2);
        requests[0] =
            EnhancedOptions.CustodyReleaseRequest({owner: maker, vaultId: 1, asset: address(underlying), amount: 1 ether});
        requests[1] =
            EnhancedOptions.CustodyReleaseRequest({owner: maker, vaultId: 2, asset: address(underlying), amount: 2 ether});
    }

    function _seedMMarketOtokenBalance() internal {
        otoken.mint(maker, 1 ether);
        vm.prank(maker);
        otoken.approve(address(mmarket), 1 ether);

        MMarketOperations.Operation[] memory operations = new MMarketOperations.Operation[](1);
        operations[0] = MMarketOperations.Operation({
            operationType: MMarketOperations.OperationType.Deposit,
            user1: maker,
            user2: maker,
            asset1: address(otoken),
            asset2: address(0),
            amount1: 1 ether,
            amount2: 0,
            data: ""
        });

        vm.prank(address(enhancedOptions));
        mmarket.operate(operations);
    }

    function _redeemArgs()
        internal
        view
        returns (MMarketOperations.Operation[] memory operations, Actions.ActionArgs[] memory actions)
    {
        operations = new MMarketOperations.Operation[](1);
        operations[0] = MMarketOperations.Operation({
            operationType: MMarketOperations.OperationType.Withdraw,
            user1: maker,
            user2: address(enhancedOptions),
            asset1: address(otoken),
            asset2: address(0),
            amount1: 1 ether,
            amount2: 0,
            data: ""
        });

        actions = new Actions.ActionArgs[](1);
        actions[0] = Actions.ActionArgs({
            actionType: Actions.ActionType.Redeem,
            owner: address(0),
            secondAddress: maker,
            asset: address(otoken),
            vaultId: 0,
            amount: 1 ether,
            index: 0,
            data: ""
        });
    }

    function _setMakerCustodyLimitBps(address targetMaker, address targetReceiver, uint256 bps) internal {
        vm.prank(owner);
        enhancedOptions.setMakerCustodyLimitBps(targetMaker, targetReceiver, bps);
    }

    function _setVaultCollateral(address vaultOwner, uint256 vaultId, address asset, uint256 amount) internal {
        controller.setVaultCollateral(vaultOwner, vaultId, asset, amount);
    }

    function _signCustodyRelease(
        address signer,
        address signedReceiver,
        uint64 nonce,
        uint64 validUntil,
        EnhancedOptions.CustodyReleaseRequest[] memory requests
    ) internal view returns (bytes memory sig) {
        bytes32 structHash = keccak256(
            abi.encode(
                CUSTODY_RELEASE_TYPEHASH, signer, signedReceiver, block.chainid, nonce, validUntil, _requestsHash(requests)
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", _enhancedDomainSeparator(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(MAKER_PK, digest);
        sig = abi.encodePacked(r, s, v);
    }

    function _requestsHash(EnhancedOptions.CustodyReleaseRequest[] memory requests) internal pure returns (bytes32) {
        bytes32[] memory hashes = new bytes32[](requests.length);
        for (uint256 i; i < requests.length; i++) {
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

    function _enhancedDomainSeparator() internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                EIP712_DOMAIN_TYPEHASH,
                ENHANCED_NAME_HASH,
                ENHANCED_VERSION_HASH,
                block.chainid,
                address(enhancedOptions)
            )
        );
    }

    function _unlockInitializers(address target) internal {
        bytes32 initializableStorageSlot = 0xf0c57e16840df040f15088dc2f81fe391c3923bec73e23a9662efc9c229c6a00;
        vm.store(target, initializableStorageSlot, bytes32(0));
    }
}

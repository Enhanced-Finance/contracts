// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "lib/solmate/src/utils/SafeTransferLib.sol";

import {AddressBook} from "src/core/AddressBook.sol";
import {Oracle} from "src/core/Oracle.sol";
import {Whitelist} from "src/core/Whitelist.sol";
import {MarginPool} from "src/core/MarginPool.sol";
import {MarginCalculator} from "src/core/MarginCalculator.sol";
import {ControllerLogic} from "src/core/ControllerLogic.sol";
import {OtokenFactory} from "src/core/OtokenFactory.sol";
import {Otoken} from "src/core/Otoken.sol";
import {Controller} from "src/core/Controller.sol";
import {MMarket} from "src/core/MMarket.sol";
import {EnhancedOptions} from "src/core/EnhancedOptions.sol";
import {ManualPricer} from "src/core/ManualPricer.sol";
import {IEnhancedOptionsTimelock} from "src/core/interfaces/IEnhancedOptionsTimelock.sol";
import {ISwapRouter} from "src/core/interfaces/ISwapRouter.sol";
import {Parser} from "src/core/libs/Parser.sol";
import {MarginVault} from "src/core/libs/MarginVault.sol";
import {EnhancedOptionsTimelockLib} from "src/core/libs/EnhancedOptionsTimelockLib.sol";
import {EnhancedVault} from "src/periphery/vault/EnhancedVault.sol";
import {EnhancedVaultLinkedLibraries} from "./EnhancedVaultLinkedLibraries.sol";

contract EnhancedVaultFixtureERC20 is ERC20 {
    constructor(string memory name_, string memory symbol_, uint8 decimals_) ERC20(name_, symbol_, decimals_) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract EnhancedVaultBuybackOnlySwapRouterMock is ISwapRouter {
    using SafeTransferLib for ERC20;

    address internal immutable STRIKE_ASSET;
    address internal immutable COLLATERAL_ASSET;

    constructor(address strikeAsset_, address collateralAsset_) {
        STRIKE_ASSET = strikeAsset_;
        COLLATERAL_ASSET = collateralAsset_;
    }

    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut) {
        require(params.tokenIn == STRIKE_ASSET, "UNSUPPORTED_INPUT");
        require(params.tokenOut == COLLATERAL_ASSET, "UNSUPPORTED_OUTPUT");

        ERC20(params.tokenIn).safeTransferFrom(msg.sender, address(this), params.amountIn);

        amountOut = params.amountIn;
        require(amountOut >= params.amountOutMinimum, "INSUFFICIENT_OUTPUT");

        // Test-only behavior: tokenOut is expected to be the fixture mintable ERC20.
        EnhancedVaultFixtureERC20(params.tokenOut).mint(params.recipient, amountOut);
    }

    function exactInput(ExactInputParams calldata) external payable returns (uint256) {
        revert("UNSUPPORTED");
    }

    function exactOutputSingle(ExactOutputSingleParams calldata) external payable returns (uint256) {
        revert("UNSUPPORTED");
    }

    function exactOutput(ExactOutputParams calldata) external payable returns (uint256) {
        revert("UNSUPPORTED");
    }
}

abstract contract EnhancedVaultIntegrationBase is EnhancedVaultLinkedLibraries {
    uint256 internal constant OWNER_PK = 0xA11CE;
    uint256 internal constant OPERATOR_PK = 0xB0B;
    uint256 internal constant VAULT_SIGNER_PK = 0xC0DE;
    uint256 internal constant USER_PK = 0xD00D;
    uint256 internal constant MAKER_PK = 0xE11E;
    uint256 internal constant BOT_PK = 0xF00D;

    uint256 internal constant INITIAL_USER_BALANCE = 1_000_000e18;
    uint256 internal constant INITIAL_MAKER_BALANCE = 1_000_000e18;
    uint256 internal constant SEEDED_UNDERLYING_PRICE = 2_000e8;
    address internal constant PARSER_LIBRARY_PLACEHOLDER = 0x848368Aa602C0634900992CBB3fD7B1E040080c0;
    address internal constant MARGIN_VAULT_LIBRARY_PLACEHOLDER = 0xB08C826f656D4BF7de6aB6Ad473ea0e0A7479c25;
    address internal constant ENHANCED_OPTIONS_TIMELOCK_LIBRARY_PLACEHOLDER =
        0xeF3cD61FDc9a41e32F6100FBef544bAB712dec9e;

    address internal owner;
    address internal operator;
    address internal vaultSigner;
    address internal user;
    address internal maker;
    address internal bot;

    EnhancedVaultFixtureERC20 internal underlying;
    EnhancedVaultFixtureERC20 internal strike;
    // Task 1 only deploys the router; wiring/exercising swap flows is deferred to later buyback tasks.
    EnhancedVaultBuybackOnlySwapRouterMock internal swapRouter;

    AddressBook internal addressBook;
    Oracle internal oracle;
    Whitelist internal whitelist;
    MarginPool internal marginPool;
    MarginCalculator internal marginCalculator;
    ControllerLogic internal controllerLogic;
    OtokenFactory internal factory;
    Otoken internal otokenImplementation;
    Controller internal controller;
    MMarket internal mmarket;
    EnhancedOptions internal enhancedOptions;
    ManualPricer internal manualPricer;
    EnhancedVault internal vault;

    bytes32 internal vaultHash;
    EnhancedVault.VaultParams internal defaultVaultParams;

    bytes32 internal constant EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 internal constant ENHANCED_NAME_HASH = keccak256(bytes("enhanced"));
    bytes32 internal constant ENHANCED_VERSION_HASH = keccak256(bytes("0.0.0"));
    bytes32 internal constant VAULT_NAME_HASH = keccak256(bytes("Vault"));
    bytes32 internal constant VAULT_VERSION_HASH = keccak256(bytes("0.0.0"));

    bytes32 internal constant TRANSFER_TYPEHASH =
        keccak256("Transfer(address user,address asset,uint256 chainId,uint256 amount,bool isDeposit,uint64 nonce)");
    bytes32 internal constant QUOTE_TYPEHASH = keccak256(
        "Quote(address assetAddress,uint256 chainId,bool isPut,bool isPhysicallySettled,uint256 strike,uint64 expiry,address maker,uint64 nonce,uint256 price,uint256 quantity,bool isTakerBuy,uint64 validUntil,address usd,address collateralAsset)"
    );
    bytes32 internal constant VAULT_ORDER_TYPEHASH = keccak256("VaultOrder(bytes32 vaultHash,bytes32 payloadHash)");

    struct TransferConfig {
        address user;
        address asset;
        uint256 amount;
        bool isDeposit;
        uint64 nonce;
    }

    struct OrderConfig {
        uint256 strikePrice;
        uint256 premiumPrice;
        uint256 quoteQuantity;
        uint256 quantity;
        uint256 collateralAmount;
        uint256 protocolFee;
        uint256 makerFee;
        uint64 expiry;
        bool isPut;
        bool isPhysicallySettled;
        uint64 quoteNonce;
        uint64 confirmationNonce;
        uint64 validUntil;
        bool isTakerBuy;
        address maker;
        address taker;
        address assetAddress;
        address usd;
        address collateralAsset;
    }

    struct OrderOverrides {
        uint256 strikePrice;
        uint256 premiumPrice;
        uint256 quoteQuantity;
        uint256 quantity;
        uint256 collateralAmount;
        uint256 protocolFee;
        uint256 makerFee;
        uint64 expiry;
        uint64 quoteNonce;
        uint64 confirmationNonce;
        uint64 validUntil;
        address maker;
        address taker;
        address assetAddress;
        address usd;
        address collateralAsset;
        bool hasIsPut;
        bool isPut;
        bool hasIsPhysicallySettled;
        bool isPhysicallySettled;
        bool hasIsTakerBuy;
        bool isTakerBuy;
    }

    function _vaultState(bytes32 targetVaultHash) internal view returns (EnhancedVault.VaultState memory st) {
        (
            EnhancedVault.VaultParams memory params,
            bool isActive,
            uint256 currentCycleId,
            uint256 currentCycleStart,
            uint256 totalDeposited,
            bool isPaused,
            bool isEnd,
            uint256 protocolFeeRate
        ) = vault.vaults(targetVaultHash);

        st = EnhancedVault.VaultState({
            params: params,
            isActive: isActive,
            currentCycleId: currentCycleId,
            currentCycleStart: currentCycleStart,
            totalDeposited: totalDeposited,
            isPaused: isPaused,
            isEnd: isEnd,
            protocolFeeRate: protocolFeeRate
        });
    }

    function _currentCycleId(bytes32 targetVaultHash) internal view returns (uint256 currentCycleId) {
        (,, currentCycleId,,,,,) = vault.vaults(targetVaultHash);
    }

    function _userFund(bytes32 targetVaultHash, address targetUser)
        internal
        view
        returns (EnhancedVault.UserFund memory fund)
    {
        (
            fund.activePrincipal,
            fund.pendingActivePrincipal,
            fund.pendingWithdrawAmount,
            fund.stoppedPrincipal,
            fund.systemPausedPrincipal,
            fund.materializedPremium,
            fund.entryCumCollateral,
            fund.entryCumPremium,
            fund.initialAmountTotal,
            fund.nextRecordId,
            fund.buybackEnabled,
            fund.exists,
            fund.autoBuyEnabled
        ) = vault.userFunds(targetVaultHash, targetUser);
    }

    function _cycleRecord(bytes32 targetVaultHash, uint256 cycleId)
        internal
        view
        returns (EnhancedVault.CycleRecord memory rec)
    {
        (
            rec.totalActiveCollateral,
            rec.remainingActiveCollateral,
            rec.totalPremium,
            rec.collateralRatio,
            rec.premiumRatio
        ) = vault.cycleRecords(targetVaultHash, cycleId);
    }

    function setUp() public virtual {
        _deployAndWireFixture();
    }

    function _deployAndWireFixture() internal virtual {
        _assignActors();
        _deployTokens();
        _deployCoreContracts();
        _initializeCoreContracts();

        vm.startPrank(owner);

        addressBook.setOracle(address(oracle));
        addressBook.setWhitelist(address(whitelist));
        addressBook.setMarginPool(address(marginPool));
        addressBook.setMarginCalculator(address(marginCalculator));
        addressBook.setControllerLogic(address(controllerLogic));
        addressBook.setOtokenFactory(address(factory));
        addressBook.setOtokenImpl(address(otokenImplementation));

        controller = new Controller();
        _unlockInitializers(address(controller));
        controller.initialize(address(addressBook), owner, address(enhancedOptions));
        addressBook.setController(address(controller));

        controller = Controller(address(addressBook.getController()));
        controllerLogic = ControllerLogic(address(addressBook.getControllerLogic()));
        marginPool = MarginPool(address(addressBook.getMarginPool()));

        controller.setManager(address(enhancedOptions));
        controller.refreshConfiguration();
        controllerLogic.refreshConfiguration();

        mmarket.setOperator(address(enhancedOptions));
        enhancedOptions.setController(address(controller));
        enhancedOptions.setMMarket(address(mmarket));
        enhancedOptions.setFactory(address(factory));
        enhancedOptions.setMarginPool(address(marginPool));
        enhancedOptions.setOperator(operator);
        _setMakerWhitelistAsOwner(maker, maker);

        vault.setAssetApprovalMarginPool(address(underlying), true);
        vault.setSwapRouter(address(swapRouter));
        vault.setAssetApprovalSwapRouter(address(strike), true);

        whitelist.whitelistCollateral(address(underlying));
        whitelist.whitelistCoveredCollateral(address(underlying), address(underlying), false);
        whitelist.whitelistProduct(address(underlying), address(strike), address(underlying), false);

        oracle.setStablePrice(address(strike), 1e8);
        oracle.setAssetPricer(address(underlying), address(manualPricer));
        oracle.setLockingPeriod(address(manualPricer), 0);
        oracle.setDisputePeriod(address(manualPricer), 0);

        manualPricer.setPriceTimeValidity(30 days);
        manualPricer.setDeviationMultiplier(10_000);

        _createDefaultVault();

        vm.stopPrank();

        _approveUserDeposits();
        _approveMakerFunding();
        _seedUnderlyingSpotPrice();
    }

    function _assignActors() internal {
        owner = vm.addr(OWNER_PK);
        operator = vm.addr(OPERATOR_PK);
        vaultSigner = vm.addr(VAULT_SIGNER_PK);
        user = vm.addr(USER_PK);
        maker = vm.addr(MAKER_PK);
        bot = vm.addr(BOT_PK);
    }

    function _deployTokens() internal virtual {
        underlying = new EnhancedVaultFixtureERC20("Fixture Underlying", "fUND", 18);
        strike = new EnhancedVaultFixtureERC20("Fixture Strike", "fUSD", 18);

        underlying.mint(user, INITIAL_USER_BALANCE);
        underlying.mint(maker, INITIAL_MAKER_BALANCE);
        strike.mint(maker, INITIAL_MAKER_BALANCE);
    }

    function _deployCoreContracts() internal {
        // Direct-instance tests do not go through the production deployment linker, so we
        // materialize external library code at the compile-time placeholder addresses.
        vm.etch(PARSER_LIBRARY_PLACEHOLDER, type(Parser).runtimeCode);
        vm.etch(MARGIN_VAULT_LIBRARY_PLACEHOLDER, type(MarginVault).runtimeCode);
        vm.etch(ENHANCED_OPTIONS_TIMELOCK_LIBRARY_PLACEHOLDER, type(EnhancedOptionsTimelockLib).runtimeCode);
        _etchEnhancedVaultLibraries();

        swapRouter = new EnhancedVaultBuybackOnlySwapRouterMock(address(strike), address(underlying));

        addressBook = new AddressBook();
        oracle = new Oracle();
        whitelist = new Whitelist();
        marginPool = new MarginPool();
        marginCalculator = new MarginCalculator();
        controllerLogic = new ControllerLogic();
        factory = new OtokenFactory();
        otokenImplementation = new Otoken();
        mmarket = new MMarket();
        enhancedOptions = new EnhancedOptions();
        manualPricer = new ManualPricer();
        vault = new EnhancedVault();
    }

    function _initializeCoreContracts() internal {
        vm.startPrank(owner);
        _unlockInitializers(address(addressBook));
        addressBook.initialize(owner);

        _unlockInitializers(address(oracle));
        oracle.initialize(owner);

        _unlockInitializers(address(whitelist));
        whitelist.initialize(address(addressBook), owner);

        _unlockInitializers(address(marginPool));
        marginPool.initialize(address(addressBook), owner);

        _unlockInitializers(address(marginCalculator));
        marginCalculator.initialize(address(oracle), address(addressBook), owner);

        _unlockInitializers(address(controllerLogic));
        controllerLogic.initialize(address(addressBook), owner);

        _unlockInitializers(address(factory));
        factory.initialize(address(addressBook), owner);

        _unlockInitializers(address(mmarket));
        mmarket.initialize();

        _unlockInitializers(address(enhancedOptions));
        address[] memory initialTrustedTakers = new address[](1);
        initialTrustedTakers[0] = address(vault);
        address[] memory initialTrustedMakers = new address[](1);
        initialTrustedMakers[0] = maker;
        enhancedOptions.initialize(initialTrustedTakers, initialTrustedMakers, operator, operator);

        _unlockInitializers(address(manualPricer));
        manualPricer.initialize(bot, address(underlying), address(oracle), address(addressBook), owner);

        _unlockInitializers(address(vault));
        vault.initialize(address(enhancedOptions), operator, vaultSigner, owner);
        vm.stopPrank();
    }

    function _createDefaultVault() internal {
        defaultVaultParams = EnhancedVault.VaultParams({
            cycleDuration: 7 days,
            underlyingAsset: address(underlying),
            collateralAsset: address(underlying),
            strikeAsset: address(strike),
            isPut: false,
            capacity: 1_000_000e18,
            minInvestmentAmount: 1e18,
            startTime: block.timestamp + 1 days,
            strikePriceBps: 0,
            minPrincipalRatio: 0,
            buybackPriceRatio: 0
        });
        vaultHash = vault.createVault(defaultVaultParams, 0);
    }

    function _approveUserDeposits() internal {
        vm.prank(user);
        underlying.approve(address(vault), type(uint256).max);
    }

    function _approveMakerFunding() internal {
        vm.startPrank(maker);
        underlying.approve(address(mmarket), type(uint256).max);
        strike.approve(address(mmarket), type(uint256).max);
        vm.stopPrank();
    }

    function _seedUnderlyingSpotPrice() internal {
        if (block.timestamp <= 1) {
            vm.warp(2);
        }
        vm.prank(bot);
        manualPricer.setExpiryPriceInOracle(block.timestamp - 1, SEEDED_UNDERLYING_PRICE);
    }

    function _depositAs(address depositor, uint256 amount) internal {
        // Integration tests use a small cast of actors; lazily top up balance/approval so
        // multi-user flows can focus on lifecycle assertions instead of fixture bookkeeping.
        _ensureVaultDepositReady(depositor, amount);
        vm.prank(depositor);
        vault.deposit(vaultHash, amount);
    }

    function _warpToCycleEnd() internal {
        EnhancedVault.VaultState memory st = _vaultState(vaultHash);
        vm.warp(st.currentCycleStart + st.params.cycleDuration);
    }

    function _settleAndProcessInSingleBatch(bytes32 targetVaultHash) internal {
        vm.prank(operator);
        vault.nextCycle(targetVaultHash);
    }

    function _makerDepositStrikeToMMarket(uint256 amount) internal {
        TransferConfig memory cfg = _defaultTransferConfig();
        cfg.user = maker;
        cfg.asset = address(strike);
        cfg.amount = amount;
        cfg.isDeposit = true;
        cfg.nonce = uint64(_currentCycleId(vaultHash));

        bytes memory payload = _buildSignedTransferPayload(cfg);
        vm.prank(operator);
        enhancedOptions.ingressoTransferAsset(payload);
    }

    function _currentCycleExpiry() internal view returns (uint64) {
        EnhancedVault.VaultState memory st = _vaultState(vaultHash);
        return uint64(st.currentCycleStart + st.params.cycleDuration);
    }

    function _setExpiryPrice(uint256 expiry, uint256 price) internal {
        vm.warp(expiry + 1);
        vm.prank(bot);
        manualPricer.setExpiryPriceInOracle(expiry, price);
    }

    function _createOrderAsOperator(bytes32 targetVaultHash, OrderOverrides memory overrides)
        internal
        returns (uint256 vaultId)
    {
        uint256 cycleId = _currentCycleId(targetVaultHash);
        OrderConfig memory cfg = _createDefaultOrder(overrides);
        cfg.expiry = _currentCycleExpiry();

        bytes memory payload = _buildSignedOrderPayload(cfg);
        bytes memory vaultSig = _signVaultOrder(payload);

        uint256[] memory beforeVaultIds = vault.getVaultIds(targetVaultHash, cycleId);
        vm.prank(operator);
        vault.createOrder(targetVaultHash, payload, vaultSig, false);

        uint256[] memory afterVaultIds = vault.getVaultIds(targetVaultHash, cycleId);
        require(afterVaultIds.length == beforeVaultIds.length + 1, "vault count did not increase");
        vaultId = afterVaultIds[afterVaultIds.length - 1];
    }

    function _activateUserPosition(address depositor, uint256 amount) internal {
        _depositAs(depositor, amount);
        _warpToCycleEnd();
        _settleAndProcessInSingleBatch(vaultHash);
    }

    function _activateUsers(address firstUser, address secondUser, address thirdUser) internal {
        _depositAs(firstUser, 10 ether);
        _depositAs(secondUser, 10 ether);
        _depositAs(thirdUser, 10 ether);

        _warpToCycleEnd();
        _settleAndProcessInSingleBatch(vaultHash);

        // Queue all three users back into the current cycle so batched processing exercises
        // the real settled snapshot path instead of the empty-queue fast path.
        _depositAs(firstUser, 1 ether);
        _depositAs(secondUser, 1 ether);
        _depositAs(thirdUser, 1 ether);
    }

    function _finishCycleAtPrice(uint256 expiryPrice) internal {
        _ensureDefaultOrderOpen();

        uint256 cycleExpiry = _currentCycleExpiry();
        _setExpiryPrice(cycleExpiry, expiryPrice);
        vm.warp(cycleExpiry + 2);

        // Leave the vault in SETTLED so tests can exercise systemPause/process/start separately.
        vm.prank(operator);
        vault.settlePreviousCycle(vaultHash);
    }

    function _finishCycleInBatchesAtPrice(uint256 expiryPrice, uint256 limitPerBatch) internal {
        _finishCycleAtPrice(expiryPrice);
        _settleAndProcessInBatches(vaultHash, limitPerBatch);
    }

    function _settleAndProcessInBatches(bytes32 targetVaultHash, uint256 limitPerBatch) internal {
        require(limitPerBatch != 0, "invalid batch size");

        (
            EnhancedVault.CyclePhase phase,
            uint256 queueLen,
            uint256 processedCount,
            uint256 remaining,
            bool canStartNextCycle
        ) = vault.getQueueProgress(targetVaultHash);

        if (queueLen == 0) {
            require(
                phase == EnhancedVault.CyclePhase.PROCESSING_DONE && canStartNextCycle,
                "empty queue should already be startable"
            );
        }

        uint256 offset = processedCount;
        uint256 iterations;
        while (remaining > 0) {
            uint256 previousProcessed = processedCount;

            vm.prank(operator);
            vault.processQueuedUsers(targetVaultHash, offset, limitPerBatch);

            (phase, queueLen, processedCount, remaining, canStartNextCycle) = vault.getQueueProgress(targetVaultHash);
            require(processedCount > previousProcessed, "queue processing did not advance");
            require(queueLen >= processedCount, "processed count exceeds queue length");

            offset = processedCount;
            iterations += 1;
            require(iterations < 128, "queue processing did not converge");
        }

        require(phase == EnhancedVault.CyclePhase.PROCESSING_DONE, "phase should advance after queue processing");
        require(canStartNextCycle, "next cycle should be startable after queue processing");

        vm.prank(operator);
        vault.startNextCycle(targetVaultHash);
    }

    function _processCurrentSettledQueue(uint256 limitPerBatch) internal {
        vm.prank(operator);
        vault.processQueuedUsers(vaultHash, 0, limitPerBatch);
    }

    function _openNextCycleWithoutOrder() internal {
        _warpToCycleEnd();
        vm.prank(operator);
        vault.nextCycle(vaultHash);
    }

    function _users(address onlyUser) internal pure returns (address[] memory users) {
        users = new address[](1);
        users[0] = onlyUser;
    }

    function _defaultSwapParams(uint256 amountIn) internal view returns (EnhancedVault.SwapParams memory) {
        return EnhancedVault.SwapParams({
            amountIn: amountIn, amountOutMinimum: amountIn, deadline: block.timestamp + 1 hours, fee: 3_000
        });
    }

    function _configureMinPrincipalRatioVault(uint256 minPrincipalRatio) internal {
        EnhancedVault.VaultParams memory params = defaultVaultParams;
        params.startTime = block.timestamp + 1 days;
        params.minPrincipalRatio = minPrincipalRatio;

        vm.prank(owner);
        vaultHash = vault.createVault(params, 0);

        defaultVaultParams = params;
    }

    function _ensureVaultDepositReady(address depositor, uint256 amount) internal {
        uint256 balance = underlying.balanceOf(depositor);
        if (balance < amount) {
            underlying.mint(depositor, amount - balance);
        }

        if (underlying.allowance(depositor, address(vault)) < amount) {
            vm.prank(depositor);
            underlying.approve(address(vault), type(uint256).max);
        }
    }

    function _ensureDefaultOrderOpen() internal {
        uint256 cycleId = _currentCycleId(vaultHash);
        if (vault.getVaultIds(vaultHash, cycleId).length != 0) {
            return;
        }

        // Each cycle needs a fresh maker quote/confirmation nonce pair so repeated integration
        // flows exercise real signature validation instead of replaying the first order payload.
        OrderOverrides memory overrides = _defaultOrderOverrides();
        overrides.quoteNonce = uint64(cycleId);
        overrides.confirmationNonce = uint64(cycleId);
        overrides.validUntil = uint64(block.timestamp + 1 days);

        _makerDepositStrikeToMMarket(1_000 ether);
        _createOrderAsOperator(vaultHash, overrides);
    }

    function _setMakerWhitelistAsOwner(address targetMaker, address receiver) internal {
        bytes memory key = abi.encode(targetMaker);
        enhancedOptions.scheduleConfigUpdate(
            IEnhancedOptionsTimelock.TimelockConfigType.MakerWhitelist, abi.encode(targetMaker, receiver)
        );
        (, uint64 executeAfter) =
            enhancedOptions.pendingConfigUpdate(IEnhancedOptionsTimelock.TimelockConfigType.MakerWhitelist, key);
        vm.warp(executeAfter);
        enhancedOptions.executeConfigUpdate(IEnhancedOptionsTimelock.TimelockConfigType.MakerWhitelist, key);
    }

    function _unlockInitializers(address target) internal {
        // Direct-instance fixture tests intentionally bypass _disableInitializers().
        // This depends on current OZ Initializable storage layout and must be revisited if OZ internals change.
        bytes32 initializableStorageSlot = 0xf0c57e16840df040f15088dc2f81fe391c3923bec73e23a9662efc9c229c6a00;
        vm.store(target, initializableStorageSlot, bytes32(0));
    }

    function _defaultTransferConfig() internal view returns (TransferConfig memory cfg) {
        cfg = TransferConfig({user: user, asset: address(underlying), amount: 1e18, isDeposit: true, nonce: 1});
    }

    function _defaultOrderOverrides() internal pure returns (OrderOverrides memory) {
        return OrderOverrides({
            strikePrice: 0,
            premiumPrice: 0,
            quoteQuantity: 0,
            quantity: 0,
            collateralAmount: 0,
            protocolFee: 0,
            makerFee: 0,
            expiry: 0,
            quoteNonce: 0,
            confirmationNonce: 0,
            validUntil: 0,
            maker: address(0),
            taker: address(0),
            assetAddress: address(0),
            usd: address(0),
            collateralAsset: address(0),
            hasIsPut: false,
            isPut: false,
            hasIsPhysicallySettled: false,
            isPhysicallySettled: false,
            hasIsTakerBuy: false,
            isTakerBuy: false
        });
    }

    function _createDefaultOrder(OrderOverrides memory overrides) internal view returns (OrderConfig memory cfg) {
        cfg = OrderConfig({
            strikePrice: SEEDED_UNDERLYING_PRICE,
            premiumPrice: 1e18,
            quoteQuantity: 1e18,
            quantity: 1e18,
            collateralAmount: 1e18,
            protocolFee: 0,
            makerFee: 0,
            expiry: uint64(defaultVaultParams.startTime + defaultVaultParams.cycleDuration),
            isPut: defaultVaultParams.isPut,
            isPhysicallySettled: false,
            quoteNonce: 1,
            confirmationNonce: 1,
            validUntil: uint64(block.timestamp + 1 days),
            isTakerBuy: true,
            maker: maker,
            taker: address(vault),
            assetAddress: address(underlying),
            usd: address(strike),
            collateralAsset: address(underlying)
        });

        if (overrides.strikePrice != 0) cfg.strikePrice = overrides.strikePrice;
        if (overrides.premiumPrice != 0) cfg.premiumPrice = overrides.premiumPrice;
        if (overrides.quoteQuantity != 0) cfg.quoteQuantity = overrides.quoteQuantity;
        if (overrides.quantity != 0) cfg.quantity = overrides.quantity;
        if (overrides.collateralAmount != 0) cfg.collateralAmount = overrides.collateralAmount;
        if (overrides.protocolFee != 0) cfg.protocolFee = overrides.protocolFee;
        if (overrides.makerFee != 0) cfg.makerFee = overrides.makerFee;
        if (overrides.expiry != 0) cfg.expiry = overrides.expiry;
        if (overrides.quoteNonce != 0) cfg.quoteNonce = overrides.quoteNonce;
        if (overrides.confirmationNonce != 0) cfg.confirmationNonce = overrides.confirmationNonce;
        if (overrides.validUntil != 0) cfg.validUntil = overrides.validUntil;
        if (overrides.maker != address(0)) cfg.maker = overrides.maker;
        if (overrides.taker != address(0)) cfg.taker = overrides.taker;
        if (overrides.assetAddress != address(0)) cfg.assetAddress = overrides.assetAddress;
        if (overrides.usd != address(0)) cfg.usd = overrides.usd;
        if (overrides.collateralAsset != address(0)) cfg.collateralAsset = overrides.collateralAsset;
        if (overrides.hasIsPut) cfg.isPut = overrides.isPut;
        if (overrides.hasIsPhysicallySettled) cfg.isPhysicallySettled = overrides.isPhysicallySettled;
        if (overrides.hasIsTakerBuy) cfg.isTakerBuy = overrides.isTakerBuy;
    }

    function _buildSignedTransferPayload(TransferConfig memory cfg) internal view returns (bytes memory) {
        // The payload is packed into Parser's uint128 amount slot, so test inputs must stay in-range.
        require(cfg.amount <= type(uint128).max, "transfer amount overflow");
        bytes memory sig = _signTransfer(cfg);
        return abi.encodePacked(cfg.asset, uint128(cfg.amount), cfg.isDeposit, cfg.nonce, sig, cfg.user);
    }

    function _buildSignedOrderPayload(OrderConfig memory cfg) internal view returns (bytes memory) {
        // These fields are parsed from packed uint128 slots on-chain and must match the signed values exactly.
        require(cfg.premiumPrice <= type(uint128).max, "premium overflow");
        require(cfg.quoteQuantity <= type(uint128).max, "quote quantity overflow");
        require(cfg.quantity <= type(uint128).max, "quantity overflow");
        require(cfg.strikePrice <= type(uint128).max, "strike overflow");
        require(cfg.collateralAmount <= type(uint128).max, "collateral overflow");
        require(cfg.protocolFee <= type(uint128).max, "protocol fee overflow");
        require(cfg.makerFee <= type(uint128).max, "maker fee overflow");
        bytes memory quoteSig = _signMakerQuote(cfg);
        bytes memory confSig = new bytes(65);
        return abi.encodePacked(
            cfg.maker,
            cfg.assetAddress,
            uint64(cfg.expiry),
            cfg.isPut,
            cfg.isPhysicallySettled,
            cfg.confirmationNonce,
            uint128(cfg.premiumPrice),
            uint128(cfg.quoteQuantity),
            uint128(cfg.quantity),
            cfg.quoteNonce,
            quoteSig,
            confSig,
            uint128(cfg.strikePrice),
            cfg.taker,
            cfg.isTakerBuy,
            cfg.validUntil,
            cfg.usd,
            cfg.collateralAsset,
            uint128(cfg.collateralAmount),
            uint128(cfg.protocolFee),
            uint128(cfg.makerFee)
        );
    }

    function _signTransfer(TransferConfig memory cfg) internal view returns (bytes memory sig) {
        bytes32 structHash = keccak256(
            abi.encode(TRANSFER_TYPEHASH, cfg.user, cfg.asset, block.chainid, cfg.amount, cfg.isDeposit, cfg.nonce)
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", _enhancedDomainSeparator(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_privateKeyFor(cfg.user), digest);
        sig = abi.encodePacked(r, s, v);
    }

    function _signMakerQuote(OrderConfig memory cfg) internal view returns (bytes memory sig) {
        bytes memory encodedFirstHalf = abi.encode(
            QUOTE_TYPEHASH,
            cfg.assetAddress,
            block.chainid,
            cfg.isPut,
            cfg.isPhysicallySettled,
            cfg.strikePrice,
            cfg.expiry
        );
        bytes memory encodedSecondHalf = abi.encode(
            cfg.maker,
            cfg.quoteNonce,
            cfg.premiumPrice,
            cfg.quoteQuantity,
            cfg.isTakerBuy,
            cfg.validUntil,
            cfg.usd,
            cfg.collateralAsset
        );

        bytes32 structHash = keccak256(bytes.concat(encodedFirstHalf, encodedSecondHalf));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", _enhancedDomainSeparator(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_privateKeyFor(cfg.maker), digest);
        sig = abi.encodePacked(r, s, v);
    }

    function _signVaultOrder(bytes memory payload) internal view returns (bytes memory sig) {
        bytes32 structHash = keccak256(abi.encode(VAULT_ORDER_TYPEHASH, vaultHash, keccak256(payload)));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", _vaultDomainSeparator(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(VAULT_SIGNER_PK, digest);
        sig = abi.encodePacked(r, s, v);
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

    function _vaultDomainSeparator() internal view returns (bytes32) {
        return keccak256(
            abi.encode(EIP712_DOMAIN_TYPEHASH, VAULT_NAME_HASH, VAULT_VERSION_HASH, block.chainid, address(vault))
        );
    }

    function _privateKeyFor(address signer) internal view returns (uint256) {
        if (signer == owner) return OWNER_PK;
        if (signer == operator) return OPERATOR_PK;
        if (signer == vaultSigner) return VAULT_SIGNER_PK;
        if (signer == user) return USER_PK;
        if (signer == maker) return MAKER_PK;
        if (signer == bot) return BOT_PK;
        revert("unknown signer");
    }
}

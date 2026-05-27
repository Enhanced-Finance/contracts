-include .env

.PHONY: deploy_enhanced_options_impl deploy_enhanced_options \
		deploy_enhanced_strategy_impl deploy_enhanced_strategy_proxy \
        deploy_address_book_impl deploy_address_book_proxy \
        deploy_controller_impl deploy_controller_proxy \
        deploy_controller_logic_impl deploy_controller_logic_proxy \
        deploy_mmarket_impl deploy_mmarket_proxy \
        deploy_margin_calculator_impl deploy_margin_calculator_proxy \
        deploy_margin_pool_impl deploy_margin_pool_proxy \
        deploy_oracle_impl deploy_oracle_proxy \
        deploy_otoken_impl \
        deploy_otoken_factory_impl deploy_otoken_factory_proxy \
        deploy_whitelist_impl deploy_whitelist_proxy \
        deploy_all_impl deploy_all_proxy deploy_all_configure deploy_all \
        deploy_address_book deploy_controller deploy_controller_logic deploy_mmarket \
        deploy_margin_calculator deploy_margin_pool deploy_oracle deploy_otoken \
        deploy_otoken_factory deploy_whitelist \
        deploy_enhanced_strategy \
        configure_enhanced_strategy configure_enhanced_options_trusted_roles create_strategy \
        build

.PHONY: strategy_set_active strategy_set_operator strategy_set_signer \
		strategy_set_swap_router \
		strategy_deposit strategy_create_order strategy_next_cycle \
		strategy_buyback strategy_force_pause_funds strategy_clear_force_exit strategy_pause_fund \
		strategy_cancel_pause strategy_withdraw strategy_set_margin_pool strategy_set_asset_approval_margin_pool \
		strategy_set_asset_approval_swap_router

.PHONY: ingresso_new_user_position ingresso_transfer_asset ingresso_mmarket_deposit ingresso_otc_trade ingresso_redeem ingresso_settle ingresso_deposit_and_open

.PHONY: upgrade_enhanced_strategy deploy_multicall3

# Default RPC URL if not set in .env
RPC_URL ?= https://evm-rpc-testnet.sei-apis.com
CHAIN_ID ?= 1328

# Helper function to update .env with implementation address
# define update_env_impl
# 	@echo "Updating .env..."
# 	@node -e 'const fs = require("fs"); const chainId = "$(CHAIN_ID)"; const deployFile = "./.deploy/" + chainId + ".json"; if (fs.existsSync(deployFile)) { const data = JSON.parse(fs.readFileSync(deployFile)); const contractData = data.$(1); if (contractData) { const envFile = ".env"; let envContent = fs.existsSync(envFile) ? fs.readFileSync(envFile, "utf8") : ""; const implKey = contractData.contractName + "_IMPL"; const newLine = `${implKey}=${contractData.implementationAddress}`; if (envContent.includes(implKey)) { envContent = envContent.replace(new RegExp(`${implKey}=.*`), newLine); } else { if (envContent.length > 0 && !envContent.endsWith("\n")) envContent += "\n"; envContent += newLine; } fs.writeFileSync(envFile, envContent); console.log(`Updated .env with ${newLine}`); } else { console.error("Contract data for $(1) not found in deploy file"); process.exit(1); } } else { console.error("Deploy file not found:", deployFile); process.exit(1); }'
# endef

build:
	@echo "Building contracts..."
	forge clean && forge build --via-ir

# ==========================================
# 0. Deploy Libraries
# ==========================================
deploy_libs: deploy_parser deploy_margin_vault

deploy_parser:
	@echo "Deploying Parser..."
	forge create src/core/libs/Parser.sol:Parser --rpc-url $(RPC_URL) --private-key $(PRIVATE_KEY) --broadcast

deploy_margin_vault:
	@echo "Deploying MarginVault..."
	forge create src/libs/MarginVault.sol:MarginVault --rpc-url $(RPC_URL) --private-key $(PRIVATE_KEY) --broadcast

# ==========================================
# 1. Deploy All Implementations
# ==========================================
deploy_all_impl: deploy_address_book_impl \
                 deploy_oracle_impl \
                 deploy_whitelist_impl \
                 deploy_margin_pool_impl \
                 deploy_margin_calculator_impl \
                 deploy_controller_logic_impl \
                 deploy_controller_impl \
                 deploy_otoken_impl \
                 deploy_otoken_factory_impl \
                 deploy_mmarket_impl \
                 deploy_enhanced_options_impl \
                 deploy_enhanced_strategy_impl

# ==========================================
# 2. Deploy All Proxies
# Order matters due to dependencies!
# ==========================================
deploy_all_proxy: deploy_enhanced_options \
                  deploy_address_book_proxy \
                  deploy_oracle_proxy \
                  deploy_whitelist_proxy \
                  deploy_margin_pool_proxy \
                  deploy_margin_calculator_proxy \
                  deploy_controller_logic_proxy \
                  deploy_controller_proxy \
                  deploy_otoken_factory_proxy \
                  deploy_mmarket_proxy \
                  deploy_enhanced_strategy_proxy

# ==========================================
# 3. Configure All
# ==========================================
deploy_all_configure: configure_enhanced_options \
                      configure_enhanced_options_trusted_roles \
                      configure_address_book \
                      configure_oracle \
                      configure_whitelist \
                      configure_margin_pool \
                      configure_margin_calculator \
                      configure_controller_logic \
                      configure_controller \
                      configure_mmarket \
                      configure_enhanced_strategy \
                      refresh_controller_config \
					  whitelist_product

# ==========================================
# 4. Deploy Single Contract Full (Impl + Proxy)
# ==========================================
deploy_address_book: deploy_address_book_impl deploy_address_book_proxy
deploy_controller: deploy_controller_impl deploy_controller_proxy
deploy_controller_logic: deploy_controller_logic_impl deploy_controller_logic_proxy
deploy_mmarket: deploy_mmarket_impl deploy_mmarket_proxy
deploy_margin_calculator: deploy_margin_calculator_impl deploy_margin_calculator_proxy
deploy_margin_pool: deploy_margin_pool_impl deploy_margin_pool_proxy
deploy_oracle: deploy_oracle_impl deploy_oracle_proxy
deploy_otoken: deploy_otoken_impl
deploy_otoken_factory: deploy_otoken_factory_impl deploy_otoken_factory_proxy
deploy_whitelist: deploy_whitelist_impl deploy_whitelist_proxy
deploy_enhanced_strategy: deploy_enhanced_strategy_impl deploy_enhanced_strategy_proxy

# ==========================================
# 5. Deploy Everything
# ==========================================
deploy_all: deploy_all_impl deploy_all_proxy deploy_all_configure

# ==========================================
# Individual Deployment Commands
# ==========================================

deploy_enhanced_options_impl:
	@echo "Deploying EnhancedOptions Implementation..."
	forge script ./script/EnhancedOptions/DeployEnhancedOptions.s.sol --rpc-url $(RPC_URL) --broadcast
	# $(call update_env_impl,EnhancedOptions)

deploy_enhanced_options:
	@echo "Deploying EnhancedOptions Proxy..."
	forge script ./script/EnhancedOptions/DeployEnhancedOptionsProxy.s.sol --rpc-url $(RPC_URL) --broadcast -g 500

deploy_enhanced_strategy_impl:
	@echo "Deploying EnhancedStrategy Implementation..."
	forge script ./script/EnhancedStrategy/DeployEnhancedStrategy.s.sol --rpc-url $(RPC_URL) --via-ir --broadcast

deploy_enhanced_strategy_proxy:
	@echo "Deploying EnhancedStrategy Proxy..."
	forge script ./script/EnhancedStrategy/DeployEnhancedStrategyProxy.s.sol --rpc-url $(RPC_URL)  --via-ir --broadcast -g 500

deploy_address_book_impl:
	@echo "Deploying AddressBook Implementation..."
	forge script ./script/AddressBook/DeployAddressBook.s.sol --rpc-url $(RPC_URL) --broadcast
	# $(call update_env_impl,AddressBook)

deploy_address_book_proxy:
	@echo "Deploying AddressBook Proxy..."
	forge script ./script/AddressBook/DeployAddressBookProxy.s.sol --rpc-url $(RPC_URL) --broadcast -g 500

deploy_controller_impl:
	@echo "Deploying Controller Implementation..."
	forge script ./script/Controller/DeployController.s.sol --rpc-url $(RPC_URL) --broadcast
	# $(call update_env_impl,Controller)

deploy_controller_proxy:
	@echo "Deploying Controller Proxy..."
	forge script ./script/Controller/DeployControllerProxy.s.sol --rpc-url $(RPC_URL) --broadcast -g 500

deploy_controller_logic_impl:
	@echo "Deploying ControllerLogic Implementation..."
	forge script ./script/ControllerLogic/DeployControllerLogic.s.sol --rpc-url $(RPC_URL) --broadcast
	# $(call update_env_impl,ControllerLogic)

deploy_controller_logic_proxy:
	@echo "Deploying ControllerLogic Proxy..."
	forge script ./script/ControllerLogic/DeployControllerLogicProxy.s.sol --rpc-url $(RPC_URL) --broadcast -g 500

deploy_mmarket_impl:
	@echo "Deploying MMarket Implementation..."
	forge script ./script/MMarket/DeployMMarket.s.sol --rpc-url $(RPC_URL) --broadcast
	# $(call update_env_impl,MMarket)

deploy_mmarket_proxy:
	@echo "Deploying MMarket Proxy..."
	forge script ./script/MMarket/DeployMMarketProxy.s.sol --rpc-url $(RPC_URL) --broadcast -g 500

deploy_margin_calculator_impl:
	@echo "Deploying MarginCalculator Implementation..."
	forge script ./script/MarginCalculator/DeployMarginCalculator.s.sol --rpc-url $(RPC_URL) --broadcast
	# $(call update_env_impl,MarginCalculator)

deploy_margin_calculator_proxy:
	@echo "Deploying MarginCalculator Proxy..."
	forge script ./script/MarginCalculator/DeployMarginCalculatorProxy.s.sol --rpc-url $(RPC_URL) --broadcast -g 500

deploy_margin_pool_impl:
	@echo "Deploying MarginPool Implementation..."
	forge script ./script/MarginPool/DeployMarginPool.s.sol --rpc-url $(RPC_URL) --broadcast
	# $(call update_env_impl,MarginPool)

deploy_margin_pool_proxy:
	@echo "Deploying MarginPool Proxy..."
	forge script ./script/MarginPool/DeployMarginPoolProxy.s.sol --rpc-url $(RPC_URL) --broadcast -g 500

deploy_oracle_impl:
	@echo "Deploying Oracle Implementation..."
	forge script ./script/Oracle/DeployOracle.s.sol --rpc-url $(RPC_URL) --broadcast
	# $(call update_env_impl,Oracle)

deploy_oracle_proxy:
	@echo "Deploying Oracle Proxy..."
	forge script ./script/Oracle/DeployOracleProxy.s.sol --rpc-url $(RPC_URL) --broadcast -g 500

deploy_otoken_impl:
	@echo "Deploying Otoken Implementation..."
	forge script ./script/Otoken/DeployOtoken.s.sol --rpc-url $(RPC_URL) --broadcast -g 200
	# $(call update_env_impl,Otoken)

deploy_otoken_factory_impl:
	@echo "Deploying OtokenFactory Implementation..."
	forge script ./script/OtokenFactory/DeployOtokenFactory.s.sol --rpc-url $(RPC_URL) --broadcast
	# $(call update_env_impl,OtokenFactory)

deploy_otoken_factory_proxy:
	@echo "Deploying OtokenFactory Proxy..."
	forge script ./script/OtokenFactory/DeployOtokenFactoryProxy.s.sol --rpc-url $(RPC_URL) --broadcast -g 500

deploy_whitelist_impl:
	@echo "Deploying Whitelist Implementation..."
	forge script ./script/Whitelist/DeployWhitelist.s.sol --rpc-url $(RPC_URL) --broadcast
	# $(call update_env_impl,Whitelist)

deploy_whitelist_proxy:
	@echo "Deploying Whitelist Proxy..."
	forge script ./script/Whitelist/DeployWhitelistProxy.s.sol --rpc-url $(RPC_URL) --broadcast -g 500

# ==========================================
# Configuration Commands
# ==========================================

configure_address_book:
	@echo "Configuring AddressBook..."
	forge script ./script/AddressBook/ConfigureAddressBook.s.sol --rpc-url $(RPC_URL) --broadcast -g 500

configure_controller:
	@echo "Configuring Controller..."
	forge script ./script/Controller/ConfigureController.s.sol --rpc-url $(RPC_URL) --broadcast -g 500

configure_controller_logic:
	@echo "Configuring ControllerLogic..."
	forge script ./script/ControllerLogic/ConfigureControllerLogic.s.sol --rpc-url $(RPC_URL) --broadcast -g 500

configure_margin_calculator:
	@echo "Configuring MarginCalculator..."
	forge script ./script/MarginCalculator/ConfigureMarginCalculator.s.sol --rpc-url $(RPC_URL) --broadcast -g 500

configure_margin_pool:
	@echo "Configuring MarginPool..."
	forge script ./script/MarginPool/ConfigureMarginPool.s.sol --rpc-url $(RPC_URL) --broadcast -g 500

configure_oracle:
	@echo "Configuring Oracle..."
	forge script ./script/Oracle/ConfigureOracle.s.sol --rpc-url $(RPC_URL) --broadcast -g 500

configure_whitelist:
	@echo "Configuring Whitelist..."
	forge script ./script/Whitelist/ConfigureWhitelist.s.sol --rpc-url $(RPC_URL) --broadcast -g 500

configure_mmarket:
	@echo "Configuring MMarket..."
	forge script ./script/MMarket/ConfigureMMarket.s.sol --rpc-url $(RPC_URL) --broadcast -g 500

configure_enhanced_options:
	@echo "Configuring EnhancedOptions..."
	forge script ./script/EnhancedOptions/ConfigureEnhancedOptions.s.sol --rpc-url $(RPC_URL) --broadcast -g 500

configure_enhanced_options_trusted_roles:
	@echo "Managing EnhancedOptions trusted roles (takers + makers)..."
	forge script ./script/EnhancedOptions/ManageTrustedOperators.s.sol --via-ir --rpc-url $(RPC_URL) --broadcast -g 500

configure_enhanced_strategy:
	@echo "Configuring EnhancedStrategy..."
	forge script ./script/EnhancedStrategy/ConfigureEnhancedStrategy.s.sol --via-ir --rpc-url $(RPC_URL) --broadcast -g 500

refresh_controller_config:
	@echo "Refreshing Controller & Logic Config..."
	forge script ./script/Controller/RefreshControllerConfig.s.sol --rpc-url $(RPC_URL) --broadcast -g 500

# ==========================================
# Ingresso Commands
# ==========================================

ingresso_new_user_position:
	@echo "Executing IngressoNewUserPosition..."
	forge script ./script/EnhancedOptions/Ingresso/IngressoNewUserPosition.s.sol --rpc-url $(RPC_URL) --broadcast --via-ir -g 300

ingresso_transfer_asset:
	@echo "Executing IngressoTransferAsset..."
	forge script ./script/EnhancedOptions/Ingresso/IngressoTransferAsset.s.sol --rpc-url $(RPC_URL) --broadcast --via-ir --legacy -g 200

ingresso_mmarket_deposit:
	@echo "Executing IngressoMMarketDeposit..."
	forge script ./script/EnhancedOptions/Ingresso/IngressoMMarketDeposit.s.sol --rpc-url $(RPC_URL) --broadcast --via-ir --legacy -g 200

ingresso_otc_trade:
	@echo "Executing IngressoOTCTrade (enhancedSigner signature uses PRIVATE_KEY)..."
	forge script ./script/EnhancedOptions/Ingresso/IngressoOTCTrade.s.sol --rpc-url $(RPC_URL) --broadcast -g 200

ingresso_redeem:
	@echo "Executing IngressoRedeem..."
	forge script ./script/EnhancedOptions/Ingresso/IngressoRedeem.s.sol --via-ir --rpc-url $(RPC_URL) --broadcast -g 200

ingresso_settle:
	@echo "Executing IngressoSettle..."
	forge script ./script/EnhancedOptions/Ingresso/IngressoSettle.s.sol --rpc-url $(RPC_URL) --broadcast -g 200

ingresso_deposit_and_open:
	@echo "Executing IngressoDepositAndOpen..."
	forge script ./script/EnhancedOptions/Ingresso/IngressoDepositAndOpen.s.sol --rpc-url $(RPC_URL) --broadcast --via-ir -g 300

# ==========================================
# Oracle Commands
# ==========================================

oracle_set_expiry_price:
	@echo "Setting Expiry Price on Oracle..."
	forge script ./script/Oracle/SetExpiryPrice.s.sol --rpc-url $(RPC_URL) --broadcast  -g 200 --with-gas-price 21000000000

oracle_set_asset_pricer:
	@echo "Setting Asset Pricer on Oracle..."
	forge script ./script/Oracle/SetAssetPricer.s.sol --rpc-url $(RPC_URL) --broadcast --via-ir -g 200

oracle_set_locking_period:
	@echo "Setting Locking Period on Oracle..."
	forge script ./script/Oracle/SetLockingPeriod.s.sol --rpc-url $(RPC_URL) --broadcast --via-ir -g 200

# ==========================================
# ManualPricer Commands
# ==========================================

deploy_manual_pricer_implementation:
	@echo "Deploying ManualPricer Implementation..."
	forge script ./script/ManualPricer/DeployManualPricerImplementation.s.sol --rpc-url $(RPC_URL) --broadcast --via-ir -g 200

deploy_manual_pricer_proxy:
	@echo "Deploying ManualPricer Proxy..."
	forge script ./script/ManualPricer/DeployManualPricerProxy.s.sol --rpc-url $(RPC_URL) --broadcast --via-ir -g 500 --legacy

upgrade_address_book:
	@echo "Upgrading AddressBook..."
	forge script ./script/AddressBook/UpgradeAddressBook.s.sol --rpc-url $(RPC_URL) --broadcast --via-ir -g 200

upgrade_oracle:
	@echo "Upgrading Oracle..."
	forge script ./script/Oracle/UpgradeOracle.s.sol --rpc-url $(RPC_URL) --broadcast --via-ir -g 200

upgrade_whitelist:
	@echo "Upgrading Whitelist..."
	forge script ./script/Whitelist/UpgradeWhitelist.s.sol --rpc-url $(RPC_URL) --broadcast --via-ir -g 200

upgrade_margin_pool:
	@echo "Upgrading MarginPool..."
	forge script ./script/MarginPool/UpgradeMarginPool.s.sol --rpc-url $(RPC_URL) --broadcast --via-ir -g 200

upgrade_margin_calculator:
	@echo "Upgrading MarginCalculator..."
	forge script ./script/MarginCalculator/UpgradeMarginCalculator.s.sol --rpc-url $(RPC_URL) --broadcast --via-ir -g 200

upgrade_controller_logic:
	@echo "Upgrading ControllerLogic..."
	forge script ./script/ControllerLogic/UpgradeControllerLogic.s.sol --rpc-url $(RPC_URL) --broadcast --via-ir -g 200

upgrade_controller:
	@echo "Upgrading Controller..."
	forge script ./script/Controller/UpgradeController.s.sol --rpc-url $(RPC_URL) --broadcast --via-ir -g 200

upgrade_otoken_factory:
	@echo "Upgrading OtokenFactory..."
	forge script ./script/OtokenFactory/UpgradeOtokenFactory.s.sol --rpc-url $(RPC_URL) --broadcast --via-ir -g 200

upgrade_mmarket:
	@echo "Upgrading MMarket..."
	forge script ./script/MMarket/UpgradeMMarket.s.sol --rpc-url $(RPC_URL) --broadcast --via-ir -g 200

upgrade_enhanced_options:
	@echo "Upgrading EnhancedOptions..."
	forge script ./script/EnhancedOptions/UpgradeEnhancedOptions.s.sol --rpc-url $(RPC_URL) --broadcast --via-ir -g 200

upgrade_enhanced_strategy:
	@echo "Upgrading EnhancedStrategy..."
	forge script ./script/EnhancedStrategy/UpgradeEnhancedStrategy.s.sol --rpc-url $(RPC_URL) --broadcast --via-ir -g 200

upgrade_manual_pricer:
	@echo "Upgrading ManualPricer..."
	forge script ./script/ManualPricer/UpgradeManualPricer.s.sol --rpc-url $(RPC_URL) --broadcast --via-ir -g 200

configure_manual_pricer:
	@echo "Configuring ManualPricer..."
	forge script ./script/ManualPricer/ConfigureManualPricer.s.sol --rpc-url $(RPC_URL) --broadcast --via-ir -g 200

set_expiry_price_manual:
	@echo "Setting Expiry Price via ManualPricer..."
	forge script ./script/ManualPricer/SetExpiryPriceInOracle.s.sol --rpc-url $(RPC_URL) --broadcast --via-ir -g 500 --with-gas-price 11000000000

whitelist_product:
	@echo "Whitelisting Product..."
	forge script ./script/Whitelist/WhitelistProduct.s.sol --rpc-url $(RPC_URL) --broadcast -g 200 --with-gas-price 21000000000

# ==========================================
# Query Commands
# ==========================================

query_address_book:
	@echo "Querying AddressBook..."
	forge script ./script/AddressBook/QueryAddressBook.s.sol --via-ir --rpc-url $(RPC_URL)

create_strategy:
	@echo "Creating Strategy..."
	forge script ./script/EnhancedStrategy/optionals/CreateStrategy.s.sol --via-ir --rpc-url $(RPC_URL) --broadcast -g 500

strategy_set_active:
	@echo "Setting Strategy Active..."
	forge script ./script/EnhancedStrategy/optionals/SetStrategyActive.s.sol --via-ir --rpc-url $(RPC_URL) --broadcast -g 500

strategy_set_operator:
	@echo "Setting Strategy Operator..."
	forge script ./script/EnhancedStrategy/optionals/SetOperator.s.sol --via-ir --rpc-url $(RPC_URL) --broadcast -g 500

strategy_set_signer:
	@echo "Setting Strategy Signer..."
	forge script ./script/EnhancedStrategy/optionals/SetStrategySigner.s.sol --via-ir --rpc-url $(RPC_URL) --broadcast -g 500

strategy_set_margin_pool:
	@echo "Setting Strategy MarginPool..."
	forge script ./script/EnhancedStrategy/optionals/SetMarginPool.s.sol --via-ir --rpc-url $(RPC_URL) --broadcast -g 500

strategy_set_asset_approval_margin_pool:
	@echo "Setting Strategy asset approval for MarginPool..."
	forge script ./script/EnhancedStrategy/optionals/SetAssetApprovalMarginPool.s.sol --via-ir --rpc-url $(RPC_URL) --broadcast -g 500

strategy_set_asset_approval_swap_router:
	@echo "Setting Strategy asset approval for SwapRouter..."
	forge script ./script/EnhancedStrategy/optionals/SetAssetApprovalSwapRouter.s.sol --via-ir --rpc-url $(RPC_URL) --broadcast -g 500

strategy_set_swap_router:
	@echo "Setting Strategy Swap Router..."
	forge script ./script/EnhancedStrategy/optionals/SetSwapRouter.s.sol --via-ir --rpc-url $(RPC_URL) --broadcast -g 500

strategy_deposit:
	@echo "Executing Strategy Deposit..."
	forge script ./script/EnhancedStrategy/optionals/Deposit.s.sol --via-ir --rpc-url $(RPC_URL) --broadcast -g 500

strategy_create_order:
	@echo "Executing Strategy CreateOrder (maker uses MAKER_PRIVATE_KEY, strategySigner uses PRIVATE_KEY)..."
	forge script ./script/EnhancedStrategy/optionals/CreateOrder.s.sol --via-ir --rpc-url $(RPC_URL) --broadcast -g 500

strategy_next_cycle:
	@echo "Executing Strategy NextCycle..."
	forge script ./script/EnhancedStrategy/optionals/NextCycle.s.sol --via-ir --rpc-url $(RPC_URL) --broadcast -g 500

strategy_buyback:
	@echo "Executing Strategy Buyback..."
	forge script ./script/EnhancedStrategy/optionals/Buyback.s.sol --via-ir --rpc-url $(RPC_URL) --broadcast -g 500

strategy_force_pause_funds:
	@echo "Executing Strategy ForcePauseFunds..."
	forge script ./script/EnhancedStrategy/optionals/ForcePauseFunds.s.sol --via-ir --rpc-url $(RPC_URL) --broadcast -g 500

strategy_clear_force_exit:
	@echo "Executing Strategy ClearForceExit..."
	forge script ./script/EnhancedStrategy/optionals/ClearForceExit.s.sol --via-ir --rpc-url $(RPC_URL) --broadcast -g 500

strategy_pause_fund:
	@echo "Executing Strategy PauseFund..."
	forge script ./script/EnhancedStrategy/optionals/PauseFund.s.sol --via-ir --rpc-url $(RPC_URL) --broadcast -g 500

strategy_cancel_pause:
	@echo "Executing Strategy CancelPause..."
	forge script ./script/EnhancedStrategy/optionals/CancelPause.s.sol --via-ir --rpc-url $(RPC_URL) --broadcast -g 500

strategy_withdraw:
	@echo "Executing Strategy Withdraw..."
	forge script ./script/EnhancedStrategy/optionals/Withdraw.s.sol --via-ir --rpc-url $(RPC_URL) --broadcast -g 500

# ==========================================
# Mock Commands
# ==========================================

deploy_mock_token:
	@echo "Deploying Mock Token..."
	forge script ./script/Mock/DeployMockERC20.s.sol --rpc-url $(RPC_URL) --broadcast -g 200

deploy_multicall3:
	@echo "Deploying Multicall3..."
	forge script ./script/Multicall3/DeployMulticall3.s.sol --rpc-url $(RPC_URL) --broadcast -g 200

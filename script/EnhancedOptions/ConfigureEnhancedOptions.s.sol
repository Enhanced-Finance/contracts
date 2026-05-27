// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {EnhancedOptions} from "src/core/EnhancedOptions.sol";
import {stdJson} from "lib/forge-std/src/StdJson.sol";

contract ConfigureEnhancedOptions is Script {
    using stdJson for string;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        uint256 chainId = block.chainid;
        string memory chainIdStr = vm.toString(chainId);
        string memory deployPath = string.concat(vm.projectRoot(), "/.deploy/", chainIdStr, ".json");
        string memory configPath = string.concat(vm.projectRoot(), "/config/", chainIdStr, ".json");

        require(vm.isFile(deployPath), "Deploy file not found");
        require(vm.isFile(configPath), "Config file not found");

        string memory deployJson = vm.readFile(deployPath);
        string memory configJson = vm.readFile(configPath);

        address enhancedOptionsAddr = deployJson.readAddress(".EnhancedOptions.proxyAddress");
        require(enhancedOptionsAddr != address(0), "EnhancedOptions proxy not found");

        EnhancedOptions enhancedOptions = EnhancedOptions(enhancedOptionsAddr);
        console.log("Configuring EnhancedOptions at:", enhancedOptionsAddr);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Operator
        if (vm.keyExists(configJson, ".EnhancedOptions.operator")) {
            address desiredOperator = configJson.readAddress(".EnhancedOptions.operator");
            if (enhancedOptions.operator() != desiredOperator && desiredOperator != address(0)) {
                console.log("Updating Operator...");
                enhancedOptions.setOperator(desiredOperator);
            }
        }

        // 2. Controller (Check .deploy first)
        address desiredController;
        if (vm.keyExists(deployJson, ".Controller.proxyAddress")) {
            desiredController = deployJson.readAddress(".Controller.proxyAddress");
        } else if (vm.keyExists(configJson, ".EnhancedOptions.controller")) {
            desiredController = configJson.readAddress(".EnhancedOptions.controller");
        }
        if (desiredController != address(0) && address(enhancedOptions.controller()) != desiredController) {
            console.log("Updating Controller...");
            enhancedOptions.setController(desiredController);
        }

        // 3. MMarket (Check .deploy first)
        address desiredMMarket;
        if (vm.keyExists(deployJson, ".MMarket.proxyAddress")) {
            desiredMMarket = deployJson.readAddress(".MMarket.proxyAddress");
        } else if (vm.keyExists(configJson, ".EnhancedOptions.mmarket")) {
            desiredMMarket = configJson.readAddress(".EnhancedOptions.mmarket");
        }
        if (desiredMMarket != address(0) && address(enhancedOptions.mmarket()) != desiredMMarket) {
            console.log("Updating MMarket...");
            enhancedOptions.setMMarket(desiredMMarket);
        }

        // 4. Factory (OtokenFactory) (Check .deploy first)
        address desiredFactory;
        if (vm.keyExists(deployJson, ".OtokenFactory.proxyAddress")) {
            desiredFactory = deployJson.readAddress(".OtokenFactory.proxyAddress");
        } else if (vm.keyExists(configJson, ".EnhancedOptions.factory")) {
            desiredFactory = configJson.readAddress(".EnhancedOptions.factory");
        }
        if (desiredFactory != address(0) && address(enhancedOptions.factory()) != desiredFactory) {
            console.log("Updating Factory...");
            enhancedOptions.setFactory(desiredFactory);
        }

        // 5. MarginPool (Check .deploy first)
        address desiredMarginPool;
        if (vm.keyExists(deployJson, ".MarginPool.proxyAddress")) {
            desiredMarginPool = deployJson.readAddress(".MarginPool.proxyAddress");
        } else if (vm.keyExists(configJson, ".EnhancedOptions.marginPool")) {
            desiredMarginPool = configJson.readAddress(".EnhancedOptions.marginPool");
        }
        if (desiredMarginPool != address(0) && enhancedOptions.marginPool() != desiredMarginPool) {
            console.log("Updating MarginPool...");
            enhancedOptions.setMarginPool(desiredMarginPool);
        }

        // 6. FlashLoanPool
        if (vm.keyExists(configJson, ".EnhancedOptions.flashLoanPool")) {
            address desiredFlashLoanPool = configJson.readAddress(".EnhancedOptions.flashLoanPool");
            if (enhancedOptions.flashLoanPool() != desiredFlashLoanPool && desiredFlashLoanPool != address(0)) {
                console.log("Updating FlashLoanPool...");
                enhancedOptions.setFlashLoanPool(desiredFlashLoanPool);
            }
        }

        // 7. SwapRouter
        if (vm.keyExists(configJson, ".EnhancedOptions.swapRouter")) {
            address desiredSwapRouter = configJson.readAddress(".EnhancedOptions.swapRouter");
            if (enhancedOptions.swapRouter() != desiredSwapRouter && desiredSwapRouter != address(0)) {
                console.log("Updating SwapRouter...");
                enhancedOptions.setSwapRouter(desiredSwapRouter);
            }
        }

        // 8. FeeRecipient
        if (vm.keyExists(configJson, ".EnhancedOptions.feeRecipient")) {
            address desiredFeeRecipient = configJson.readAddress(".EnhancedOptions.feeRecipient");
            if (enhancedOptions.feeRecipient() != desiredFeeRecipient && desiredFeeRecipient != address(0)) {
                console.log("Updating FeeRecipient...");
                enhancedOptions.setFeeRecipient(desiredFeeRecipient);
            }
        }

        // 9. EnhancedSigner
        if (vm.keyExists(configJson, ".EnhancedOptions.enhancedSigner")) {
            address desiredEnhancedSigner = configJson.readAddress(".EnhancedOptions.enhancedSigner");
            if (enhancedOptions.enhancedSigner() != desiredEnhancedSigner && desiredEnhancedSigner != address(0)) {
                console.log("Updating EnhancedSigner...");
                enhancedOptions.setEnhancedSigner(desiredEnhancedSigner);
            }
        }

        // 10. FlashLoanRedeemPeriodStart (Blind set as it is internal)
        if (vm.keyExists(configJson, ".EnhancedOptions.flashLoanRedeemPeriodStart")) {
            uint256 desiredPeriod = configJson.readUint(".EnhancedOptions.flashLoanRedeemPeriodStart");
            console.log("Updating FlashLoanRedeemPeriodStart...");
            enhancedOptions.setFlashLoanRedeemPeriodStart(desiredPeriod);
        }

        vm.stopBroadcast();
    }
}

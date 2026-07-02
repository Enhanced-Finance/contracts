// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

contract ScriptPrivacyTest is Test {
    string[] private scriptPaths;
    string[] private forbiddenLiterals;

    function setUp() external {
        scriptPaths.push("script/EnhancedVault/optionals/CancelDeposit.s.sol");
        scriptPaths.push("script/EnhancedVault/optionals/CancelPause.s.sol");
        scriptPaths.push("script/EnhancedVault/optionals/ProcessQueuedUsers.s.sol");
        scriptPaths.push("script/EnhancedVault/optionals/StartNextCycle.s.sol");
        scriptPaths.push("script/EnhancedVault/optionals/NextCycle.s.sol");
        scriptPaths.push("script/EnhancedVault/optionals/Buyback.s.sol");
        scriptPaths.push("script/EnhancedVault/optionals/Withdraw.s.sol");
        scriptPaths.push("script/EnhancedVault/optionals/SystemPauseFunds.s.sol");
        scriptPaths.push("script/EnhancedVault/optionals/SetOperator.s.sol");
        scriptPaths.push("script/EnhancedVault/optionals/SetSwapRouter.s.sol");
        scriptPaths.push("script/EnhancedVault/optionals/SetAssetApprovalSwapRouter.s.sol");
        scriptPaths.push("script/EnhancedVault/optionals/EndVault.s.sol");
        scriptPaths.push("script/EnhancedVault/optionals/SetVaultSigner.s.sol");
        scriptPaths.push("script/EnhancedVault/optionals/SettlePreviousCycle.s.sol");
        scriptPaths.push("script/EnhancedVault/optionals/CreateOrder.s.sol");
        scriptPaths.push("script/EnhancedVault/optionals/SetVaultActive.s.sol");
        scriptPaths.push("script/EnhancedVault/optionals/Deposit.s.sol");
        scriptPaths.push("script/EnhancedOptions/optionals/SetCustodyOperator.s.sol");
        scriptPaths.push("script/EnhancedOptions/optionals/SetOperator.s.sol");
        scriptPaths.push("script/EnhancedOptions/Ingresso/IngressoRedeem.s.sol");
        scriptPaths.push("script/EnhancedOptions/Ingresso/IngressoTransferAsset.s.sol");
        scriptPaths.push("script/EnhancedOptions/Ingresso/IngressoTrustedMakerDepositAndOpen.s.sol");
        scriptPaths.push("script/EnhancedOptions/Ingresso/IngressoReleaseCollateralToCustody.s.sol");
        scriptPaths.push("script/EnhancedOptions/Ingresso/IngressoDepositAndOpen.s.sol");
        scriptPaths.push("script/EnhancedOptions/Ingresso/IngressoMMarketDeposit.s.sol");

        forbiddenLiterals.push("0x62636cc6f993b3d3f0b9eedb473ce0bc98695e5bd02e667fa6b3552c5f5b7c29");
        forbiddenLiterals.push("0x9832d172f61a4ac7cca7bad266a425d65bcb8fb83a3d195c378972572c5f2c3b");
        forbiddenLiterals.push("0x6b6979f17637ca1eb879d1b92f786e3cd2419172c0f4b79d4fa675774aac0614");
        forbiddenLiterals.push("0x0734DB84C106Fa211D6057A299CcaD5612953232");
        forbiddenLiterals.push("0xB76104Fc40b933C28FDB02E48B1242A78ca1b411");
        forbiddenLiterals.push("0x134b5f74d65a34eb6F9CdaD5eD664b45A167cC43");
        forbiddenLiterals.push("0xAaAC452FdbEf9481157A16E19b5245Aae65D2e94");
        forbiddenLiterals.push("0x56E49A068e368F2D40FFE9314033671CF3402eC1");
        forbiddenLiterals.push("0xB244033d5bb4EdDb113EDe60fbE2bDf62Cc6fD0d");
        forbiddenLiterals.push("0x778E2B531dc9AfE710Fe0803b5C6bF474c321F39");
        forbiddenLiterals.push("0xf320E0f410D93F86cC241Db11DA3e24C8F2bEF44");
        forbiddenLiterals.push("0xB23a0F16c24c564cc1CbA876F6b1D506F6fa266B");
        forbiddenLiterals.push("0x7d583eDED21b204AEd3dF317B615ef1a2Cc7Ab1B");
        forbiddenLiterals.push("0xFfFFFFff00000000000000000000000000000001");
        forbiddenLiterals.push("0xD157F637262B0E6Af035baa35a5475E56b100D1b");
        forbiddenLiterals.push("0x5cc75d8c5D9A22AC35D7cb734159b2Da5554981f");
        forbiddenLiterals.push("0x483688fb8fe19cbf746438ed4571d7075eeabf0f");
        forbiddenLiterals.push("0xea2d8c2c17a36eaa77765505b325e0c8b0918057");
    }

    function testScripts_ShouldNotContainTrackedAddressHashOrPayloadLiterals() external view {
        for (uint256 i = 0; i < scriptPaths.length; i++) {
            string memory source = vm.readFile(scriptPaths[i]);
            for (uint256 j = 0; j < forbiddenLiterals.length; j++) {
                assertFalse(
                    _contains(source, forbiddenLiterals[j]),
                    string.concat("forbidden tracked literal remains in ", scriptPaths[i])
                );
            }
        }
    }

    function _contains(string memory value, string memory needle) internal pure returns (bool) {
        bytes memory valueBytes = bytes(value);
        bytes memory needleBytes = bytes(needle);

        if (needleBytes.length == 0 || needleBytes.length > valueBytes.length) return false;

        for (uint256 i = 0; i <= valueBytes.length - needleBytes.length; i++) {
            bool matches = true;
            for (uint256 j = 0; j < needleBytes.length; j++) {
                if (valueBytes[i + j] != needleBytes[j]) {
                    matches = false;
                    break;
                }
            }
            if (matches) return true;
        }

        return false;
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {SetAssetApproval} from "../script/EnhancedOptions/optionals/SetAssetApproval.s.sol";
import {SetController} from "../script/EnhancedOptions/optionals/SetController.s.sol";
import {SetCustodyOperator} from "../script/EnhancedOptions/optionals/SetCustodyOperator.s.sol";
import {SetFactory} from "../script/EnhancedOptions/optionals/SetFactory.s.sol";
import {SetFeeRecipient} from "../script/EnhancedOptions/optionals/SetFeeRecipient.s.sol";
import {SetMMarket} from "../script/EnhancedOptions/optionals/SetMMarket.s.sol";
import {SetMakerCustodyLimitBps} from "../script/EnhancedOptions/optionals/SetMakerCustodyLimitBps.s.sol";
import {SetMarginPool} from "../script/EnhancedOptions/optionals/SetMarginPool.s.sol";
import {SetOperator} from "../script/EnhancedOptions/optionals/SetOperator.s.sol";
import {SetTrustedMaker} from "../script/EnhancedOptions/optionals/SetTrustedMaker.s.sol";
import {SetTrustedTaker} from "../script/EnhancedOptions/optionals/SetTrustedTaker.s.sol";

contract EnhancedOptionsSetterScriptsTest is Test {
    function testSetterScripts_ShouldBeDeployableIndividually() external {
        assertTrue(address(new SetOperator()) != address(0));
        assertTrue(address(new SetCustodyOperator()) != address(0));
        assertTrue(address(new SetController()) != address(0));
        assertTrue(address(new SetMMarket()) != address(0));
        assertTrue(address(new SetFactory()) != address(0));
        assertTrue(address(new SetMarginPool()) != address(0));
        assertTrue(address(new SetFeeRecipient()) != address(0));
        assertTrue(address(new SetTrustedTaker()) != address(0));
        assertTrue(address(new SetTrustedMaker()) != address(0));
        assertTrue(address(new SetMakerCustodyLimitBps()) != address(0));
        assertTrue(address(new SetAssetApproval()) != address(0));
    }
}

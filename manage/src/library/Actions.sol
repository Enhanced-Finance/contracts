/**
 * SPDX-License-Identifier: UNLICENSED
 */
pragma solidity ^0.8.22;

/**
 * @title Actions
 * @author Opyn Team
 * @notice A library that provides a ActionArgs struct, sub types of Action structs, and functions to parse ActionArgs into specific Actions.
 *
 */
library Actions {
    // possible actions that can be performed
    enum ActionType {
        OpenVault,
        MintShortOption,
        BurnShortOption,
        DepositLongOption,
        WithdrawLongOption,
        DepositCollateral,
        WithdrawCollateral,
        SettleVault,
        Redeem,
        Call,
        Liquidate
    }

    struct ActionArgs {
        // type of action that is being performed on the system
        ActionType actionType;
        // address of the account owner
        address owner;
        // address which we move assets from or to (depending on the action type)
        address secondAddress;
        // asset that is to be transfered
        address asset;
        // index of the vault that is to be modified (if any)
        uint256 vaultId;
        // amount of asset that is to be transfered
        uint256 amount;
        // each vault can hold multiple short / long / collateral assets but we are restricting the scope to only 1 of each in this version
        // in future versions this would be the index of the short / long / collateral asset that needs to be modified
        uint256 index;
        // any other data that needs to be passed in for arbitrary function calls
        bytes data;
    }

    struct MintArgs {
        // address of the account owner
        address owner;
        // index of the vault from which the asset will be minted
        uint256 vaultId;
        // address to which we transfer the minted oTokens
        address to;
        // oToken that is to be minted
        address otoken;
        // each vault can hold multiple short / long / collateral assets but we are restricting the scope to only 1 of each in this version
        // in future versions this would be the index of the short / long / collateral asset that needs to be modified
        uint256 index;
        // amount of oTokens that is to be minted
        uint256 amount;
    }

    struct BurnArgs {
        // address of the account owner
        address owner;
        // index of the vault from which the oToken will be burned
        uint256 vaultId;
        // address from which we transfer the oTokens
        address from;
        // oToken that is to be burned
        address otoken;
        // each vault can hold multiple short / long / collateral assets but we are restricting the scope to only 1 of each in this version
        // in future versions this would be the index of the short / long / collateral asset that needs to be modified
        uint256 index;
        // amount of oTokens that is to be burned
        uint256 amount;
    }

    struct OpenVaultArgs {
        // address of the account owner
        address owner;
        // vault id to create
        uint256 vaultId;
        // vault type, 0 for spread/max loss and 1 for naked margin vault, 2 for physially settled
        uint256 vaultType;
    }

    struct DepositArgs {
        // address of the account owner
        address owner;
        // index of the vault to which the asset will be added
        uint256 vaultId;
        // address from which we transfer the asset
        address from;
        // asset that is to be deposited
        address asset;
        // each vault can hold multiple short / long / collateral assets but we are restricting the scope to only 1 of each in this version
        // in future versions this would be the index of the short / long / collateral asset that needs to be modified
        uint256 index;
        // amount of asset that is to be deposited
        uint256 amount;
    }

    struct RedeemArgs {
        // address to which we pay out the oToken proceeds
        address receiver;
        // oToken that is to be redeemed
        address otoken;
        // amount of oTokens that is to be redeemed
        uint256 amount;
    }

    struct WithdrawArgs {
        // address of the account owner
        address owner;
        // index of the vault from which the asset will be withdrawn
        uint256 vaultId;
        // address to which we transfer the asset
        address to;
        // asset that is to be withdrawn
        address asset;
        // each vault can hold multiple short / long / collateral assets but we are restricting the scope to only 1 of each in this version
        // in future versions this would be the index of the short / long / collateral asset that needs to be modified
        uint256 index;
        // amount of asset that is to be withdrawn
        uint256 amount;
    }

    struct SettleVaultArgs {
        // address of the account owner
        address owner;
        // index of the vault to which is to be settled
        uint256 vaultId;
        // address to which we transfer the remaining collateral
        address to;
    }

    struct LiquidateArgs {
        // address of the vault owner to liquidate
        address owner;
        // address of the liquidated collateral receiver
        address receiver;
        // vault id to liquidate
        uint256 vaultId;
        // amount of debt(otoken) to repay
        uint256 amount;
        // chainlink round id
        uint256 roundId;
    }

    struct CallArgs {
        // address of the callee contract
        address callee;
        // data field for external calls
        bytes data;
    }

    function _constructFlashLoanRedeemActionArgs(bytes calldata packedEncodedArgs)
        internal
        view
        returns (ActionArgs memory, address, bytes memory, uint256)
    {
        uint256 len;
        address otoken;
        uint256 amount;
        address redeemer;
        uint256 maxAmountIn;
        bytes memory uniswapRoute;

        len = packedEncodedArgs.length;
        otoken = address(bytes20(packedEncodedArgs[0:20]));
        amount = uint256(bytes32(packedEncodedArgs[20:52]));
        redeemer = address(bytes20(packedEncodedArgs[52:72]));
        maxAmountIn = uint256(bytes32(packedEncodedArgs[72:104]));
        uniswapRoute = packedEncodedArgs[104:len];

        return (
            ActionArgs(
                Actions.ActionType.Redeem,
                address(0),
                address(this), // redeem receiver is rysk contract so funds can be swapped to repay loan
                otoken,
                0,
                amount,
                0,
                bytes("")
            ),
            redeemer,
            uniswapRoute,
            maxAmountIn
        );
    }
}

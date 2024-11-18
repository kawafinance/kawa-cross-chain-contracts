// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.20;

abstract contract ComptrollerInterface {
    /// @notice Indicator that this is a Comptroller contract (for inspection)
    bool public constant isComptroller = true;

    /*** Assets You Are In ***/

    function enterMarkets(
        address[] calldata kTokens
    ) external virtual returns (uint[] memory);
    function exitMarket(address kToken) external virtual returns (uint);

    /*** Policy Hooks ***/

    function mintAllowed(
        address kToken,
        address minter,
        uint mintAmount
    ) external virtual returns (uint);

    function redeemAllowed(
        address kToken,
        address redeemer,
        uint redeemTokens
    ) external virtual returns (uint);

    // Do not remove, still used by KToken
    function redeemVerify(
        address kToken,
        address redeemer,
        uint redeemAmount,
        uint redeemTokens
    ) external pure virtual;

    function borrowAllowed(
        address kToken,
        address borrower,
        uint borrowAmount
    ) external virtual returns (uint);

    function repayBorrowAllowed(
        address kToken,
        address payer,
        address borrower,
        uint repayAmount
    ) external virtual returns (uint);

    function liquidateBorrowAllowed(
        address kTokenBorrowed,
        address kTokenCollateral,
        address liquidator,
        address borrower,
        uint repayAmount
    ) external view virtual returns (uint);

    function seizeAllowed(
        address kTokenCollateral,
        address kTokenBorrowed,
        address liquidator,
        address borrower,
        uint seizeTokens
    ) external virtual returns (uint);

    function transferAllowed(
        address kToken,
        address src,
        address dst,
        uint transferTokens
    ) external virtual returns (uint);

    /*** Liquidity/Liquidation Calculations ***/

    function liquidateCalculateSeizeTokens(
        address kTokenBorrowed,
        address kTokenCollateral,
        uint repayAmount
    ) external view virtual returns (uint, uint);
}

// The hooks that were patched out of the comptroller to make room for the supply caps, if we need them
abstract contract ComptrollerInterfaceWithAllVerificationHooks is
    ComptrollerInterface
{
    function mintVerify(
        address kToken,
        address minter,
        uint mintAmount,
        uint mintTokens
    ) external virtual;

    // Included in ComptrollerInterface already
    // function redeemVerify(address kToken, address redeemer, uint redeemAmount, uint redeemTokens) virtual external;

    function borrowVerify(
        address kToken,
        address borrower,
        uint borrowAmount
    ) external virtual;

    function repayBorrowVerify(
        address kToken,
        address payer,
        address borrower,
        uint repayAmount,
        uint borrowerIndex
    ) external virtual;

    function liquidateBorrowVerify(
        address kTokenBorrowed,
        address kTokenCollateral,
        address liquidator,
        address borrower,
        uint repayAmount,
        uint seizeTokens
    ) external virtual;

    function seizeVerify(
        address kTokenCollateral,
        address kTokenBorrowed,
        address liquidator,
        address borrower,
        uint seizeTokens
    ) external virtual;

    function transferVerify(
        address kToken,
        address src,
        address dst,
        uint transferTokens
    ) external virtual;
}

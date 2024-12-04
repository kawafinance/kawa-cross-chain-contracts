// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.20;

import "./KErc20DelegatorBase.sol";

/**
 * @title Kawa's KErc20Delegator.sol Contract
 * @notice KTokens which wrap an EIP-20 underlying and delegate to an implementation
 * @author Kawa
 */
contract KErc20CrossChainDelegator is KErc20DelegatorBase, KErc20CrossChainInterface {
    /**
     * @notice Construct a new money market
     * @param underlying_ The address of the underlying asset
     * @param comptroller_ The address of the Comptroller
     * @param interestRateModel_ The address of the interest rate model
     * @param initialExchangeRateMantissa_ The initial exchange rate, scaled by 1e18
     * @param name_ ERC-20 name of this token
     * @param symbol_ ERC-20 symbol of this token
     * @param decimals_ ERC-20 decimal precision of this token
     * @param admin_ Address of the administrator of this token
     * @param implementation_ The address of the implementation the contract delegates to
     * @param becomeImplementationData The encoded args for becomeImplementation
     * @param centralHub_ The address of the MessageHub
     */
    constructor(
        address underlying_,
        ComptrollerInterface comptroller_,
        InterestRateModel interestRateModel_,
        uint initialExchangeRateMantissa_,
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        address centralHub_,
        address payable admin_,
        address implementation_,
        bytes memory becomeImplementationData
    ) {
        // Creator of the contract is admin during initialization
        admin = payable(msg.sender);

        // First delegate gets to initialize the delegator (i.e. storage contract)
        delegateTo(
            implementation_,
            abi.encodeWithSignature(
                "initialize(address,address,address,uint256,string,string,uint8,address)",
                underlying_,
                comptroller_,
                interestRateModel_,
                initialExchangeRateMantissa_,
                name_,
                symbol_,
                decimals_,
                centralHub_
            )
        );

        // New implementations always get set via the settor (post-initialize)
        _setImplementation(implementation_, false, becomeImplementationData);

        // Set the proper admin now that initialization is done
        admin = admin_;
    }

    /**
     * @notice Sender supplies assets into the market and receives kTokens in exchange
     * @dev Accrues interest whether or not the operation succeeds, unless reverted
     * @param minter The address of the account which is supplying the assets
     * @param mintAmount The amount of the underlying asset to supply
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function mint(
        address minter,
        uint mintAmount
    ) external override returns (uint) {
        bytes memory data = delegateToImplementation(
            abi.encodeWithSignature(
                "mint(address,uint256)",
                minter,
                mintAmount
            )
        );
        return abi.decode(data, (uint));
    }
    /**
     * @notice Sender repays their own borrow
     * @param payer the account paying off the borrow
     * @param repayAmount The amount to repay, or uint.max for the full outstanding amount
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function repayBorrow(
        address payer,
        uint repayAmount
    ) external override returns (uint) {
        bytes memory data = delegateToImplementation(
            abi.encodeWithSignature(
                "repayBorrow(address,uint256)",
                payer,
                repayAmount
            )
        );
        return abi.decode(data, (uint));
    }

    /**
     * @notice Sender repays a borrow belonging to borrower
     * @param payer the account paying off the borrow
     * @param borrower the account with the debt being payed off
     * @param repayAmount The amount to repay, or uint.max for the full outstanding amount
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function repayBorrowBehalf(
        address payer,
        address borrower,
        uint repayAmount
    ) external override returns (uint) {
        bytes memory data = delegateToImplementation(
            abi.encodeWithSignature(
                "repayBorrowBehalf(address,address,uint256)",
                payer,
                borrower,
                repayAmount
            )
        );
        return abi.decode(data, (uint));
    }

    /**
     * @notice Sender redeems kTokens in exchange for the underlying asset
     * @dev Accrues interest whether or not the operation succeeds, unless reverted
     * @param redeemTokens The number of kTokens to redeem into underlying
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function redeem(uint redeemTokens) external payable override returns (uint) {
        bytes memory data = delegateToImplementation(
            abi.encodeWithSignature("redeem(uint256)", redeemTokens)
        );
        return abi.decode(data, (uint));
    }

    /**
     * @notice Sender redeems kTokens in exchange for a specified amount of underlying asset
     * @dev Accrues interest whether or not the operation succeeds, unless reverted
     * @param redeemAmount The amount of underlying to redeem
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function redeemUnderlying(
        uint redeemAmount
    ) external payable override returns (uint) {
        bytes memory data = delegateToImplementation(
            abi.encodeWithSignature("redeemUnderlying(uint256)", redeemAmount)
        );
        return abi.decode(data, (uint));
    }

    /**
     * @notice Sender borrows assets from the protocol to their own address
     * @param borrowAmount The amount of the underlying asset to borrow
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function borrow(uint borrowAmount) external payable override returns (uint) {
        bytes memory data = delegateToImplementation(
            abi.encodeWithSignature("borrow(uint256)", borrowAmount)
        );
        return abi.decode(data, (uint));
    }

    /**
     * @notice The sender liquidates the borrowers collateral.
     *  The collateral seized is transferred to the liquidator.
     * @param liquidator The address repaying the borrow and seizing collateral
     * @param borrower The borrower of this kToken to be liquidated
     * @param kTokenCollateral The market in which to seize collateral from the borrower
     * @param repayAmount The amount of the underlying borrowed asset to repay
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function liquidateBorrow(
        address liquidator,
        address borrower,
        uint repayAmount,
        KTokenInterface kTokenCollateral
    ) external override returns (uint) {
        bytes memory data = delegateToImplementation(
            abi.encodeWithSignature(
                "liquidateBorrow(address,address,uint256,address)",
                liquidator,
                borrower,
                repayAmount,
                kTokenCollateral
            )
        );
        return abi.decode(data, (uint));
    }

    function _setCentralHub(address newCentralHub) external override {
        delegateToImplementation(
            abi.encodeWithSignature("_setCentralHub(address)", newCentralHub)
        );
    }

}

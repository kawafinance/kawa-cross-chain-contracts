// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import "./KErc20Base.sol";
import "./KTokenInterfaces.sol";

/**
 * @title Kawa's KErc20 Contract
 * @notice KTokens which wrap an EIP-20 underlying
 * @author Kawa
 */
contract KErc20 is KErc20Base, KErc20Interface {
    /**
     * @notice Initialize the new money market
     * @param underlying_ The address of the underlying asset
     * @param comptroller_ The address of the Comptroller
     * @param interestRateModel_ The address of the interest rate model
     * @param initialExchangeRateMantissa_ The initial exchange rate, scaled by 1e18
     * @param name_ ERC-20 name of this token
     * @param symbol_ ERC-20 symbol of this token
     * @param decimals_ ERC-20 decimal precision of this token
     */
    function initialize(
        address underlying_,
        ComptrollerInterface comptroller_,
        InterestRateModel interestRateModel_,
        uint initialExchangeRateMantissa_,
        string memory name_,
        string memory symbol_,
        uint8 decimals_
    ) public {
        // KToken initialize does the bulk of the work
        super.initialize(
            comptroller_,
            interestRateModel_,
            initialExchangeRateMantissa_,
            name_,
            symbol_,
            decimals_
        );

        // Set underlying and sanity check it
        underlying = underlying_;
        EIP20Interface(underlying).totalSupply();
    }

    /*** User Interface ***/

    /**
     * @notice Sender supplies assets into the market and receives kTokens in exchange
     * @dev Accrues interest whether or not the operation succeeds, unless reverted
     * @param mintAmount The amount of the underlying asset to supply
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function mint(uint mintAmount) external override returns (uint) {
        (uint err, ) = mintInternal(mintAmount);
        return err;
    }

    /**
     * @notice Supply assets but without a 2-step approval process, EIP-2612
     * @dev Simply calls the underlying token's `permit()` function and then assumes things worked
     * @param mintAmount The amount of the underlying asset to supply
     * @param deadline The amount of the underlying asset to supply
     * @param v ECDSA recovery id for the signature
     * @param r ECDSA r parameter for the signature
     * @param s ECDSA s parameter for the signature
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function mintWithPermit(
        uint mintAmount,
        uint deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external override returns (uint) {
        IERC20Permit token = IERC20Permit(underlying);

        // Go submit our pre-approval signature data to the underlying token, but
        // explicitly fail if there is an issue.
        SafeERC20.safePermit(
            token,
            msg.sender,
            address(this),
            mintAmount,
            deadline,
            v,
            r,
            s
        );

        (uint err, ) = mintInternal(mintAmount);
        return err;
    }

    /**
     * @notice Sender repays their own borrow
     * @param repayAmount The amount to repay, or uint.max for the full outstanding amount
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function repayBorrow(uint repayAmount) external override returns (uint) {
        (uint err, ) = repayBorrowInternal(repayAmount);
        return err;
    }

    /**
     * @notice Sender repays a borrow belonging to borrower
     * @param borrower the account with the debt being payed off
     * @param repayAmount The amount to repay, or uint.max for the full outstanding amount
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function repayBorrowBehalf(
        address borrower,
        uint repayAmount
    ) external override returns (uint) {
        (uint err, ) = repayBorrowBehalfInternal(borrower, repayAmount);
        return err;
    }

    /**
     * @notice Sender redeems kTokens in exchange for the underlying asset
     * @dev Accrues interest whether or not the operation succeeds, unless reverted
     * @param redeemTokens The number of kTokens to redeem into underlying
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function redeem(uint redeemTokens) external override returns (uint) {
        return redeemInternal(redeemTokens);
    }

    /**
     * @notice Sender redeems kTokens in exchange for a specified amount of underlying asset
     * @dev Accrues interest whether or not the operation succeeds, unless reverted
     * @param redeemAmount The amount of underlying to redeem
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function redeemUnderlying(
        uint redeemAmount
    ) external override returns (uint) {
        return redeemUnderlyingInternal(redeemAmount);
    }

    /**
     * @notice Sender borrows assets from the protocol to their own address
     * @param borrowAmount The amount of the underlying asset to borrow
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function borrow(uint borrowAmount) external override returns (uint) {
        return borrowInternal(borrowAmount);
    }

    /**
     * @notice The sender liquidates the borrowers collateral.
     *  The collateral seized is transferred to the liquidator.
     * @param borrower The borrower of this kToken to be liquidated
     * @param repayAmount The amount of the underlying borrowed asset to repay
     * @param kTokenCollateral The market in which to seize collateral from the borrower
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function liquidateBorrow(
        address borrower,
        uint repayAmount,
        KTokenInterface kTokenCollateral
    ) external override returns (uint) {
        (uint err, ) = liquidateBorrowInternal(
            borrower,
            repayAmount,
            kTokenCollateral
        );
        return err;
    }

    /*** Internal Functions ***/

    /**
     * @notice Sender supplies assets into the market and receives kTokens in exchange
     * @dev Accrues interest whether or not the operation succeeds, unless reverted
     * @param mintAmount The amount of the underlying asset to supply
     * @return (uint, uint) An error code (0=success, otherwise a failure, see ErrorReporter.sol), and the actual mint amount.
     */
    function mintInternal(
        uint mintAmount
    ) internal nonReentrant returns (uint, uint) {
        uint error = accrueInterest();
        if (error != uint(Error.NO_ERROR)) {
            // accrueInterest emits logs on errors, but we still want to log the fact that an attempted borrow failed
            return (
                fail(Error(error), FailureInfo.MINT_ACCRUE_INTEREST_FAILED),
                0
            );
        }
        // mintFresh emits the actual Mint event if successful and logs on errors, so we don't need to
        return mintFresh(msg.sender, mintAmount);
    }

    /**
     * @notice Sender repays their own borrow
     * @param repayAmount The amount to repay
     * @return (uint, uint) An error code (0=success, otherwise a failure, see ErrorReporter.sol), and the actual repayment amount.
     */
    function repayBorrowInternal(
        uint repayAmount
    ) internal nonReentrant returns (uint, uint) {
        uint error = accrueInterest();
        if (error != uint(Error.NO_ERROR)) {
            // accrueInterest emits logs on errors, but we still want to log the fact that an attempted borrow failed
            return (
                fail(
                Error(error),
                FailureInfo.REPAY_BORROW_ACCRUE_INTEREST_FAILED
            ),
                0
            );
        }
        // repayBorrowFresh emits repay-borrow-specific logs on errors, so we don't need to
        return repayBorrowFresh(msg.sender, msg.sender, repayAmount);
    }

    /**
     * @notice Sender repays a borrow belonging to borrower
     * @param borrower the account with the debt being payed off
     * @param repayAmount The amount to repay
     * @return (uint, uint) An error code (0=success, otherwise a failure, see ErrorReporter.sol), and the actual repayment amount.
     */
    function repayBorrowBehalfInternal(
        address borrower,
        uint repayAmount
    ) internal nonReentrant returns (uint, uint) {
        uint error = accrueInterest();
        if (error != uint(Error.NO_ERROR)) {
            // accrueInterest emits logs on errors, but we still want to log the fact that an attempted borrow failed
            return (
                fail(
                Error(error),
                FailureInfo.REPAY_BEHALF_ACCRUE_INTEREST_FAILED
            ),
                0
            );
        }
        // repayBorrowFresh emits repay-borrow-specific logs on errors, so we don't need to
        return repayBorrowFresh(msg.sender, borrower, repayAmount);
    }

    /**
     * @notice The sender liquidates the borrowers collateral.
     *  The collateral seized is transferred to the liquidator.
     * @param borrower The borrower of this kToken to be liquidated
     * @param kTokenCollateral The market in which to seize collateral from the borrower
     * @param repayAmount The amount of the underlying borrowed asset to repay
     * @return (uint, uint) An error code (0=success, otherwise a failure, see ErrorReporter.sol), and the actual repayment amount.
     */
    function liquidateBorrowInternal(
        address borrower,
        uint repayAmount,
        KTokenInterface kTokenCollateral
    ) internal nonReentrant returns (uint, uint) {
        uint error = accrueInterest();
        if (error != uint(Error.NO_ERROR)) {
            // accrueInterest emits logs on errors, but we still want to log the fact that an attempted liquidation failed
            return (
                fail(
                Error(error),
                FailureInfo.LIQUIDATE_ACCRUE_BORROW_INTEREST_FAILED
            ),
                0
            );
        }

        error = kTokenCollateral.accrueInterest();
        if (error != uint(Error.NO_ERROR)) {
            // accrueInterest emits logs on errors, but we still want to log the fact that an attempted liquidation failed
            return (
                fail(
                Error(error),
                FailureInfo.LIQUIDATE_ACCRUE_COLLATERAL_INTEREST_FAILED
            ),
                0
            );
        }

        // liquidateBorrowFresh emits borrow-specific logs on errors, so we don't need to
        return
            liquidateBorrowFresh(
            msg.sender,
            borrower,
            repayAmount,
            kTokenCollateral
        );
    }

    /**
     * @dev Similar to EIP20 transfer, except it handles a False result from `transferFrom` and reverts in that case.
     *      This will revert due to insufficient balance or insufficient allowance.
     *      This function returns the actual amount received,
     *      which may be less than `amount` if there is a fee attached to the transfer.
     *
     *      Note: This wrapper safely handles non-standard ERC-20 tokens that do not return a value.
     *            See here: https://medium.com/coinmonks/missing-return-value-bug-at-least-130-tokens-affected-d67bf08521ca
     */
    function doTransferIn(
        address from,
        uint amount
    ) internal virtual override returns (uint) {
        // Read from storage once
        address underlying_ = underlying;
        EIP20NonStandardInterface token = EIP20NonStandardInterface(
            underlying_
        );
        uint balanceBefore = EIP20Interface(underlying_).balanceOf(
            address(this)
        );
        token.transferFrom(from, address(this), amount);

        bool success;
        assembly {
            switch returndatasize()
            case 0 {
                // This is a non-standard ERC-20
                success := not(0) // set success to true
            }
            case 32 {
                // This is a compliant ERC-20
                returndatacopy(0, 0, 32)
                success := mload(0) // Set `success = returndata` of external call
            }
            default {
                // This is an excessively non-compliant ERC-20, revert.
                revert(0, 0)
            }
        }
        require(success, "TOKEN_TRANSFER_IN_FAILED");

        // Calculate the amount that was *actually* transferred
        uint balanceAfter = EIP20Interface(underlying_).balanceOf(
            address(this)
        );
        require(balanceAfter >= balanceBefore, "TOKEN_TRANSFER_IN_OVERFLOW");
        return balanceAfter - balanceBefore; // underflow already checked above, just subtract
    }

    /**
     * @dev Similar to EIP20 transfer, except it handles a False success from `transfer` and returns an explanatory
     *      error code rather than reverting. If caller has not called checked protocol's balance, this may revert due to
     *      insufficient cash held in this contract. If caller has checked protocol's balance prior to this call, and verified
     *      it is >= amount, this should not revert in normal conditions.
     *
     *      Note: This wrapper safely handles non-standard ERC-20 tokens that do not return a value.
     *            See here: https://medium.com/coinmonks/missing-return-value-bug-at-least-130-tokens-affected-d67bf08521ca
     */
    function doTransferOut(
        address payable to,
        uint amount
    ) internal virtual override {
        EIP20NonStandardInterface token = EIP20NonStandardInterface(underlying);
        token.transfer(to, amount);

        bool success;
        assembly {
            switch returndatasize()
            case 0 {
                // This is a non-standard ERC-20
                success := not(0) // set success to true
            }
            case 32 {
                // This is a compliant ERC-20
                returndatacopy(0, 0, 32)
                success := mload(0) // Set `success = returndata` of override external call
            }
            default {
                // This is an excessively non-compliant ERC-20, revert.
                revert(0, 0)
            }
        }
        require(success, "TOKEN_TRANSFER_OUT_FAILED");
    }
}

// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./WErc20.sol";
import "./KErc20Base.sol";
import "./KTokenInterfaces.sol";
import "./CentralHub/MessageInterfaces.sol";

/**
 * @title Kawa's KErc20.sol Contract
 * @notice KTokens which wrap an EIP-20 underlying
 * @author Kawa
 */
contract KErc20CrossChain is KErc20Base, KErc20CrossChainInterface {
    /**
     * @notice Initialize the new money market
     * @param underlying_ The address of the underlying asset
     * @param comptroller_ The address of the Comptroller
     * @param interestRateModel_ The address of the interest rate model
     * @param initialExchangeRateMantissa_ The initial exchange rate, scaled by 1e18
     * @param name_ ERC-20 name of this token
     * @param symbol_ ERC-20 symbol of this token
     * @param decimals_ ERC-20 decimal precision of this token
     * @param centralHub_ The address of the MessageHub
     */
    function initialize(
        address underlying_,
        ComptrollerInterface comptroller_,
        InterestRateModel interestRateModel_,
        uint initialExchangeRateMantissa_,
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        address centralHub_
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

        centralHub = centralHub_;

        // Set underlying and sanity check it
        underlying = underlying_;
        EIP20Interface(underlying).totalSupply();
    }

    /*** MessageHub Interface ***/

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
        require(msg.sender == centralHub, "Unauthorized");
        (uint err,) = mintInternal(
            minter,
            mintAmount
        );
        return err;
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
        require(msg.sender == centralHub, "Unauthorized");
        (uint err,) = repayBorrowInternal(
            payer,
            repayAmount);
        return err;
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
        require(msg.sender == centralHub, "Unauthorized");
        (uint err,) = repayBorrowBehalfInternal(
            payer,
            borrower,
            repayAmount
        );
        return err;
    }

    /**
     * @notice The sender liquidates the borrowers collateral.
     *  The collateral seized is transferred to the liquidator.
     * @param liquidator The address repaying the borrow and seizing collateral
     * @param borrower The borrower of this kToken to be liquidated
     * @param repayAmount The amount of the underlying borrowed asset to repay
     * @param kTokenCollateral The market in which to seize collateral from the borrower
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function liquidateBorrow(
        address liquidator,
        address borrower,
        uint repayAmount,
        KTokenInterface kTokenCollateral
    ) external override returns (uint) {
        require(msg.sender == centralHub, "Unauthorized");
        (uint err,) = liquidateBorrowInternal(
            liquidator,
            borrower,
            repayAmount,
            kTokenCollateral
        );
        return err;
    }

    /*** User Interface ***/

    /**
     * @notice Sender redeems kTokens in exchange for the underlying asset
     * @dev Accrues interest whether or not the operation succeeds, unless reverted
     * @param redeemTokens The number of kTokens to redeem into underlying
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function redeem(uint redeemTokens) external payable override returns (uint) {
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
    ) external payable override returns (uint) {
        return redeemUnderlyingInternal(redeemAmount);
    }

    /**
     * @notice Sender borrows assets from the protocol to their own address
     * @param borrowAmount The amount of the underlying asset to borrow
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function borrow(uint borrowAmount) external payable override returns (uint) {
        return borrowInternal(borrowAmount);
    }

    /*** Internal Functions ***/

    /**
     * @notice Sender supplies assets into the market and receives kTokens in exchange
     * @dev Accrues interest whether or not the operation succeeds, unless reverted
     * @param minter The address of the account which is supplying the assets
     * @param mintAmount The amount of the underlying asset to supply
     * @return (uint, uint) An error code (0=success, otherwise a failure, see ErrorReporter.sol), and the actual mint amount.
     */
    function mintInternal(
        address minter,
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
        return mintFresh(minter, mintAmount);
    }

    /**
     * @notice Sender repays their own borrow
     * @param payer the account paying off the borrow
     * @param repayAmount The amount to repay
     * @return (uint, uint) An error code (0=success, otherwise a failure, see ErrorReporter.sol), and the actual repayment amount.
     */
    function repayBorrowInternal(
        address payer,
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
        return repayBorrowFresh(payer, payer, repayAmount);
    }

    /**
     * @notice Sender repays a borrow belonging to borrower
     * @param payer the account paying off the borrow
     * @param borrower the account with the debt being payed off
     * @param repayAmount The amount to repay
     * @return (uint, uint) An error code (0=success, otherwise a failure, see ErrorReporter.sol), and the actual repayment amount.
     */
    function repayBorrowBehalfInternal(
        address payer,
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
        return repayBorrowFresh(payer, borrower, repayAmount);
    }

    /**
     * @notice The sender liquidates the borrowers collateral.
     *  The collateral seized is transferred to the liquidator.
     * @param liquidator The address repaying the borrow and seizing collateral
     * @param borrower The borrower of this kToken to be liquidated
     * @param kTokenCollateral The market in which to seize collateral from the borrower
     * @param repayAmount The amount of the underlying borrowed asset to repay
     * @return (uint, uint) An error code (0=success, otherwise a failure, see ErrorReporter.sol), and the actual repayment amount.
     */
    function liquidateBorrowInternal(
        address liquidator,
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
            liquidator,
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
        WErc20 token = WErc20(underlying);

        uint balanceBefore = EIP20Interface(underlying_).balanceOf(
            address(this)
        );
        token.mint(address(this), amount);

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
        WErc20 token = WErc20(underlying);
        token.burn(amount);

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

        bytes memory payload = abi.encode(
            KClientInterface.releaseETH.selector,
            msg.sender,
            amount
        );
        MessageInterface(centralHub).sendMessage{value: msg.value}(msg.sender,payload);
    }

    /*** Admin Functions ***/

    function _setCentralHub(address newCentralHub) external override {
        require(msg.sender == admin, "Unauthorized");

        address oldCentralHub = centralHub;
        centralHub = newCentralHub;

        emit NewCentralHub(
            oldCentralHub,
            centralHub
        );
    }
}

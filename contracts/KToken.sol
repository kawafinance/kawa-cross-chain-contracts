// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.20;

import "./ComptrollerInterface.sol";
import "./KTokenInterfaces.sol";
import "./TokenErrorReporter.sol";
import "./Exponential.sol";
import "./EIP20Interface.sol";
import "./irm/InterestRateModel.sol";

/**
 * @title Kawa's KToken Contract
 * @notice Abstract base for KTokens
 * @author Kawa
 */
abstract contract KToken is KTokenInterface, Exponential, TokenErrorReporter {
    /**
     * @notice Initialize the money market
     * @param comptroller_ The address of the Comptroller
     * @param interestRateModel_ The address of the interest rate model
     * @param initialExchangeRateMantissa_ The initial exchange rate, scaled by 1e18
     * @param name_ EIP-20 name of this token
     * @param symbol_ EIP-20 symbol of this token
     * @param decimals_ EIP-20 decimal precision of this token
     */
    function initialize(
        ComptrollerInterface comptroller_,
        InterestRateModel interestRateModel_,
        uint initialExchangeRateMantissa_,
        string memory name_,
        string memory symbol_,
        uint8 decimals_
    ) public {
        require(msg.sender == admin, "only admin may initialize the market");
        require(
            accrualBlockTimestamp == 0 && borrowIndex == 0,
            "market may only be initialized once"
        );

        // Set initial exchange rate
        initialExchangeRateMantissa = initialExchangeRateMantissa_;
        require(
            initialExchangeRateMantissa > 0,
            "initial exchange rate must be greater than zero."
        );

        // Set the comptroller
        uint err = _setComptroller(comptroller_);
        require(err == uint(Error.NO_ERROR), "setting comptroller failed");

        // Initialize block timestamp and borrow index (block timestamp mocks depend on comptroller being set)
        accrualBlockTimestamp = getBlockTimestamp();
        borrowIndex = mantissaOne;

        // Set the interest rate model (depends on block timestamp / borrow index)
        err = _setInterestRateModelFresh(interestRateModel_);
        require(
            err == uint(Error.NO_ERROR),
            "setting interest rate model failed"
        );

        name = name_;
        symbol = symbol_;
        decimals = decimals_;

        // The counter starts true to prevent changing it from zero to non-zero (i.e. smaller cost/refund)
        _notEntered = true;
    }

    /**
     * @notice Transfer `tokens` tokens from `src` to `dst` by `spender`
     * @dev Called by both `transfer` and `transferFrom` internally
     * @param spender The address of the account performing the transfer
     * @param src The address of the source account
     * @param dst The address of the destination account
     * @param tokens The number of tokens to transfer
     * @return Whether or not the transfer succeeded
     */
    function transferTokens(
        address spender,
        address src,
        address dst,
        uint tokens
    ) internal returns (uint) {
        /* Fail if transfer not allowed */
        uint allowed = comptroller.transferAllowed(
            address(this),
            src,
            dst,
            tokens
        );
        if (allowed != 0) {
            return
                failOpaque(
                    Error.COMPTROLLER_REJECTION,
                    FailureInfo.TRANSFER_COMPTROLLER_REJECTION,
                    allowed
                );
        }

        /* Do not allow self-transfers */
        if (src == dst) {
            return fail(Error.BAD_INPUT, FailureInfo.TRANSFER_NOT_ALLOWED);
        }

        /* Get the allowance, infinite for the account owner */
        uint startingAllowance = 0;
        if (spender == src) {
            startingAllowance = type(uint).max;
        } else {
            startingAllowance = transferAllowances[src][spender];
        }

        /* Do the calculations, checking for {under,over}flow */
        MathError mathErr;
        uint allowanceNew;
        uint srcTokensNew;
        uint dstTokensNew;

        (mathErr, allowanceNew) = subUInt(startingAllowance, tokens);
        if (mathErr != MathError.NO_ERROR) {
            return fail(Error.MATH_ERROR, FailureInfo.TRANSFER_NOT_ALLOWED);
        }

        (mathErr, srcTokensNew) = subUInt(accountTokens[src], tokens);
        if (mathErr != MathError.NO_ERROR) {
            return fail(Error.MATH_ERROR, FailureInfo.TRANSFER_NOT_ENOUGH);
        }

        (mathErr, dstTokensNew) = addUInt(accountTokens[dst], tokens);
        if (mathErr != MathError.NO_ERROR) {
            return fail(Error.MATH_ERROR, FailureInfo.TRANSFER_TOO_MUCH);
        }

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)

        accountTokens[src] = srcTokensNew;
        accountTokens[dst] = dstTokensNew;

        /* Eat some of the allowance (if necessary) */
        if (startingAllowance != type(uint).max) {
            transferAllowances[src][spender] = allowanceNew;
        }

        /* We emit a Transfer event */
        emit Transfer(src, dst, tokens);

        // unused function
        // comptroller.transferVerify(address(this), src, dst, tokens);

        return uint(Error.NO_ERROR);
    }

    /**
     * @notice Transfer `amount` tokens from `msg.sender` to `dst`
     * @param dst The address of the destination account
     * @param amount The number of tokens to transfer
     * @return Whether or not the transfer succeeded
     */
    function transfer(
        address dst,
        uint256 amount
    ) external override nonReentrant returns (bool) {
        return
            transferTokens(msg.sender, msg.sender, dst, amount) ==
            uint(Error.NO_ERROR);
    }

    /**
     * @notice Transfer `amount` tokens from `src` to `dst`
     * @param src The address of the source account
     * @param dst The address of the destination account
     * @param amount The number of tokens to transfer
     * @return Whether or not the transfer succeeded
     */
    function transferFrom(
        address src,
        address dst,
        uint256 amount
    ) external override nonReentrant returns (bool) {
        return
            transferTokens(msg.sender, src, dst, amount) ==
            uint(Error.NO_ERROR);
    }

    /**
     * @notice Approve `spender` to transfer up to `amount` from `src`
     * @dev This will overwrite the approval amount for `spender`
     *  and is subject to issues noted [here](https://eips.ethereum.org/EIPS/eip-20#approve)
     * @param spender The address of the account which may transfer tokens
     * @param amount The number of tokens that are approved (uint.max means infinite)
     * @return Whether or not the approval succeeded
     */
    function approve(
        address spender,
        uint256 amount
    ) external override returns (bool) {
        address src = msg.sender;
        transferAllowances[src][spender] = amount;
        emit Approval(src, spender, amount);
        return true;
    }

    /**
     * @notice Get the current allowance from `owner` for `spender`
     * @param owner The address of the account which owns the tokens to be spent
     * @param spender The address of the account which may transfer tokens
     * @return The number of tokens allowed to be spent (uint.max means infinite)
     */
    function allowance(
        address owner,
        address spender
    ) external view override returns (uint256) {
        return transferAllowances[owner][spender];
    }

    /**
     * @notice Get the token balance of the `owner`
     * @param owner The address of the account to query
     * @return The number of tokens owned by `owner`
     */
    function balanceOf(address owner) external view override returns (uint256) {
        return accountTokens[owner];
    }

    /**
     * @notice Get the underlying balance of the `owner`
     * @dev This also accrues interest in a transaction
     * @param owner The address of the account to query
     * @return The amount of underlying owned by `owner`
     */
    function balanceOfUnderlying(
        address owner
    ) external override returns (uint) {
        Exp memory exchangeRate = Exp({mantissa: exchangeRateCurrent()});
        (MathError mErr, uint balance) = mulScalarTruncate(
            exchangeRate,
            accountTokens[owner]
        );
        require(mErr == MathError.NO_ERROR, "balance could not be calculated");
        return balance;
    }

    /**
     * @notice Get a snapshot of the account's balances, and the cached exchange rate
     * @dev This is used by comptroller to more efficiently perform liquidity checks.
     * @param account Address of the account to snapshot
     * @return (possible error, token balance, borrow balance, exchange rate mantissa)
     */
    function getAccountSnapshot(
        address account
    ) external view override returns (uint, uint, uint, uint) {
        uint kTokenBalance = accountTokens[account];
        uint borrowBalance;
        uint exchangeRateMantissa;

        MathError mErr;

        (mErr, borrowBalance) = borrowBalanceStoredInternal(account);
        if (mErr != MathError.NO_ERROR) {
            return (uint(Error.MATH_ERROR), 0, 0, 0);
        }

        (mErr, exchangeRateMantissa) = exchangeRateStoredInternal();
        if (mErr != MathError.NO_ERROR) {
            return (uint(Error.MATH_ERROR), 0, 0, 0);
        }

        return (
            uint(Error.NO_ERROR),
            kTokenBalance,
            borrowBalance,
            exchangeRateMantissa
        );
    }

    /**
     * @dev Function to simply retrieve block timestamp
     *  This exists mainly for inheriting test contracts to stub this result.
     */
    function getBlockTimestamp() internal view virtual returns (uint) {
        return block.timestamp;
    }

    /**
     * @notice Returns the current per-timestamp borrow interest rate for this kToken
     * @return The borrow interest rate per timestamp, scaled by 1e18
     */
    function borrowRatePerTimestamp() external view override returns (uint) {
        return
            interestRateModel.getBorrowRate(
                getCashPrior(),
                totalBorrows,
                totalReserves
            );
    }

    /**
     * @notice Returns the current per-timestamp supply interest rate for this kToken
     * @return The supply interest rate per timestamp, scaled by 1e18
     */
    function supplyRatePerTimestamp() external view override returns (uint) {
        return
            interestRateModel.getSupplyRate(
                getCashPrior(),
                totalBorrows,
                totalReserves,
                reserveFactorMantissa
            );
    }

    /**
     * @notice Returns the current total borrows plus accrued interest
     * @return The total borrows with interest
     */
    function totalBorrowsCurrent()
        external
        override
        nonReentrant
        returns (uint)
    {
        require(
            accrueInterest() == uint(Error.NO_ERROR),
            "accrue interest failed"
        );
        return totalBorrows;
    }

    /**
     * @notice Accrue interest to updated borrowIndex and then calculate account's borrow balance using the updated borrowIndex
     * @param account The address whose balance should be calculated after updating borrowIndex
     * @return The calculated balance
     */
    function borrowBalanceCurrent(
        address account
    ) external override nonReentrant returns (uint) {
        require(
            accrueInterest() == uint(Error.NO_ERROR),
            "accrue interest failed"
        );
        return borrowBalanceStored(account);
    }

    /**
     * @notice Return the borrow balance of account based on stored data
     * @param account The address whose balance should be calculated
     * @return The calculated balance
     */
    function borrowBalanceStored(
        address account
    ) public view override returns (uint) {
        (MathError err, uint result) = borrowBalanceStoredInternal(account);
        require(
            err == MathError.NO_ERROR,
            "borrowBalanceStored: borrowBalanceStoredInternal failed"
        );
        return result;
    }

    /**
     * @notice Return the borrow balance of account based on stored data
     * @param account The address whose balance should be calculated
     * @return (error code, the calculated balance or 0 if error code is non-zero)
     */
    function borrowBalanceStoredInternal(
        address account
    ) internal view returns (MathError, uint) {
        /* Note: we do not assert that the market is up to date */
        MathError mathErr;
        uint principalTimesIndex;
        uint result;

        /* Get borrowBalance and borrowIndex */
        BorrowSnapshot storage borrowSnapshot = accountBorrows[account];

        /* If borrowBalance = 0 then borrowIndex is likely also 0.
         * Rather than failing the calculation with a division by 0, we immediately return 0 in this case.
         */
        if (borrowSnapshot.principal == 0) {
            return (MathError.NO_ERROR, 0);
        }

        /* Calculate new borrow balance using the interest index:
         *  recentBorrowBalance = borrower.borrowBalance * market.borrowIndex / borrower.borrowIndex
         */
        (mathErr, principalTimesIndex) = mulUInt(
            borrowSnapshot.principal,
            borrowIndex
        );
        if (mathErr != MathError.NO_ERROR) {
            return (mathErr, 0);
        }

        (mathErr, result) = divUInt(
            principalTimesIndex,
            borrowSnapshot.interestIndex
        );
        if (mathErr != MathError.NO_ERROR) {
            return (mathErr, 0);
        }

        return (MathError.NO_ERROR, result);
    }

    /**
     * @notice Accrue interest then return the up-to-date exchange rate
     * @return Calculated exchange rate scaled by 1e18
     */
    function exchangeRateCurrent() public override nonReentrant returns (uint) {
        require(
            accrueInterest() == uint(Error.NO_ERROR),
            "accrue interest failed"
        );
        return exchangeRateStored();
    }

    /**
     * @notice Calculates the exchange rate from the underlying to the KToken
     * @dev This function does not accrue interest before calculating the exchange rate
     * @return Calculated exchange rate scaled by 1e18
     */
    function exchangeRateStored() public view override returns (uint) {
        (MathError err, uint result) = exchangeRateStoredInternal();
        require(
            err == MathError.NO_ERROR,
            "exchangeRateStored: exchangeRateStoredInternal failed"
        );
        return result;
    }

    /**
     * @notice Calculates the exchange rate from the underlying to the KToken
     * @dev This function does not accrue interest before calculating the exchange rate
     * @return (error code, calculated exchange rate scaled by 1e18)
     */
    function exchangeRateStoredInternal()
        internal
        view
        virtual
        returns (MathError, uint)
    {
        uint _totalSupply = totalSupply;
        if (_totalSupply == 0) {
            /*
             * If there are no tokens minted:
             *  exchangeRate = initialExchangeRate
             */
            return (MathError.NO_ERROR, initialExchangeRateMantissa);
        } else {
            /*
             * Otherwise:
             *  exchangeRate = (totalCash + totalBorrows - totalReserves) / totalSupply
             */
            uint totalCash = getCashPrior();
            uint cashPlusBorrowsMinusReserves;
            Exp memory exchangeRate;
            MathError mathErr;

            (mathErr, cashPlusBorrowsMinusReserves) = addThenSubUInt(
                totalCash,
                totalBorrows,
                totalReserves
            );
            if (mathErr != MathError.NO_ERROR) {
                return (mathErr, 0);
            }

            (mathErr, exchangeRate) = getExp(
                cashPlusBorrowsMinusReserves,
                _totalSupply
            );
            if (mathErr != MathError.NO_ERROR) {
                return (mathErr, 0);
            }

            return (MathError.NO_ERROR, exchangeRate.mantissa);
        }
    }

    /**
     * @notice Get cash balance of this kToken in the underlying asset
     * @return The quantity of underlying asset owned by this contract
     */
    function getCash() external view override returns (uint) {
        return getCashPrior();
    }

    /**
     * @notice Applies accrued interest to total borrows and reserves
     * @dev This calculates interest accrued from the last checkpointed block
     *   up to the current block and writes new checkpoint to storage.
     */
    function accrueInterest() public virtual override returns (uint) {
        /* Remember the initial block timestamp */
        uint currentBlockTimestamp = getBlockTimestamp();
        uint accrualBlockTimestampPrior = accrualBlockTimestamp;

        /* Short-circuit accumulating 0 interest */
        if (accrualBlockTimestampPrior == currentBlockTimestamp) {
            return uint(Error.NO_ERROR);
        }

        /* Read the previous values out of storage */
        uint cashPrior = getCashPrior();
        uint borrowsPrior = totalBorrows;
        uint reservesPrior = totalReserves;
        uint borrowIndexPrior = borrowIndex;

        /* Calculate the current borrow interest rate */
        uint borrowRateMantissa = interestRateModel.getBorrowRate(
            cashPrior,
            borrowsPrior,
            reservesPrior
        );
        require(
            borrowRateMantissa <= borrowRateMaxMantissa,
            "borrow rate is absurdly high"
        );

        /* Calculate the number of blocks elapsed since the last accrual */
        (MathError mathErr, uint blockDelta) = subUInt(
            currentBlockTimestamp,
            accrualBlockTimestampPrior
        );
        require(
            mathErr == MathError.NO_ERROR,
            "could not calculate block delta"
        );

        /*
         * Calculate the interest accumulated into borrows and reserves and the new index:
         *  simpleInterestFactor = borrowRate * blockDelta
         *  interestAccumulated = simpleInterestFactor * totalBorrows
         *  totalBorrowsNew = interestAccumulated + totalBorrows
         *  totalReservesNew = interestAccumulated * reserveFactor + totalReserves
         *  borrowIndexNew = simpleInterestFactor * borrowIndex + borrowIndex
         */

        Exp memory simpleInterestFactor;
        uint interestAccumulated;
        uint totalBorrowsNew;
        uint totalReservesNew;
        uint borrowIndexNew;

        (mathErr, simpleInterestFactor) = mulScalar(
            Exp({mantissa: borrowRateMantissa}),
            blockDelta
        );
        if (mathErr != MathError.NO_ERROR) {
            return
                failOpaque(
                    Error.MATH_ERROR,
                    FailureInfo
                        .ACCRUE_INTEREST_SIMPLE_INTEREST_FACTOR_CALCULATION_FAILED,
                    uint(mathErr)
                );
        }

        (mathErr, interestAccumulated) = mulScalarTruncate(
            simpleInterestFactor,
            borrowsPrior
        );
        if (mathErr != MathError.NO_ERROR) {
            return
                failOpaque(
                    Error.MATH_ERROR,
                    FailureInfo
                        .ACCRUE_INTEREST_ACCUMULATED_INTEREST_CALCULATION_FAILED,
                    uint(mathErr)
                );
        }

        (mathErr, totalBorrowsNew) = addUInt(interestAccumulated, borrowsPrior);
        if (mathErr != MathError.NO_ERROR) {
            return
                failOpaque(
                    Error.MATH_ERROR,
                    FailureInfo
                        .ACCRUE_INTEREST_NEW_TOTAL_BORROWS_CALCULATION_FAILED,
                    uint(mathErr)
                );
        }

        (mathErr, totalReservesNew) = mulScalarTruncateAddUInt(
            Exp({mantissa: reserveFactorMantissa}),
            interestAccumulated,
            reservesPrior
        );
        if (mathErr != MathError.NO_ERROR) {
            return
                failOpaque(
                    Error.MATH_ERROR,
                    FailureInfo
                        .ACCRUE_INTEREST_NEW_TOTAL_RESERVES_CALCULATION_FAILED,
                    uint(mathErr)
                );
        }

        (mathErr, borrowIndexNew) = mulScalarTruncateAddUInt(
            simpleInterestFactor,
            borrowIndexPrior,
            borrowIndexPrior
        );
        if (mathErr != MathError.NO_ERROR) {
            return
                failOpaque(
                    Error.MATH_ERROR,
                    FailureInfo
                        .ACCRUE_INTEREST_NEW_BORROW_INDEX_CALCULATION_FAILED,
                    uint(mathErr)
                );
        }

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)

        /* We write the previously calculated values into storage */
        accrualBlockTimestamp = currentBlockTimestamp;
        borrowIndex = borrowIndexNew;
        totalBorrows = totalBorrowsNew;
        totalReserves = totalReservesNew;

        /* We emit an AccrueInterest event */
        emit AccrueInterest(
            cashPrior,
            interestAccumulated,
            borrowIndexNew,
            totalBorrowsNew
        );

        return uint(Error.NO_ERROR);
    }

    struct MintLocalVars {
        Error err;
        MathError mathErr;
        uint exchangeRateMantissa;
        uint mintTokens;
        uint totalSupplyNew;
        uint accountTokensNew;
        uint actualMintAmount;
    }

    /**
     * @notice User supplies assets into the market and receives kTokens in exchange
     * @dev Assumes interest has already been accrued up to the current block
     * @param minter The address of the account which is supplying the assets
     * @param mintAmount The amount of the underlying asset to supply
     * @return (uint, uint) An error code (0=success, otherwise a failure, see ErrorReporter.sol), and the actual mint amount.
     */
    function mintFresh(
        address minter,
        uint mintAmount
    ) internal returns (uint, uint) {
        /* Fail if mint not allowed */
        uint allowed = comptroller.mintAllowed(
            address(this),
            minter,
            mintAmount
        );
        if (allowed != 0) {
            return (
                failOpaque(
                    Error.COMPTROLLER_REJECTION,
                    FailureInfo.MINT_COMPTROLLER_REJECTION,
                    allowed
                ),
                0
            );
        }

        /* Verify market's block timestamp equals current block timestamp */
        if (accrualBlockTimestamp != getBlockTimestamp()) {
            return (
                fail(Error.MARKET_NOT_FRESH, FailureInfo.MINT_FRESHNESS_CHECK),
                0
            );
        }

        MintLocalVars memory vars;

        (
            vars.mathErr,
            vars.exchangeRateMantissa
        ) = exchangeRateStoredInternal();
        if (vars.mathErr != MathError.NO_ERROR) {
            return (
                failOpaque(
                    Error.MATH_ERROR,
                    FailureInfo.MINT_EXCHANGE_RATE_READ_FAILED,
                    uint(vars.mathErr)
                ),
                0
            );
        }

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)

        /*
         *  We call `doTransferIn` for the minter and the mintAmount.
         *  Note: The kToken must handle variations between ERC-20 and ETH underlying.
         *  `doTransferIn` reverts if anything goes wrong, since we can't be sure if
         *  side-effects occurred. The function returns the amount actually transferred,
         *  in case of a fee. On success, the kToken holds an additional `actualMintAmount`
         *  of cash.
         */
        vars.actualMintAmount = doTransferIn(minter, mintAmount);

        /*
         * We get the current exchange rate and calculate the number of kTokens to be minted:
         *  mintTokens = actualMintAmount / exchangeRate
         */

        (vars.mathErr, vars.mintTokens) = divScalarByExpTruncate(
            vars.actualMintAmount,
            Exp({mantissa: vars.exchangeRateMantissa})
        );
        require(
            vars.mathErr == MathError.NO_ERROR,
            "MINT_EXCHANGE_CALCULATION_FAILED"
        );

        /*
         * We calculate the new total supply of kTokens and minter token balance, checking for overflow:
         *  totalSupplyNew = totalSupply + mintTokens
         *  accountTokensNew = accountTokens[minter] + mintTokens
         */
        (vars.mathErr, vars.totalSupplyNew) = addUInt(
            totalSupply,
            vars.mintTokens
        );
        require(
            vars.mathErr == MathError.NO_ERROR,
            "MINT_NEW_TOTAL_SUPPLY_CALCULATION_FAILED"
        );

        (vars.mathErr, vars.accountTokensNew) = addUInt(
            accountTokens[minter],
            vars.mintTokens
        );
        require(
            vars.mathErr == MathError.NO_ERROR,
            "MINT_NEW_ACCOUNT_BALANCE_CALCULATION_FAILED"
        );

        /* We write previously calculated values into storage */
        totalSupply = vars.totalSupplyNew;
        accountTokens[minter] = vars.accountTokensNew;

        /* We emit a Mint event, and a Transfer event */
        emit Mint(minter, vars.actualMintAmount, vars.mintTokens);
        emit Transfer(address(this), minter, vars.mintTokens);

        /* We call the defense hook */
        // unused function
        // comptroller.mintVerify(address(this), minter, vars.actualMintAmount, vars.mintTokens);

        return (uint(Error.NO_ERROR), vars.actualMintAmount);
    }

    /**
     * @notice Sender redeems kTokens in exchange for the underlying asset
     * @dev Accrues interest whether or not the operation succeeds, unless reverted
     * @param redeemTokens The number of kTokens to redeem into underlying
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function redeemInternal(
        uint redeemTokens
    ) internal nonReentrant returns (uint) {
        uint error = accrueInterest();
        if (error != uint(Error.NO_ERROR)) {
            // accrueInterest emits logs on errors, but we still want to log the fact that an attempted redeem failed
            return
                fail(Error(error), FailureInfo.REDEEM_ACCRUE_INTEREST_FAILED);
        }
        // redeemFresh emits redeem-specific logs on errors, so we don't need to
        return redeemFresh(payable(msg.sender), redeemTokens, 0);
    }

    /**
     * @notice Sender redeems kTokens in exchange for a specified amount of underlying asset
     * @dev Accrues interest whether or not the operation succeeds, unless reverted
     * @param redeemAmount The amount of underlying to receive from redeeming kTokens
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function redeemUnderlyingInternal(
        uint redeemAmount
    ) internal nonReentrant returns (uint) {
        uint error = accrueInterest();
        if (error != uint(Error.NO_ERROR)) {
            // accrueInterest emits logs on errors, but we still want to log the fact that an attempted redeem failed
            return
                fail(Error(error), FailureInfo.REDEEM_ACCRUE_INTEREST_FAILED);
        }
        // redeemFresh emits redeem-specific logs on errors, so we don't need to
        return redeemFresh(payable(msg.sender), 0, redeemAmount);
    }

    struct RedeemLocalVars {
        Error err;
        MathError mathErr;
        uint exchangeRateMantissa;
        uint redeemTokens;
        uint redeemAmount;
        uint totalSupplyNew;
        uint accountTokensNew;
    }

    /**
     * @notice User redeems kTokens in exchange for the underlying asset
     * @dev Assumes interest has already been accrued up to the current block
     * @param redeemer The address of the account which is redeeming the tokens
     * @param redeemTokensIn The number of kTokens to redeem into underlying (only one of redeemTokensIn or redeemAmountIn may be non-zero)
     * @param redeemAmountIn The number of underlying tokens to receive from redeeming kTokens (only one of redeemTokensIn or redeemAmountIn may be non-zero)
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function redeemFresh(
        address payable redeemer,
        uint redeemTokensIn,
        uint redeemAmountIn
    ) internal returns (uint) {
        require(
            redeemTokensIn == 0 || redeemAmountIn == 0,
            "one of redeemTokensIn or redeemAmountIn must be zero"
        );

        RedeemLocalVars memory vars;

        /* exchangeRate = invoke Exchange Rate Stored() */
        (
            vars.mathErr,
            vars.exchangeRateMantissa
        ) = exchangeRateStoredInternal();
        if (vars.mathErr != MathError.NO_ERROR) {
            return
                failOpaque(
                    Error.MATH_ERROR,
                    FailureInfo.REDEEM_EXCHANGE_RATE_READ_FAILED,
                    uint(vars.mathErr)
                );
        }

        /* If redeemTokensIn > 0: */
        if (redeemTokensIn > 0) {
            /*
             * We calculate the exchange rate and the amount of underlying to be redeemed:
             *  redeemTokens = redeemTokensIn
             *  redeemAmount = redeemTokensIn x exchangeRateCurrent
             */
            if (redeemTokensIn == type(uint).max) {
                vars.redeemTokens = accountTokens[redeemer];
            } else {
                vars.redeemTokens = redeemTokensIn;
            }

            (vars.mathErr, vars.redeemAmount) = mulScalarTruncate(
                Exp({mantissa: vars.exchangeRateMantissa}),
                vars.redeemTokens
            );
            if (vars.mathErr != MathError.NO_ERROR) {
                return
                    failOpaque(
                        Error.MATH_ERROR,
                        FailureInfo.REDEEM_EXCHANGE_TOKENS_CALCULATION_FAILED,
                        uint(vars.mathErr)
                    );
            }
        } else {
            /*
             * We get the current exchange rate and calculate the amount to be redeemed:
             *  redeemTokens = redeemAmountIn / exchangeRate
             *  redeemAmount = redeemAmountIn
             */
            if (redeemAmountIn == type(uint).max) {
                vars.redeemTokens = accountTokens[redeemer];

                (vars.mathErr, vars.redeemAmount) = mulScalarTruncate(
                    Exp({mantissa: vars.exchangeRateMantissa}),
                    vars.redeemTokens
                );
                if (vars.mathErr != MathError.NO_ERROR) {
                    return
                        failOpaque(
                            Error.MATH_ERROR,
                            FailureInfo
                                .REDEEM_EXCHANGE_TOKENS_CALCULATION_FAILED,
                            uint(vars.mathErr)
                        );
                }
            } else {
                vars.redeemAmount = redeemAmountIn;

                (vars.mathErr, vars.redeemTokens) = divScalarByExpTruncate(
                    redeemAmountIn,
                    Exp({mantissa: vars.exchangeRateMantissa})
                );
                if (vars.mathErr != MathError.NO_ERROR) {
                    return
                        failOpaque(
                            Error.MATH_ERROR,
                            FailureInfo
                                .REDEEM_EXCHANGE_AMOUNT_CALCULATION_FAILED,
                            uint(vars.mathErr)
                        );
                }
            }
        }

        /* Fail if redeem not allowed */
        uint allowed = comptroller.redeemAllowed(
            address(this),
            redeemer,
            vars.redeemTokens
        );
        if (allowed != 0) {
            return
                failOpaque(
                    Error.COMPTROLLER_REJECTION,
                    FailureInfo.REDEEM_COMPTROLLER_REJECTION,
                    allowed
                );
        }

        /* Verify market's block timestamp equals current block timestamp */
        if (accrualBlockTimestamp != getBlockTimestamp()) {
            return
                fail(
                    Error.MARKET_NOT_FRESH,
                    FailureInfo.REDEEM_FRESHNESS_CHECK
                );
        }

        /*
         * We calculate the new total supply and redeemer balance, checking for underflow:
         *  totalSupplyNew = totalSupply - redeemTokens
         *  accountTokensNew = accountTokens[redeemer] - redeemTokens
         */
        (vars.mathErr, vars.totalSupplyNew) = subUInt(
            totalSupply,
            vars.redeemTokens
        );
        if (vars.mathErr != MathError.NO_ERROR) {
            return
                failOpaque(
                    Error.MATH_ERROR,
                    FailureInfo.REDEEM_NEW_TOTAL_SUPPLY_CALCULATION_FAILED,
                    uint(vars.mathErr)
                );
        }

        (vars.mathErr, vars.accountTokensNew) = subUInt(
            accountTokens[redeemer],
            vars.redeemTokens
        );
        if (vars.mathErr != MathError.NO_ERROR) {
            return
                failOpaque(
                    Error.MATH_ERROR,
                    FailureInfo.REDEEM_NEW_ACCOUNT_BALANCE_CALCULATION_FAILED,
                    uint(vars.mathErr)
                );
        }

        /* Fail gracefully if protocol has insufficient cash */
        if (getCashPrior() < vars.redeemAmount) {
            return
                fail(
                    Error.TOKEN_INSUFFICIENT_CASH,
                    FailureInfo.REDEEM_TRANSFER_OUT_NOT_POSSIBLE
                );
        }

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)

        /* We write previously calculated values into storage */
        totalSupply = vars.totalSupplyNew;
        accountTokens[redeemer] = vars.accountTokensNew;

        /* We emit a Transfer event, and a Redeem event */
        emit Transfer(redeemer, address(this), vars.redeemTokens);
        emit Redeem(redeemer, vars.redeemAmount, vars.redeemTokens);

        /* We call the defense hook */
        comptroller.redeemVerify(
            address(this),
            redeemer,
            vars.redeemAmount,
            vars.redeemTokens
        );

        /*
         * We invoke doTransferOut for the redeemer and the redeemAmount.
         *  Note: The kToken must handle variations between ERC-20 and ETH underlying.
         *  On success, the kToken has redeemAmount less of cash.
         *  doTransferOut reverts if anything goes wrong, since we can't be sure if side effects occurred.
         */
        doTransferOut(redeemer, vars.redeemAmount);

        return uint(Error.NO_ERROR);
    }

    /**
     * @notice Sender borrows assets from the protocol to their own address
     * @param borrowAmount The amount of the underlying asset to borrow
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function borrowInternal(
        uint borrowAmount
    ) internal nonReentrant returns (uint) {
        uint error = accrueInterest();
        if (error != uint(Error.NO_ERROR)) {
            // accrueInterest emits logs on errors, but we still want to log the fact that an attempted borrow failed
            return
                fail(Error(error), FailureInfo.BORROW_ACCRUE_INTEREST_FAILED);
        }
        // borrowFresh emits borrow-specific logs on errors, so we don't need to
        return borrowFresh(payable(msg.sender), borrowAmount);
    }

    struct BorrowLocalVars {
        MathError mathErr;
        uint accountBorrows;
        uint accountBorrowsNew;
        uint totalBorrowsNew;
    }

    /**
     * @notice Users borrow assets from the protocol to their own address
     * @param borrowAmount The amount of the underlying asset to borrow
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function borrowFresh(
        address payable borrower,
        uint borrowAmount
    ) internal returns (uint) {
        /* Fail if borrow not allowed */
        uint allowed = comptroller.borrowAllowed(
            address(this),
            borrower,
            borrowAmount
        );
        if (allowed != 0) {
            return
                failOpaque(
                    Error.COMPTROLLER_REJECTION,
                    FailureInfo.BORROW_COMPTROLLER_REJECTION,
                    allowed
                );
        }

        /* Verify market's block timestamp equals current block timestamp */
        if (accrualBlockTimestamp != getBlockTimestamp()) {
            return
                fail(
                    Error.MARKET_NOT_FRESH,
                    FailureInfo.BORROW_FRESHNESS_CHECK
                );
        }

        /* Fail gracefully if protocol has insufficient underlying cash */
        if (getCashPrior() < borrowAmount) {
            return
                fail(
                    Error.TOKEN_INSUFFICIENT_CASH,
                    FailureInfo.BORROW_CASH_NOT_AVAILABLE
                );
        }

        BorrowLocalVars memory vars;

        /*
         * We calculate the new borrower and total borrow balances, failing on overflow:
         *  accountBorrowsNew = accountBorrows + borrowAmount
         *  totalBorrowsNew = totalBorrows + borrowAmount
         */
        (vars.mathErr, vars.accountBorrows) = borrowBalanceStoredInternal(
            borrower
        );
        if (vars.mathErr != MathError.NO_ERROR) {
            return
                failOpaque(
                    Error.MATH_ERROR,
                    FailureInfo.BORROW_ACCUMULATED_BALANCE_CALCULATION_FAILED,
                    uint(vars.mathErr)
                );
        }

        (vars.mathErr, vars.accountBorrowsNew) = addUInt(
            vars.accountBorrows,
            borrowAmount
        );
        if (vars.mathErr != MathError.NO_ERROR) {
            return
                failOpaque(
                    Error.MATH_ERROR,
                    FailureInfo
                        .BORROW_NEW_ACCOUNT_BORROW_BALANCE_CALCULATION_FAILED,
                    uint(vars.mathErr)
                );
        }

        (vars.mathErr, vars.totalBorrowsNew) = addUInt(
            totalBorrows,
            borrowAmount
        );
        if (vars.mathErr != MathError.NO_ERROR) {
            return
                failOpaque(
                    Error.MATH_ERROR,
                    FailureInfo.BORROW_NEW_TOTAL_BALANCE_CALCULATION_FAILED,
                    uint(vars.mathErr)
                );
        }

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)

        /* We write the previously calculated values into storage */
        accountBorrows[borrower].principal = vars.accountBorrowsNew;
        accountBorrows[borrower].interestIndex = borrowIndex;
        totalBorrows = vars.totalBorrowsNew;

        /* We emit a Borrow event */
        emit Borrow(
            borrower,
            borrowAmount,
            vars.accountBorrowsNew,
            vars.totalBorrowsNew
        );

        /*
         * We invoke doTransferOut for the borrower and the borrowAmount.
         *  Note: The kToken must handle variations between ERC-20 and ETH underlying.
         *  On success, the kToken borrowAmount less of cash.
         *  doTransferOut reverts if anything goes wrong, since we can't be sure if side effects occurred.
         */
        doTransferOut(borrower, borrowAmount);

        /* We call the defense hook */
        // unused function
        // comptroller.borrowVerify(address(this), borrower, borrowAmount);

        return uint(Error.NO_ERROR);
    }

    struct RepayBorrowLocalVars {
        Error err;
        MathError mathErr;
        uint repayAmount;
        uint borrowerIndex;
        uint accountBorrows;
        uint accountBorrowsNew;
        uint totalBorrowsNew;
        uint actualRepayAmount;
    }

    /**
     * @notice Borrows are repaid by another user (possibly the borrower).
     * @param payer the account paying off the borrow
     * @param borrower the account with the debt being payed off
     * @param repayAmount the amount of underlying tokens being returned
     * @return (uint, uint) An error code (0=success, otherwise a failure, see ErrorReporter.sol), and the actual repayment amount.
     */
    function repayBorrowFresh(
        address payer,
        address borrower,
        uint repayAmount
    ) internal returns (uint, uint) {
        /* Fail if repayBorrow not allowed */
        uint allowed = comptroller.repayBorrowAllowed(
            address(this),
            payer,
            borrower,
            repayAmount
        );
        if (allowed != 0) {
            return (
                failOpaque(
                    Error.COMPTROLLER_REJECTION,
                    FailureInfo.REPAY_BORROW_COMPTROLLER_REJECTION,
                    allowed
                ),
                0
            );
        }

        /* Verify market's block timestamp equals current block timestamp */
        if (accrualBlockTimestamp != getBlockTimestamp()) {
            return (
                fail(
                    Error.MARKET_NOT_FRESH,
                    FailureInfo.REPAY_BORROW_FRESHNESS_CHECK
                ),
                0
            );
        }

        RepayBorrowLocalVars memory vars;

        /* We remember the original borrowerIndex for verification purposes */
        vars.borrowerIndex = accountBorrows[borrower].interestIndex;

        /* We fetch the amount the borrower owes, with accumulated interest */
        (vars.mathErr, vars.accountBorrows) = borrowBalanceStoredInternal(
            borrower
        );
        if (vars.mathErr != MathError.NO_ERROR) {
            return (
                failOpaque(
                    Error.MATH_ERROR,
                    FailureInfo
                        .REPAY_BORROW_ACCUMULATED_BALANCE_CALCULATION_FAILED,
                    uint(vars.mathErr)
                ),
                0
            );
        }

        /* If repayAmount == uint.max, repayAmount = accountBorrows */
        if (repayAmount == type(uint).max) {
            vars.repayAmount = vars.accountBorrows;
        } else {
            vars.repayAmount = repayAmount;
        }

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)

        /*
         * We call doTransferIn for the payer and the repayAmount
         *  Note: The kToken must handle variations between ERC-20 and ETH underlying.
         *  On success, the kToken holds an additional repayAmount of cash.
         *  doTransferIn reverts if anything goes wrong, since we can't be sure if side effects occurred.
         *   it returns the amount actually transferred, in case of a fee.
         */
        vars.actualRepayAmount = doTransferIn(payer, vars.repayAmount);

        /*
         * We calculate the new borrower and total borrow balances, failing on underflow:
         *  accountBorrowsNew = accountBorrows - actualRepayAmount
         *  totalBorrowsNew = totalBorrows - actualRepayAmount
         */
        (vars.mathErr, vars.accountBorrowsNew) = subUInt(
            vars.accountBorrows,
            vars.actualRepayAmount
        );
        require(
            vars.mathErr == MathError.NO_ERROR,
            "REPAY_BORROW_NEW_ACCOUNT_BORROW_BALANCE_CALCULATION_FAILED"
        );

        (vars.mathErr, vars.totalBorrowsNew) = subUInt(
            totalBorrows,
            vars.actualRepayAmount
        );
        require(
            vars.mathErr == MathError.NO_ERROR,
            "REPAY_BORROW_NEW_TOTAL_BALANCE_CALCULATION_FAILED"
        );

        /* We write the previously calculated values into storage */
        accountBorrows[borrower].principal = vars.accountBorrowsNew;
        accountBorrows[borrower].interestIndex = borrowIndex;
        totalBorrows = vars.totalBorrowsNew;

        /* We emit a RepayBorrow event */
        emit RepayBorrow(
            payer,
            borrower,
            vars.actualRepayAmount,
            vars.accountBorrowsNew,
            vars.totalBorrowsNew
        );

        /* We call the defense hook */
        // unused function
        // comptroller.repayBorrowVerify(address(this), payer, borrower, vars.actualRepayAmount, vars.borrowerIndex);

        return (uint(Error.NO_ERROR), vars.actualRepayAmount);
    }

    /**
     * @notice The liquidator liquidates the borrowers collateral.
     *  The collateral seized is transferred to the liquidator.
     * @param borrower The borrower of this kToken to be liquidated
     * @param liquidator The address repaying the borrow and seizing collateral
     * @param kTokenCollateral The market in which to seize collateral from the borrower
     * @param repayAmount The amount of the underlying borrowed asset to repay
     * @return (uint, uint) An error code (0=success, otherwise a failure, see ErrorReporter.sol), and the actual repayment amount.
     */
    function liquidateBorrowFresh(
        address liquidator,
        address borrower,
        uint repayAmount,
        KTokenInterface kTokenCollateral
    ) internal returns (uint, uint) {
        /* Fail if liquidate not allowed */
        uint allowed = comptroller.liquidateBorrowAllowed(
            address(this),
            address(kTokenCollateral),
            liquidator,
            borrower,
            repayAmount
        );
        if (allowed != 0) {
            return (
                failOpaque(
                    Error.COMPTROLLER_REJECTION,
                    FailureInfo.LIQUIDATE_COMPTROLLER_REJECTION,
                    allowed
                ),
                0
            );
        }

        /* Verify market's block timestamp equals current block timestamp */
        if (accrualBlockTimestamp != getBlockTimestamp()) {
            return (
                fail(
                    Error.MARKET_NOT_FRESH,
                    FailureInfo.LIQUIDATE_FRESHNESS_CHECK
                ),
                0
            );
        }

        /* Verify kTokenCollateral market's block timestamp equals current block timestamp */
        if (kTokenCollateral.accrualBlockTimestamp() != getBlockTimestamp()) {
            return (
                fail(
                    Error.MARKET_NOT_FRESH,
                    FailureInfo.LIQUIDATE_COLLATERAL_FRESHNESS_CHECK
                ),
                0
            );
        }

        /* Fail if borrower = liquidator */
        if (borrower == liquidator) {
            return (
                fail(
                    Error.INVALID_ACCOUNT_PAIR,
                    FailureInfo.LIQUIDATE_LIQUIDATOR_IS_BORROWER
                ),
                0
            );
        }

        /* Fail if repayAmount = 0 */
        if (repayAmount == 0) {
            return (
                fail(
                    Error.INVALID_CLOSE_AMOUNT_REQUESTED,
                    FailureInfo.LIQUIDATE_CLOSE_AMOUNT_IS_ZERO
                ),
                0
            );
        }

        /* Fail if repayAmount = uint.max */
        if (repayAmount == type(uint).max) {
            return (
                fail(
                    Error.INVALID_CLOSE_AMOUNT_REQUESTED,
                    FailureInfo.LIQUIDATE_CLOSE_AMOUNT_IS_UINT_MAX
                ),
                0
            );
        }

        /* Fail if repayBorrow fails */
        (uint repayBorrowError, uint actualRepayAmount) = repayBorrowFresh(
            liquidator,
            borrower,
            repayAmount
        );
        if (repayBorrowError != uint(Error.NO_ERROR)) {
            return (
                fail(
                    Error(repayBorrowError),
                    FailureInfo.LIQUIDATE_REPAY_BORROW_FRESH_FAILED
                ),
                0
            );
        }

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)

        /* We calculate the number of collateral tokens that will be seized */
        (uint amountSeizeError, uint seizeTokens) = comptroller
            .liquidateCalculateSeizeTokens(
                address(this),
                address(kTokenCollateral),
                actualRepayAmount
            );
        require(
            amountSeizeError == uint(Error.NO_ERROR),
            "LIQUIDATE_COMPTROLLER_CALCULATE_AMOUNT_SEIZE_FAILED"
        );

        /* Revert if borrower collateral token balance < seizeTokens */
        require(
            kTokenCollateral.balanceOf(borrower) >= seizeTokens,
            "LIQUIDATE_SEIZE_TOO_MUCH"
        );

        // If this is also the collateral, run seizeInternal to avoid re-entrancy, otherwise make an external call
        uint seizeError;
        if (address(kTokenCollateral) == address(this)) {
            seizeError = seizeInternal(
                address(this),
                liquidator,
                borrower,
                seizeTokens
            );
        } else {
            seizeError = kTokenCollateral.seize(
                liquidator,
                borrower,
                seizeTokens
            );
        }

        /* Revert if seize tokens fails (since we cannot be sure of side effects) */
        require(seizeError == uint(Error.NO_ERROR), "token seizure failed");

        /* We emit a LiquidateBorrow event */
        emit LiquidateBorrow(
            liquidator,
            borrower,
            actualRepayAmount,
            address(kTokenCollateral),
            seizeTokens
        );

        /* We call the defense hook */
        // unused function
        // comptroller.liquidateBorrowVerify(address(this), address(kTokenCollateral), liquidator, borrower, actualRepayAmount, seizeTokens);

        return (uint(Error.NO_ERROR), actualRepayAmount);
    }

    /**
     * @notice Transfers collateral tokens (this market) to the liquidator.
     * @dev Will fail unless called by another kToken during the process of liquidation.
     *  Its absolutely critical to use msg.sender as the borrowed kToken and not a parameter.
     * @param liquidator The account receiving seized collateral
     * @param borrower The account having collateral seized
     * @param seizeTokens The number of kTokens to seize
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function seize(
        address liquidator,
        address borrower,
        uint seizeTokens
    ) external override nonReentrant returns (uint) {
        return seizeInternal(msg.sender, liquidator, borrower, seizeTokens);
    }

    struct SeizeInternalLocalVars {
        MathError mathErr;
        uint borrowerTokensNew;
        uint liquidatorTokensNew;
        uint liquidatorSeizeTokens;
        uint protocolSeizeTokens;
        uint protocolSeizeAmount;
        uint exchangeRateMantissa;
        uint totalReservesNew;
        uint totalSupplyNew;
    }

    /**
     * @notice Transfers collateral tokens (this market) to the liquidator.
     * @dev Called only during an in-kind liquidation, or by liquidateBorrow during the liquidation of another KToken.
     *  Its absolutely critical to use msg.sender as the seizer kToken and not a parameter.
     * @param seizerToken The contract seizing the collateral (i.e. borrowed kToken)
     * @param liquidator The account receiving seized collateral
     * @param borrower The account having collateral seized
     * @param seizeTokens The number of kTokens to seize
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function seizeInternal(
        address seizerToken,
        address liquidator,
        address borrower,
        uint seizeTokens
    ) internal returns (uint) {
        /* Fail if seize not allowed */
        uint allowed = comptroller.seizeAllowed(
            address(this),
            seizerToken,
            liquidator,
            borrower,
            seizeTokens
        );
        if (allowed != 0) {
            return
                failOpaque(
                    Error.COMPTROLLER_REJECTION,
                    FailureInfo.LIQUIDATE_SEIZE_COMPTROLLER_REJECTION,
                    allowed
                );
        }

        /* Fail if borrower = liquidator */
        if (borrower == liquidator) {
            return
                fail(
                    Error.INVALID_ACCOUNT_PAIR,
                    FailureInfo.LIQUIDATE_SEIZE_LIQUIDATOR_IS_BORROWER
                );
        }

        SeizeInternalLocalVars memory vars;

        /*
         * We calculate the new borrower and liquidator token balances, failing on underflow/overflow:
         *  borrowerTokensNew = accountTokens[borrower] - seizeTokens
         *  liquidatorTokensNew = accountTokens[liquidator] + seizeTokens
         */
        (vars.mathErr, vars.borrowerTokensNew) = subUInt(
            accountTokens[borrower],
            seizeTokens
        );
        if (vars.mathErr != MathError.NO_ERROR) {
            return
                failOpaque(
                    Error.MATH_ERROR,
                    FailureInfo.LIQUIDATE_SEIZE_BALANCE_DECREMENT_FAILED,
                    uint(vars.mathErr)
                );
        }

        vars.protocolSeizeTokens = mul_(
            seizeTokens,
            Exp({mantissa: protocolSeizeShareMantissa})
        );
        vars.liquidatorSeizeTokens = sub_(
            seizeTokens,
            vars.protocolSeizeTokens
        );

        (
            vars.mathErr,
            vars.exchangeRateMantissa
        ) = exchangeRateStoredInternal();
        require(vars.mathErr == MathError.NO_ERROR, "exchange rate math error");

        vars.protocolSeizeAmount = mul_ScalarTruncate(
            Exp({mantissa: vars.exchangeRateMantissa}),
            vars.protocolSeizeTokens
        );

        vars.totalReservesNew = add_(totalReserves, vars.protocolSeizeAmount);
        vars.totalSupplyNew = sub_(totalSupply, vars.protocolSeizeTokens);

        (vars.mathErr, vars.liquidatorTokensNew) = addUInt(
            accountTokens[liquidator],
            vars.liquidatorSeizeTokens
        );
        if (vars.mathErr != MathError.NO_ERROR) {
            return
                failOpaque(
                    Error.MATH_ERROR,
                    FailureInfo.LIQUIDATE_SEIZE_BALANCE_INCREMENT_FAILED,
                    uint(vars.mathErr)
                );
        }

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)

        /* We write the previously calculated values into storage */
        totalReserves = vars.totalReservesNew;
        totalSupply = vars.totalSupplyNew;
        accountTokens[borrower] = vars.borrowerTokensNew;
        accountTokens[liquidator] = vars.liquidatorTokensNew;

        /* Emit a Transfer event */
        emit Transfer(borrower, liquidator, vars.liquidatorSeizeTokens);
        emit Transfer(borrower, address(this), vars.protocolSeizeTokens);
        emit ReservesAdded(
            address(this),
            vars.protocolSeizeAmount,
            vars.totalReservesNew
        );

        /* We call the defense hook */
        // unused function
        // comptroller.seizeVerify(address(this), seizerToken, liquidator, borrower, seizeTokens);

        return uint(Error.NO_ERROR);
    }

    /*** Admin Functions ***/

    /**
     * @notice Begins transfer of admin rights. The newPendingAdmin must call `_acceptAdmin` to finalize the transfer.
     * @dev Admin function to begin change of admin. The newPendingAdmin must call `_acceptAdmin` to finalize the transfer.
     * @param newPendingAdmin New pending admin.
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function _setPendingAdmin(
        address payable newPendingAdmin
    ) external override returns (uint) {
        // Check caller = admin
        if (msg.sender != admin) {
            return
                fail(
                    Error.UNAUTHORIZED,
                    FailureInfo.SET_PENDING_ADMIN_OWNER_CHECK
                );
        }

        // Save current value, if any, for inclusion in log
        address oldPendingAdmin = pendingAdmin;

        // Store pendingAdmin with value newPendingAdmin
        pendingAdmin = newPendingAdmin;

        // Emit NewPendingAdmin(oldPendingAdmin, newPendingAdmin)
        emit NewPendingAdmin(oldPendingAdmin, newPendingAdmin);

        return uint(Error.NO_ERROR);
    }

    /**
     * @notice Accepts transfer of admin rights. msg.sender must be pendingAdmin
     * @dev Admin function for pending admin to accept role and update admin
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function _acceptAdmin() external override returns (uint) {
        // Check caller is pendingAdmin and pendingAdmin ≠ address(0)
        if (msg.sender != pendingAdmin || msg.sender == address(0)) {
            return
                fail(
                    Error.UNAUTHORIZED,
                    FailureInfo.ACCEPT_ADMIN_PENDING_ADMIN_CHECK
                );
        }

        // Save current values for inclusion in log
        address oldAdmin = admin;
        address oldPendingAdmin = pendingAdmin;

        // Store admin with value pendingAdmin
        admin = pendingAdmin;

        // Clear the pending value
        pendingAdmin = payable(address(0));

        emit NewAdmin(oldAdmin, admin);
        emit NewPendingAdmin(oldPendingAdmin, pendingAdmin);

        return uint(Error.NO_ERROR);
    }

    /**
     * @notice Sets a new comptroller for the market
     * @dev Admin function to set a new comptroller
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function _setComptroller(
        ComptrollerInterface newComptroller
    ) public override returns (uint) {
        // Check caller is admin
        if (msg.sender != admin) {
            return
                fail(
                    Error.UNAUTHORIZED,
                    FailureInfo.SET_COMPTROLLER_OWNER_CHECK
                );
        }

        ComptrollerInterface oldComptroller = comptroller;
        // Ensure invoke comptroller.isComptroller() returns true
        require(newComptroller.isComptroller(), "marker method returned false");

        // Set market's comptroller to newComptroller
        comptroller = newComptroller;

        // Emit NewComptroller(oldComptroller, newComptroller)
        emit NewComptroller(oldComptroller, newComptroller);

        return uint(Error.NO_ERROR);
    }

    /**
     * @notice accrues interest and sets a new reserve factor for the protocol using _setReserveFactorFresh
     * @dev Admin function to accrue interest and set a new reserve factor
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function _setReserveFactor(
        uint newReserveFactorMantissa
    ) external override nonReentrant returns (uint) {
        uint error = accrueInterest();
        if (error != uint(Error.NO_ERROR)) {
            // accrueInterest emits logs on errors, but on top of that we want to log the fact that an attempted reserve factor change failed.
            return
                fail(
                    Error(error),
                    FailureInfo.SET_RESERVE_FACTOR_ACCRUE_INTEREST_FAILED
                );
        }
        // _setReserveFactorFresh emits reserve-factor-specific logs on errors, so we don't need to.
        return _setReserveFactorFresh(newReserveFactorMantissa);
    }

    /**
     * @notice Sets a new reserve factor for the protocol (*requires fresh interest accrual)
     * @dev Admin function to set a new reserve factor
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function _setReserveFactorFresh(
        uint newReserveFactorMantissa
    ) internal returns (uint) {
        // Check caller is admin
        if (msg.sender != admin) {
            return
                fail(
                    Error.UNAUTHORIZED,
                    FailureInfo.SET_RESERVE_FACTOR_ADMIN_CHECK
                );
        }

        // Verify market's block timestamp equals current block timestamp
        if (accrualBlockTimestamp != getBlockTimestamp()) {
            return
                fail(
                    Error.MARKET_NOT_FRESH,
                    FailureInfo.SET_RESERVE_FACTOR_FRESH_CHECK
                );
        }

        // Check newReserveFactor ≤ maxReserveFactor
        if (newReserveFactorMantissa > reserveFactorMaxMantissa) {
            return
                fail(
                    Error.BAD_INPUT,
                    FailureInfo.SET_RESERVE_FACTOR_BOUNDS_CHECK
                );
        }

        uint oldReserveFactorMantissa = reserveFactorMantissa;
        reserveFactorMantissa = newReserveFactorMantissa;

        emit NewReserveFactor(
            oldReserveFactorMantissa,
            newReserveFactorMantissa
        );

        return uint(Error.NO_ERROR);
    }

    /**
     * @notice Accrues interest and reduces reserves by transferring from msg.sender
     * @param addAmount Amount of addition to reserves
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function _addReservesInternal(
        uint addAmount
    ) internal nonReentrant returns (uint) {
        uint error = accrueInterest();
        if (error != uint(Error.NO_ERROR)) {
            // accrueInterest emits logs on errors, but on top of that we want to log the fact that an attempted reduce reserves failed.
            return
                fail(
                    Error(error),
                    FailureInfo.ADD_RESERVES_ACCRUE_INTEREST_FAILED
                );
        }

        // _addReservesFresh emits reserve-addition-specific logs on errors, so we don't need to.
        (error, ) = _addReservesFresh(addAmount);
        return error;
    }

    /**
     * @notice Add reserves by transferring from caller
     * @dev Requires fresh interest accrual
     * @param addAmount Amount of addition to reserves
     * @return (uint, uint) An error code (0=success, otherwise a failure (see ErrorReporter.sol for details)) and the actual amount added, net token fees
     */
    function _addReservesFresh(uint addAmount) internal returns (uint, uint) {
        // totalReserves + actualAddAmount
        uint totalReservesNew;
        uint actualAddAmount;

        // We fail gracefully unless market's block timestamp equals current block timestamp
        if (accrualBlockTimestamp != getBlockTimestamp()) {
            return (
                fail(
                    Error.MARKET_NOT_FRESH,
                    FailureInfo.ADD_RESERVES_FRESH_CHECK
                ),
                actualAddAmount
            );
        }

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)

        /*
         * We call doTransferIn for the caller and the addAmount
         *  Note: The kToken must handle variations between ERC-20 and ETH underlying.
         *  On success, the kToken holds an additional addAmount of cash.
         *  doTransferIn reverts if anything goes wrong, since we can't be sure if side effects occurred.
         *  it returns the amount actually transferred, in case of a fee.
         */

        actualAddAmount = doTransferIn(msg.sender, addAmount);

        totalReservesNew = totalReserves + actualAddAmount;

        /* Revert on overflow */
        require(
            totalReservesNew >= totalReserves,
            "add reserves unexpected overflow"
        );

        // Store reserves[n+1] = reserves[n] + actualAddAmount
        totalReserves = totalReservesNew;

        /* Emit NewReserves(admin, actualAddAmount, reserves[n+1]) */
        emit ReservesAdded(msg.sender, actualAddAmount, totalReservesNew);

        /* Return (NO_ERROR, actualAddAmount) */
        return (uint(Error.NO_ERROR), actualAddAmount);
    }

    /**
     * @notice Accrues interest and reduces reserves by transferring to admin
     * @param reduceAmount Amount of reduction to reserves
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function _reduceReserves(
        uint reduceAmount
    ) external override nonReentrant returns (uint) {
        uint error = accrueInterest();
        if (error != uint(Error.NO_ERROR)) {
            // accrueInterest emits logs on errors, but on top of that we want to log the fact that an attempted reduce reserves failed.
            return
                fail(
                    Error(error),
                    FailureInfo.REDUCE_RESERVES_ACCRUE_INTEREST_FAILED
                );
        }
        // _reduceReservesFresh emits reserve-reduction-specific logs on errors, so we don't need to.
        return _reduceReservesFresh(reduceAmount);
    }

    /**
     * @notice Reduces reserves by transferring to admin
     * @dev Requires fresh interest accrual
     * @param reduceAmount Amount of reduction to reserves
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function _reduceReservesFresh(uint reduceAmount) internal returns (uint) {
        // totalReserves - reduceAmount
        uint totalReservesNew;

        // Check caller is admin
        if (msg.sender != admin) {
            return
                fail(
                    Error.UNAUTHORIZED,
                    FailureInfo.REDUCE_RESERVES_ADMIN_CHECK
                );
        }

        // We fail gracefully unless market's block timestamp equals current block timestamp
        if (accrualBlockTimestamp != getBlockTimestamp()) {
            return
                fail(
                    Error.MARKET_NOT_FRESH,
                    FailureInfo.REDUCE_RESERVES_FRESH_CHECK
                );
        }

        // Fail gracefully if protocol has insufficient underlying cash
        if (getCashPrior() < reduceAmount) {
            return
                fail(
                    Error.TOKEN_INSUFFICIENT_CASH,
                    FailureInfo.REDUCE_RESERVES_CASH_NOT_AVAILABLE
                );
        }

        // Check reduceAmount ≤ reserves[n] (totalReserves)
        if (reduceAmount > totalReserves) {
            return
                fail(Error.BAD_INPUT, FailureInfo.REDUCE_RESERVES_VALIDATION);
        }

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)

        totalReservesNew = totalReserves - reduceAmount;
        // We checked reduceAmount <= totalReserves above, so this should never revert.
        require(
            totalReservesNew <= totalReserves,
            "reduce reserves unexpected underflow"
        );

        // Store reserves[n+1] = reserves[n] - reduceAmount
        totalReserves = totalReservesNew;

        // doTransferOut reverts if anything goes wrong, since we can't be sure if side effects occurred.
        doTransferOut(admin, reduceAmount);

        emit ReservesReduced(admin, reduceAmount, totalReservesNew);

        return uint(Error.NO_ERROR);
    }

    /**
     * @notice accrues interest and updates the interest rate model using _setInterestRateModelFresh
     * @dev Admin function to accrue interest and update the interest rate model
     * @param newInterestRateModel the new interest rate model to use
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function _setInterestRateModel(
        InterestRateModel newInterestRateModel
    ) public override returns (uint) {
        uint error = accrueInterest();
        if (error != uint(Error.NO_ERROR)) {
            // accrueInterest emits logs on errors, but on top of that we want to log the fact that an attempted change of interest rate model failed
            return
                fail(
                    Error(error),
                    FailureInfo.SET_INTEREST_RATE_MODEL_ACCRUE_INTEREST_FAILED
                );
        }
        // _setInterestRateModelFresh emits interest-rate-model-update-specific logs on errors, so we don't need to.
        return _setInterestRateModelFresh(newInterestRateModel);
    }

    /**
     * @notice updates the interest rate model (*requires fresh interest accrual)
     * @dev Admin function to update the interest rate model
     * @param newInterestRateModel the new interest rate model to use
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function _setInterestRateModelFresh(
        InterestRateModel newInterestRateModel
    ) internal returns (uint) {
        // Used to store old model for use in the event that is emitted on success
        InterestRateModel oldInterestRateModel;

        // Check caller is admin
        if (msg.sender != admin) {
            return
                fail(
                    Error.UNAUTHORIZED,
                    FailureInfo.SET_INTEREST_RATE_MODEL_OWNER_CHECK
                );
        }

        // We fail gracefully unless market's block timestamp equals current block timestamp
        if (accrualBlockTimestamp != getBlockTimestamp()) {
            return
                fail(
                    Error.MARKET_NOT_FRESH,
                    FailureInfo.SET_INTEREST_RATE_MODEL_FRESH_CHECK
                );
        }

        // Track the market's current interest rate model
        oldInterestRateModel = interestRateModel;

        // Ensure invoke newInterestRateModel.isInterestRateModel() returns true
        require(
            newInterestRateModel.isInterestRateModel(),
            "marker method returned false"
        );

        // Set the interest rate model to newInterestRateModel
        interestRateModel = newInterestRateModel;

        // Emit NewMarketInterestRateModel(oldInterestRateModel, newInterestRateModel)
        emit NewMarketInterestRateModel(
            oldInterestRateModel,
            newInterestRateModel
        );

        return uint(Error.NO_ERROR);
    }

    /**
     * @notice accrues interest and updates the protocol seize share using _setProtocolSeizeShareFresh
     * @dev Admin function to accrue interest and update the protocol seize share
     * @param newProtocolSeizeShareMantissa the new protocol seize share to use
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function _setProtocolSeizeShare(
        uint newProtocolSeizeShareMantissa
    ) external override nonReentrant returns (uint) {
        uint error = accrueInterest();
        if (error != uint(Error.NO_ERROR)) {
            // accrueInterest emits logs on errors, but on top of that we want to log the fact that an attempted change of protocol seize share failed
            return
                fail(
                    Error(error),
                    FailureInfo.SET_PROTOCOL_SEIZE_SHARE_ACCRUE_INTEREST_FAILED
                );
        }
        // _setProtocolSeizeShareFresh emits protocol-seize-share-update-specific logs on errors, so we don't need to.
        return _setProtocolSeizeShareFresh(newProtocolSeizeShareMantissa);
    }

    /**
     * @notice updates the protocol seize share (*requires fresh interest accrual)
     * @dev Admin function to update the protocol seize share
     * @param newProtocolSeizeShareMantissa the new protocol seize share to use
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function _setProtocolSeizeShareFresh(
        uint newProtocolSeizeShareMantissa
    ) internal returns (uint) {
        // Used to store old share for use in the event that is emitted on success
        uint oldProtocolSeizeShareMantissa;

        // Check caller is admin
        if (msg.sender != admin) {
            return
                fail(
                    Error.UNAUTHORIZED,
                    FailureInfo.SET_PROTOCOL_SEIZE_SHARE_OWNER_CHECK
                );
        }

        // We fail gracefully unless market's block timestamp equals current block timestamp
        if (accrualBlockTimestamp != getBlockTimestamp()) {
            return
                fail(
                    Error.MARKET_NOT_FRESH,
                    FailureInfo.SET_PROTOCOL_SEIZE_SHARE_FRESH_CHECK
                );
        }

        // Track the market's current protocol seize share
        oldProtocolSeizeShareMantissa = protocolSeizeShareMantissa;

        // Set the protocol seize share to newProtocolSeizeShareMantissa
        protocolSeizeShareMantissa = newProtocolSeizeShareMantissa;

        // Emit NewProtocolSeizeShareMantissa(oldProtocolSeizeShareMantissa, newProtocolSeizeShareMantissa)
        emit NewProtocolSeizeShare(
            oldProtocolSeizeShareMantissa,
            newProtocolSeizeShareMantissa
        );

        return uint(Error.NO_ERROR);
    }

    /*** Safe Token ***/

    /**
     * @notice Gets balance of this contract in terms of the underlying
     * @dev This excludes the value of the current message, if any
     * @return The quantity of underlying owned by this contract
     */
    function getCashPrior() internal view virtual returns (uint);

    /**
     * @dev Performs a transfer in, reverting upon failure. Returns the amount actually transferred to the protocol, in case of a fee.
     *  This may revert due to insufficient balance or insufficient allowance.
     */
    function doTransferIn(
        address from,
        uint amount
    ) internal virtual returns (uint);

    /**
     * @dev Performs a transfer out, ideally returning an explanatory error code upon failure tather than reverting.
     *  If caller has not called checked protocol's balance, may revert due to insufficient cash held in the contract.
     *  If caller has checked protocol's balance, and verified it is >= amount, this should not revert in normal conditions.
     */
    function doTransferOut(address payable to, uint amount) internal virtual;

    /*** Reentrancy Guard ***/

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     */
    modifier nonReentrant() {
        require(_notEntered, "re-entered");
        _notEntered = false;
        _;
        _notEntered = true; // get a gas-refund post-Istanbul
    }
}

// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.20;

import "./KToken.sol";
import "./TokenErrorReporter.sol";
import "./oracles/PriceOracle.sol";
import "./ComptrollerInterface.sol";
import "./ComptrollerStorage.sol";
import "./Unitroller.sol";

/**
 * @title Kawa's Comptroller Contract
 * @author Kawa
 */
contract Comptroller is
    ComptrollerV2Storage,
    ComptrollerInterface,
    ComptrollerErrorReporter,
    ExponentialNoError
{
    /// @notice Emitted when an admin supports a market
    event MarketListed(KToken kToken);

    /// @notice Emitted when an account enters a market
    event MarketEntered(KToken kToken, address account);

    /// @notice Emitted when an account exits a market
    event MarketExited(KToken kToken, address account);

    /// @notice Emitted when close factor is changed by admin
    event NewCloseFactor(
        uint oldCloseFactorMantissa,
        uint newCloseFactorMantissa
    );

    /// @notice Emitted when a collateral factor is changed by admin
    event NewCollateralFactor(
        KToken kToken,
        uint oldCollateralFactorMantissa,
        uint newCollateralFactorMantissa
    );

    /// @notice Emitted when liquidation incentive is changed by admin
    event NewLiquidationIncentive(
        uint oldLiquidationIncentiveMantissa,
        uint newLiquidationIncentiveMantissa
    );

    /// @notice Emitted when price oracle is changed
    event NewPriceOracle(
        PriceOracle oldPriceOracle,
        PriceOracle newPriceOracle
    );

    /// @notice Emitted when pause guardian is changed
    event NewPauseGuardian(address oldPauseGuardian, address newPauseGuardian);

    /// @notice Emitted when an action is paused globally
    event ActionPaused(string action, bool pauseState);

    /// @notice Emitted when an action is paused on a market
    event ActionPaused(KToken kToken, string action, bool pauseState);

    /// @notice Emitted when borrow cap for a kToken is changed
    event NewBorrowCap(KToken indexed kToken, uint newBorrowCap);

    /// @notice Emitted when borrow cap guardian is changed
    event NewBorrowCapGuardian(
        address oldBorrowCapGuardian,
        address newBorrowCapGuardian
    );

    /// @notice Emitted when supply cap for a kToken is changed
    event NewSupplyCap(KToken indexed kToken, uint newSupplyCap);

    /// @notice Emitted when supply cap guardian is changed
    event NewSupplyCapGuardian(
        address oldSupplyCapGuardian,
        address newSupplyCapGuardian
    );

    /// @notice Emitted when reward distributor is changed
    event NewRewardDistributor(
        MultiRewardDistributor oldRewardDistributor,
        MultiRewardDistributor newRewardDistributor
    );

    // closeFactorMantissa must be strictly greater than this value
    uint internal constant closeFactorMinMantissa = 0.05e18; // 0.05

    // closeFactorMantissa must not exceed this value
    uint internal constant closeFactorMaxMantissa = 0.9e18; // 0.9

    // No collateralFactorMantissa may exceed this value
    uint internal constant collateralFactorMaxMantissa = 0.9e18; // 0.9

    constructor() {
        admin = msg.sender;
    }

    /*** Assets You Are In ***/

    /**
     * @notice Returns the assets an account has entered
     * @param account The address of the account to pull assets for
     * @return A dynamic list with the assets the account has entered
     */
    function getAssetsIn(
        address account
    ) external view returns (KToken[] memory) {
        KToken[] memory assetsIn = accountAssets[account];

        return assetsIn;
    }

    /**
     * @notice Returns whether the given account is entered in the given asset
     * @param account The address of the account to check
     * @param kToken The kToken to check
     * @return True if the account is in the asset, otherwise false.
     */
    function checkMembership(
        address account,
        KToken kToken
    ) external view returns (bool) {
        return markets[address(kToken)].accountMembership[account];
    }

    /**
     * @notice Add assets to be included in account liquidity calculation
     * @param kTokens The list of addresses of the kToken markets to be enabled
     * @return Success indicator for whether each corresponding market was entered
     */
    function enterMarkets(
        address[] memory kTokens
    ) public override returns (uint[] memory) {
        uint len = kTokens.length;

        uint[] memory results = new uint[](len);
        for (uint i = 0; i < len; i++) {
            KToken kToken = KToken(kTokens[i]);

            results[i] = uint(addToMarketInternal(kToken, msg.sender));
        }

        return results;
    }

    /**
     * @notice Add the market to the borrower's "assets in" for liquidity calculations
     * @param kToken The market to enter
     * @param borrower The address of the account to modify
     * @return Success indicator for whether the market was entered
     */
    function addToMarketInternal(
        KToken kToken,
        address borrower
    ) internal returns (Error) {
        Market storage marketToJoin = markets[address(kToken)];

        if (!marketToJoin.isListed) {
            // market is not listed, cannot join
            return Error.MARKET_NOT_LISTED;
        }

        if (marketToJoin.accountMembership[borrower] == true) {
            // already joined
            return Error.NO_ERROR;
        }

        // survived the gauntlet, add to list
        // NOTE: we store these somewhat redundantly as a significant optimization
        //  this avoids having to iterate through the list for the most common use cases
        //  that is, only when we need to perform liquidity checks
        //  and not whenever we want to check if an account is in a particular market
        marketToJoin.accountMembership[borrower] = true;
        accountAssets[borrower].push(kToken);

        emit MarketEntered(kToken, borrower);

        return Error.NO_ERROR;
    }

    /**
     * @notice Removes asset from sender's account liquidity calculation
     * @dev Sender must not have an outstanding borrow balance in the asset,
     *  or be providing necessary collateral for an outstanding borrow.
     * @param kTokenAddress The address of the asset to be removed
     * @return Whether or not the account successfully exited the market
     */
    function exitMarket(
        address kTokenAddress
    ) external override returns (uint) {
        KToken kToken = KToken(kTokenAddress);
        /* Get sender tokensHeld and amountOwed underlying from the kToken */
        (uint oErr, uint tokensHeld, uint amountOwed, ) = kToken
            .getAccountSnapshot(msg.sender);
        require(oErr == 0, "exitMarket: getAccountSnapshot failed"); // semi-opaque error code

        /* Fail if the sender has a borrow balance */
        if (amountOwed != 0) {
            return
                fail(
                    Error.NONZERO_BORROW_BALANCE,
                    FailureInfo.EXIT_MARKET_BALANCE_OWED
                );
        }

        /* Fail if the sender is not permitted to redeem all of their tokens */
        uint allowed = redeemAllowedInternal(
            kTokenAddress,
            msg.sender,
            tokensHeld
        );
        if (allowed != 0) {
            return
                failOpaque(
                    Error.REJECTION,
                    FailureInfo.EXIT_MARKET_REJECTION,
                    allowed
                );
        }

        Market storage marketToExit = markets[address(kToken)];

        /* Return true if the sender is not already ‘in’ the market */
        if (!marketToExit.accountMembership[msg.sender]) {
            return uint(Error.NO_ERROR);
        }

        /* Set kToken account membership to false */
        delete marketToExit.accountMembership[msg.sender];

        /* Delete kToken from the account’s list of assets */
        // load into memory for faster iteration
        KToken[] memory userAssetList = accountAssets[msg.sender];
        uint len = userAssetList.length;
        uint assetIndex = len;
        for (uint i = 0; i < len; i++) {
            if (userAssetList[i] == kToken) {
                assetIndex = i;
                break;
            }
        }

        // We *must* have found the asset in the list or our redundant data structure is broken
        assert(assetIndex < len);

        // copy last item in list to location of item to be removed, reduce length by 1
        KToken[] storage storedList = accountAssets[msg.sender];
        storedList[assetIndex] = storedList[storedList.length - 1];
        storedList.pop();

        emit MarketExited(kToken, msg.sender);

        return uint(Error.NO_ERROR);
    }

    /*** Policy Hooks ***/

    /**
     * @notice Checks if the account should be allowed to mint tokens in the given market
     * @param kToken The market to verify the mint against
     * @param minter The account which would get the minted tokens
     * @param mintAmount The amount of underlying being supplied to the market in exchange for tokens
     * @return 0 if the mint is allowed, otherwise a semi-opaque error code (See ErrorReporter.sol)
     */
    function mintAllowed(
        address kToken,
        address minter,
        uint mintAmount
    ) external override returns (uint) {
        // Pausing is a very serious situation - we revert to sound the alarms
        require(!mintGuardianPaused[kToken], "mint is paused");

        // Shh - currently unused
        mintAmount;

        if (!markets[kToken].isListed) {
            return uint(Error.MARKET_NOT_LISTED);
        }

        uint supplyCap = supplyCaps[kToken];
        // Supply cap of 0 corresponds to unlimited supplying
        if (supplyCap != 0) {
            uint totalCash = KToken(kToken).getCash();
            uint totalBorrows = KToken(kToken).totalBorrows();
            uint totalReserves = KToken(kToken).totalReserves();
            // totalSupplies = totalCash + totalBorrows - totalReserves
            uint totalSupplies = sub_(
                add_(totalCash, totalBorrows),
                totalReserves
            );

            uint nextTotalSupplies = add_(totalSupplies, mintAmount);
            require(nextTotalSupplies < supplyCap, "market supply cap reached");
        }

        // Keep the flywheel moving
        updateAndDistributeSupplierRewardsForToken(kToken, minter);
        return uint(Error.NO_ERROR);
    }

    /**
     * @notice Checks if the account should be allowed to redeem tokens in the given market
     * @param kToken The market to verify the redeem against
     * @param redeemer The account which would redeem the tokens
     * @param redeemTokens The number of kTokens to exchange for the underlying asset in the market
     * @return 0 if the redeem is allowed, otherwise a semi-opaque error code (See ErrorReporter.sol)
     */
    function redeemAllowed(
        address kToken,
        address redeemer,
        uint redeemTokens
    ) external override returns (uint) {
        uint allowed = redeemAllowedInternal(kToken, redeemer, redeemTokens);
        if (allowed != uint(Error.NO_ERROR)) {
            return allowed;
        }

        // Keep the flywheel moving
        updateAndDistributeSupplierRewardsForToken(kToken, redeemer);

        return uint(Error.NO_ERROR);
    }

    function redeemAllowedInternal(
        address kToken,
        address redeemer,
        uint redeemTokens
    ) internal view returns (uint) {
        if (!markets[kToken].isListed) {
            return uint(Error.MARKET_NOT_LISTED);
        }

        /* If the redeemer is not 'in' the market, then we can bypass the liquidity check */
        if (!markets[kToken].accountMembership[redeemer]) {
            return uint(Error.NO_ERROR);
        }

        /* Otherwise, perform a hypothetical liquidity check to guard against shortfall */
        (Error err, , uint shortfall) = getHypotheticalAccountLiquidityInternal(
            redeemer,
            KToken(kToken),
            redeemTokens,
            0
        );
        if (err != Error.NO_ERROR) {
            return uint(err);
        }
        if (shortfall > 0) {
            return uint(Error.INSUFFICIENT_LIQUIDITY);
        }

        return uint(Error.NO_ERROR);
    }

    /**
     * @notice Validates redeem and reverts on rejection. May emit logs.
     * @param kToken Asset being redeemed
     * @param redeemer The address redeeming the tokens
     * @param redeemAmount The amount of the underlying asset being redeemed
     * @param redeemTokens The number of tokens being redeemed
     */
    function redeemVerify(
        address kToken,
        address redeemer,
        uint redeemAmount,
        uint redeemTokens
    ) external pure override {
        // Shh - currently unused
        kToken;
        redeemer;

        // Require tokens is zero or amount is also zero
        if (redeemTokens == 0 && redeemAmount > 0) {
            revert("redeemTokens zero");
        }
    }

    /**
     * @notice Checks if the account should be allowed to borrow the underlying asset of the given market
     * @param kToken The market to verify the borrow against
     * @param borrower The account which would borrow the asset
     * @param borrowAmount The amount of underlying the account would borrow
     * @return 0 if the borrow is allowed, otherwise a semi-opaque error code (See ErrorReporter.sol)
     */
    function borrowAllowed(
        address kToken,
        address borrower,
        uint borrowAmount
    ) external override returns (uint) {
        // Pausing is a very serious situation - we revert to sound the alarms
        require(!borrowGuardianPaused[kToken], "borrow is paused");

        if (!markets[kToken].isListed) {
            return uint(Error.MARKET_NOT_LISTED);
        }

        if (!markets[kToken].accountMembership[borrower]) {
            // only kTokens may call borrowAllowed if borrower not in market
            require(msg.sender == kToken, "sender must be kToken");

            // attempt to add borrower to the market
            Error addToMarketErr = addToMarketInternal(
                KToken(msg.sender),
                borrower
            );
            if (addToMarketErr != Error.NO_ERROR) {
                return uint(addToMarketErr);
            }

            // it should be impossible to break the important invariant
            assert(markets[kToken].accountMembership[borrower]);
        }

        if (oracle.getUnderlyingPrice(KToken(kToken)) == 0) {
            return uint(Error.PRICE_ERROR);
        }

        uint borrowCap = borrowCaps[kToken];
        // Borrow cap of 0 corresponds to unlimited borrowing
        if (borrowCap != 0) {
            uint totalBorrows = KToken(kToken).totalBorrows();
            uint nextTotalBorrows = add_(totalBorrows, borrowAmount);
            require(nextTotalBorrows < borrowCap, "market borrow cap reached");
        }

        (Error err, , uint shortfall) = getHypotheticalAccountLiquidityInternal(
            borrower,
            KToken(kToken),
            0,
            borrowAmount
        );
        if (err != Error.NO_ERROR) {
            return uint(err);
        }
        if (shortfall > 0) {
            return uint(Error.INSUFFICIENT_LIQUIDITY);
        }

        // Keep the flywheel moving
        updateAndDistributeBorrowerRewardsForToken(kToken, borrower);

        return uint(Error.NO_ERROR);
    }

    /**
     * @notice Checks if the account should be allowed to repay a borrow in the given market
     * @param kToken The market to verify the repay against
     * @param payer The account which would repay the asset
     * @param borrower The account which would borrowed the asset
     * @param repayAmount The amount of the underlying asset the account would repay
     * @return 0 if the repay is allowed, otherwise a semi-opaque error code (See ErrorReporter.sol)
     */
    function repayBorrowAllowed(
        address kToken,
        address payer,
        address borrower,
        uint repayAmount
    ) external override returns (uint) {
        // Shh - currently unused
        payer;
        borrower;
        repayAmount;

        if (!markets[kToken].isListed) {
            return uint(Error.MARKET_NOT_LISTED);
        }

        // Keep the flywheel moving
        updateAndDistributeBorrowerRewardsForToken(kToken, borrower);

        return uint(Error.NO_ERROR);
    }

    /**
     * @notice Checks if the liquidation should be allowed to occur
     * @param kTokenBorrowed Asset which was borrowed by the borrower
     * @param kTokenCollateral Asset which was used as collateral and will be seized
     * @param liquidator The address repaying the borrow and seizing the collateral
     * @param borrower The address of the borrower
     * @param repayAmount The amount of underlying being repaid
     */
    function liquidateBorrowAllowed(
        address kTokenBorrowed,
        address kTokenCollateral,
        address liquidator,
        address borrower,
        uint repayAmount
    ) external view override returns (uint) {
        // Shh - currently unused
        liquidator;

        if (
            !markets[kTokenBorrowed].isListed ||
            !markets[kTokenCollateral].isListed
        ) {
            return uint(Error.MARKET_NOT_LISTED);
        }

        /* The borrower must have shortfall in order to be liquidatable */
        (Error err, , uint shortfall) = getAccountLiquidityInternal(borrower);
        if (err != Error.NO_ERROR) {
            return uint(err);
        }
        if (shortfall == 0) {
            return uint(Error.INSUFFICIENT_SHORTFALL);
        }

        /* The liquidator may not repay more than what is allowed by the closeFactor */
        uint borrowBalance = KToken(kTokenBorrowed).borrowBalanceStored(
            borrower
        );
        uint maxClose = mul_ScalarTruncate(
            Exp({mantissa: closeFactorMantissa}),
            borrowBalance
        );
        if (repayAmount > maxClose) {
            return uint(Error.TOO_MUCH_REPAY);
        }

        return uint(Error.NO_ERROR);
    }

    /**
     * @notice Checks if the seizing of assets should be allowed to occur
     * @param kTokenCollateral Asset which was used as collateral and will be seized
     * @param kTokenBorrowed Asset which was borrowed by the borrower
     * @param liquidator The address repaying the borrow and seizing the collateral
     * @param borrower The address of the borrower
     * @param seizeTokens The number of collateral tokens to seize
     */
    function seizeAllowed(
        address kTokenCollateral,
        address kTokenBorrowed,
        address liquidator,
        address borrower,
        uint seizeTokens
    ) external override returns (uint) {
        // Pausing is a very serious situation - we revert to sound the alarms
        require(!seizeGuardianPaused, "seize is paused");

        // Shh - currently unused
        seizeTokens;

        if (
            !markets[kTokenCollateral].isListed ||
            !markets[kTokenBorrowed].isListed
        ) {
            return uint(Error.MARKET_NOT_LISTED);
        }

        if (
            KToken(kTokenCollateral).comptroller() !=
            KToken(kTokenBorrowed).comptroller()
        ) {
            return uint(Error.COMPTROLLER_MISMATCH);
        }

        // Keep the flywheel moving
        // Note: We don't update borrower indices here because as part of liquidations
        //       repayBorrowFresh is called, which in turn calls `borrowAllow`, which updates
        //       the liquidated borrower's indices.
        updateAndDistributeSupplierRewardsForToken(kTokenCollateral, borrower);
        updateAndDistributeSupplierRewardsForToken(
            kTokenCollateral,
            liquidator
        );

        return uint(Error.NO_ERROR);
    }

    /**
     * @notice Checks if the account should be allowed to transfer tokens in the given market
     * @param kToken The market to verify the transfer against
     * @param src The account which sources the tokens
     * @param dst The account which receives the tokens
     * @param transferTokens The number of kTokens to transfer
     * @return 0 if the transfer is allowed, otherwise a semi-opaque error code (See ErrorReporter.sol)
     */
    function transferAllowed(
        address kToken,
        address src,
        address dst,
        uint transferTokens
    ) external override returns (uint) {
        // Pausing is a very serious situation - we revert to sound the alarms
        require(!transferGuardianPaused, "transfer is paused");

        // Currently the only consideration is whether or not
        //  the src is allowed to redeem this many tokens
        uint allowed = redeemAllowedInternal(kToken, src, transferTokens);
        if (allowed != uint(Error.NO_ERROR)) {
            return allowed;
        }

        // Keep the flywheel moving
        updateAndDistributeSupplierRewardsForToken(kToken, src);
        updateAndDistributeSupplierRewardsForToken(kToken, dst);

        return uint(Error.NO_ERROR);
    }

    /*** Liquidity/Liquidation Calculations ***/

    /**
     * @dev Local vars for avoiding stack-depth limits in calculating account liquidity.
     *  Note that `kTokenBalance` is the number of kTokens the account owns in the market,
     *  whereas `borrowBalance` is the amount of underlying that the account has borrowed.
     */
    struct AccountLiquidityLocalVars {
        uint sumCollateral;
        uint sumBorrowPlusEffects;
        uint kTokenBalance;
        uint borrowBalance;
        uint exchangeRateMantissa;
        uint oraclePriceMantissa;
        Exp collateralFactor;
        Exp exchangeRate;
        Exp oraclePrice;
        Exp tokensToDenom;
    }

    /**
     * @notice Determine the current account liquidity wrt collateral requirements
     * @return (possible error code (semi-opaque),
                account liquidity in excess of collateral requirements,
     *          account shortfall below collateral requirements)
     */
    function getAccountLiquidity(
        address account
    ) public view returns (uint, uint, uint) {
        (
            Error err,
            uint liquidity,
            uint shortfall
        ) = getHypotheticalAccountLiquidityInternal(
                account,
                KToken(address(0)),
                0,
                0
            );

        return (uint(err), liquidity, shortfall);
    }

    /**
     * @notice Determine the current account liquidity wrt collateral requirements
     * @return (possible error code,
                account liquidity in excess of collateral requirements,
     *          account shortfall below collateral requirements)
     */
    function getAccountLiquidityInternal(
        address account
    ) internal view returns (Error, uint, uint) {
        return
            getHypotheticalAccountLiquidityInternal(
                account,
                KToken(address(0)),
                0,
                0
            );
    }

    /**
     * @notice Determine what the account liquidity would be if the given amounts were redeemed/borrowed
     * @param kTokenModify The market to hypothetically redeem/borrow in
     * @param account The account to determine liquidity for
     * @param redeemTokens The number of tokens to hypothetically redeem
     * @param borrowAmount The amount of underlying to hypothetically borrow
     * @return (possible error code (semi-opaque),
                hypothetical account liquidity in excess of collateral requirements,
     *          hypothetical account shortfall below collateral requirements)
     */
    function getHypotheticalAccountLiquidity(
        address account,
        address kTokenModify,
        uint redeemTokens,
        uint borrowAmount
    ) public view returns (uint, uint, uint) {
        (
            Error err,
            uint liquidity,
            uint shortfall
        ) = getHypotheticalAccountLiquidityInternal(
                account,
                KToken(kTokenModify),
                redeemTokens,
                borrowAmount
            );
        return (uint(err), liquidity, shortfall);
    }

    /**
     * @notice Determine what the account liquidity would be if the given amounts were redeemed/borrowed
     * @param kTokenModify The market to hypothetically redeem/borrow in
     * @param account The account to determine liquidity for
     * @param redeemTokens The number of tokens to hypothetically redeem
     * @param borrowAmount The amount of underlying to hypothetically borrow
     * @dev Note that we calculate the exchangeRateStored for each collateral kToken using stored data,
     *  without calculating accumulated interest.
     * @return (possible error code,
                hypothetical account liquidity in excess of collateral requirements,
     *          hypothetical account shortfall below collateral requirements)
     */
    function getHypotheticalAccountLiquidityInternal(
        address account,
        KToken kTokenModify,
        uint redeemTokens,
        uint borrowAmount
    ) internal view returns (Error, uint, uint) {
        AccountLiquidityLocalVars memory vars; // Holds all our calculation results
        uint oErr;

        // For each asset the account is in
        KToken[] memory assets = accountAssets[account];
        for (uint i = 0; i < assets.length; i++) {
            KToken asset = assets[i];

            // Read the balances and exchange rate from the kToken
            (
                oErr,
                vars.kTokenBalance,
                vars.borrowBalance,
                vars.exchangeRateMantissa
            ) = asset.getAccountSnapshot(account);
            if (oErr != 0) {
                // semi-opaque error code, we assume NO_ERROR == 0 is invariant between upgrades
                return (Error.SNAPSHOT_ERROR, 0, 0);
            }
            vars.collateralFactor = Exp({
                mantissa: markets[address(asset)].collateralFactorMantissa
            });
            vars.exchangeRate = Exp({mantissa: vars.exchangeRateMantissa});

            // Get the normalized price of the asset
            vars.oraclePriceMantissa = oracle.getUnderlyingPrice(asset);
            if (vars.oraclePriceMantissa == 0) {
                return (Error.PRICE_ERROR, 0, 0);
            }
            vars.oraclePrice = Exp({mantissa: vars.oraclePriceMantissa});

            // Pre-compute a conversion factor from tokens -> eth (normalized price value)
            vars.tokensToDenom = mul_(
                mul_(vars.collateralFactor, vars.exchangeRate),
                vars.oraclePrice
            );

            // sumCollateral += tokensToDenom * kTokenBalance
            vars.sumCollateral = mul_ScalarTruncateAddUInt(
                vars.tokensToDenom,
                vars.kTokenBalance,
                vars.sumCollateral
            );

            // sumBorrowPlusEffects += oraclePrice * borrowBalance
            vars.sumBorrowPlusEffects = mul_ScalarTruncateAddUInt(
                vars.oraclePrice,
                vars.borrowBalance,
                vars.sumBorrowPlusEffects
            );

            // Calculate effects of interacting with kTokenModify
            if (asset == kTokenModify) {
                // redeem effect
                // sumBorrowPlusEffects += tokensToDenom * redeemTokens
                vars.sumBorrowPlusEffects = mul_ScalarTruncateAddUInt(
                    vars.tokensToDenom,
                    redeemTokens,
                    vars.sumBorrowPlusEffects
                );

                // borrow effect
                // sumBorrowPlusEffects += oraclePrice * borrowAmount
                vars.sumBorrowPlusEffects = mul_ScalarTruncateAddUInt(
                    vars.oraclePrice,
                    borrowAmount,
                    vars.sumBorrowPlusEffects
                );
            }
        }

        // These are safe, as the underflow condition is checked first
        if (vars.sumCollateral > vars.sumBorrowPlusEffects) {
            return (
                Error.NO_ERROR,
                vars.sumCollateral - vars.sumBorrowPlusEffects,
                0
            );
        } else {
            return (
                Error.NO_ERROR,
                0,
                vars.sumBorrowPlusEffects - vars.sumCollateral
            );
        }
    }

    /**
     * @notice Calculate number of tokens of collateral asset to seize given an underlying amount
     * @dev Used in liquidation (called in kToken.liquidateBorrowFresh)
     * @param kTokenBorrowed The address of the borrowed kToken
     * @param kTokenCollateral The address of the collateral kToken
     * @param actualRepayAmount The amount of kTokenBorrowed underlying to convert into kTokenCollateral tokens
     * @return (errorCode, number of kTokenCollateral tokens to be seized in a liquidation)
     */
    function liquidateCalculateSeizeTokens(
        address kTokenBorrowed,
        address kTokenCollateral,
        uint actualRepayAmount
    ) external view override returns (uint, uint) {
        /* Read oracle prices for borrowed and collateral markets */
        uint priceBorrowedMantissa = oracle.getUnderlyingPrice(
            KToken(kTokenBorrowed)
        );
        uint priceCollateralMantissa = oracle.getUnderlyingPrice(
            KToken(kTokenCollateral)
        );
        if (priceBorrowedMantissa == 0 || priceCollateralMantissa == 0) {
            return (uint(Error.PRICE_ERROR), 0);
        }

        /*
         * Get the exchange rate and calculate the number of collateral tokens to seize:
         *  seizeAmount = actualRepayAmount * liquidationIncentive * priceBorrowed / priceCollateral
         *  seizeTokens = seizeAmount / exchangeRate
         *   = actualRepayAmount * (liquidationIncentive * priceBorrowed) / (priceCollateral * exchangeRate)
         */
        uint exchangeRateMantissa = KToken(kTokenCollateral)
            .exchangeRateStored(); // Note: reverts on error
        uint seizeTokens;
        Exp memory numerator;
        Exp memory denominator;
        Exp memory ratio;

        numerator = mul_(
            Exp({mantissa: liquidationIncentiveMantissa}),
            Exp({mantissa: priceBorrowedMantissa})
        );
        denominator = mul_(
            Exp({mantissa: priceCollateralMantissa}),
            Exp({mantissa: exchangeRateMantissa})
        );
        ratio = div_(numerator, denominator);

        seizeTokens = mul_ScalarTruncate(ratio, actualRepayAmount);

        return (uint(Error.NO_ERROR), seizeTokens);
    }

    /*** Admin Functions ***/

    /**
     * @notice Sets a new price oracle for the comptroller
     * @dev Admin function to set a new price oracle
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function _setPriceOracle(PriceOracle newOracle) public returns (uint) {
        // Check caller is admin
        if (msg.sender != admin) {
            return
                fail(
                    Error.UNAUTHORIZED,
                    FailureInfo.SET_PRICE_ORACLE_OWNER_CHECK
                );
        }

        // Track the old oracle for the comptroller
        PriceOracle oldOracle = oracle;

        // Set comptroller's oracle to newOracle
        oracle = newOracle;

        // Emit NewPriceOracle(oldOracle, newOracle)
        emit NewPriceOracle(oldOracle, newOracle);

        return uint(Error.NO_ERROR);
    }

    /**
     * @notice Sets the closeFactor used when liquidating borrows
     * @dev Admin function to set closeFactor
     * @param newCloseFactorMantissa New close factor, scaled by 1e18
     * @return uint 0=success, otherwise a failure
     */
    function _setCloseFactor(
        uint newCloseFactorMantissa
    ) external returns (uint) {
        // Check caller is admin
        require(msg.sender == admin, "only admin can set close factor");

        uint oldCloseFactorMantissa = closeFactorMantissa;
        closeFactorMantissa = newCloseFactorMantissa;
        emit NewCloseFactor(oldCloseFactorMantissa, closeFactorMantissa);

        return uint(Error.NO_ERROR);
    }

    /**
     * @notice Sets the collateralFactor for a market
     * @dev Admin function to set per-market collateralFactor
     * @param kToken The market to set the factor on
     * @param newCollateralFactorMantissa The new collateral factor, scaled by 1e18
     * @return uint 0=success, otherwise a failure. (See ErrorReporter for details)
     */
    function _setCollateralFactor(
        KToken kToken,
        uint newCollateralFactorMantissa
    ) external returns (uint) {
        // Check caller is admin
        if (msg.sender != admin) {
            return
                fail(
                    Error.UNAUTHORIZED,
                    FailureInfo.SET_COLLATERAL_FACTOR_OWNER_CHECK
                );
        }

        // Verify market is listed
        Market storage market = markets[address(kToken)];
        if (!market.isListed) {
            return
                fail(
                    Error.MARKET_NOT_LISTED,
                    FailureInfo.SET_COLLATERAL_FACTOR_NO_EXISTS
                );
        }

        Exp memory newCollateralFactorExp = Exp({
            mantissa: newCollateralFactorMantissa
        });

        // Check collateral factor <= 0.9
        Exp memory highLimit = Exp({mantissa: collateralFactorMaxMantissa});
        if (lessThanExp(highLimit, newCollateralFactorExp)) {
            return
                fail(
                    Error.INVALID_COLLATERAL_FACTOR,
                    FailureInfo.SET_COLLATERAL_FACTOR_VALIDATION
                );
        }

        // If collateral factor != 0, fail if price == 0
        if (
            newCollateralFactorMantissa != 0 &&
            oracle.getUnderlyingPrice(kToken) == 0
        ) {
            return
                fail(
                    Error.PRICE_ERROR,
                    FailureInfo.SET_COLLATERAL_FACTOR_WITHOUT_PRICE
                );
        }

        // Set market's collateral factor to new collateral factor, remember old value
        uint oldCollateralFactorMantissa = market.collateralFactorMantissa;
        market.collateralFactorMantissa = newCollateralFactorMantissa;

        // Emit event with asset, old collateral factor, and new collateral factor
        emit NewCollateralFactor(
            kToken,
            oldCollateralFactorMantissa,
            newCollateralFactorMantissa
        );

        return uint(Error.NO_ERROR);
    }

    /**
     * @notice Sets liquidationIncentive
     * @dev Admin function to set liquidationIncentive
     * @param newLiquidationIncentiveMantissa New liquidationIncentive scaled by 1e18
     * @return uint 0=success, otherwise a failure. (See ErrorReporter for details)
     */
    function _setLiquidationIncentive(
        uint newLiquidationIncentiveMantissa
    ) external returns (uint) {
        // Check caller is admin
        if (msg.sender != admin) {
            return
                fail(
                    Error.UNAUTHORIZED,
                    FailureInfo.SET_LIQUIDATION_INCENTIVE_OWNER_CHECK
                );
        }

        // Save current value for use in log
        uint oldLiquidationIncentiveMantissa = liquidationIncentiveMantissa;

        // Set liquidation incentive to new incentive
        liquidationIncentiveMantissa = newLiquidationIncentiveMantissa;

        // Emit event with old incentive, new incentive
        emit NewLiquidationIncentive(
            oldLiquidationIncentiveMantissa,
            newLiquidationIncentiveMantissa
        );

        return uint(Error.NO_ERROR);
    }

    /**
     * @notice Add the market to the markets mapping and set it as listed
     * @dev Admin function to set isListed and add support for the market
     * @param kToken The address of the market (token) to list
     * @return uint 0=success, otherwise a failure. (See enum Error for details)
     */
    function _supportMarket(KToken kToken) external returns (uint) {
        if (msg.sender != admin) {
            return
                fail(
                    Error.UNAUTHORIZED,
                    FailureInfo.SUPPORT_MARKET_OWNER_CHECK
                );
        }

        if (markets[address(kToken)].isListed) {
            return
                fail(
                    Error.MARKET_ALREADY_LISTED,
                    FailureInfo.SUPPORT_MARKET_EXISTS
                );
        }

        require(kToken.isKToken(), "Must be an KToken"); // Sanity check to make sure its really a KToken

        Market storage newMarket = markets[address(kToken)];
        newMarket.isListed = true;
        newMarket.collateralFactorMantissa = 0;

        _addMarketInternal(address(kToken));

        emit MarketListed(kToken);

        return uint(Error.NO_ERROR);
    }

    function _addMarketInternal(address kToken) internal {
        for (uint i = 0; i < allMarkets.length; i++) {
            require(allMarkets[i] != KToken(kToken), "market already added");
        }
        allMarkets.push(KToken(kToken));
    }

    /**
     * @notice Set the given borrow caps for the given kToken markets. Borrowing that brings total borrows to or above borrow cap will revert.
     * @dev Admin or borrowCapGuardian function to set the borrow caps. A borrow cap of 0 corresponds to unlimited borrowing.
     * @param kTokens The addresses of the markets (tokens) to change the borrow caps for
     * @param newBorrowCaps The new borrow cap values in underlying to be set. A value of 0 corresponds to unlimited borrowing.
     */
    function _setMarketBorrowCaps(
        KToken[] calldata kTokens,
        uint[] calldata newBorrowCaps
    ) external {
        require(
            msg.sender == admin || msg.sender == borrowCapGuardian,
            "only admin or borrow cap guardian can set borrow caps"
        );

        uint numMarkets = kTokens.length;
        uint numBorrowCaps = newBorrowCaps.length;

        require(
            numMarkets != 0 && numMarkets == numBorrowCaps,
            "invalid input"
        );

        for (uint i = 0; i < numMarkets; i++) {
            borrowCaps[address(kTokens[i])] = newBorrowCaps[i];
            emit NewBorrowCap(kTokens[i], newBorrowCaps[i]);
        }
    }

    /**
     * @notice Admin function to change the Borrow Cap Guardian
     * @param newBorrowCapGuardian The address of the new Borrow Cap Guardian
     */
    function _setBorrowCapGuardian(address newBorrowCapGuardian) external {
        require(msg.sender == admin, "only admin can set borrow cap guardian");

        // Save current value for inclusion in log
        address oldBorrowCapGuardian = borrowCapGuardian;

        // Store borrowCapGuardian with value newBorrowCapGuardian
        borrowCapGuardian = newBorrowCapGuardian;

        // Emit NewBorrowCapGuardian(OldBorrowCapGuardian, NewBorrowCapGuardian)
        emit NewBorrowCapGuardian(oldBorrowCapGuardian, newBorrowCapGuardian);
    }

    /**
     * @notice Set the given supply caps for the given kToken markets. Supplying that brings total supplies to or above supply cap will revert.
     * @dev Admin or supplyCapGuardian function to set the supply caps. A supply cap of 0 corresponds to unlimited supplying.
     * @param kTokens The addresses of the markets (tokens) to change the supply caps for
     * @param newSupplyCaps The new supply cap values in underlying to be set. A value of 0 corresponds to unlimited supplying.
     */
    function _setMarketSupplyCaps(
        KToken[] calldata kTokens,
        uint[] calldata newSupplyCaps
    ) external {
        require(
            msg.sender == admin || msg.sender == supplyCapGuardian,
            "only admin or supply cap guardian can set supply caps"
        );

        uint numMarkets = kTokens.length;
        uint numSupplyCaps = newSupplyCaps.length;

        require(
            numMarkets != 0 && numMarkets == numSupplyCaps,
            "invalid input"
        );

        for (uint i = 0; i < numMarkets; i++) {
            supplyCaps[address(kTokens[i])] = newSupplyCaps[i];
            emit NewSupplyCap(kTokens[i], newSupplyCaps[i]);
        }
    }

    /**
     * @notice Admin function to change the Supply Cap Guardian
     * @param newSupplyCapGuardian The address of the new Supply Cap Guardian
     */
    function _setSupplyCapGuardian(address newSupplyCapGuardian) external {
        require(msg.sender == admin, "only admin can set supply cap guardian");

        // Save current value for inclusion in log
        address oldSupplyCapGuardian = supplyCapGuardian;

        // Store supplyCapGuardian with value newSupplyCapGuardian
        supplyCapGuardian = newSupplyCapGuardian;

        // Emit NewSupplyCapGuardian(OldSupplyCapGuardian, NewSupplyCapGuardian)
        emit NewSupplyCapGuardian(oldSupplyCapGuardian, newSupplyCapGuardian);
    }

    /**
     * @notice Admin function to change the Pause Guardian
     * @param newPauseGuardian The address of the new Pause Guardian
     * @return uint 0=success, otherwise a failure. (See enum Error for details)
     */
    function _setPauseGuardian(address newPauseGuardian) public returns (uint) {
        if (msg.sender != admin) {
            return
                fail(
                    Error.UNAUTHORIZED,
                    FailureInfo.SET_PAUSE_GUARDIAN_OWNER_CHECK
                );
        }

        // Save current value for inclusion in log
        address oldPauseGuardian = pauseGuardian;

        // Store pauseGuardian with value newPauseGuardian
        pauseGuardian = newPauseGuardian;

        // Emit NewPauseGuardian(OldPauseGuardian, NewPauseGuardian)
        emit NewPauseGuardian(oldPauseGuardian, pauseGuardian);

        return uint(Error.NO_ERROR);
    }

    /**
     * @notice Admin function to change the Reward Distributor
     * @param newRewardDistributor The address of the new Reward Distributor
     */
    function _setRewardDistributor(
        MultiRewardDistributor newRewardDistributor
    ) public {
        require(msg.sender == admin, "Unauthorized");

        MultiRewardDistributor oldRewardDistributor = rewardDistributor;

        rewardDistributor = newRewardDistributor;

        emit NewRewardDistributor(oldRewardDistributor, newRewardDistributor);
    }

    function _setMintPaused(KToken kToken, bool state) public returns (bool) {
        require(
            markets[address(kToken)].isListed,
            "cannot pause a market that is not listed"
        );
        require(
            msg.sender == pauseGuardian || msg.sender == admin,
            "only pause guardian and admin can pause"
        );
        require(msg.sender == admin || state == true, "only admin can unpause");

        mintGuardianPaused[address(kToken)] = state;
        emit ActionPaused(kToken, "Mint", state);
        return state;
    }

    function _setBorrowPaused(KToken kToken, bool state) public returns (bool) {
        require(
            markets[address(kToken)].isListed,
            "cannot pause a market that is not listed"
        );
        require(
            msg.sender == pauseGuardian || msg.sender == admin,
            "only pause guardian and admin can pause"
        );
        require(msg.sender == admin || state == true, "only admin can unpause");

        borrowGuardianPaused[address(kToken)] = state;
        emit ActionPaused(kToken, "Borrow", state);
        return state;
    }

    function _setTransferPaused(bool state) public returns (bool) {
        require(
            msg.sender == pauseGuardian || msg.sender == admin,
            "only pause guardian and admin can pause"
        );
        require(msg.sender == admin || state == true, "only admin can unpause");

        transferGuardianPaused = state;
        emit ActionPaused("Transfer", state);
        return state;
    }

    function _setSeizePaused(bool state) public returns (bool) {
        require(
            msg.sender == pauseGuardian || msg.sender == admin,
            "only pause guardian and admin can pause"
        );
        require(msg.sender == admin || state == true, "only admin can unpause");

        seizeGuardianPaused = state;
        emit ActionPaused("Seize", state);
        return state;
    }

    function _become(Unitroller unitroller) public {
        require(
            msg.sender == unitroller.admin(),
            "only unitroller admin can change brains"
        );
        require(
            unitroller._acceptImplementation() == 0,
            "change not authorized"
        );
    }

    /**
     * @notice Sweep ERC-20 tokens from the comptroller to the admin
     * @param _tokenAddress The address of the token to transfer
     * @param _amount The amount of tokens to sweep, uint.max means everything
     */
    function _rescueFunds(address _tokenAddress, uint _amount) external {
        require(msg.sender == admin, "Unauthorized");

        IERC20 token = IERC20(_tokenAddress);
        // Similar to kTokens, if this is uint.max that means "transfer everything"
        if (_amount == type(uint).max) {
            token.transfer(admin, token.balanceOf(address(this)));
        } else {
            token.transfer(admin, _amount);
        }
    }

    /*** WELL Distribution ***/

    /**
     * @notice Call out to the reward distributor to update its supply index and this user's index too
     * @param kToken The market to synchronize indexes for
     * @param supplier The supplier to whom rewards are going
     */
    function updateAndDistributeSupplierRewardsForToken(
        address kToken,
        address supplier
    ) internal {
        if (address(rewardDistributor) != address(0)) {
            rewardDistributor.updateMarketSupplyIndexAndDisburseSupplierRewards(
                KToken(kToken),
                supplier,
                false
            );
        }
    }

    /**
     * @notice Call out to the reward distributor to update its borrow index and this user's index too
     * @param kToken The market to synchronize indexes for
     * @param borrower The borrower to whom rewards are going
     */
    function updateAndDistributeBorrowerRewardsForToken(
        address kToken,
        address borrower
    ) internal {
        if (address(rewardDistributor) != address(0)) {
            rewardDistributor.updateMarketBorrowIndexAndDisburseBorrowerRewards(
                KToken(kToken),
                borrower,
                false
            );
        }
    }

    /**
     * @notice Claim all the WELL accrued by holder in all markets
     */
    function claimReward() public {
        claimReward(msg.sender, allMarkets);
    }

    /**
     * @notice Claim all the rewards accrued by specified holder in all markets
     * @param holder The address to claim rewards for
     */
    function claimReward(address holder) public {
        claimReward(holder, allMarkets);
    }

    /**
     * @notice Claim all the rewards accrued by holder in the specified markets
     * @param holder The address to claim rewards for
     * @param kTokens The list of markets to claim rewards in
     */
    function claimReward(address holder, KToken[] memory kTokens) public {
        address[] memory holders = new address[](1);
        holders[0] = holder;
        claimReward(holders, kTokens, true, true);
    }

    /**
     * @notice Claim all rewards for a specified group of users, tokens, and market sides
     * @param holders The addresses to claim for
     * @param kTokens The list of markets to claim in
     * @param borrowers Whether or not to claim earned by borrowing
     * @param suppliers Whether or not to claim earned by supplying
     */
    function claimReward(
        address[] memory holders,
        KToken[] memory kTokens,
        bool borrowers,
        bool suppliers
    ) public {
        require(
            address(rewardDistributor) != address(0),
            "No reward distributor configured!"
        );

        for (uint i = 0; i < kTokens.length; i++) {
            // Safety check that the supplied kTokens are active/listed
            KToken kToken = kTokens[i];
            require(markets[address(kToken)].isListed, "market must be listed");

            // Disburse supply side
            if (suppliers == true) {
                rewardDistributor.updateMarketSupplyIndex(kToken);
                for (
                    uint holderIndex = 0;
                    holderIndex < holders.length;
                    holderIndex++
                ) {
                    rewardDistributor.disburseSupplierRewards(
                        kToken,
                        holders[holderIndex],
                        true
                    );
                }
            }

            // Disburse borrow side
            if (borrowers == true) {
                rewardDistributor.updateMarketBorrowIndex(kToken);
                for (
                    uint holderIndex = 0;
                    holderIndex < holders.length;
                    holderIndex++
                ) {
                    rewardDistributor.disburseBorrowerRewards(
                        kToken,
                        holders[holderIndex],
                        true
                    );
                }
            }
        }
    }

    /**
     * @notice Return all of the markets
     * @dev The automatic getter may be used to access an individual market.
     * @return The list of market addresses
     */
    function getAllMarkets() public view returns (KToken[] memory) {
        return allMarkets;
    }

    function getBlockTimestamp() public view returns (uint) {
        return block.timestamp;
    }

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     * Calling a `nonReentrant` function from another `nonReentrant`
     * function is not supported. It is possible to prevent this from happening
     * by making the `nonReentrant` function external, and make it call a
     * `private` function that does the actual work.
     */
    modifier nonReentrant() {
        // On the first call to nonReentrant, _notEntered will be true
        require(_locked != 1, "ReentrancyGuard: reentrant call");

        // Any calls to nonReentrant after this point will fail
        _locked = 1;

        _;

        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _locked = 0;
    }
}

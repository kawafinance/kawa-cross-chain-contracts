// @ts-nocheck
import {task} from "hardhat/config";
import {getConfig} from "../config";
import {BigNumber} from "ethers";
import {MaxUint256} from "@ethersproject/constants";
import * as ethers from "ethers";

const WETH_ABI = [
    "function deposit() public payable",
    "function withdraw(uint wad) public",
    "function balanceOf(address owner) view returns (uint256)",
];

task("circleUSDC", "do a full usdc circle actions")
    .setAction(async (taskArgs, hre) => {

        const {deployer} = await hre.getNamedAccounts();

        // @ts-ignore
        const checkApprove = async (token, spender, amount) => {
            console.log('underlying', underlyingAddress)
            const underlying = await hre.ethers.getContractAt('KErc20Delegator', token)

            const allowance = await underlying.allowance(deployer, spender)
            console.log('allowance', allowance.toString())

            if (allowance.lt(amount)) {
                console.log('approving ', amount)
                results = await underlying.approve(spender, MaxUint256)
                results.wait(30)
            }
        }

        let results

        console.log('USDC Circle')
        const amount = 10000
        const kTokenAddress = (await hre.deployments.get('kUSDC')).address
        console.log('kToken: ', kTokenAddress)
        const KErc20Delegator = await hre.ethers.getContractAt('KErc20Delegator', kTokenAddress)

        const underlyingAddress = await KErc20Delegator.underlying()
        console.log('underlying', underlyingAddress)
        const underlying = await hre.ethers.getContractAt('KErc20Delegator', underlyingAddress)

        const unitrollerAddress = (await hre.deployments.get('Unitroller')).address
        console.log('Unitroller: ', unitrollerAddress)
        const Comptroller = await hre.ethers.getContractAt('Comptroller', unitrollerAddress)

        const balanceOfToken = await underlying.balanceOf(deployer)
        console.log('balanceOfUnderlying\t', balanceOfToken.toString())
        console.log('amount\t\t\t', amount)

        await checkApprove(underlyingAddress, kTokenAddress, amount)

        console.log('Deposit', amount)
        results = await KErc20Delegator.mint(amount)
        await results.wait(1)

        const balanceOfUnderlying = await KErc20Delegator.callStatic.balanceOfUnderlying(deployer)
        console.log('balanceOfUnderlying', balanceOfUnderlying.toString())
        // const totalSupply = await KErc20Delegator.totalSupply()
        // console.log('totalSupply', totalSupply.toString())

        console.log('Enabling collaterall...')
        results = await Comptroller.enterMarkets([kTokenAddress])
        await results.wait(1)

        const markets = await Comptroller.getAssetsIn(deployer)
        console.log('markets of user', markets)

        const borrowAmmount = amount / 10
        console.log('Borrowing', borrowAmmount)
        results = await KErc20Delegator.borrow(borrowAmmount)
        await results.wait(1)

        let borrowBalanceCurrent = await KErc20Delegator.callStatic.borrowBalanceCurrent(deployer)
        console.log('borrowBalanceCurrent', borrowBalanceCurrent.toString())

        await checkApprove(underlyingAddress, kTokenAddress, borrowBalanceCurrent.toNumber())

        // console.log('Repaying...')
        // results = await KErc20Delegator.repayBorrowBehalf(deployer, borrowBalanceCurrent.toNumber())
        // // results = await KErc20Delegator.repayBorrow(borrowBalanceCurrent.toNumber())
        // await results.wait(1)

        // const totalBorrows = await KErc20Delegator.callStatic.totalBorrows()
        // console.log('totalBorrows', totalBorrows.toString())

        // const totalBorrowsCurrent = await KErc20Delegator.callStatic.totalBorrowsCurrent()
        // console.log('totalBorrowsCurrent', totalBorrowsCurrent.toString())

        console.log('RepayingAll...')
        results = await KErc20Delegator.repayBorrowBehalf(deployer, MaxUint256)
        // results = await KErc20Delegator.repayBorrow(borrowBalanceCurrent.toNumber())
        await results.wait(1)

        borrowBalanceCurrent = await KErc20Delegator.callStatic.borrowBalanceCurrent(deployer)
        console.log('borrowBalanceCurrent', borrowBalanceCurrent.toString())

        let balanceOf = await KErc20Delegator.balanceOf(deployer)

        console.log('Withdrawing', balanceOf.toString())
        results = await KErc20Delegator.redeem(balanceOf)
        await results.wait(1)
        balanceOf = await KErc20Delegator.balanceOf(deployer)
        console.log('balanceOf', balanceOf.toString())

        console.log('Disabling collaterall...')
        results = await Comptroller.exitMarket(kTokenAddress)
        await results.wait(1)
    });


task("circleSEI", "do a full sei circle actions")
    .setAction(async (taskArgs, hre) => {
        let results

        const {deployer} = await hre.getNamedAccounts();
        console.log('deployer', deployer)
        console.log('SEI Circle')
        const amount = 1000000000000 // 1e13
        const kSEIAddress = (await hre.deployments.get('kSEI')).address
        console.log('kSEI: ', kSEIAddress)
        const KNative = await hre.ethers.getContractAt('KNative', kSEIAddress)
        const unitrollerAddress = (await hre.deployments.get('Unitroller')).address
        console.log('Unitroller: ', unitrollerAddress)
        const Comptroller = await hre.ethers.getContractAt('Comptroller', unitrollerAddress)
        const maximillionAddress = (await hre.deployments.get('Maximillion')).address
        console.log('Maximillion: ', maximillionAddress)
        const Maximillion = await hre.ethers.getContractAt('Maximillion', maximillionAddress)
        const maxNative = await Maximillion.kNative()
        console.log('Maximillion KNative', maxNative)

        console.log('Deposit...')
        results = await KNative.mint({value: amount})
        await results.wait(1)

        const balanceOf = await KNative.balanceOf(deployer)
        console.log('balanceOf', balanceOf.toString())
        const totalSupply = await KNative.totalSupply()
        console.log('totalSupply', totalSupply.toString())
        let borrowBalanceCurrent = await KNative.borrowBalanceCurrent(deployer)
        console.log('borrowBalanceCurrent', borrowBalanceCurrent)
        let balanceOfUnderlying = await KNative.balanceOfUnderlying(deployer)
        console.log('balanceOfUnderlying', balanceOfUnderlying)

        console.log('Enabling collaterall...')
        results = await Comptroller.enterMarkets([kSEIAddress])
        await results.wait(1)
        console.log(results.hash)

        const markets = await Comptroller.getAssetsIn(deployer)
        console.log('markets of user', markets)
        const borrowCaps = await Comptroller.borrowCaps(kSEIAddress)
        console.log('borrowCaps', borrowCaps.toString())

        console.log('Borrowing...')
        results = await KNative.borrow(amount / 10)
        await results.wait(1)

        // borrowBalanceCurrent = await KNative.callStatic.borrowBalanceCurrent(deployer)
        // console.log('borrowBalanceCurrent', borrowBalanceCurrent.toString())
        //
        // balanceOfUnderlying = await KNative.callStatic.balanceOfUnderlying(deployer)
        // console.log('balanceOfUnderlying', balanceOfUnderlying.toString())

        const totalBorrows = await KNative.callStatic.totalBorrows()
        console.log('totalBorrows', totalBorrows.toString())

        // console.log('RepayingAll...')
        // const repayAmount = totalBorrows
        // // await Maximillion.estimateGas.repayBehalf(deployer, {value: repayAmount })
        // results = await Maximillion.repayBehalf(deployer, {value: repayAmount})
        // await results.wait(1)
        //
        // console.log('Withdrawing...')
        // results = await KNative.redeem(balanceOf)
        // await results.wait(1)
        //
        // const balanceOfAfter = await KNative.balanceOf(deployer)
        // console.log('balanceOfAfter', balanceOfAfter.toString())

    });

task("liquidateInfo", "test liquidator")
    .setAction(async (taskArgs, hre) => {
        const {LIQUIDATOR_ADDRESS} = getConfig(hre.network.name);
        const liquidatorContract = await hre.ethers.getContractAt('DragonswapLiquidator', LIQUIDATOR_ADDRESS)
        const kseiAddress = (await hre.deployments.get('kSEI')).address
        const balanceksei = await hre.ethers.provider.getBalance(kseiAddress)
        // const kseiContract = await hre.ethers.getContractAt('KNative', kseiAddress)
        // const kseiWsei = kseiContract.underlying()
        const wsei = await liquidatorContract.WSEI()
        const ksei = await liquidatorContract.KSEI()
        const usdc = await liquidatorContract.USDC()
        console.log('liquidator: ', LIQUIDATOR_ADDRESS)
        console.log('liq wsei: ', wsei)
        console.log('ksei bal: ', balanceksei.div(BigNumber.from(10).pow(BigNumber.from(18))).toNumber(), balanceksei.toString())
        console.log('liq ksei: ', ksei)
        console.log('dep ksei: ', kseiAddress)
        console.log('liq usdc: ', usdc)
    })

task("liquidate", "test liquidator")
    .setAction(async (taskArgs, hre) => {
        const {LIQUIDATOR_ADDRESS} = getConfig(hre.network.name);
        const liquidatorContract = await hre.ethers.getContractAt('DragonswapLiquidator', LIQUIDATOR_ADDRESS)
        const kseiAddress = (await hre.deployments.get('kSEI')).address
        const compAddress = (await hre.deployments.get('Unitroller')).address
        const balanceksei = await hre.ethers.provider.getBalance(kseiAddress)
        const balancecomp = await hre.ethers.provider.getBalance(compAddress)
        // const kseiContract = await hre.ethers.getContractAt('KNative', kseiAddress)
        // const kseiWsei = kseiContract.underlying()
        const wsei = await liquidatorContract.WSEI()
        const ksei = await liquidatorContract.KSEI()
        const usdc = await liquidatorContract.USDC()
        console.log('liquidator: ', LIQUIDATOR_ADDRESS)
        console.log('liq wsei: ', wsei)
        console.log('ksei bal: ', balanceksei)
        console.log('comp bal: ', balancecomp)
        console.log('liq ksei: ', ksei)
        console.log('dep ksei: ', kseiAddress)
        console.log('liq usdc: ', usdc)

        const params = {
            borrower: '0xc9dfb1ac9db06c71d6a096f2141696abbe6111a4',
            repay: '0x48345eb0ff40798640f2688e8fe4a19477f13f6c',
            seize: '0x76cd23a2d024be2638335b5b4bf93870cb914019',
            amount: '375000',
            borrowedValue: 0.375,
            suppliedValue: 0.7613892545366056
        }

        console.log('Liquidate Params', params);

        try {

            // const data = this.liquidatorContract.interface.encodeFunctionData(
            //   'liquidate',
            //   [
            //     account.address,
            //     bestMarketRepay.id,
            //     bestMarketSeize.id,
            //     amountRepay.toFixed(0),
            //   ],
            // );
            // const rawTx = {
            //   to: LIQUIDATOR_ADDRESS,
            //   data: data,
            //   gasLimit: '0x989680',
            // };
            // const txhash = await this.signer.sendTransaction(rawTx);
            // await txhash.wait(1);
            // console.log('hash: ', txhash.hash);
            // console.log('tx: ', txhash);
            // console.log('estimating gas...');
            // const estimateGas = await this.provider.estimateGas(rawTx);
            // console.log(estimateGas);
            const tx = await liquidatorContract.liquidate(
                params.borrower,
                params.repay,
                params.seize,
                params.amount,
            );

            const receipt = await tx.wait(1);
            console.log('liquidated tx', {hash: tx.hash});
            receipt.events?.forEach(event => {
                console.log(event)
            })
        } catch (error) {
            console.log(error)
            console.log(`${error.reason}: ${error.code}`);
            console.log("Hash: ", error.transactionHash);
            console.log("Logs: ", error.transaction.logs);
            // error.transaction.events?.forEach( event => {
            //     console.log(event)
            // })
            try {
                console.log('Getting receipt...')
                const receipt = await hre.ethers.provider.getTransactionReceipt(error.transaction.hash);

                if (receipt && receipt.logs) {
                    receipt.logs.forEach(log => {
                        try {
                            const parsedLog = liquidatorContract.interface.parseLog(log);
                            console.log(`Event: ${parsedLog.name}, Args: ${JSON.stringify(parsedLog.args)}`);
                        } catch (parseError) {
                            console.error("Log parsing error:", parseError);
                        }
                    });
                }
            } catch (receiptError) {
                console.error("Failed to fetch transaction receipt:", receiptError);
            }
        }

    });

task("redeem", "redeem kToken from liquidator")
    .addParam("address", "kToken address")
    .setAction(async ({address}, hre) => {
        const {LIQUIDATOR_ADDRESS} = getConfig(hre.network.name);
        const token = await hre.ethers.getContractAt('IERC20', address);
        const liquidatorContract = await hre.ethers.getContractAt('DragonswapLiquidator', LIQUIDATOR_ADDRESS)
        try {
            const balanceOf = await token.balanceOf(LIQUIDATOR_ADDRESS)
            console.log('Balance', balanceOf.toString())
            const tx = await liquidatorContract.redeemKToken(address)
            await tx.wait(1)

            console.log('Redeem', address, tx.hash);
        } catch (e) {
            console.log(e)
        }

    });

task("balanceOf", "balanceOf token of liquidator")
    .addParam("address", "token address")
    .setAction(async ({address}, hre) => {
        const {LIQUIDATOR_ADDRESS} = getConfig(hre.network.name);
        const token = await hre.ethers.getContractAt('IERC20', address);
        try {
            const nativeBalance = await hre.ethers.provider.getBalance(LIQUIDATOR_ADDRESS);
            console.log('Native', nativeBalance.toString())
            const balanceOf = await token.balanceOf(LIQUIDATOR_ADDRESS)
            const decimals = await token.decimals()
            console.log('Balance', balanceOf.toString())
        } catch (e) {
            console.log(e)
        }

    });

task("priceProvider", "ask token price of price provider")
    .setAction(async ({address}, hre) => {
        const {PRICE_PROVIDER_ADDRESS} = getConfig(hre.network.name);
        const priceProviderContract = await hre.ethers.getContractAt('PriceProvider', PRICE_PROVIDER_ADDRESS)
        try {
            const tokenPriceUSD = await priceProviderContract.getTokenPriceUsd()
            console.log('TokenPriceUSD', tokenPriceUSD.toString())
            const tokenPriceSEI = await priceProviderContract.getTokenPrice()
            console.log('TokenPrice', tokenPriceSEI.toString())
            const seiPrice = await priceProviderContract.getEthPrice()
            console.log('SeiPrice', seiPrice.toString())
            const lpTokenPriceUSD = await priceProviderContract.getLpTokenPriceUsd()
            console.log('lpTokenPriceUSD', lpTokenPriceUSD.toString())
            const lpTokenPrice = await priceProviderContract.getLpTokenPrice()
            console.log('lpTokenPrice', lpTokenPrice.toString())
            const reserves = await priceProviderContract.getReserves()
            console.log('reserves', reserves)
            const lpPrice = await priceProviderContract.getLpPrice(tokenPriceSEI)
            console.log('lpPrice', lpPrice.toString())
        } catch (e) {
            console.log(e)
        }
    });

task("ask", "test liquidator")
    .setAction(async (taskArgs, hre) => {
        const {LIQUIDATOR_ADDRESS} = getConfig(hre.network.name);
        const unitrollerAddress = (await hre.deployments.get('Unitroller')).address
        const comptroller = await hre.ethers.getContractAt('Comptroller', unitrollerAddress)
        const [signer] = await hre.ethers.getSigners();
        const params = {
            kTokenBorrowed: "0x76cd23a2d024be2638335b5b4bf93870cb914019",
            kTokenCollateral: "0x76cd23a2d024be2638335b5b4bf93870cb914019",
            liquidator: signer.address,
            borrower: "0xaf7798fb00b04501ffa1a61d4036f8797766891e",
            repayAmount: "335093200000000000"
        }
        const params2 = {
            kTokenBorrowed: "0x48345eb0ff40798640f2688e8fe4a19477f13f6c",
            kTokenCollateral: "0x76cd23a2d024be2638335b5b4bf93870cb914019",
            liquidator: signer.address,
            borrower: "0xc9dfb1ac9db06c71d6a096f2141696abbe6111a4",
            repayAmount: "94535"
        }

        const allowed = await comptroller.callStatic.liquidateBorrowAllowed(
            params.kTokenBorrowed,
            params.kTokenCollateral,
            params.liquidator,
            params.borrower,
            params.repayAmount
        )
        console.log('static: ', allowed.toString())

        const allowed2 = await comptroller.liquidateBorrowAllowed(
            params.kTokenBorrowed,
            params.kTokenCollateral,
            params.liquidator,
            params.borrower,
            params.repayAmount,
            // {gasLimit: "100000"}
        )
        await allowed2.wait(1)
        console.log('live: ', allowed2.value.toString())

        const allowed3 = await comptroller.callStatic.liquidateBorrowAllowed(
            params2.kTokenBorrowed,
            params2.kTokenCollateral,
            params2.liquidator,
            params2.borrower,
            params2.repayAmount
        )
        console.log('static2: ', allowed3.toString())

        const allowed4 = await comptroller.liquidateBorrowAllowed(
            params2.kTokenBorrowed,
            params2.kTokenCollateral,
            params2.liquidator,
            params2.borrower,
            params2.repayAmount,
            // {gasLimit: "100000"}
        )
        await allowed4.wait(1)
        console.log('live2: ', allowed4)
    });

task("liq", "test liquidator")
    .setAction(async (taskArgs, hre) => {
        const {LIQUIDATOR_ADDRESS} = getConfig(hre.network.name);
        const liquidatorContract = await hre.ethers.getContractAt('DragonswapLiquidator', LIQUIDATOR_ADDRESS)

        try {
            const tx = await liquidatorContract.test("0")
            const receipt = await tx.wait(1);
            console.log('tx', {hash: tx.hash});
            receipt.events?.forEach(event => {
                console.log(event)
            })
        } catch (error) {
            console.log(error)
            console.log(`${error.reason}: ${error.code}`);
            console.log("Hash: ", error.transactionHash);
            console.log("Logs: ", error.transaction.logs);
            // error.transaction.events?.forEach( event => {
            //     console.log(event)
            // })
            try {
                console.log('Getting receipt...')
                const receipt = await hre.ethers.provider.getTransactionReceipt(error.transaction.hash);

                if (receipt && receipt.logs) {
                    receipt.logs.forEach(log => {
                        try {
                            const parsedLog = liquidatorContract.interface.parseLog(log);
                            console.log(`Event: ${parsedLog.name}, Args: ${JSON.stringify(parsedLog.args)}`);
                        } catch (parseError) {
                            console.error("Log parsing error:", parseError);
                        }
                    });
                }
            } catch (receiptError) {
                console.error("Failed to fetch transaction receipt:", receiptError);
            }
        }

    });

task("rewardsinfo", "user lock info of incentives distributor")
    .setAction(async (taskArgs, hre) => {
        const {deployer} = await hre.getNamedAccounts();
        const {
            INCENTIVES_DISTRIBUTOR_ADDRESS,
            INCENTIVES_ELIGIBILITY_ADDRESS,
            INCENTIVES_CONTROLLER_ADDRESS
        } = getConfig(hre.network.name);
        const unitrollerAddress = (await hre.deployments.get('Unitroller')).address
        const incentivesEligibility = await hre.ethers.getContractAt('IncentivesEligibility', INCENTIVES_ELIGIBILITY_ADDRESS)
        const incentivesDistributor = await hre.ethers.getContractAt('IncentivesDistributor', INCENTIVES_DISTRIBUTOR_ADDRESS)
        const incentivesController = await hre.ethers.getContractAt('IncentivesController', INCENTIVES_CONTROLLER_ADDRESS)
        const comptroller = await hre.ethers.getContractAt('Comptroller', unitrollerAddress)
        const kseiaddress = (await hre.deployments.get('kSEI')).address
        const kusdcaddress = (await hre.deployments.get('kUSDC')).address
        try {
            let res = await incentivesDistributor.rewardTokens(0)
            console.log('rewardTokens', res)
            res = await incentivesDistributor.lockInfo(deployer)
            console.log('lockInfo', res)
            res = await incentivesDistributor.totalBalance(deployer)
            console.log('totalBalance', res)
            res = await incentivesDistributor.lockedBalances(deployer)
            console.log('lockedBalances', res)
            res = await incentivesDistributor.earnedBalances(deployer)
            console.log('earnedBalances', res)
            res = await incentivesDistributor.withdrawableBalance(deployer)
            console.log('withdrawableBalance', res)
            res = await incentivesDistributor.defaultLockIndex(deployer)
            console.log('defaultLockIndex', res)
            res = await incentivesDistributor.claimableRewards(deployer)
            console.log('claimableRewards', res)
            res = await incentivesController.userInfo(kseiaddress, deployer)
            console.log('userInfo ksei', res)
            res = await incentivesController.userInfo(kusdcaddress, deployer)
            console.log('userInfo kusdc', res)
            // res = await incentivesDistributor.rewards(deployer)
            // console.log('rewards', res)
            res = await incentivesEligibility.callStatic.isEligibleForRewards(deployer)
            console.log('isEligibleForRewards', res)
            res = await comptroller.getAccountCollateral(deployer)
            console.log('accountCollateral', Number(res) / 10 ** 18)
            res = await incentivesEligibility.lockedUsdValue(deployer)
            console.log('lockedUsdValue', Number(res) / 10 ** 8)
            res = await incentivesEligibility.requiredUsdValue(deployer)
            console.log('requiredUsdValue', Number(res) / 10 ** 8)
        } catch (error) {
            console.log(error)
        }

    });

task("exit", "exit - Withdraw full unlocked balance and earnings, optionally claim pending rewards.")
    .setAction(async (taskArgs, hre) => {
        const {deployer} = await hre.getNamedAccounts();
        const {INCENTIVES_DISTRIBUTOR_ADDRESS} = getConfig(hre.network.name);
        const incentivesDistributor = await hre.ethers.getContractAt('IncentivesDistributor', INCENTIVES_DISTRIBUTOR_ADDRESS)

        try {
            let res = await (await incentivesDistributor.exit(true)).wait(1)
            console.log('exit', res)
        } catch (error) {
            console.log(error)
        }

    });

task("earlyExit", "individualEarlyExit - Withdraw individual unlocked balance and earnings, optionally claim pending rewards.")
    .setAction(async (taskArgs, hre) => {
        const {deployer} = await hre.getNamedAccounts();
        const {INCENTIVES_DISTRIBUTOR_ADDRESS} = getConfig(hre.network.name);
        const incentivesDistributor = await hre.ethers.getContractAt('IncentivesDistributor', INCENTIVES_DISTRIBUTOR_ADDRESS)
        const currentTime = Math.floor(Date.now() / 1000);
        let deadline = currentTime + 60 * 60 * 24 * 1000;

        try {
            let res = await incentivesDistributor.lockedBalances(deployer)
            console.log('lockData', res)
            deadline = res.lockData[0].unlockTime
            console.log("earlyExiting", deadline) // should come from earnedBalances(user)
            res = await (await incentivesDistributor.individualEarlyExit(false, deadline)).wait(1)
            console.log('earlyExit', res)
            res = await incentivesDistributor.lockedBalances(deployer)
            console.log("lockedBalances", res)
        } catch (error) {
            console.log(error)
        }

    });

task("withdraw", "withdraw - Withdraw tokens from earnings and unlocked.")
    .setAction(async (taskArgs, hre) => {
        const {deployer} = await hre.getNamedAccounts();
        const {INCENTIVES_DISTRIBUTOR_ADDRESS} = getConfig(hre.network.name);
        const incentivesDistributor = await hre.ethers.getContractAt('IncentivesDistributor', INCENTIVES_DISTRIBUTOR_ADDRESS)

        try {
            let res = await incentivesDistributor.lockedBalances(deployer)
            console.log('lockedBalances', res)
            const amount = res.unlockable
            console.log('withdrawing', amount)
            res = await (await incentivesDistributor.withdraw(amount)).wait(1)
            console.log('withdraw', res)
            res = await incentivesDistributor.lockedBalances(deployer)
            console.log('lockedBalances', res)
        } catch (error) {
            console.log(error)
        }

    });

task("withdrawlocks", "withdrawExpiredLocksFor - Withdraw all currently locked tokens where the unlock time has passed.")
    .setAction(async (taskArgs, hre) => {
        const {deployer} = await hre.getNamedAccounts();
        const {INCENTIVES_DISTRIBUTOR_ADDRESS} = getConfig(hre.network.name);
        const incentivesDistributor = await hre.ethers.getContractAt('IncentivesDistributor', INCENTIVES_DISTRIBUTOR_ADDRESS)

        try {
            let res = await incentivesDistributor.lockedBalances(deployer)
            console.log('lockedBalances', res)
            res = await (await incentivesDistributor.withdrawExpiredLocksForWithOptions(deployer, 0, true)).wait(1)
            console.log('withdraw', res)
            res = await incentivesDistributor.lockedBalances(deployer)
            console.log('lockedBalances', res)
        } catch (error) {
            console.log(error)
        }

    });

task("setdurations", "set lock/mult/dur of incentives distributor for testing")
    .setAction(async (taskArgs, hre) => {
        if (hre.network.name === 'mainnet') {
            console.log('WARNING - MAINNET SET DURATIONS ABOARDED')
            return
        }
        const {INCENTIVES_DISTRIBUTOR_ADDRESS} = getConfig(hre.network.name);
        const incentivesDistributor = await hre.ethers.getContractAt('IncentivesDistributor', INCENTIVES_DISTRIBUTOR_ADDRESS)
        const day = 60 * 60 * 24
        try {
            await (await incentivesDistributor.setLockTypeInfo([60, 5 * 60, 10 * 60, day], [1, 4, 10, 25])).wait(1);
            await (await incentivesDistributor.setLookback(60)).wait(1);
            await (await incentivesDistributor.setDuration(5 * 60)).wait(1);
            await (await incentivesDistributor.setVestDuration(10 * 60)).wait(1);
        } catch (error) {
            console.log(error)
        }

    });

task("addLiq", "add liq")
    .setAction(async (taskArgs, hre) => {
        const {deployer} = await hre.getNamedAccounts();
        const KAWA_ADDRESS = (await hre.deployments.get('KawaOFT')).address
        const {DRAGONSWAP_ROUTER_ADDRESS, WSEI_ADDRESS,} = getConfig(hre.network.name);
        const wsei = await hre.ethers.getContractAt('IWETH', WSEI_ADDRESS)
        const router = await hre.ethers.getContractAt('IDragonswapRouter', DRAGONSWAP_ROUTER_ADDRESS)
        const kawaOFT = await hre.ethers.getContractAt('KawaOFT', KAWA_ADDRESS)

        const weth = '10000'
        const kawa = '1000000000000000'
        const amountWETHMin = 2
        const amountKawaMin = 2
        const currentTime = Math.floor(Date.now() / 1000);
        const deadline = currentTime + 600;

        try {
            let res
            const balanceOf = await wsei.callStatic.balanceOf(deployer)
            if (balanceOf > 0) {
                res = await (await wsei.withdraw(balanceOf)).wait(1)
                console.log(res)
            }
            res = await (await wsei.deposit({value: weth})).wait(1)
            console.log(res)

            res = await (await wsei.approve(DRAGONSWAP_ROUTER_ADDRESS, weth)).wait(1);
            console.log(res)

            res = await (await kawaOFT.approve(DRAGONSWAP_ROUTER_ADDRESS, kawa)).wait(1);
            console.log(res)

            res = await (await router.addLiquidity(
                WSEI_ADDRESS,
                KAWA_ADDRESS,
                weth,
                kawa,
                amountWETHMin,
                amountKawaMin,
                deployer,
                deadline)).wait(1)
            console.log(res)
        } catch (error) {
            console.log(error)
        }

    });

task("remLiq", "remove liq")
    .setAction(async (taskArgs, hre) => {
        const {deployer} = await hre.getNamedAccounts();
        const {DRAGONSWAP_ROUTER_ADDRESS, KAWA_LP_ADDRESS} = getConfig(hre.network.name);
        const KAWA_ADDRESS = (await hre.deployments.get('KawaOFT')).address

        const lpToken = await hre.ethers.getContractAt('IERC20', KAWA_LP_ADDRESS)
        const router = await hre.ethers.getContractAt('contracts/Incentives/Interfaces/IDragonswapRouter.sol:IDragonswapRouter', DRAGONSWAP_ROUTER_ADDRESS)

        const currentTime = Math.floor(Date.now() / 1000);
        const deadline = currentTime + 600;

        try {
            let res
            const balanceOf = await lpToken.callStatic.balanceOf(deployer)

            console.log('Removing ', balanceOf.toString())

            const allowance = await lpToken.callStatic.allowance(deployer, DRAGONSWAP_ROUTER_ADDRESS)
            if (allowance.lt(balanceOf)) {
                console.log('Approving...')
                res = await (await lpToken.approve(DRAGONSWAP_ROUTER_ADDRESS, MaxUint256)).wait(1);
                console.log(res)
            }

            res = await (await router.removeLiquiditySEI(
                KAWA_ADDRESS,
                balanceOf,
                2,
                2,
                deployer,
                deadline
            )).wait(1)

            console.log(res)
        } catch (error) {
            console.log(error)
        }

    });

task("zapIn", "user lock info of incentives distributor")
    .setAction(async (taskArgs, hre) => {

        const {deployer} = await hre.getNamedAccounts();
        const {LOCK_ZAP_ADDRESS, KAWA_LP_ADDRESS} = getConfig(hre.network.name);
        const KAWA_ADDRESS = (await hre.deployments.get('KawaOFT')).address

        const lockZap = await hre.ethers.getContractAt('LockZap', LOCK_ZAP_ADDRESS)
        const pool = await hre.ethers.getContractAt('IClassicPool', KAWA_LP_ADDRESS)
        const kawaOFT = await hre.ethers.getContractAt('KawaOFT', KAWA_ADDRESS)

        const weth = hre.ethers.BigNumber.from('1000000000000000000')
        const amountWETHMin = 2

        const reserves = await pool.getReserves()
        const token0 = await pool.token0()
        const token1 = await pool.token1()
        console.log('Reserves', token0, token1, reserves)

        try {
            let res

            // res = await (await kawaOFT.approve(LOCK_ZAP_ADDRESS, kawa)).wait(1);
            // console.log(res)

            res = await lockZap.callStatic.zap(
                weth,
                amountWETHMin,
                0,
                0,
                {value: weth}
            )
            console.log(res)
            res = await (await lockZap.zap(
                weth,
                amountWETHMin,
                0,
                0,
                {value: weth}
            )).wait(1)
            console.log(res)
        } catch (error) {
            console.log(error)
        }

    });

task("recover", "recover kawa from lockZap")
    .setAction(async (taskArgs, hre) => {
        const {deployer} = await hre.getNamedAccounts();
        const {LOCK_ZAP_ADDRESS, KAWA_LP_ADDRESS} = getConfig(hre.network.name);
        const KAWA_ADDRESS = (await hre.deployments.get('KawaOFT')).address

        const lockZap = await hre.ethers.getContractAt('LockZap', LOCK_ZAP_ADDRESS)
        const pool = await hre.ethers.getContractAt('IClassicPool', KAWA_LP_ADDRESS)
        const kawaOFT = await hre.ethers.getContractAt('KawaOFT', KAWA_ADDRESS)


        try {
            let res
            res = await kawaOFT.balanceOf(LOCK_ZAP_ADDRESS)
            console.log(res)
            res = await (await lockZap.recoverERC20(KAWA_ADDRESS, res)).wait(1)
            console.log(res)

            // res = await (await lockZap.zap(
            //     weth,
            //     kawa,
            //     0,
            //     0,
            //     amountWETHMin,
            //     amountKawaMin,
            //     deadline,
            //     {value: weth}
            // )).wait(1)
            // console.log(res)
        } catch (error) {
            console.log(error)
        }

    });

task("configComp", "config comptroller")
    .setAction(async ({}, hre) => {

        const {TOKENS} = getConfig(hre.network.name);
        const deployer = (await hre.ethers.getSigners())[0].address;

        const UNITROLLER_ADDRESS = (await hre.deployments.get('Unitroller')).address
        const comptroller = await hre.ethers.getContractAt('Comptroller', UNITROLLER_ADDRESS)

        for (const token of TOKENS) {
            console.log(`Configuring market for ${token.name}`);
            console.log(`==========================================`)
            console.log('')

            const kTokenAddress = (await hre.deployments.get(token.kToken.symbol)).address
            const KErc20Delegator = await hre.ethers.getContractAt('KErc20Delegator', kTokenAddress)

            let seizeShare = ethers.BigNumber.from(token.kToken.seizeShare).mul(ethers.BigNumber.from("10").pow("16"));
            let reserveFactor = ethers.BigNumber.from(token.kToken.reserveFactor).mul(ethers.BigNumber.from("10").pow("16"));

            // console.log(`Setting protocol seize share: ${seizeShare}`);
            // let result = await KErc20Delegator._setProtocolSeizeShare(seizeShare);
            // await result.wait(1);
            let result
            // console.log(`Setting reserve factor: ${reserveFactor}`);
            // result = await KErc20Delegator._setReserveFactor(reserveFactor);
            // await result.wait(1);
            //
            // console.log(`Setting pending admin: ${deployer}`);
            // result = await KErc20Delegator._setPendingAdmin(
            //     deployer
            // );
            // await result.wait(1);
            //
            // console.log(`Configuring Comptroller for ${token.symbol}`);
            // result = await comptroller._supportMarket(kTokenAddress);
            // await result.wait(1);

            let collateralFactorRaw = ethers.BigNumber.from(token.kToken.collateralFactor).mul(ethers.BigNumber.from("10").pow("16"));
            console.log(`Setting collateral factor: ${collateralFactorRaw}`);
            result = await comptroller._setCollateralFactor(
                kTokenAddress,
                collateralFactorRaw
            );
            await result.wait(1);

        }
    })

task("configCompBNB", "config comptroller")
    .setAction(async ({}, hre) => {

        const {TOKENS} = getConfig(hre.network.name);
        const deployer = (await hre.ethers.getSigners())[0].address;

        const UNITROLLER_ADDRESS = (await hre.deployments.get('Unitroller')).address
        const comptroller = await hre.ethers.getContractAt('Comptroller', UNITROLLER_ADDRESS)

        const token = TOKENS.find(t => t.symbol == "BNB");
        console.log(`Configuring market for ${token.name}`);
        console.log(`==========================================`)
        console.log('')

        const kTokenAddress = (await hre.deployments.get(token.kToken.symbol)).address
        const KErc20Delegator = await hre.ethers.getContractAt('KErc20Delegator', kTokenAddress)

        let result
        let seizeShare = ethers.BigNumber.from(token.kToken.seizeShare).mul(ethers.BigNumber.from("10").pow("16"));
        let reserveFactor = ethers.BigNumber.from(token.kToken.reserveFactor).mul(ethers.BigNumber.from("10").pow("16"));

        // console.log(`Setting protocol seize share: ${seizeShare}`);
        // result = await KErc20Delegator._setProtocolSeizeShare(seizeShare);
        // await result.wait(1);

        console.log(`Setting reserve factor: ${reserveFactor}`);
        result = await KErc20Delegator._setReserveFactor(reserveFactor);
        await result.wait(1);

        console.log(`Setting pending admin: ${deployer}`);
        result = await KErc20Delegator._setPendingAdmin(
            deployer
        );
        await result.wait(1);

        console.log(`Configuring Comptroller for ${token.symbol}`);
        result = await comptroller._supportMarket(kTokenAddress);
        await result.wait(1);

        let collateralFactorRaw = ethers.BigNumber.from(token.kToken.collateralFactor).mul(ethers.BigNumber.from("10").pow("16"));
        console.log(`Setting collateral factor: ${collateralFactorRaw}`);
        result = await comptroller._setCollateralFactor(
            kTokenAddress,
            collateralFactorRaw
        );
        await result.wait(1);
    })


task("replayMsgSepolia", "replay msg to message hub sepolia")
    .setAction(async ({}, hre) => {
        if (hre.network.name !== hre.userConfig.defaultNetwork) {
            console.log('\x1b[31m%s\x1b[0m', '\n--------> Wrong network <--------\n')
            return;
        }
        let result
        const commandId = '0xd755b320e70ac22f12a02ca389945dc448f0f07567ae990e2c589dfeb9a9ab68'
        const sourceChain = 'binance'
        const sourceAddress = '0xE82fDEE72c6B7F729c66c281f2CDf33b0B2CF23f'
        const payload = '0x40c10f19000000000000000000000000000000000000000000000000000000000000000000000000000000006027862a465ef7d842e32a8a16a39d4d83c25d3a00000000000000000000000000000000000000000000000000005af3107a4000'
        const kBNBCentralHubAddress = (await hre.deployments.get('kBNBCentralHub')).address
        const kBNBCentralHub = await hre.ethers.getContractAt('CentralHub', kBNBCentralHubAddress)
        result = await kBNBCentralHub.estimateGas.execute(
            commandId,
            sourceChain,
            sourceAddress,
            payload
        )
        console.log(result)
        result = await kBNBCentralHub.callStatic.execute(
            commandId,
            sourceChain,
            sourceAddress,
            payload
        )
        console.log(result)

        // result = await kBNBCentralHub.execute(
        //     commandId,
        //     sourceChain,
        //     sourceAddress,
        //     payload
        // )
        // await result.wait(1);
        // console.log('tx hash: ', result.hash)
    });

task("replayMsgBsc", "replay msg to client bsc")
    .setAction(async ({}, hre) => {
        if (hre.network.name !== 'bscTestnet') {
            console.log('\x1b[31m%s\x1b[0m', '\n--------> Wrong network <--------\n')
            return;
        }
        let result
        const commandId = '0x89d158e6a23e41020a2c015375eee6096687217ddccbf59c73c7fc89bf87ca97'
        const sourceChain = 'ethereum-sepolia'
        const sourceAddress = '0x1362856d8577D8eB638102F8C18eeb716f4a0612'
        const payload = '0x0000000000000000000000006027862a465ef7d842e32a8a16a39d4d83c25d3a000000000000000000000000000000000000000000000000000009184e72a000'


        const {TOKENS} = getConfig(hre.network.name);
        const bnb = TOKENS.find(t => t.symbol == "BNB");
        const KClient = await hre.ethers.getContractAt('KClient', bnb?.kClientImplementation)

        result = await KClient.callStatic.execute(
            commandId,
            sourceChain,
            sourceAddress,
            payload
        )
        console.log(result)

        // result = await KClient.execute(
        //     commandId,
        //     sourceChain,
        //     sourceAddress,
        //     payload
        // )
        // await result.wait(1);
        // console.log('tx hash: ', result.hash)
    });

task("gasEst", "estimate gas to send axelar msg")
    .setAction(async ({}, hre) => {
        const deployer = (await hre.ethers.getSigners())[0].address;
        const kBNBCentralHubAddress = (await hre.deployments.get('kBNBCentralHub')).address
        const kBNBCentralHub = await hre.ethers.getContractAt('CentralHub', kBNBCentralHubAddress)
        let result = await kBNBCentralHub.calculateGas(deployer, '10000000000000', '1000')
        console.log(result)
    });

task("adminWithdraw", "admin withdraw Native")
    .setAction(async ({}, hre) => {
        const {TOKENS} = getConfig(hre.network.name);

        let result
        const bnb = TOKENS.find(t => t.symbol == "BNB");
        let contract
        let contractAddress
        if (hre.network.name == hre.userConfig.defaultNetwork) {
            contractAddress = (await hre.deployments.get('kBNB')).address;
            contract = await hre.ethers.getContractAt("KErc20CrossChainDelegator", contractAddress)
        } else {
            contractAddress = bnb?.kClientImplementation
            contract = await hre.ethers.getContractAt('KClient', contractAddress)
        }
        contract = await hre.ethers.getContractAt('KClient', contractAddress)

        const balance = await hre.ethers.provider.getBalance(contractAddress)
        console.log('Withdraw Native...', balance.toString())
        result = await contract.adminWithdraw(balance)
        await result.wait(1);
        console.log('tx hash: ', result.hash)
    });


task("checkPayload", "check payload return")
    .setAction(async ({}, hre) => {

        let abi
        let iface
        let data
        let result

        const payload = '0x40c10f190000000000000000000000006027862a465ef7d842e32a8a16a39d4d83c25d3a00000000000000000000000000000000000000000000000000005af3107a4000'

        // const kTokenContractAddress = (await hre.deployments.get('kBNB')).address
        // const kToken = await hre.ethers.getContractAt("KErc20Delegator", kTokenContractAddress)

        const types = ["bytes4", "address", "uint256"];
        [selector, sender, amount] = ethers.utils.defaultAbiCoder.decode(types, payload);
        console.log("Selector:", selector);
        console.log("Sender:", sender);
        console.log("Amount:", amount.toString());

        // abi = ["function checkView() view returns (uint)"];
        // iface = new ethers.utils.Interface(abi);
        // data = iface.encodeFunctionData("checkView", []);
        // result = await kToken.delegateToViewImplementation(data)
        // console.log(result)
        // amount = iface.decodeFunctionResult("checkView", result);
        // console.log(amount.toString())


        // abi = ["function checkPayload(bytes calldata payload) view returns (bytes4, address, uint)"];
        // iface = new ethers.utils.Interface(abi);
        // data = iface.encodeFunctionData("checkPayload", [hre.ethers.utils.arrayify(payload)]);
        //
        // result = await kToken.delegateToViewImplementation(data)
        // console.log(result)
        // let [selector, sender, amount] = iface.decodeFunctionResult("checkPayload", result);
        //
        // console.log("Selector:", selector);
        // console.log("Sender:", sender);
        // console.log("Amount:", amount.toString());

        abi = ["function checkPayload2(bytes calldata payload) view returns (address, uint)"];
        iface = new ethers.utils.Interface(abi);
        data = iface.encodeFunctionData("checkPayload2", [hre.ethers.utils.arrayify(payload)]);

        result = await kToken.delegateToViewImplementation(data)
        console.log(result)
        let [sender, amount] = iface.decodeFunctionResult("checkPayload2", result);
        console.log("Sender:", sender);
        console.log("Amount:", amount.toString());

    });

task("checkBalance", "check balance of kBNB")
    .setAction(async ({}, hre) => {

        const bnbAddress = (await hre.deployments.get('BNB')).address
        const kbnbAddress = (await hre.deployments.get('kBNB')).address

        const BNB = await hre.ethers.getContractAt('WErc20', bnbAddress)
        let result = await BNB.balanceOf(kbnbAddress)
        console.log(result)
    });

task("balances", "deposit ETH")
    .setAction(async ({}, hre) => {
        const {WETH_ADDRESS} = getConfig(hre.network.name);
        const deployer = ((await hre.ethers.getSigners())[0]).address
        const kethAddress = (await hre.deployments.get('kETH')).address
        const weth = await hre.ethers.getContractAt('WErc20', WETH_ADDRESS)

        let res = await weth.balanceOf(kethAddress)
        console.log('kethAddress balance', res)
        res = await weth.balanceOf(deployer)
        console.log('deployer balance', res)

        const kbnbAddress = (await hre.deployments.get('kBNB')).address
        const kbnb = await hre.ethers.getContractAt('KErc20Delegator', kbnbAddress)
        const werc20Address = await kbnb.underlying()
        const wErc20 = await hre.ethers.getContractAt('WErc20', werc20Address)
        res = await wErc20.balanceOf(kbnbAddress)
        console.log('kbnb balance', res)
    });

task("lzgas", 'change lz gas limit')
    .setAction(async ({}, hre) => {
        const gasLimit = 600000
        const NATIVE_SYMBOL = "SEI"

        const {TOKENS} = getConfig(hre.network.name);
        const tokens = TOKENS.filter(r => r.symbol !== NATIVE_SYMBOL)
        const adapterTypes = ['LayerZero']
        for (const token of tokens) {
            for (const adapterType of adapterTypes) {
                const adapterName = token.kToken.symbol + 'Adapter' + adapterType
                console.log(`Configuring ${adapterName}...`)
                const adapterAddress = (await hre.deployments.get(adapterName)).address
                const adapter = await hre.ethers.getContractAt('Adapter' + adapterType, adapterAddress)
                let result = await adapter._setGasLimit(gasLimit)
                await result.wait(1)
            }
        }
    });


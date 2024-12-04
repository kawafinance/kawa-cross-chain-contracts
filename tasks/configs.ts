import {task} from "hardhat/config";
import {getConfig} from "../config";

task("configOracle", "config oracle")
    .setAction(async (taskArgs, hre) => {

        const pythOracleAddress = (await hre.deployments.get('PythOracle')).address
        const pythOracle = await hre.ethers.getContractAt('PythOracle', pythOracleAddress)
        console.log('pythOracle: ', pythOracleAddress)

        const kUSDCAddress = (await hre.deployments.get('kUSDC')).address
        console.log('kUSDC: ', kUSDCAddress)
        const KErc20Delegator = await hre.ethers.getContractAt('KErc20Delegator', kUSDCAddress)
        const underlyingAddress = await KErc20Delegator.underlying()
        console.log('underlying', underlyingAddress)

        const unitrollerAddress = (await hre.deployments.get('Unitroller')).address
        console.log('Unitroller: ', unitrollerAddress)
        const Comptroller = await hre.ethers.getContractAt('Comptroller', unitrollerAddress)

        let results

        // console.log('Set direct prices')
        // results = await pythOracle.setDirectPrice(ETH_ADDRESS, '150000000000000000000') // 150*1e18
        // results.wait(1)
        results = await pythOracle.setDirectPrice(underlyingAddress, 0) // 1e18
        results.wait(1)

        const {TOKENS} = getConfig(hre.network.name);

        const priceFeedTokens = TOKENS.map(token => {
            return {
                contractAddress: token.contractAddress,
                priceFeed: token.priceFeed
            }
        })
        await pythOracle.updatePythPriceIds(priceFeedTokens.map(r => r.contractAddress), priceFeedTokens.map(r => r.priceFeed))

        // for (const token of TOKENS) {
        //     try {
        //         const kTokenAddress = (await hre.deployments.get(token.kToken.symbol)).address
        //         let collateralFactorRaw = ethers.BigNumber.from(token.kToken.collateralFactor).mul(ethers.BigNumber.from("10").pow("16"));
        //         console.log(`Setting collateral factor for ${token.kToken.symbol}: ${collateralFactorRaw}`);
        //         results = await Comptroller._setCollateralFactor(
        //             kTokenAddress,
        //             collateralFactorRaw
        //         );
        //     } catch (e) {
        //         console.log(token.symbol, 'failed: ', e)
        //     }
        // }

        console.log('Check SEI')
        const kSEIAddress = (await hre.deployments.get('kSEI')).address
        results = await pythOracle.getUnderlyingPrice(kSEIAddress)
        console.log('price sei: ', results)

        console.log('Check USDC')
        results = await pythOracle.getUnderlyingPrice(kUSDCAddress)
        console.log('price usdc: ', results)
    });

task("configIncentivesController", "config incentives controller for all tokens")
    .setAction(async (taskArgs, hre) => {
        const {TOKENS, INCENTIVES_CONTROLLER_ADDRESS} = getConfig(hre.network.name);

        for (const token of TOKENS) {
            const kTokenAddress = (await hre.deployments.get(token.kToken.symbol)).address
            const kToken = await hre.ethers.getContractAt('KToken', kTokenAddress)
            console.log('Setting IncentiveController for', token.kToken.symbol);
            await (await kToken._setIncentivesController(INCENTIVES_CONTROLLER_ADDRESS)).wait(1)
        }
    });

// task("configIncentivesDistributor", "configure incentives distributor")
//     .setAction(async (taskArgs, hre) => {
//         const {
//             PRICE_PROVIDER_ADDRESS,
//             INCENTIVES_CONTROLLER_ADDRESS,
//             REWARDS_CONTROLLER_ADDRESS,
//             INCENTIVES_DISTRIBUTOR_ADDRESS
//         } = getConfig(hre.network.name);
//
//         const incentivesDistributor = await hre.ethers.getContractAt('IncentivesDistributor', INCENTIVES_DISTRIBUTOR_ADDRESS)
//
//         await incentivesDistributor.setPriceProvider
//
//     });
import {task} from "hardhat/config";
import {getConfig} from "../config";
import * as ethers from "ethers";
import {delay} from "../deploy_all/utils_func";

task("disableBorrowAll", "disable Borrow on all markets")
    .setAction(async (taskArgs, hre) => {
        const {TOKENS} = getConfig(hre.network.name);
        const UNITROLLER_ADDRESS = (await hre.deployments.get('Unitroller')).address
        const comptroller = await hre.ethers.getContractAt('Comptroller', UNITROLLER_ADDRESS)

        for (const token of TOKENS) {
            console.log(`Configuring market for ${token.name}`);
            console.log(`==========================================`)
            console.log('')
            const kTokenAddress = (await hre.deployments.get(token.kToken.symbol)).address

            console.log(`Deactivating borrow: ${token.kToken.symbol}`);
            let result = await comptroller._setBorrowPaused(
                kTokenAddress,
                true
            );
            await result.wait(1);

            let collateralFactorRaw = ethers.BigNumber.from(0);

            console.log(`Setting collateral factor: ${collateralFactorRaw}`);
            result = await comptroller._setCollateralFactor(
                kTokenAddress,
                collateralFactorRaw
            );
            await result.wait(1);
            console.log('')
        }
    })

task("enableBorrow", "enable Borrow on all markets")
    .addParam("symbol", "token symbol")
    .setAction(async ({symbol}, hre) => {

        const {TOKENS} = getConfig(hre.network.name);
        const token = TOKENS.find(t => t.symbol == symbol);
        if (!token) {
            console.log(`Token ${symbol} not found)`)
            return
        }

        const UNITROLLER_ADDRESS = (await hre.deployments.get('Unitroller')).address
        const comptroller = await hre.ethers.getContractAt('Comptroller', UNITROLLER_ADDRESS)

        console.log(`Configuring market for ${token.name}`);
        console.log(`==========================================`)
        console.log('')
        const kTokenAddress = (await hre.deployments.get(token.kToken.symbol)).address
        const borrowGuardianPaused = await comptroller.borrowGuardianPaused(kTokenAddress)
        // console.log('borrowGuardianPaused:\t', borrowGuardianPaused)
        let result
        if (borrowGuardianPaused) {
            console.log(`Activating borrow: ${token.kToken.symbol}`);
            result = await comptroller._setBorrowPaused(
                kTokenAddress,
                false
            );
            await result.wait(1);
        }
        let collateralFactorRaw = ethers.BigNumber.from(token.collateralFactor).mul(ethers.BigNumber.from("10").pow("16"));

        console.log(`Setting collateral factor: ${collateralFactorRaw}`);
        result = await comptroller._setCollateralFactor(
            kTokenAddress,
            collateralFactorRaw
        );
        await result.wait(1);
        console.log('')

        let borrowCap = ethers.BigNumber.from(token.borrowCap).mul(ethers.BigNumber.from("10").pow(token.decimals));

        console.log(`Setting borrow cap: ${borrowCap}`);
        result = await comptroller._setMarketBorrowCaps(
            [kTokenAddress],
            [borrowCap]
        );
        await result.wait(1);
    })

task("enableBorrowAll", "enable Borrow on all markets")
    .setAction(async (taskArgs, hre) => {
        const {TOKENS} = getConfig(hre.network.name);
        const UNITROLLER_ADDRESS = (await hre.deployments.get('Unitroller')).address
        const comptroller = await hre.ethers.getContractAt('Comptroller', UNITROLLER_ADDRESS)

        for (const token of TOKENS) {
            console.log(`Configuring market for ${token.name}`);
            console.log(`==========================================`)
            console.log('')
            const kTokenAddress = (await hre.deployments.get(token.kToken.symbol)).address
            const borrowGuardianPaused = await comptroller.borrowGuardianPaused(kTokenAddress)
            // console.log('borrowGuardianPaused:\t', borrowGuardianPaused)
            let result
            if (borrowGuardianPaused) {
                console.log(`Activating borrow: ${token.kToken.symbol}`);
                result = await comptroller._setBorrowPaused(
                    kTokenAddress,
                    false
                );
                await result.wait(1);
            }
            let collateralFactorRaw = ethers.BigNumber.from(token.collateralFactor).mul(ethers.BigNumber.from("10").pow("16"));

            console.log(`Setting collateral factor: ${collateralFactorRaw}`);
            result = await comptroller._setCollateralFactor(
                kTokenAddress,
                collateralFactorRaw
            );
            await result.wait(1);
            console.log('')

            let borrowCap = ethers.BigNumber.from(token.borrowCap).mul(ethers.BigNumber.from("10").pow(token.decimals));

            console.log(`Setting borrow cap: ${borrowCap}`);
            result = await comptroller._setMarketBorrowCaps(
                [kTokenAddress],
                [borrowCap]
            );
            await result.wait(1);
        }
    })

task("collateralFactorAll", "enable collateral factor on all markets")
    .setAction(async (taskArgs, hre) => {
        const {TOKENS} = getConfig(hre.network.name);
        const UNITROLLER_ADDRESS = (await hre.deployments.get('Unitroller')).address
        const comptroller = await hre.ethers.getContractAt('Comptroller', UNITROLLER_ADDRESS)

        for (const token of TOKENS) {
            console.log(`Configuring market for ${token.name}`);
            console.log(`==========================================`)
            console.log('')
            const kTokenAddress = (await hre.deployments.get(token.kToken.symbol)).address
            let collateralFactorRaw = ethers.BigNumber.from(token.collateralFactor).mul(ethers.BigNumber.from("10").pow("16"));

            console.log(`Setting collateral factor: ${collateralFactorRaw}`);
            let result = await comptroller._setCollateralFactor(
                kTokenAddress,
                collateralFactorRaw
            );
            await result.wait(1);

            let borrowCap = ethers.BigNumber.from(token.borrowCap).mul(ethers.BigNumber.from("10").pow(token.decimals));

            console.log(`Setting borrow cap: ${borrowCap}`);
            result = await comptroller._setMarketBorrowCaps(
                [kTokenAddress],
                [borrowCap]
            );
            await result.wait(1);
            console.log('')
        }
    })

task("deployMarkets", "run Deploy_Markets script")
    .setAction(async ({}, hre) => {

        await hre.run("compile")

        const configScripts = [
            "../deploy_all/Deploy_Markets.ts"
        ];

        for (const script of configScripts) {
            console.log("")
            console.log(`\t\t\t\tRunning ${script}...`);
            console.log("")

            const deployFunction = require(script).default;

            await deployFunction(hre);

            await delay(5000);
        }
    })
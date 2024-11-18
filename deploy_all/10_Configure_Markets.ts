import * as ethers from "ethers";
import {HardhatRuntimeEnvironment} from "hardhat/types";
import {getConfig} from '../config'

const func = async function (hre: HardhatRuntimeEnvironment) {

    const {TOKENS} = getConfig(hre.network.name);
    const deployer = (await hre.ethers.getSigners())[0].address;

    const UNITROLLER_ADDRESS =  (await hre.deployments.get('Unitroller')).address
    const comptroller = await hre.ethers.getContractAt('Comptroller', UNITROLLER_ADDRESS)

    console.log('Updating Pyth Prices...')
    await hre.run("updatePrices");

    for (const token of TOKENS) {

        console.log(`Configuring market for ${token.name}`);
        console.log(`==========================================`)
        console.log('')

        const kTokenAddress = (await hre.deployments.get(token.kToken.symbol)).address
        const KErc20Delegator = await hre.ethers.getContractAt('KErc20Delegator', kTokenAddress)

        let seizeShare = ethers.BigNumber.from(token.kToken.seizeShare).mul(ethers.BigNumber.from("10").pow("16"));
        let reserveFactor = ethers.BigNumber.from(token.kToken.reserveFactor).mul(ethers.BigNumber.from("10").pow("16"));

        let result

        console.log(`Setting protocol seize share: ${seizeShare}`);
        result = await KErc20Delegator._setProtocolSeizeShare(seizeShare);
        await result.wait(3);

        console.log(`Setting reserve factor: ${reserveFactor}`);
        result = await KErc20Delegator._setReserveFactor(reserveFactor);
        await result.wait(3);

        console.log(`Setting pending admin: ${deployer}`);
        result = await KErc20Delegator._setPendingAdmin(
            deployer
        );
        await result.wait(3);

        console.log(`Configuring Comptroller for ${token.symbol}`);
        result = await comptroller._supportMarket(kTokenAddress);
        await result.wait(3);

        let collateralFactorRaw = ethers.BigNumber.from(token.kToken.collateralFactor).mul(ethers.BigNumber.from("10").pow("16"));
        console.log(`Setting collateral factor: ${collateralFactorRaw}`);
        result = await comptroller._setCollateralFactor(
            kTokenAddress,
            collateralFactorRaw
        );
        await result.wait(3);
    }

}

export default func

func.tags = ['PythOracle']
func.dependencies = ['Unitroller', 'kSEI', 'kTokens']



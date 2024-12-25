
import * as ethers from "ethers";
import {HardhatRuntimeEnvironment} from "hardhat/types";
import {readFile, readFileSync, existsSync, writeFileSync} from "fs";
import {getConfig} from '../config'
import {Artifacts} from "../config/types";
import {MaxUint256} from "@ethersproject/constants";

const func = async function (hre: HardhatRuntimeEnvironment) {

    const {PYTH_ADDRESS, TOKENS} = getConfig(hre.network.name);
    const BURN_ADDRESS = '0x000000000000000000000000000000000000dEaD'

    if (!PYTH_ADDRESS) {
        console.log('Missing configuration... [PYTH_ADDRESS]')
        return;
    }

    const deployer = (await hre.ethers.getSigners())[0].address;

    const UNITROLLER_ADDRESS =  (await hre.deployments.get('Unitroller')).address

    console.log("=== Deploying PythOracle  ===");

    const pythOracle = await hre.deployments.deploy('PythOracle', {
        from: deployer,
        args: [PYTH_ADDRESS],
        log: true,
        deterministicDeployment: false,
    });

    // await hre.run('verify:verify', {
    //   address: pythOracle.address,
    //   contract: fullyQualifiedName,
    //   constructorArguments: [PYTH_ADDRESS]
    // })

    console.log(`PythOracle deployed: ${pythOracle.address}\n`);

    console.log("Setting price oracle");

    const comptroller = await hre.ethers.getContractAt('Comptroller', UNITROLLER_ADDRESS)
    const setPriceOracleResult = await comptroller._setPriceOracle(pythOracle.address);
    await setPriceOracleResult.wait(3);

    console.log("=== Configuring PythOracle ===");

    const priceFeedTokens = []
    for (let token of TOKENS){
        let contractAddress = token.contractAddress
        if (!contractAddress){
            contractAddress = (await hre.deployments.get(token.symbol)).address;
        }
        priceFeedTokens.push({
            contractAddress,
            priceFeed: token.priceFeed
        });
    }

    const pythOracleContract = await hre.ethers.getContractAt('PythOracle', pythOracle.address)
    // @ts-ignore
    const result = await pythOracleContract.updatePythPriceIds(priceFeedTokens.map(r => r.contractAddress), priceFeedTokens.map(r => r.priceFeed))
    await result.wait(3)
}

export default func

func.tags = ['PythOracle']
func.dependencies = ['Unitroller', 'kSEI', 'kTokens']



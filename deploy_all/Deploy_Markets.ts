import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {delay} from "./utils_func";

const func = async function (hre: HardhatRuntimeEnvironment) {

    console.log('Deploying Market')

    const deploy_allScripts = [
        "../deploy_all/00_Deploy_MessageHubs.ts",
        "../deploy_all/07_Deploy_kTokens.ts",
        "../deploy_all/08_Deploy_PythOracle.ts",
        "../deploy_all/10_Configure_Markets.ts",
        "../deploy_all/30_Configure_MessageHubs.ts"
    ];

    for (const script of deploy_allScripts) {
        console.log("")
        console.log(`\t\t\t\tRunning ${script}...`);
        console.log("")

        const deployFunction = require(script).default;

        await deployFunction(hre);

        await delay(5000);
    }

    console.log("All deploy scripts executed.");
};

export default func
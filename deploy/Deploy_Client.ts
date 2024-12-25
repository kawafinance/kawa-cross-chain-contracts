import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {delay} from "../deploy_all/utils_func";

const func = async function (hre: HardhatRuntimeEnvironment) {

    if(hre.network.name === hre.userConfig.defaultNetwork){
        console.log('Skipping Deploy Client for Main network')
        return
    }

    const deploy_allScripts = [
        "../deploy_all/00_Deploy_MessageHubs.ts",
        "../deploy_all/20_Deploy_KClientDelegate.ts",
        "../deploy_all/21_Deploy_KClient.ts",
        "../deploy_all/30_Configure_MessageHubs.ts",
    ];

    for (const script of deploy_allScripts) {
        console.log(`\t\t\t\tRunning ${script}...`);

        const deployFunction = require(script).default;
        await deployFunction(hre);

        await delay(5000);
    }

    console.log("All deploy scripts executed.");
};

export default func
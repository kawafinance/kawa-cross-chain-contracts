import {HardhatRuntimeEnvironment} from 'hardhat/types';

const func = async function (hre: HardhatRuntimeEnvironment) {

    if(hre.network.name !== 'bnbTestnet'){
        console.log('Skipping Deploy Client for Main network')
        return
    }

    const deploy_allScripts = [
        "../deploy_all/20_Deploy_KClientDelegate.ts",
        "../deploy_all/21_Deploy_KClient.ts",
        "../deploy_all/30_Configure_MessageHubs.ts",
    ];

    const delay = (ms) => {
        return new Promise(resolve => setTimeout(resolve, ms));
    }

    for (const script of deploy_allScripts) {
        console.log(`Running ${script}...`);

        const deployFunction = require(script).default;
        await deployFunction(hre);

        await delay(5000);
    }

    console.log("All deploy scripts executed.");
};

export default func
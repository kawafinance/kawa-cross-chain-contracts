import {HardhatRuntimeEnvironment} from 'hardhat/types';

const func = async function (hre: HardhatRuntimeEnvironment) {

    if(hre.network.name !== 'sepolia'){
        console.log('Skipping Deploy Protocol for Client network')
        return
    }

    const deploy_allScripts = [
        "../deploy_all/01_Deploy_Unitroller.ts",
        "../deploy_all/02_Deploy_Comptroller.ts",
        "../deploy_all/03_Deploy_JumpRateModel.ts",
        "../deploy_all/04_Deploy_KWethDelegate.ts",
        "../deploy_all/05_Deploy_KErc20CrossChainDelegate.ts",
        "../deploy_all/06_Deploy_kNative.ts",
        "../deploy_all/07_Deploy_kTokens.ts",
        "../deploy_all/08_Deploy_PythOracle.ts",
        "../deploy_all/09_Deploy_WETHRouter.ts",
        "../deploy_all/10_Configure_Markets.ts",
        "../deploy_all/30_Configure_MessageHubs.ts"
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
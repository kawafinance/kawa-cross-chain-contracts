import {HardhatRuntimeEnvironment} from 'hardhat/types';

const func = async function (hre: HardhatRuntimeEnvironment) {

    console.log('Deploying Multicall3...')

    const deployer = (await hre.ethers.getSigners())[0].address;

    const deployment = await hre.deployments.deploy('Multicall3', {
        from: deployer,
        args: [],
        log: true,
        deterministicDeployment: false,
    });

    console.log('Successfully deployed Multicall3 at ' + deployment.address)
};

export default func
func.tags = ['Multicall3'];




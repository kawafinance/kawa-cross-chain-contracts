import {HardhatRuntimeEnvironment} from "hardhat/types";
import {getConfig} from '../config'

const func = async function (hre: HardhatRuntimeEnvironment) {

    const NATIVE_SYMBOL = "ETH"

    const {TOKENS} = getConfig(hre.network.name);
    const KCLIENT_DELEGATE_ADDRESS = (await hre.deployments.get('KClientDelegate')).address

    const deployer = (await hre.ethers.getSigners())[0].address;

    const tokens = TOKENS.filter(r => r.symbol !== NATIVE_SYMBOL)

    let result

    for (const token of tokens) {

        console.log("=== Deploying " + token.kToken.symbol + "Client implementation ===");
        let centralHubAddress = "0x0000000000000000000000000000000000000000"
        try {
            centralHubAddress = (await hre.deployments.get(token.kToken.symbol + "CentralHub")).address
        } catch (error) {
            console.log('centralHubAddress not found. Using', centralHubAddress);
        }

        const deploymentArgs = [
            centralHubAddress,
            deployer,
            KCLIENT_DELEGATE_ADDRESS,
            "0x00"
        ]

        const kTokenContract = await hre.deployments.deploy(token.kToken.symbol + "Client", {
            from: deployer,
            contract: 'KClientDelegator',
            args: deploymentArgs,
            log: true,
            deterministicDeployment: false,
        });
        console.log(`Deployed a ${token.kToken.symbol}Client at : ${kTokenContract.address}\n`);

        if(centralHubAddress !== "0x0000000000000000000000000000000000000000"){
            console.log(`Configuring ${token.kToken.symbol}CentralHub for ${token.kToken.name}...\n`);
            const CentralHubContract = await hre.ethers.getContractAt("CentralHub", centralHubAddress)
            result = await CentralHubContract._setKToken(kTokenContract.address);
            await result.wait(1);
        }
    }
}

export default func
func.tags = ['KClient']



import * as ethers from "ethers";
import {HardhatRuntimeEnvironment} from "hardhat/types";
import {readFileSync} from "fs";
import {getConfig} from '../config'
import path from "path";

function getDeploymentAddress(networkName, contractName) {
    try {
        // Construct the path to the deployment file
        const deploymentPath = path.resolve(
            process.cwd(),
            `deployments/${networkName}/${contractName}.json`
        );

        // Read and parse the deployment file
        const deploymentData = JSON.parse(readFileSync(deploymentPath, "utf-8"));
        return deploymentData.address;
    } catch (error) {
        // Return the zero address if deployment data is not found
        return "0x0000000000000000000000000000000000000000";
    }
}

const func = async function (hre: HardhatRuntimeEnvironment) {

    const {TOKENS} = getConfig(hre.network.name);

    let result

    const otherClientTag = hre.network.name === 'sepolia' ? 'Client' : ''
    for (const token of TOKENS) {
        const otherChain = token.otherChain === 'binance'
            ? 'bnbTestnet'
            : token.otherChain === 'ethereum-sepolia'
                ? 'sepolia'
                : token.otherChain

        let clientContractAddress = getDeploymentAddress(otherChain, token.kToken.symbol + "MessageHub" + clientTag);
        if (clientContractAddress !== '') {
            console.log(`Configuring ${token.kToken.symbol}MessageHub${clientTag} for ${token.kToken.name}...\n`);
            const messageHubAddress = (await hre.deployments.get(token.kToken.symbol + "MessageHubClient")).address;
            const MessageHubContract = await hre.ethers.getContractAt("MessageHubClient", messageHubAddress)
            result = await MessageHubContract._setClientContract(token.otherChainMessageHub);
            await result.wait(1);
        } else {
            console.log(token.kToken.symbol, "OtherChainContract not found.");
        }

    }

}

export default func



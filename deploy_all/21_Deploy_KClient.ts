import * as ethers from "ethers";
import {HardhatRuntimeEnvironment} from "hardhat/types";
import {readFile, readFileSync, existsSync, writeFileSync} from "fs";
import {getConfig} from '../config'
import {Artifacts} from "../config/types";
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

    const NATIVE_SYMBOL = "ETH"

    const {TOKENS, AXELAR_GATEWAY, AXELAR_GAS_RECEIVER} = getConfig(hre.network.name);
    const KCLIENT_DELEGATE_ADDRESS = (await hre.deployments.get('KClientDelegate')).address

    const deployer = (await hre.ethers.getSigners())[0].address;

    const tokens = TOKENS.filter(r => r.symbol !== NATIVE_SYMBOL)

    let result

    for (const token of tokens) {
        console.log("=== Deploying " + token.kToken.symbol + "MessageHubClient ===");
        let otherChain = token.otherChain === 'ethereum-sepolia' ? 'sepolia' : token.otherChain
        let clientContract = getDeploymentAddress(otherChain, token.kToken.symbol + "MessageHubClient");

        const messageHubArgs = [
            "0x0000000000000000000000000000000000000000",
            AXELAR_GATEWAY,
            AXELAR_GAS_RECEIVER,
            clientContract,
            token.otherChain
        ]

        const messageHub = await hre.deployments.deploy(token.kToken.symbol + "MessageHubClient", {
            from: deployer,
            contract: 'MessageHubClient',
            args: messageHubArgs,
            log: true,
            deterministicDeployment: false,
        });

        console.log(`Deployed ${token.kToken.symbol}MessageHubClient at : ${messageHub.address}\n`);

        console.log("=== Deploying " + token.kToken.symbol + "Client implementation ===");

        const deploymentArgs = [
            messageHub.address,
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

        console.log(`Configuring ${token.kToken.symbol}MessageHubClient for ${token.kToken.name}...\n`);
        const MessageHubContract = await hre.ethers.getContractAt("MessageHubClient", messageHub.address)
        result = await MessageHubContract._setKToken(kTokenContract.address);
        await result.wait(1);
    }
}

export default func
func.tags = ['KClient']



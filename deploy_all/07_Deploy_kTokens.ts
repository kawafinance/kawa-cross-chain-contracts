import * as ethers from "ethers";
import {HardhatRuntimeEnvironment} from "hardhat/types";
import {readFile, readFileSync, existsSync, writeFileSync} from "fs";
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

    const NATIVE_SYMBOL = "ETH"

    const {TOKENS, AXELAR_GATEWAY, AXELAR_GAS_RECEIVER} = getConfig(hre.network.name);

    const UNITROLLER_ADDRESS = (await hre.deployments.get('Unitroller')).address
    const JUMPRATEMODEL_ADDRESS = (await hre.deployments.get('JumpRateModel')).address
    const KERC20_CROSSCHAIN_DELEGATE_ADDRESS = (await hre.deployments.get('KErc20CrossChainDelegate')).address

    const deployer = (await hre.ethers.getSigners())[0].address;

    const tokens = TOKENS.filter(r => r.symbol !== NATIVE_SYMBOL)

    let result

    for (const token of tokens) {

        const initialExchangeRateMantissa = ethers.BigNumber.from("10").pow(token.decimals + 8).mul("2");

        let underlyingContractAddress = token.contractAddress
        if (!underlyingContractAddress) {
            console.log("Missing contract address for " + token.symbol);
            console.log("=== Deploying " + token.symbol + " implementation ===");
            const underlyingArguments = [
                token.name,
                token.symbol
            ]

            const underlyingContract = await hre.deployments.deploy(token.symbol, {
                from: deployer,
                contract: 'WErc20',
                args: underlyingArguments,
                log: true,
                deterministicDeployment: false,
            });

            // const Underlying = await hre.ethers.getContractFactory("WErc20");
            // const underlyingContract = await hre.upgrades.deployProxy(Underlying, underlyingArguments, { initializer: 'initialize'});

            console.log(`Deployed a ${token.symbol} at : ${underlyingContract.address}\n`);

            underlyingContractAddress = underlyingContract.address
        }

        console.log("=== Deploying " + token.kToken.symbol + "MessageHub ===");

        let otherChain = token.otherChain === 'binance' ? 'bnbTestnet' : token.otherChain
        let clientContract = getDeploymentAddress(otherChain, token.kToken.symbol + "MessageHubClient");

        const messageHubArgs = [
            "0x0000000000000000000000000000000000000000",
            AXELAR_GATEWAY,
            AXELAR_GAS_RECEIVER,
            clientContract,
            token.otherChain
        ]

        const messageHub = await hre.deployments.deploy(token.kToken.symbol + "MessageHub", {
            from: deployer,
            contract: 'MessageHub',
            args: messageHubArgs,
            log: true,
            deterministicDeployment: false,
        });

        console.log(`Deployed ${token.kToken.symbol}MessageHub at : ${messageHub.address}\n`);

        console.log("=== Deploying " + token.kToken.symbol + " implementation ===");

        const deploymentArgs = [
            underlyingContractAddress,
            UNITROLLER_ADDRESS,
            JUMPRATEMODEL_ADDRESS,
            initialExchangeRateMantissa,
            token.kToken.name,
            token.kToken.symbol,
            ethers.BigNumber.from("8"),
            messageHub.address,
            deployer,
            KERC20_CROSSCHAIN_DELEGATE_ADDRESS,
            "0x00"
        ]

        const kTokenContract = await hre.deployments.deploy(token.kToken.symbol, {
            from: deployer,
            contract: 'KErc20CrossChainDelegator',
            args: deploymentArgs,
            log: true,
            deterministicDeployment: false,
        });

        // await hre.run('verify:verify', {
        //     address: kTokenContract.address,
        //     contract: fullyQualifiedName,
        //     constructorArguments: deploymentArgs
        // })

        console.log(`Deployed a ${token.kToken.symbol} at : ${kTokenContract.address}\n`);

        console.log(`Setting ownership...`);
        const UnderlyingContract = await hre.ethers.getContractAt("WErc20", underlyingContractAddress)
        result = await UnderlyingContract.transferOwnership(kTokenContract.address);
        await result.wait(1);

        console.log(`Configuring ${token.kToken.symbol}MessageHub for ${token.kToken.name}...\n`);
        const MessageHubContract = await hre.ethers.getContractAt("MessageHub", messageHub.address)
        result = await MessageHubContract._setKToken(kTokenContract.address);
        await result.wait(1);

        try {
            const configFilePath = `./config/bnbTestnet.ts`;
            let content = readFileSync(configFilePath, 'utf8');
            const regex = /otherChainMessageHub:\s*\S+/g;
            content = content.replace(regex, `otherChainMessageHub: "${messageHub.address}",`);
            writeFileSync(configFilePath, content, 'utf8');
            console.log('Config file updated successfully.');
        } catch (error) {
            console.error('Error modifying config:', error);
        }
    }
}

export default func
func.tags = ['kTokens']
func.dependencies = ['Unitroller', 'JumpRateModel', 'KErc20CrossChainDelegate']



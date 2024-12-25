import * as ethers from "ethers";
import {HardhatRuntimeEnvironment} from "hardhat/types";
import {getConfig} from '../config'


const func = async function (hre: HardhatRuntimeEnvironment) {

    const NATIVE_SYMBOL = "SEI"

    const {TOKENS} = getConfig(hre.network.name);

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

        console.log("=== Deploying " + token.kToken.symbol + " implementation ===");
        let centralHubAddress = "0x0000000000000000000000000000000000000000"
        try {
            centralHubAddress = (await hre.deployments.get(token.kToken.symbol + "CentralHub")).address
        } catch (error) {
            console.log('centralHubAddress not found. Using', centralHubAddress);
        }

        const deploymentArgs = [
            underlyingContractAddress,
            UNITROLLER_ADDRESS,
            JUMPRATEMODEL_ADDRESS,
            initialExchangeRateMantissa,
            token.kToken.name,
            token.kToken.symbol,
            ethers.BigNumber.from("8"),
            centralHubAddress,
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

        if (centralHubAddress !== "0x0000000000000000000000000000000000000000") {
            console.log(`Configuring ${token.kToken.symbol}CentralHub for ${token.kToken.name}...\n`);
            const CentralHubContract = await hre.ethers.getContractAt("CentralHub", centralHubAddress)
            result = await CentralHubContract._setKToken(kTokenContract.address);
            await result.wait(1);
        }

        // try {
        //     const configFilePath = `./config/bscTestnet.ts`;
        //     let content = readFileSync(configFilePath, 'utf8');
        //     const regex = /otherChainCentralHub:\s*\S+/g;
        //     content = content.replace(regex, `otherChainCentralHub: "${centralHub.address}",`);
        //     writeFileSync(configFilePath, content, 'utf8');
        //     console.log('Config file updated successfully.');
        // } catch (error) {
        //     console.error('Error modifying config:', error);
        // }
    }
}

export default func
func.tags = ['kTokens']
func.dependencies = ['Unitroller', 'JumpRateModel', 'KErc20CrossChainDelegate']



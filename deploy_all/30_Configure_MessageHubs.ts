import {HardhatRuntimeEnvironment} from "hardhat/types";
import {getConfig} from '../config'
import {getDeploymentAddress} from "./utils_func";


const func = async function (hre: HardhatRuntimeEnvironment) {

    const NATIVE_SYMBOL = "ETH"
    const {TOKENS} = getConfig(hre.network.name);
    const tokens = TOKENS.filter(r => r.symbol !== NATIVE_SYMBOL)

    let contractName
    let contractAddress
    let contract
    let argAddress
    let result
    let checkAddress
    const otherChain = hre.network.name === 'sepolia'
        ? 'bnbTestnet'
        : 'sepolia'
    const clientTag = hre.network.name === 'sepolia' ? '' : 'Client'

    for (const token of tokens) {

        const tokenContractName = token.kToken.symbol + clientTag
        const centralHubContractName = token.kToken.symbol + 'CentralHub'

        console.log(`Configuring ${tokenContractName} Messaging Hubs...`);

        let tokenContractAddress
        try {
            tokenContractAddress = (await hre.deployments.get(tokenContractName)).address;
        } catch (e) {
            console.log('tokenContract address not found.');
        }

        let centralHubContractAddress
        try {
            centralHubContractAddress = (await hre.deployments.get(centralHubContractName)).address;
        } catch (e) {
            console.log('centralHubContract address not found.');
        }

        if(tokenContractAddress && centralHubContractAddress) {

            contract = await hre.ethers.getContractAt(
                hre.network.name === 'sepolia'
                    ? 'KErc20CrossChainDelegator'
                    : 'KClientDelegator',
                tokenContractAddress
            )
            checkAddress = await contract.centralHub()
            if(checkAddress !== centralHubContractAddress) {
                console.log(`Configuring ${tokenContractName}... ${centralHubContractAddress}`);
                result = await contract._setCentralHub(centralHubContractAddress)
                await result.wait(1);
            }

            contract = await hre.ethers.getContractAt("CentralHub", centralHubContractAddress)
            checkAddress = await contract.kToken()
            if(checkAddress !== tokenContractAddress) {
                console.log(`Configuring ${centralHubContractName}... ${tokenContractAddress}`);
                result = await contract._setKToken(tokenContractAddress)
                await result.wait(1);
            }
        }

        contractName = token.kToken.symbol + 'AdapterAxelar'
        console.log(`Configuring ${contractName}...`);
        argAddress = getDeploymentAddress(otherChain, contractName);
        if (argAddress !== "0x0000000000000000000000000000000000000000") {
            contractAddress = (await hre.deployments.get(token.kToken.symbol + "AdapterAxelar")).address;
            contract = await hre.ethers.getContractAt("AdapterAxelar", contractAddress)
            result = await contract._setPeerContract(argAddress)
            await result.wait(1);
        } else {
            console.log('Peer address not found.');
        }

        contractName = token.kToken.symbol + 'AdapterWormhole'
        console.log(`Configuring ${contractName}...`);
        argAddress = getDeploymentAddress(otherChain, contractName);
        if (argAddress !== "0x0000000000000000000000000000000000000000") {
            contractAddress = (await hre.deployments.get(contractName)).address;
            contract = await hre.ethers.getContractAt("AdapterWormhole", contractAddress)
            result = await contract._setPeerContract(
                hre.ethers.utils.hexZeroPad(argAddress, 32)
            )
            await result.wait(1);
        } else {
            console.log('Peer address not found.');
        }
    }

}

export default func

import {HardhatRuntimeEnvironment} from "hardhat/types";
import {getConfig} from '../config'
import {getDeploymentAddress} from "./utils_func";


const func = async function (hre: HardhatRuntimeEnvironment) {

    const NATIVE_SYMBOL = "SEI"
    const {TOKENS} = getConfig(hre.network.name);
    const tokens = TOKENS.filter(r => r.symbol !== NATIVE_SYMBOL)

    let contractName
    let contractAddress
    let contract
    let peerContract
    let result
    let checkAddress

    const clientTag = hre.network.name === hre.userConfig.defaultNetwork ? '' : 'Client'

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


        const adapterLayerZeroName = token.kToken.symbol + 'AdapterLayerZero'
        let adapterLayerZeroAddress
        try {
            adapterLayerZeroAddress = (await hre.deployments.get(adapterLayerZeroName)).address;
        }catch (e) {
            console.log('adapterLayerZeroAddress not found.');
        }

        if(tokenContractAddress && centralHubContractAddress) {

            const kToken = await hre.ethers.getContractAt(
                hre.network.name === hre.userConfig.defaultNetwork
                    ? 'KErc20CrossChainDelegator'
                    : 'KClientDelegator',
                tokenContractAddress
            )
            checkAddress = await kToken.centralHub()
            if(checkAddress !== centralHubContractAddress) {
                console.log(`Configuring ${tokenContractName}...`);
                result = await kToken._setCentralHub(centralHubContractAddress)
                await result.wait(1);
            }

            const centralHub = await hre.ethers.getContractAt("CentralHub", centralHubContractAddress)
            checkAddress = await centralHub.kToken()
            if(checkAddress !== tokenContractAddress) {
                console.log(`Configuring ${centralHubContractName}...`);
                result = await centralHub._setKToken(tokenContractAddress)
                await result.wait(1);
            }

            if (adapterLayerZeroAddress){
                try {
                    result = await centralHub._addAdapter(adapterLayerZeroAddress)
                }catch (e) {
                    console.log(adapterLayerZeroName + ' already added.');
                }
            }

        }

        // Axelar Adapter
        // contractName = token.kToken.symbol + 'AdapterAxelar'
        // console.log(`Configuring ${contractName}...`);
        // argAddress = getDeploymentAddress(otherChain, contractName);
        // if (argAddress !== "0x0000000000000000000000000000000000000000") {
        //     contractAddress = (await hre.deployments.get(token.kToken.symbol + "AdapterAxelar")).address;
        //     contract = await hre.ethers.getContractAt("AdapterAxelar", contractAddress)
        //     result = await contract._setPeerContract(argAddress)
        //     await result.wait(1);
        // } else {
        //     console.log('Peer address not found.');
        // }


        // Wormwhole Adapter
        // contractName = token.kToken.symbol + 'AdapterWormhole'
        // console.log(`Configuring ${contractName}...`);
        // argAddress = getDeploymentAddress(otherChain, contractName);
        // if (argAddress !== "0x0000000000000000000000000000000000000000") {
        //     contractAddress = (await hre.deployments.get(contractName)).address;
        //     contract = await hre.ethers.getContractAt("AdapterWormhole", contractAddress)
        //     result = await contract._setPeerContract(
        //         hre.ethers.utils.hexZeroPad(argAddress, 32)
        //     )
        //     await result.wait(1);
        // } else {
        //     console.log('Peer address not found.');
        // }


        // LayerZero Adapter
        console.log(`Configuring ${adapterLayerZeroName}...`);
        peerContract = getDeploymentAddress(token.peerChain!, adapterLayerZeroName);
        if (peerContract !== "0x0000000000000000000000000000000000000000" && adapterLayerZeroAddress) {
            contract = await hre.ethers.getContractAt("AdapterLayerZero", adapterLayerZeroAddress)
            result = await contract.setPeer(
                token.adapters?.layerZero.peerChain,
                hre.ethers.utils.hexZeroPad(peerContract, 32)
            )
            await result.wait(1);
        } else {
            console.log('Peer address not found.');
        }
    }

}

export default func

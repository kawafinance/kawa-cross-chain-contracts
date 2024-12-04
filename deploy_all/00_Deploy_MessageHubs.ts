import {HardhatRuntimeEnvironment} from "hardhat/types";
import {getConfig} from '../config'
import {getDeploymentAddress} from "./utils_func";

const func = async function (hre: HardhatRuntimeEnvironment) {

    const deployer = (await hre.ethers.getSigners())[0].address;

    const NATIVE_SYMBOL = "ETH"
    const {TOKENS, AXELAR_GATEWAY, AXELAR_GAS_RECEIVER, WORMHOLE_RELAYER, WORMHOLE_CHAIN_ID} = getConfig(hre.network.name);
    const tokens = TOKENS.filter(r => r.symbol !== NATIVE_SYMBOL)

    let result
    let adapterName
    const otherChain = hre.network.name === 'sepolia'
        ? 'bnbTestnet'
        : 'sepolia'
    const clientTag = hre.network.name === 'sepolia' ? '' : 'Client'

    for (const token of tokens) {

        const centralHubName = token.kToken.symbol + "CentralHub"
        console.log("=== Deploying " + centralHubName + " ===");
        let kTokenAddress =  "0x0000000000000000000000000000000000000000"
        try {
            kTokenAddress = (await hre.deployments.get(token.kToken.symbol + clientTag)).address;
        } catch (error) {
            console.log('kToken not found. Using', kTokenAddress);
        }
        const centralHub = await hre.deployments.deploy(centralHubName, {
            from: deployer,
            contract: 'CentralHub',
            args: [kTokenAddress],
            log: true,
            deterministicDeployment: false,
        });
        console.log(`Deployed ${centralHubName} at : ${centralHub.address}\n`);
        const CentralHubContract = await hre.ethers.getContractAt("CentralHub", centralHub.address)

        console.log("Deploying Adapters...");

        adapterName = token.kToken.symbol + "AdapterAxelar"
        console.log("=== Deploying " + adapterName + " ===");
        const peerAxelarContractAddress = getDeploymentAddress(otherChain, adapterName);
        const axelarArgs = [
            centralHub.address,
            peerAxelarContractAddress,
            token.adapters?.axelar.peerChain,
            AXELAR_GATEWAY,
            AXELAR_GAS_RECEIVER
        ]
        const adapterAxelar = await hre.deployments.deploy(adapterName, {
            from: deployer,
            contract: 'AdapterAxelar',
            args: axelarArgs,
            log: true,
            deterministicDeployment: false,
        });
        console.log(`Deployed ${adapterName} at : ${adapterAxelar.address}\n`);
        console.log(`Adding ${adapterName} to CentralHub...\n`);
        result = await CentralHubContract._addAdapter(adapterAxelar.address);
        await result.wait(1);


        adapterName = token.kToken.symbol + "AdapterWormhole"
        console.log("=== Deploying " + adapterName + " ===");
        const peerWormholeContractAddress = getDeploymentAddress(otherChain, adapterName);
        const wormholeArgs = [
            centralHub.address,
            hre.ethers.utils.hexZeroPad(peerWormholeContractAddress, 32),
            token.adapters?.wormhole.peerChain,
            WORMHOLE_CHAIN_ID,
            WORMHOLE_RELAYER
        ]
        const adapterWormhole = await hre.deployments.deploy(adapterName, {
            from: deployer,
            contract: 'AdapterWormhole',
            args: wormholeArgs,
            log: true,
            deterministicDeployment: false,
        });
        console.log(`Deployed ${adapterName} at : ${adapterWormhole.address}\n`);
        console.log(`Adding ${adapterName} to CentralHub...\n`);
        result = await CentralHubContract._addAdapter(adapterWormhole.address);
        await result.wait(1);

    }

}

export default func



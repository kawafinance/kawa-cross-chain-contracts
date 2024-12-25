import {task} from "hardhat/config";
import {getDeploymentAddress} from "../deploy_all/utils_func";
import {getConfig} from "../config";

task("listAdapters", "list all Central Hub Adapters")
    .setAction(async (taskArgs, hre) => {
        const NATIVE_SYMBOL = "SEI"

        const {TOKENS} = getConfig(hre.network.name);
        const tokens = TOKENS.filter(r => r.symbol !== NATIVE_SYMBOL)
        for (const token of tokens) {
            console.log(token.kToken.symbol + 'CentralHub')
            const centralHubAddress = (await hre.deployments.get(token.kToken.symbol +'CentralHub')).address
            const centralHub = await hre.ethers.getContractAt('CentralHub', centralHubAddress)
            let more = true
            let count = 0
            while (more) {
                try {
                    let result = await centralHub.adapters(count)
                    console.log(count, result)
                    count++
                } catch (e) {
                    more = false
                }
            }
        }
    })

task("removeAdapters", "remove all Central Hub Adapters")
    .setAction(async (taskArgs, hre) => {
        const centralHubAddress = (await hre.deployments.get('kBNBCentralHub')).address
        const centralHub = await hre.ethers.getContractAt('CentralHub', centralHubAddress)
        let more = true
        let count = 0
        let result
        while (more) {
            try {
                const adapter = await centralHub.adapters(0)
                result = await centralHub._removeAdapter(adapter)
                await result.wait(1);
            } catch (e) {
                more = false
            }
        }
    })

task("removeAxelar", "remove Axelar Adapter")
    .setAction(async (taskArgs, hre) => {
        const centralHubAddress = (await hre.deployments.get('kBNBCentralHub')).address
        const adapterAddress = (await hre.deployments.get('kBNBAdapterAxelar')).address
        const centralHub = await hre.ethers.getContractAt('CentralHub', centralHubAddress)
        let result = await centralHub._removeAdapter(adapterAddress)
        await result.wait(1);
    })

task("addAxelar", "add Axelar Adapter")
    .setAction(async (taskArgs, hre) => {
        const centralHubAddress = (await hre.deployments.get('kBNBCentralHub')).address
        const adapterAddress = (await hre.deployments.get('kBNBAdapterAxelar')).address
        const centralHub = await hre.ethers.getContractAt('CentralHub', centralHubAddress)
        let result = await centralHub._addAdapter(adapterAddress)
        await result.wait(1);
    })

task("removeWormhole", "remove Wormhole Adapter")
    .setAction(async (taskArgs, hre) => {
        const centralHubAddress = (await hre.deployments.get('kBNBCentralHub')).address
        const adapterAddress = (await hre.deployments.get('kBNBAdapterWormhole')).address
        const centralHub = await hre.ethers.getContractAt('CentralHub', centralHubAddress)
        let result = await centralHub._removeAdapter(adapterAddress)
        await result.wait(1);
    })

task("addWormhole", "add Wormhole Adapter")
    .setAction(async (taskArgs, hre) => {
        const centralHubAddress = (await hre.deployments.get('kBNBCentralHub')).address
        const adapterAddress = (await hre.deployments.get('kBNBAdapterWormhole')).address
        const centralHub = await hre.ethers.getContractAt('CentralHub', centralHubAddress)
        let result = await centralHub._addAdapter(adapterAddress)
        await result.wait(1);
    })

task("updateWormhole", "update Wormhole Adapters")
    .setAction(async (taskArgs, hre) => {
        const {
            TOKENS,
            AXELAR_GATEWAY,
            AXELAR_GAS_RECEIVER,
            WORMHOLE_RELAYER,
            WORMHOLE_CHAIN_ID
        } = getConfig(hre.network.name);
        const centralHubAddress = (await hre.deployments.get('kBNBCentralHub')).address
        const NATIVE_SYMBOL = "SEI"
        const deployer = (await hre.ethers.getSigners())[0].address;

        await hre.run("compile");
        await hre.run("removeWormhole");
        const tokens = TOKENS.filter(r => r.symbol !== NATIVE_SYMBOL)

        for (const token of tokens) {
            const  adapterName = token.kToken.symbol + "AdapterWormhole";
            const peerWormholeContractAddress = getDeploymentAddress(token.peerChain!, adapterName);
            const wormholeArgs = [
                centralHubAddress,
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
            console.log(`Deployed AdapterWormhole at : ${adapterWormhole.address}\n`);
        }
        await hre.run("addWormhole");
    })
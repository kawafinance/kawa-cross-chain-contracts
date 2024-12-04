import {task} from "hardhat/config";
import * as ethers from "ethers";
import fs from "fs";
import path from "path";
import {getConfig} from "../config";
import {readFileSync} from "fs";
import {KClient} from "../typechain";

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
        return "0x000000000000000000000000000000000000dead";
    }
}

const printCheckValue = (label: string, contractAddress: any, wantedAddress: any) => {
    if (contractAddress !== wantedAddress) {
        console.log(`${label} \x1b[31m%s\x1b[0m`, contractAddress)
    } else {
        console.log(`${label} \x1b[32m%s\x1b[0m`, contractAddress)
    }
}

const printCheckAddress = (label: string, contractAddress: any, wantedAddress: any) => {
    if (contractAddress.toLowerCase() !== wantedAddress.toLowerCase()) {
        console.log(`${label} \x1b[31m%s\x1b[0m`, contractAddress)
    } else {
        console.log(`${label} \x1b[32m%s\x1b[0m`, contractAddress)
    }
}

const printReverseCheckAddress = (label: string, contractAddress: any, unwantedAddress: any) => {
    if (contractAddress.toLowerCase() === unwantedAddress.toLowerCase()) {
        console.log(`${label} \x1b[31m%s\x1b[0m`, contractAddress)
    } else {
        console.log(`${label} \x1b[32m%s\x1b[0m`, contractAddress)
    }
}

const printAddress = (label: string, address: string) => {
    const tabs = label.length > 6
        ? label.length > 16
            ? '\t'
            : '\t\t'
        : '\t\t\t'
    console.log(`${label}:${tabs}${address}`)
}

const formatTime = (seconds: any) => {
    if (seconds.gte(2592000)) return seconds.div(2592000).toString() + 'M'
    if (seconds.gte(86400)) return seconds.div(86400).toString() + 'd'
    if (seconds.gte(3600)) return seconds.div(3600).toString() + 'h'
    if (seconds.gte(60)) return seconds.div(60).toString() + 'm'
    return seconds.toString() + 's'
}

task("contractsInfo", "get all protocol info")
    .setAction(async (taskArgs, hre) => {

        console.log('')

        const artifactFilePath = __dirname + '/../deployments/' + hre.network.name;

        let filenames
        try {
            filenames = fs.readdirSync(artifactFilePath);
        } catch (error) {
            console.error('Error reading directory:', error);
            return [];
        }
        const artifacts = filenames.filter(filename => filename.endsWith('.json')).map(filename => path.parse(filename).name);

        const otherNetwork = hre.network.name === 'sepolia'
            ? 'bnbTestnet'
            : 'sepolia'

        const {
            AXELAR_GATEWAY,
            AXELAR_GAS_RECEIVER,
            WORMHOLE_RELAYER,
            WORMHOLE_CHAIN_ID
        } = getConfig(hre.network.name);

        const {
            WORMHOLE_CHAIN_ID: OTHER_WORMHOLE_CHAIN_ID
        } = getConfig(otherNetwork);

        const printAdapterAxelar = async (artifact: string, artifactAddress: string) => {
            const Adapter = await hre.ethers.getContractAt('AdapterAxelar', artifactAddress)
            const endOfSymbol = artifact.indexOf("AdapterAxelar");
            const adapterSymbol = artifact.slice(0, endOfSymbol);
            const adapterCentralHubWant = (await hre.deployments.get(adapterSymbol + "CentralHub")).address
            const adaptercentralHub = await Adapter.centralHub()
            printCheckAddress('\tcentralHub:\t\t', adaptercentralHub, adapterCentralHubWant)
            const adaptergateway = await Adapter.gateway()
            printCheckAddress('\tgateway:\t\t', adaptergateway, AXELAR_GATEWAY)
            const adaptergasReceiver = await Adapter.gasReceiver()
            printCheckAddress('\tgasReceiver:\t\t', adaptergasReceiver, AXELAR_GAS_RECEIVER)
            const adapterPeerContract = await Adapter.peerContract()
            const adapterPeerContractWant = getDeploymentAddress(otherNetwork, artifact)
            printCheckAddress('\tPeerContract:\t\t', adapterPeerContract, adapterPeerContractWant)
            const messageHubpeerChain = await Adapter.peerChain()
            console.log('\tpeerChain:\t\t', messageHubpeerChain)
        }

        const printAdapterWormhole = async (artifact: string, artifactAddress: string) => {
            const Adapter = await hre.ethers.getContractAt('AdapterWormhole', artifactAddress)
            const endOfSymbol = artifact.indexOf("AdapterWormhole");
            const adapterSymbol = artifact.slice(0, endOfSymbol);
            const adapterCentralHubWant = (await hre.deployments.get(adapterSymbol + "CentralHub")).address
            const adaptercentralHub = await Adapter.centralHub()
            printCheckAddress('\tcentralHub:\t\t', adaptercentralHub, adapterCentralHubWant)
            const adapterwormholeRelayer = await Adapter.wormholeRelayer()
            printCheckAddress('\twormholeRelayer:\t', adapterwormholeRelayer, WORMHOLE_RELAYER)
            const adapterPeerContract = await Adapter.peerContract()
            const adapterPeerContractWant = getDeploymentAddress(otherNetwork, artifact)
            printCheckAddress('\tPeerContract:\t\t', adapterPeerContract, hre.ethers.utils.hexZeroPad(adapterPeerContractWant, 32))
            const adapterPeerContractAddr = await Adapter.getPeerContract()
            printCheckAddress('\tPeerContract:\t\t', adapterPeerContractAddr, adapterPeerContractWant)
            const adapterpeerChain = await Adapter.peerChain()
            printCheckValue('\tpeerChain:\t\t', adapterpeerChain, OTHER_WORMHOLE_CHAIN_ID)
            const adapterthisChain = await Adapter.thisChain()
            printCheckValue('\tthisChain:\t\t', adapterthisChain, WORMHOLE_CHAIN_ID)
        }

        if (hre.network.name === 'sepolia') {
            const UNITROLLER_ADDRESS = (await hre.deployments.get('Unitroller')).address
            const PYTH_ORACLE_ADDRESS = (await hre.deployments.get('PythOracle')).address
            const JUMP_RATE_MODEL_ADDRESS = (await hre.deployments.get('JumpRateModel')).address
            const KWETH_DELEGATE_ADDRESS = (await hre.deployments.get('KWethDelegate')).address
            const KERC20_CROSSCHAIN_DELEGATE_ADDRESS = (await hre.deployments.get('KErc20CrossChainDelegate')).address
            const KETH_ADDRESS = (await hre.deployments.get('kETH')).address

            const printKToken = async (kTokenAddress: any) => {
                const KErc20Delegator = await hre.ethers.getContractAt('KErc20CrossChainDelegator', kTokenAddress)
                const name = await KErc20Delegator.name()
                console.log('\tname:\t\t\t', name)
                const symbol = await KErc20Delegator.symbol()
                console.log('\tsymbol:\t\t\t', symbol)
                const decimals = await KErc20Delegator.decimals()
                console.log('\tdecimals:\t\t', decimals)
                const comptroller = await KErc20Delegator.comptroller()
                printCheckAddress('\tcomptroller:\t\t', comptroller, UNITROLLER_ADDRESS)
                const underlying = symbol == 'kSEI' ? '' : await KErc20Delegator.underlying()
                console.log('\tunderlying:\t\t', underlying)
                const implementation = await KErc20Delegator.implementation()
                printCheckAddress('\timplementation:\t\t', implementation, symbol === 'kETH' ? KWETH_DELEGATE_ADDRESS : KERC20_CROSSCHAIN_DELEGATE_ADDRESS)
                // const incentivesControllerAddress = await KErc20Delegator.incentivesController()
                const interestRateModel = await KErc20Delegator.interestRateModel()
                printCheckAddress('\tinterestRateModel:\t', interestRateModel, JUMP_RATE_MODEL_ADDRESS)
                const reserveFactor = (await KErc20Delegator.reserveFactorMantissa()).div(ethers.BigNumber.from("10").pow("16"))
                console.log('\treserveFactor:\t\t', reserveFactor.toString())
                const protocolSeizeShare = (await KErc20Delegator.protocolSeizeShareMantissa()).div(ethers.BigNumber.from("10").pow("16"))
                console.log('\tseizeShare:\t\t', protocolSeizeShare.toString())
                const accrualBlockTimestamp = await KErc20Delegator.accrualBlockTimestamp()
                console.log('\taccrualBlockTimestamp:\t', accrualBlockTimestamp.toString())
                const borrowIndex = await KErc20Delegator.borrowIndex()
                console.log('\tborrowIndex:\t\t', borrowIndex.toString())
                const totalBorrows = await KErc20Delegator.totalBorrows()
                console.log('\ttotalBorrows:\t\t', totalBorrows.toString())
                const totalReserves = await KErc20Delegator.totalReserves()
                console.log('\ttotalReserves:\t\t', totalReserves.toString())
                const totalSupply = await KErc20Delegator.totalSupply()
                console.log('\ttotalSupply:\t\t', totalSupply.toString())
                try {
                    const centralHubAddress = (await hre.deployments.get(symbol + "CentralHub")).address
                    const centralHub = await KErc20Delegator.centralHub()
                    printCheckAddress('\tcentralHub:\t\t', centralHub, centralHubAddress)
                } catch (e) {
                    console.log('\tcentralHub:\t\t', '-')
                }
            }

            const comptroller = await hre.ethers.getContractAt('Comptroller', UNITROLLER_ADDRESS)

            for (const artifact of artifacts) {
                const artifactAddress = (await hre.deployments.get(artifact)).address
                printAddress(artifact, artifactAddress)
                if (artifact.startsWith('k')) {
                    if (artifact.includes('CentralHub')) {
                        const CentralHub = await hre.ethers.getContractAt('CentralHub', artifactAddress)
                        const endOfSymbol = artifact.indexOf("CentralHub");
                        const centralHubSymbol = artifact.slice(0, endOfSymbol);
                        const centralHubImplKToken = (await hre.deployments.get(centralHubSymbol)).address
                        const centralHubKToken = await CentralHub.kToken()
                        printCheckAddress('\tkToken:\t\t\t', centralHubKToken, centralHubImplKToken)
                        // const messageHubgateway = await CentralHub.gateway()
                        // printCheckAddress('\tgateway:\t\t', messageHubgateway, AXELAR_GATEWAY)
                        // const messageHubgasReceiver = await CentralHub.gasReceiver()
                        // printCheckAddress('\tgasReceiver:\t\t', messageHubgasReceiver, AXELAR_GAS_RECEIVER)
                        // const messageHubclientContract = await CentralHub.clientContract()
                        // const messageHubOtherContract = getDeploymentAddress(otherNetwork, artifact + 'Client')
                        // printCheckAddress('\tclientContract:\t\t', messageHubclientContract, messageHubOtherContract)
                        // const messageHubclientChain = await CentralHub.clientChain()
                        // console.log('\tclientChain:\t\t', messageHubclientChain)
                    } else if (artifact.includes('AdapterAxelar')) {
                        await printAdapterAxelar(artifact, artifactAddress)
                    } else if (artifact.includes('AdapterWormhole')) {
                        await printAdapterWormhole(artifact, artifactAddress)
                    } else {
                        await printKToken(artifactAddress)
                        const borrowCap = await comptroller.borrowCaps(artifactAddress)
                        console.log('\tborrowCap:\t\t', borrowCap.toString())
                        const mintGuardianPaused = await comptroller.mintGuardianPaused(artifactAddress)
                        console.log('\tmintGuardianPaused:\t', mintGuardianPaused)
                        const borrowGuardianPaused = await comptroller.borrowGuardianPaused(artifactAddress)
                        console.log('\tborrowGuardianPaused:\t', borrowGuardianPaused)
                        const market = await comptroller.markets(artifactAddress)
                        console.log('\tcollateralFactor:\t', market.collateralFactorMantissa.toString())
                        printCheckValue('\tisListed:\t\t', market.isListed, true)
                    }
                } else if (artifact === 'Unitroller') {
                    // const _borrowGuardianPaused = await comptroller._borrowGuardianPaused()
                    // console.log('\t_borrowGuardianPaused:\t', _borrowGuardianPaused)
                    // const maxAssets = await comptroller.maxAssets()
                    // console.log('\tmaxAssets:\t\t', maxAssets.toString())
                    const admin = await comptroller.admin()
                    console.log('\tadmin:\t\t\t', admin)
                    const oracle = await comptroller.oracle()

                    if (oracle !== PYTH_ORACLE_ADDRESS) {
                        console.log('\toracle:\t\t\t \x1b[31m%s\x1b[0m', oracle)
                    } else {
                        console.log('\toracle:\t\t\t \x1b[32m%s\x1b[0m', oracle)
                    }
                } else if (artifact === 'PythOracle') {
                    // const pythOracle = await hre.ethers.getContractAt('PythOracle', artifactAddress)
                    // const pythPriceIds = await pythOracle.pythPriceIds()
                } else if (artifact === 'WETHRouter') {
                    const WETHRouter = await hre.ethers.getContractAt('WETHRouter', artifactAddress)
                    const WETHRouterKToken = await WETHRouter.kToken()
                    printCheckAddress('\tkToken:\t\t', WETHRouterKToken, KETH_ADDRESS)
                    const WETHRouterweth = await WETHRouter.weth()
                    console.log('\tweth:\t\t', WETHRouterweth)
                }
            }
        } else {
            for (const artifact of artifacts) {
                const artifactAddress = (await hre.deployments.get(artifact)).address
                printAddress(artifact, artifactAddress)
                if (artifact.includes('AdapterAxelar')) {
                    await printAdapterAxelar(artifact, artifactAddress)
                } else if (artifact.includes('AdapterWormhole')) {
                    await printAdapterWormhole(artifact, artifactAddress)
                } else if (artifact.includes('Client') && !artifact.includes('Delegate')) {
                    const KClientDelegator = await hre.ethers.getContractAt('KClientDelegator', artifactAddress)
                    const endOfSymbol = artifact.indexOf("Client");
                    const kClientSymbol = artifact.slice(0, endOfSymbol);
                    const centralHubClientAddress = (await hre.deployments.get(kClientSymbol + "CentralHub")).address
                    const kClientcentralHub = await KClientDelegator.centralHub()
                    printCheckAddress('\tcentralHub:\t', kClientcentralHub, centralHubClientAddress)
                    const kClientImplementation = await KClientDelegator.implementation()
                    const implementationAddress = (await hre.deployments.get('KClientDelegate')).address
                    printCheckAddress('\timplementation:\t', kClientImplementation, implementationAddress)
                }
            }
        }
        console.log('')
    });

task("clientInfo", "get client info")
    .setAction(async (taskArgs, hre) => {

        const {
            AXELAR_GATEWAY,
            AXELAR_GAS_RECEIVER
        } = getConfig(hre.network.name);

        console.log('')
        const bnbClientAddress = "0xd67219296b51788b26e0162d4037a643fd35986d"
        const KClient = await hre.ethers.getContractAt('KClient', bnbClientAddress)
        printAddress('KClient', bnbClientAddress)
        const baseContract = await KClient.callStatic.baseContract()
        printAddress('\tbaseContract\t\t', baseContract)
        const baseChain = await KClient.callStatic.baseChain()
        printAddress('\tbaseChain\t\t', baseChain)
        const gateway = await KClient.callStatic.gateway()
        printCheckAddress('\tgateway\t\t', gateway, AXELAR_GATEWAY)
        const gasReceiver = await KClient.callStatic.gasReceiver()
        printCheckAddress('\tgasReceiver\t\t', gasReceiver, AXELAR_GAS_RECEIVER)
        console.log('')
    });


task("oracleInfo", "get oracle info")
    .setAction(async (taskArgs, hre) => {
        const oracleAddress = (await hre.deployments.get('PythOracle')).address
        console.log('Oracle Address:', oracleAddress)
        const oracleContract = await hre.ethers.getContractAt('PythOracle', oracleAddress)
        const isOracle = await oracleContract.isPriceOracle()
        console.log('IsOracle:\t', isOracle)
    });


task("proxyImplementation", "get implementation address of proxy")
    .addParam("address", "proxy address")
    .setAction(async ({address}, hre) => {
        const IMPLEMENTATION_SLOT = "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc";
        const rawImplementationAddress = await hre.ethers.provider.getStorageAt(address, IMPLEMENTATION_SLOT)
        const implementationAddress = ethers.utils.getAddress("0x" + rawImplementationAddress.slice(26));

        // const implementation = await oracleContract.implementation()
        console.log('Implementation:\t', implementationAddress)
    });


task("userInfo", "get user info")
    .setAction(async (taskArgs, hre) => {
        const deployer = (await hre.ethers.getSigners())[0].address;

        const UNITROLLER_ADDRESS = (await hre.deployments.get('Unitroller')).address
        const comptroller = await hre.ethers.getContractAt('Comptroller', UNITROLLER_ADDRESS)
        const liquidity = await comptroller.callStatic.getAccountLiquidity(deployer)
        console.log('liquidity:')
        console.log('error', liquidity[0].toString())
        console.log('liquidity', liquidity[1].toString())
        console.log('shortfall', liquidity[2].toString())
        console.log()
        const assetsIn = await comptroller.getAssetsIn(deployer)
        console.log('assetsIn:', assetsIn)
        for (const asset of assetsIn) {
            const contract = await hre.ethers.getContractAt('KErc20CrossChainDelegator', asset)
            console.log('asset:', asset)
            const borrowBalanceCurrent = await contract.callStatic.borrowBalanceCurrent(deployer)
            console.log('borrowBalanceCurrent:', borrowBalanceCurrent.toString())
            const borrowBalanceStored = await contract.borrowBalanceStored(deployer)
            console.log('borrowBalanceStored:', borrowBalanceStored.toString())
            console.log()
        }
    });

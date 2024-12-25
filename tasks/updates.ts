import * as ethers from "ethers";
import {HardhatRuntimeEnvironment} from "hardhat/types";
import {readFile, readFileSync, existsSync, writeFileSync} from "fs";
import {getConfig} from '../config'
import {Artifacts} from "../config/types";
import {task} from "hardhat/config";
import {deployments} from "hardhat";
import path from "path";
import {delay} from "../deploy_all/utils_func";

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

task("deployBase", "deploy base conracts - not native")
    .setAction(async (taskArgs, hre) => {
        if (hre.network.name !== hre.userConfig.defaultNetwork) {
            console.log('Wrong Base network')
            return;
        }

        await hre.run("compile");

        const {TOKENS} = getConfig(hre.network.name);
        const NATIVE_SYMBOL = 'SEI'
        const tokens = TOKENS.filter(r => r.symbol !== NATIVE_SYMBOL)

        console.log("=== Deploying KErc20CrossChainDelegate implementation ===");
        const deployer = (await hre.ethers.getSigners())[0].address;

        const KErc20CrossChainDelegate = await hre.deployments.deploy('KErc20CrossChainDelegate', {
            from: deployer,
            args: [],
            log: true,
            deterministicDeployment: false,
        });

        console.log(`Deployed a KErc20CrossChainDelegate implementation at : ${KErc20CrossChainDelegate.address}\n`);

        const UNITROLLER_ADDRESS = (await hre.deployments.get('Unitroller')).address
        const JUMPRATEMODEL_ADDRESS = (await hre.deployments.get('JumpRateModel')).address
        const KERC20_CROSSCHAIN_DELEGATE_ADDRESS = KErc20CrossChainDelegate.address

        let result

        const comptroller = await hre.ethers.getContractAt('Comptroller', UNITROLLER_ADDRESS)
        const allMarkets = await comptroller.getAllMarkets()
        for (const token of tokens) {

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

            console.log(`Deployed a ${token.symbol} at : ${underlyingContract.address}\n`);

            let underlyingContractAddress = underlyingContract.address

            const pythOracleAddress = (await hre.deployments.get('PythOracle')).address
            const pythOracle = await hre.ethers.getContractAt('PythOracle', pythOracleAddress)
            const currentPriceId = await pythOracle.pythPriceIds(underlyingContractAddress)
            if (currentPriceId !== token.priceFeed) {
                console.log('Configuring PythOracle feed...')
                result = await pythOracle.updatePythPriceIds([underlyingContractAddress], [token.priceFeed!])
                await result.wait(1)
            } else {
                console.log('PythOracle feed already set.')
            }


            console.log('UPDATE contractAddress config!!!!!!!!!', underlyingContractAddress)

            console.log("=== Deploying " + token.kToken.symbol + " implementation ===");

            const MESSAGEHUB_ADDRESS = (await hre.deployments.get(token.kToken.symbol + 'MessageHub')).address
            const initialExchangeRateMantissa = ethers.BigNumber.from("10").pow(token.decimals + 8).mul("2");
            const deploymentArgs = [
                underlyingContractAddress,
                UNITROLLER_ADDRESS,
                JUMPRATEMODEL_ADDRESS,
                initialExchangeRateMantissa,
                token.kToken.name,
                token.kToken.symbol,
                ethers.BigNumber.from("8"),
                MESSAGEHUB_ADDRESS,
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
            console.log(`Deployed a ${token.kToken.symbol} at : ${kTokenContract.address}\n`);

            try {
                console.log('Updating config file...')
                const configFilePath = `./config/bscTestnet.ts`;
                let content = readFileSync(configFilePath, 'utf8');
                const regex = /otherChainContract:\s*\S+/g;
                content = content.replace(regex, `otherChainContract: "${MESSAGEHUB_ADDRESS}",`);
                writeFileSync(configFilePath, content, 'utf8');
                console.log('Config file updated successfully.');
            } catch (error) {
                console.error('Error modifying config:', error);
            }

            const UnderlyingContract = await hre.ethers.getContractAt("WErc20", underlyingContractAddress)
            const currentOwner = await UnderlyingContract.owner()
            if (currentOwner === deployer) {
                console.log(`Setting ownership...`);
                result = await UnderlyingContract.transferOwnership(kTokenContract.address);
                await result.wait(1);
            } else if (currentOwner === kTokenContract.address) {
                console.log('Owner already set.')
            } else {
                throw Error('Unknown owner');
            }

            const MessageHubContract = await hre.ethers.getContractAt("MessageHub", MESSAGEHUB_ADDRESS)
            const currentKToken = await MessageHubContract.kToken()
            if (currentKToken !== kTokenContract.address) {
                console.log(`Configuring MessageHub for ${token.kToken.name}...`);
                result = await MessageHubContract._setKToken(kTokenContract.address);
                await result.wait(1);
            } else {
                console.log('MessageHub\'s kToken already set.')
            }

            const KToken = await hre.ethers.getContractAt("KErc20CrossChainDelegator", kTokenContract.address)

            const currentMessageHub = await KToken.messageHub()
            if (currentMessageHub !== MESSAGEHUB_ADDRESS) {
                console.log(`Configuring ${token.kToken.symbol} for MessageHub...`);
                console.log(`found ${currentMessageHub}`);
                result = await KToken._setMessageHub(MESSAGEHUB_ADDRESS);
                await result.wait(1);
            } else {
                console.log('KToken\'s MessageHub already set.')
            }

            const currentMarket = await comptroller.markets(kTokenContract.address)
            if (!currentMarket.isListed) {
                console.log(`Configuring Comptroller for ${token.kToken.symbol}`);
                result = await comptroller._supportMarket(kTokenContract.address);
                await result.wait(1);
            } else {
                console.log("Market already supported.")
            }

            const currentAdmin = await KToken.admin()
            if (currentAdmin.toLowerCase() !== deployer.toLowerCase()) {
                console.log(`Setting pending admin: ${deployer}`);
                result = await KToken._setPendingAdmin(
                    deployer
                );
                await result.wait(1);
            } else {
                console.log('Admin already set.')
            }

            let collateralFactorRaw = ethers.BigNumber.from(token.kToken.collateralFactor).mul(ethers.BigNumber.from("10").pow("16"));
            if (!collateralFactorRaw.eq(currentMarket.collateralFactorMantissa)) {
                console.log(`Setting collateral factor: ${collateralFactorRaw}`);
                result = await comptroller._setCollateralFactor(
                    kTokenContract.address,
                    collateralFactorRaw
                );
                await result.wait(3);
            } else {
                console.log('Collateral factor already set.')
            }


            let seizeShare = ethers.BigNumber.from(token.kToken.seizeShare).mul(ethers.BigNumber.from("10").pow("16"));
            const currentProtocolSeizeShare = await KToken.protocolSeizeShareMantissa()
            if (!seizeShare.eq(currentProtocolSeizeShare)) {
                console.log(`Setting protocol seize share: ${seizeShare}`);
                result = await KToken._setProtocolSeizeShare(seizeShare);
                await result.wait(3);
            } else {
                console.log('Protocol seize share already set.')
            }

            let reserveFactor = ethers.BigNumber.from(token.kToken.reserveFactor).mul(ethers.BigNumber.from("10").pow("16"));
            const currentReserveFactor = await KToken.reserveFactorMantissa()
            if (!reserveFactor.eq(currentReserveFactor)) {
                console.log(`Setting reserve factor: ${reserveFactor}`);
                result = await KToken._setReserveFactor(reserveFactor);
                await result.wait(1);
            } else {
                console.log('Reserve factor share already set.')
            }
        }
    })

task("supportMarkets", "support markets - not native")
    .setAction(async (taskArgs, hre) => {
        if (hre.network.name !== hre.userConfig.defaultNetwork) {
            console.log('Wrong Base network')
            return;
        }

        await hre.run("compile");

        const {TOKENS} = getConfig(hre.network.name);
        const NATIVE_SYMBOL = 'SEI'
        const tokens = TOKENS.filter(r => r.symbol !== NATIVE_SYMBOL)
        const UNITROLLER_ADDRESS = (await hre.deployments.get('Unitroller')).address
        const comptroller = await hre.ethers.getContractAt('Comptroller', UNITROLLER_ADDRESS)

        for (const token of tokens) {
            let result

            const kTokenContract = await hre.deployments.get(token.kToken.symbol);

            console.log(`Configuring Comptroller for ${token.kToken.symbol}`);
            result = await comptroller._supportMarket(kTokenContract.address);
            await result.wait(1);

            let collateralFactorRaw = ethers.BigNumber.from(token.kToken.collateralFactor).mul(ethers.BigNumber.from("10").pow("16"));
            console.log(`Setting collateral factor: ${collateralFactorRaw}`);
            result = await comptroller._setCollateralFactor(
                kTokenContract.address,
                collateralFactorRaw
            );
            await result.wait(1);

        }
    })

task("updateBase", "update base conracts - not native")
    .setAction(async (taskArgs, hre) => {
        if (hre.network.name !== hre.userConfig.defaultNetwork) {
            console.log('Wrong Base network')
            return;
        }

        await hre.run("compile");

        const {TOKENS} = getConfig(hre.network.name);
        const NATIVE_SYMBOL = 'SEI'

        console.log("=== Deploying KErc20CrossChainDelegate implementation ===");
        const deployer = (await hre.ethers.getSigners())[0].address;

        const KErc20CrossChainDelegate = await hre.deployments.deploy('KErc20CrossChainDelegate', {
            from: deployer,
            args: [],
            log: true,
            deterministicDeployment: false,
        });

        console.log(`Deployed a KErc20CrossChainDelegate implementation at : ${KErc20CrossChainDelegate.address}\n`);

        const tokens = TOKENS.filter(r => r.symbol !== NATIVE_SYMBOL)
        for (const token of tokens) {
            console.log(`=== Configuring ${token.kToken.symbol} KErc20CrossChainDelegate implementation ===`);
            const kTokenAddress = (await hre.deployments.get(token.kToken.symbol)).address
            const kBNB = await hre.ethers.getContractAt('KErc20CrossChainDelegator', kTokenAddress)
            let result = await kBNB._setImplementation(KErc20CrossChainDelegate.address, false, "0x00")
            await result.wait(1);
        }
    })


task("updateImpl", "update bnb implementation")
    .setAction(async ({}, hre) => {

        if (hre.network.name !== hre.userConfig.defaultNetwork) {
            console.log('Wrong Base network')
            return;
        }

        await hre.run("compile");

        const {TOKENS} = getConfig(hre.network.name);
        const NATIVE_SYMBOL = 'SEI'
        const deployer = (await hre.ethers.getSigners())[0].address;


        console.log("=== Deploying KErc20CrossChainDelegate implementation ===");

        const KErc20DelegateBase = await hre.deployments.deploy('KErc20CrossChainDelegate', {
            from: deployer,
            args: [],
            log: true,
            deterministicDeployment: false,
        });

        console.log(`Deployed a KErc20CrossChainDelegate implementation at : ${KErc20DelegateBase.address}\n`);

        const tokens = TOKENS.filter(r => r.symbol !== NATIVE_SYMBOL)
        for (const token of tokens) {
            console.log(`=== Configuring ${token.kToken.symbol} KErc20CrossChainDelegate implementation ===`);
            const kTokenAddress = (await hre.deployments.get(token.kToken.symbol)).address
            const kBNB = await hre.ethers.getContractAt('KErc20CrossChainDelegator', kTokenAddress)
            let result = await kBNB._setImplementation(KErc20DelegateBase.address, false, "0x00")
            await result.wait(1);
        }
    });


task("updateMsgHub", "update bnb MessageHub implementation")
    .setAction(async ({}, hre) => {

        await hre.run("compile");

        const updateScripts = [
            "../deploy_all/00_Deploy_MessageHubs.ts",
            "../deploy_all/30_Configure_MessageHubs.ts"
        ];

        for (const script of updateScripts) {
            console.log("")
            console.log(`\t\t\t\tRunning ${script}...`);
            console.log("")

            const deployFunction = require(script).default;

            await deployFunction(hre);

            await delay(5000);
        }
        
        // const clientTag = hre.network.name === hre.userConfig.defaultNetwork ? '' : 'Client'
        //
        //
        // const {TOKENS, LAYERZERO_ENDPOINT} = getConfig(hre.network.name);
        // const NATIVE_SYMBOL = 'SEI'
        // const deployer = (await hre.ethers.getSigners())[0].address;
        // let result
        // const tokens = TOKENS.filter(r => r.symbol !== NATIVE_SYMBOL)
        // for (const token of tokens) {
        //     const kTokenAddress = (await hre.deployments.get(token.kToken.symbol + clientTag)).address
        //
        //     console.log("=== Deploying " + token.kToken.symbol + "CentralHub ===");
        //
        //     const centralHub = await hre.deployments.deploy(token.kToken.symbol + "CentralHub", {
        //         from: deployer,
        //         contract: 'CentralHub',
        //         args: [kTokenAddress],
        //         log: true,
        //         deterministicDeployment: false,
        //     });
        //
        //     console.log(`Deployed ${token.kToken.symbol}CentralHub at : ${centralHub.address}\n`);
        //
        //     console.log(`=== Configuring ${token.kToken.symbol} ===`);
        //     const kBNB = await hre.ethers.getContractAt(
        //         hre.network.name === hre.userConfig.defaultNetwork ? 'KErc20CrossChainDelegator' : 'KClient',
        //         kTokenAddress
        //     )
        //     result = await kBNB._setCentralHub(centralHub.address)
        //     await result.wait(1);
        //
        //
        //     const adapterName = token.kToken.symbol + "AdapterLayerZero"
        //     console.log("=== Deploying " + adapterName + " ===");
        //
        //     const peerContract = getDeploymentAddress(token.peerChain!, adapterName);
        //
        //     const layerZeroArgs = [
        //         centralHub.address,
        //         hre.ethers.utils.hexZeroPad(peerContract, 32),
        //         token.adapters?.layerZero.peerChain,
        //         LAYERZERO_ENDPOINT
        //     ]
        //
        //     const adapterLayerZero = await hre.deployments.deploy(adapterName, {
        //         from: deployer,
        //         contract: 'AdapterLayerZero',
        //         args: layerZeroArgs,
        //         log: true,
        //         deterministicDeployment: false,
        //     });
        //
        //     console.log(`Deployed ${token.kToken.symbol}AdapterLayerZero at : ${adapterLayerZero.address}\n`);
        //
        //
        //
        //
        // }
    });

task("configMsgHub", "config MessageHub")
    .setAction(async ({}, hre) => {

        await hre.run("compile");

        const configScripts = [
            "../deploy_all/30_Configure_MessageHubs.ts"
        ];

        for (const script of configScripts) {
            console.log("")
            console.log(`\t\t\t\tRunning ${script}...`);
            console.log("")

            const deployFunction = require(script).default;

            await deployFunction(hre);

            await delay(5000);
        }
        //
        // const {TOKENS} = getConfig(hre.network.name);
        // const NATIVE_SYMBOL = 'SEI'
        // const clientTag = hre.network.name === hre.userConfig.defaultNetwork ? '' : 'Client'
        // const otherClientTag = hre.network.name === hre.userConfig.defaultNetwork ? 'Client' : ''
        //
        // const tokens = TOKENS.filter(r => r.symbol !== NATIVE_SYMBOL)
        // for (const token of tokens) {
        //
        //     const clientContractAddress = getDeploymentAddress(token.peerChain, token.kToken.symbol + "MessageHub" + otherClientTag);
        //     if (clientContractAddress !== '') {
        //         const messageHubAddress = (await hre.deployments.get(token.kToken.symbol + "MessageHub" + clientTag)).address;
        //         const MessageHub = await hre.ethers.getContractAt('MessageHub', messageHubAddress)
        //         console.log(`=== Configuring ${token.kToken.symbol}MessageHub${clientTag} ===`);
        //         let result = await MessageHub._setClientContract(token.otherChainMessageHub!)
        //         await result.wait(1);
        //     } else {
        //         console.log(token.kToken.symbol, "OtherChainContract not found.");
        //     }
        // }
    });


task("configMarkets", "config markets")
    .setAction(async ({}, hre) => {

        if (hre.network.name !== hre.userConfig.defaultNetwork) {
            console.log('Wrong Base network')
            return;
        }

        await hre.run("compile");

        const {TOKENS} = getConfig(hre.network.name);
        const deployer = (await hre.ethers.getSigners())[0].address;
        const UNITROLLER_ADDRESS = (await hre.deployments.get('Unitroller')).address
        const comptroller = await hre.ethers.getContractAt('Comptroller', UNITROLLER_ADDRESS)

        let result
        for (const token of TOKENS) {

            if (token.name === 'ETH') continue;

            console.log(`=== Configuring ${token.kToken.symbol} ===`);
            console.log(`==========================================`)
            console.log('')

            const kTokenAddress = (await hre.deployments.get(token.kToken.symbol)).address
            const KToken = await hre.ethers.getContractAt('KErc20Delegator', kTokenAddress)

            const currentMarket = await comptroller.markets(kTokenAddress)
            if (!currentMarket.isListed) {
                console.log(`Configuring Comptroller for ${token.kToken.symbol}`);
                result = await comptroller._supportMarket(kTokenAddress);
                await result.wait(1);
            } else {
                console.log("Market already supported.")
            }

            const currentAdmin = await KToken.admin()
            if (currentAdmin.toLowerCase() !== deployer.toLowerCase()) {
                console.log(`Setting pending admin: ${deployer}`);
                result = await KToken._setPendingAdmin(
                    deployer
                );
                await result.wait(1);
            } else {
                console.log('Admin already set.')
            }

            let collateralFactorRaw = ethers.BigNumber.from(token.kToken.collateralFactor).mul(ethers.BigNumber.from("10").pow("16"));
            if (!collateralFactorRaw.eq(currentMarket.collateralFactorMantissa)) {
                console.log(`Setting collateral factor: ${collateralFactorRaw}`);
                result = await comptroller._setCollateralFactor(
                    kTokenAddress,
                    collateralFactorRaw
                );
                await result.wait(3);
            } else {
                console.log('Collateral factor already set.')
            }

            let seizeShare = ethers.BigNumber.from(token.kToken.seizeShare).mul(ethers.BigNumber.from("10").pow("16"));
            const currentProtocolSeizeShare = await KToken.protocolSeizeShareMantissa()
            if (!seizeShare.eq(currentProtocolSeizeShare)) {
                console.log(`Setting protocol seize share: ${seizeShare}`);
                result = await KToken._setProtocolSeizeShare(seizeShare);
                await result.wait(3);
            } else {
                console.log('Protocol seize share already set.')
            }

            let reserveFactor = ethers.BigNumber.from(token.kToken.reserveFactor).mul(ethers.BigNumber.from("10").pow("16"));
            const currentReserveFactor = await KToken.reserveFactorMantissa()
            if (!reserveFactor.eq(currentReserveFactor)) {
                console.log(`Setting reserve factor: ${reserveFactor}`);
                result = await KToken._setReserveFactor(reserveFactor);
                await result.wait(1);
            } else {
                console.log('Reserve factor share already set.')
            }
        }
    });

task("updateClient", "update all client conracts")
    .setAction(async (taskArgs, hre) => {
        if (hre.network.name !== 'bscTestnet') {
            console.log('Wrong Client network')
            return;
        }

        await hre.run("compile");

        const {TOKENS} = getConfig(hre.network.name);

        for (const token of TOKENS) {
            console.log("=== Updating KClient " + token.kToken.symbol + " implementation ===");
            const KClient = await hre.ethers.getContractFactory("KClient");
            await hre.upgrades.upgradeProxy(token!, KClient);
            console.log(`Updated ${token.kToken.symbol} at : ${token.kClientImplementation}\n`);
        }
    });

task("configClient", "config all client conracts")
    .setAction(async (taskArgs, hre) => {
        if (hre.network.name !== 'bscTestnet') {
            console.log('Wrong Client network')
            return;
        }

        const {TOKENS} = getConfig(hre.network.name);

        for (const token of TOKENS) {
            console.log(`Configuring Cross Chain for ${token.name}`);
            console.log(`==========================================`)
            console.log('')
            const kClient = await hre.ethers.getContractAt('KClient', token.kClientImplementation!)
            console.log(`Setting Base Contract...`);
            let result = await kClient.setBaseContract(token.otherChainMessageHub!);
            await result.wait(1);
        }
    });

task("configOracle", "config price oracle feed")
    .setAction(async (taskArgs, hre) => {
        const {TOKENS} = getConfig(hre.network.name);
        const PYTHORACLE_ADDRESS = (await hre.deployments.get('PythOracle')).address

        const priceFeedTokens = TOKENS.map(token => {
            return {
                contractAddress: token.contractAddress,
                priceFeed: token.priceFeed
            }
        })

        const pythOracleContract = await hre.ethers.getContractAt('PythOracle', PYTHORACLE_ADDRESS)
        // @ts-ignore
        let result = await pythOracleContract.updatePythPriceIds(priceFeedTokens.map(r => r.contractAddress), priceFeedTokens.map(r => r.priceFeed))
        await result.wait(1)
    });




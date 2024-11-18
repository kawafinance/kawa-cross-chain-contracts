import {task} from "hardhat/config";
import {getConfig} from "../config";
import PythAbi from "@pythnetwork/pyth-sdk-solidity/abis/IPyth.json";
import * as ethers from "ethers";
import axios from "axios";

const ETH_ADDRESS = '0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE'

task("getPriceUSDC", "get USDC price from oracle")
    .setAction(async (taskArgs, hre) => {
        const pythOracleAddress = (await hre.deployments.get('PythOracle')).address
        const pythOracle = await hre.ethers.getContractAt('PythOracle', pythOracleAddress)
        console.log('pythOracle: ', pythOracleAddress)
        const kUSDCAddress = (await hre.deployments.get('kUSDC')).address
        console.log('kUSDC: ', kUSDCAddress)

        let results

        console.log('Get Oracle USDC price')
        const price = await pythOracle.getUnderlyingPrice(kUSDCAddress)
        console.log('price: ', price)
    });

task("getPriceETH", "get ETH price from mainnet")
    .setAction(async (taskArgs, hre) => {

        const {PYTH_ADDRESS} = getConfig(hre.network.name);
        console.log('Address', PYTH_ADDRESS)
        const id = '0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace'
        const provider = hre.ethers.provider
        const pyth = new hre.ethers.Contract(PYTH_ADDRESS, PythAbi, provider)
        const results = await pyth.getPriceUnsafe(id)
        console.log('pyth', results)

    });

task("getPrice", "get price ")
    .setAction(async (taskArgs, hre) => {

        const {PYTH_ADDRESS, TOKENS} = getConfig(hre.network.name);
        console.log('Pyth Address', PYTH_ADDRESS)
        const provider = hre.ethers.provider
        const pyth = new hre.ethers.Contract(PYTH_ADDRESS, PythAbi, provider)
        for (let token of TOKENS) {
            let results = await pyth.getPriceUnsafe(token.priceFeed)
            console.log(token.name, results)
        }

    });

task("getPrice2", "get price ")
    .setAction(async (taskArgs, hre) => {
        const {TOKENS} = getConfig(hre.network.name);
        const pythOracleAddress = (await hre.deployments.get('PythOracle')).address
        const pythOracle = await hre.ethers.getContractAt('PythOracle', pythOracleAddress)
        for (let token of TOKENS) {
            console.log(token.kToken.symbol)
            const kTokenAddress = (await hre.deployments.get(token.kToken.symbol)).address
            const id = await pythOracle.pythPriceIds(token.contractAddress!)
            console.log('id', id)
            const price = await pythOracle.getPrice(kTokenAddress)
            console.log("price", price)
        }
    });

task("getSomePrice", "get some price")
    .setAction(async (taskArgs, hre) => {
        const ETH_ADDRESS = '0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE'
        const oracleAddress = (await hre.deployments.get('PythOracle')).address
        console.log('Attaching Pyth Oracle at ', oracleAddress)
        const pythOracle = await hre.ethers.getContractAt('PythOracle', oracleAddress)
        const kTokenAddress = (await hre.deployments.get('kUSDC')).address
        console.log('kToken: ', kTokenAddress)
        const KErc20Delegator = await hre.ethers.getContractAt('KErc20Delegator', kTokenAddress)
        const underlying = await KErc20Delegator.underlying()
        console.log('Underlying: ', underlying)
        const priceID = await pythOracle.pythPriceIds(ETH_ADDRESS)
        console.log('Price ID: ', priceID)
        const price = await pythOracle.getUnderlyingPrice(kTokenAddress)
        console.log('Price: ', price)
    });

task("getPythPrices", "get some price")
    .setAction(async (taskArgs, hre) => {
        const {PYTH_ADDRESS, TOKENS} = getConfig(hre.network.name);
        const pyth = await hre.ethers.getContractAt(PythAbi, PYTH_ADDRESS)
        for (let token of TOKENS) {
            try {
                let price = await pyth.getPriceNoOlderThan(
                    token.priceFeed,
                    24 * 60 * 60
                );
                console.log(`${token.symbol}: ${price}`)
            } catch (e) {
                console.log(e)
            }

            let price = await pyth.getPriceNoOlderThan(
                token.priceFeed,
                24 * 60 * 60 * 10
            );

            console.log(`${token.symbol}-10: ${price}`)
        }
    });

task("getOraclePrices", "get some price")
    .setAction(async (taskArgs, hre) => {
        const {TOKENS} = getConfig(hre.network.name);
        const oracleAddress = (await hre.deployments.get('PythOracle')).address
        const Oracle = await hre.ethers.getContractAt('PythOracle', oracleAddress)

        for (let token of TOKENS) {
            const ktokenAddress = (await hre.deployments.get(token.kToken.symbol)).address
            try {
                let price = await Oracle.getUnderlyingPrice(ktokenAddress);
                console.log(`${token.kToken.symbol}: ${price}`)
            } catch (e) {
                console.log(e)
            }
        }
    });

task("getPriceSEI", "get SEI price from oracle")
    .setAction(async (taskArgs, hre) => {

        const {PYTH_ADDRESS} = getConfig(hre.network.name);

        const pythOracleAddress = (await hre.deployments.get('PythOracle')).address
        const pythOracle = await hre.ethers.getContractAt('PythOracle', pythOracleAddress)
        console.log('pythOracle: ', pythOracleAddress)
        const kSEIAddress = (await hre.deployments.get('kETH')).address
        console.log('kETH: ', kSEIAddress)

        let results

        console.log('Get price ID')
        const id = await pythOracle.pythPriceIds(ETH_ADDRESS)
        console.log('id: ', id)

        const pyth = new hre.ethers.Contract(PYTH_ADDRESS, PythAbi, hre.ethers.getDefaultProvider())
        results = await pyth.getPriceUnsafe(
            id,
            // 24 * 60 * 60 * 300
        )
        console.log('pyth', results)

        console.log('Get Oracle SEI price')
        const price = await pythOracle.getUnderlyingPrice(kSEIAddress)
        console.log('price: ', price)
    });

task("fixUSDCPrice", "fix USDC price")
    .setAction(async (taskArgs, hre) => {

        const {PYTH_ADDRESS, TOKENS} = getConfig(hre.network.name);

        const pythOracleAddress = (await hre.deployments.get('PythOracle')).address
        const pythOracle = await hre.ethers.getContractAt('PythOracle', pythOracleAddress)
        console.log('pythOracle: ', pythOracleAddress)
        const kUSDCAddress = (await hre.deployments.get('kUSDC')).address
        console.log('kUSDCAddress: ', kUSDCAddress)
        const kUSDC = await hre.ethers.getContractAt('KErc20Delegator', kUSDCAddress)
        const usdcAddress = await kUSDC.underlying()
        console.log('usdcAddress', usdcAddress)

        const fixPrice = ethers.BigNumber.from("10").pow("18")
        console.log('Setting direct price', fixPrice)
        await pythOracle.setDirectPrice(usdcAddress, fixPrice)

        console.log('Get Oracle usdc price')
        const price = await pythOracle.getUnderlyingPrice(kUSDCAddress)
        console.log('price: ', price)
    });

task("updatePrices", "update and get prices")
    .setAction(async (taskArgs, hre) => {

        const {PYTH_ADDRESS, TOKENS} = getConfig(hre.network.name);
        console.log('Pyth address', PYTH_ADDRESS)

        // const hermesBaseURL = hre.network.name === 'devnet' ? 'https://hermes-beta.pyth.network' : 'https://hermes.pyth.network'
        const hermesBaseURL = 'https://hermes.pyth.network'
        console.log('Hermes', hermesBaseURL)
        const [signer] = await hre.ethers.getSigners();
        const pyth = new hre.ethers.Contract(PYTH_ADDRESS, PythAbi, signer)

        for (const token of TOKENS) {
            console.log(token.symbol)
            let updateData
            try {
                const url = hermesBaseURL + '/v2/updates/price/latest?ids[]=' + token.priceFeed
                const response = await axios.get(url);
                updateData = ['0x' + response.data.binary.data[0]]

            } catch (error) {
                // @ts-ignore
                console.error("Error fetching API data:", error.message);
            }

            const fee = await pyth.getUpdateFee(updateData);
            console.log('fee', fee)

            const tx = await pyth.updatePriceFeeds(updateData, {value: fee});
            await tx.wait(1);

            const results = await pyth.getPriceUnsafe(token.priceFeed)
            console.log('price', results)
        }
    });

task("updatePrice", "update and get prices")
    .addParam("symbol", "token symbol")
    .setAction(async ({symbol}, hre) => {

        const {PYTH_ADDRESS, TOKENS} = getConfig(hre.network.name);
        console.log('Pyth address', PYTH_ADDRESS)

        // const hermesBaseURL = hre.network.name === 'devnet' ? 'https://hermes-beta.pyth.network' : 'https://hermes.pyth.network'
        const hermesBaseURL = 'https://hermes.pyth.network'
        console.log('Hermes', hermesBaseURL)
        const [signer] = await hre.ethers.getSigners();
        const pyth = new hre.ethers.Contract(PYTH_ADDRESS, PythAbi, signer)
        const token = TOKENS.find(t => t.symbol == symbol);

        let updateData
        try {
            const url = hermesBaseURL + '/v2/updates/price/latest?ids[]=' + token.priceFeed
            const response = await axios.get(url);
            updateData = ['0x' + response.data.binary.data[0]]

        } catch (error) {
            // @ts-ignore
            console.error("Error fetching API data:", error.message);
        }

        const fee = await pyth.getUpdateFee(updateData);
        console.log('fee', fee)

        const tx = await pyth.updatePriceFeeds(updateData, {value: fee});
        await tx.wait(1);

        const results = await pyth.getPriceUnsafe(token.priceFeed)
        console.log('price', results)

    });

task("getPriceId", "update and get USDC and SEI prices")
    .setAction(async (taskArgs, hre) => {
        const {TOKENS} = getConfig(hre.network.name);
        const oracleAddress = (await hre.deployments.get('PythOracle')).address
        const Oracle = await hre.ethers.getContractAt('PythOracle', oracleAddress)
        for (const token of TOKENS) {
            const kTokenAddress = (await hre.deployments.get(token.kToken.symbol)).address
            const KErc20Delegator = await hre.ethers.getContractAt('KErc20Delegator', kTokenAddress)
            const underlying = await KErc20Delegator.underlying()
            console.log(token.kToken.symbol, 'should have underlying', token.contractAddress, 'it has', underlying)
            const priceFeed = await Oracle.pythPriceIds(underlying)
            console.log(token.kToken.symbol, 'should have priceFeed', token.priceFeed, 'it has', priceFeed)
        }
    });

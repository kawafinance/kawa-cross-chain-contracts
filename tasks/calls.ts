import {task} from "hardhat/config";
import * as ethers from "ethers";
import {getConfig} from "../config";

// BNB - Client
task("sendBNB", "send BNB to Client")
    .setAction(async ({}, hre) => {

        if (hre.network.name !== 'bscTestnet') {
            console.log('\x1b[31m%s\x1b[0m', '\n--------> Wrong network <--------\n')
            return;
        }

        const deployer = (await hre.ethers.getSigners())[0].address;

        const kclientAddress = (await hre.deployments.get('kBNBClient')).address;
        const KClient = await hre.ethers.getContractAt('KClient', kclientAddress)
        console.log('Estimating gas...')
        const kBNBCentralHubAddress = (await hre.deployments.get('kBNBCentralHub')).address
        const kBNBCentralHub = await hre.ethers.getContractAt('CentralHub', kBNBCentralHubAddress)
        const amount = '1000000000000000'
        const mintSignature = hre.ethers.utils.keccak256(
            hre.ethers.utils.toUtf8Bytes("mint(address,uint256)")
        ).slice(0, 10);

        const payload = hre.ethers.utils.defaultAbiCoder.encode(
            ['bytes4', 'address', 'uint256'],
            [mintSignature, deployer, amount]
        )
        console.log('payload', payload)
        let gas = await kBNBCentralHub.calculateGas(payload)
        let gasStatic = await kBNBCentralHub.callStatic.calculateGas(payload)
        let finalValue = ethers.BigNumber.from(gas).add(amount)
        console.log('amount\t' , amount.toString())
        console.log('gas\t\t' , gas.toString())
        console.log('gasStatic\t',gasStatic.toString())
        console.log('finalValue\t',finalValue.toString())
        let result
        result = await KClient.callStatic.mint(amount, {value: finalValue})
        console.log(result)
        result = await KClient.mint(amount, {value: finalValue})
        await result.wait(1);
        console.log('tx hash: ', result.hash)
    });

task("borrowBNB", "borrow BNB")
    .setAction(async ({}, hre) => {
        if (hre.network.name !== hre.userConfig.defaultNetwork) {
            console.log('\x1b[31m%s\x1b[0m', '\n--------> Wrong network <--------\n')
            return;
        }
        const deployer = (await hre.ethers.getSigners())[0].address;
        let result
        const kBNBAddress = (await hre.deployments.get('kBNB')).address

        const unitrollerAddress = (await hre.deployments.get('Unitroller')).address
        const Comptroller = await hre.ethers.getContractAt('Comptroller', unitrollerAddress)
        const currentAssetsIn = await Comptroller.getAssetsIn(deployer)
        if (!currentAssetsIn.includes(kBNBAddress)) {
            console.log('Enabling collateral...')
            result = await Comptroller.enterMarkets([kBNBAddress])
            await result.wait(1)
        } else {
            console.log('Collateral already enabled.')
        }
        const borrowAmount = '10000000000000'
        console.log('Estimating gas...')

        const kBNBCentralHubAddress = (await hre.deployments.get('kBNBCentralHub')).address
        const kBNBCentralHub = await hre.ethers.getContractAt('CentralHub', kBNBCentralHubAddress)
        const releaseETHSignature =  hre.ethers.utils.keccak256(
            hre.ethers.utils.toUtf8Bytes("releaseETH(address,uint)")
        ).slice(0, 10); // '0x' + 4 bytes

        const payload = hre.ethers.utils.defaultAbiCoder.encode(["bytes4", "address", "uint256"], [releaseETHSignature, deployer, borrowAmount]);
        let gas = await kBNBCentralHub.calculateGas(payload)
        let gasStatic = await kBNBCentralHub.callStatic.calculateGas(payload)
        const finalValue = gas
        console.log('borrowAmount\t' , borrowAmount.toString())
        console.log('gas\t\t' , gas.toString())
        console.log('gasStatic\t',gasStatic.toString())
        console.log('finalValue\t',finalValue.toString())
        console.log('payload', payload)
        console.log('Borrowing BNB...')
        const kBNB = await hre.ethers.getContractAt('KErc20CrossChainDelegator', kBNBAddress)
        result = await kBNB.callStatic.borrow(borrowAmount, {value: finalValue})
        console.log(result)
        result = await kBNB.borrow(borrowAmount, {value: finalValue})
        await result.wait(1);
        console.log('tx hash: ', result.hash)
    });

task("repayBNB", "repay BNB")
    .setAction(async ({}, hre) => {
        if (hre.network.name !== 'bscTestnet') {
            console.log('\x1b[31m%s\x1b[0m', '\n--------> Wrong network <--------\n')
            return;
        }

        const deployer = (await hre.ethers.getSigners())[0].address;
        const {TOKENS} = getConfig(hre.network.name);
        const bnb = TOKENS.find(t => t.symbol == "BNB");
        const borrowAmount = '1000000000000'
        console.log('Estimating gas...')
        const kBNBCentralHubAddress = (await hre.deployments.get('kBNBCentralHub')).address
        const kBNBCentralHub = await hre.ethers.getContractAt('CentralHub', kBNBCentralHubAddress)
        const repayBorrowBehalfSignature = hre.ethers.utils.keccak256(
            hre.ethers.utils.toUtf8Bytes("repayBorrowBehalf(address,address,uint256)")
        ).slice(0, 10);
        console.log(repayBorrowBehalfSignature)
        const payload = hre.ethers.utils.defaultAbiCoder.encode(
            ['bytes4', 'address', 'address', 'uint256'],
            [repayBorrowBehalfSignature, deployer, deployer, borrowAmount])
        console.log('payload', payload)
        let gas = await kBNBCentralHub.calculateGas(payload)
        let gasStatic = await kBNBCentralHub.callStatic.calculateGas(payload)
        console.log('gas\t\t' , gas.toString())
        console.log('gasStatic\t',gasStatic.toString())
        const kBNBClientAddress = (await hre.deployments.get('kBNBClient')).address
        const KClient = await hre.ethers.getContractAt('KClient', kBNBClientAddress)
        let result
        result = await KClient.callStatic.repayBorrowBehalf(deployer, borrowAmount, {value: ethers.BigNumber.from(gas).add(borrowAmount)})
        console.log(result)
        result = await KClient.repayBorrowBehalf(deployer, borrowAmount, {value: ethers.BigNumber.from(gas).add(borrowAmount)})
        await result.wait(1);
        console.log('tx hash: ', result.hash)
    });

task("redeemBNB", "redeem BNB")
    .setAction(async ({}, hre) => {
        if (hre.network.name !== hre.userConfig.defaultNetwork) {
            console.log('\x1b[31m%s\x1b[0m', '\n--------> Wrong network <--------\n')
            return;
        }
        const deployer = (await hre.ethers.getSigners())[0].address;
        let result
        const kBNBAddress = (await hre.deployments.get('kBNB')).address
        const borrowAmount = '1000000000000'

        console.log('Estimating gas...')
        const kBNBCentralHubAddress = (await hre.deployments.get('kBNBCentralHub')).address
        const kBNBCentralHub = await hre.ethers.getContractAt('CentralHub', kBNBCentralHubAddress)

        const releaseETHSignature =  hre.ethers.utils.keccak256(
            hre.ethers.utils.toUtf8Bytes("releaseETH(address,uint)")
        ).slice(0, 10); // '0x' + 4 bytes

        const payload = hre.ethers.utils.defaultAbiCoder.encode(["bytes4", "address", "uint256"], [releaseETHSignature, deployer, borrowAmount]);

        let gas = await kBNBCentralHub.calculateGas(payload)
        console.log('gas\t\t' , gas.toString())

        console.log('Redeeming BNB...')
        const kBNB = await hre.ethers.getContractAt('KErc20CrossChainDelegator', kBNBAddress)
        result = await kBNB.redeemUnderlying(borrowAmount, {value: ethers.BigNumber.from(gas)})
        await result.wait(1);
        console.log('tx hash: ', result.hash)
    });


// Native
task("sendETH", "deposit ETH")
    .setAction(async ({}, hre) => {
        if (hre.network.name !== hre.userConfig.defaultNetwork) {
            console.log('\x1b[31m%s\x1b[0m', '\n--------> Wrong Base network <--------\n')
            return;
        }
        const deployer = (await hre.ethers.getSigners())[0].address;
        const WETHRouterAddress = (await hre.deployments.get('WETHRouter')).address
        const WETHRouter = await hre.ethers.getContractAt('WETHRouter', WETHRouterAddress)
        let result = await WETHRouter.mint(deployer, {value: '10000000000000000'})
        await result.wait(1);

        console.log('tx hash: ', result.hash)
    });

// task("sendETH2", "deposit ETH")
//     .setAction(async ({}, hre) => {
//         if (hre.network.name !== hre.userConfig.defaultNetwork) {
//             console.log('\x1b[31m%s\x1b[0m', '\n--------> Wrong Base network <--------\n')
//             return;
//         }
//         const signer = (await hre.ethers.getSigners())[0]
//         const {WETH_ADDRESS} = getConfig(hre.network.name);
//         const weth = new hre.ethers.Contract(WETH_ADDRESS, WETH_ABI, signer);
//         const amountInWei = '100000000';
//
//         const tx = await weth.deposit({value: amountInWei});
//         await tx.wait();
//         console.log(`${amountInWei} ETH wrapped into WETH.`);
//
//         console.log('tx hash: ', tx.hash)
//
//         const kEthAddress = (await hre.deployments.get('kETH')).address
//         const kEth = await hre.ethers.getContractAt('KErc20Delegator', kEthAddress)
//         let result = await kEth.mint(amountInWei)
//         await result.wait()
//         console.log(`${amountInWei} WETH deposited.`);
//         console.log('tx hash: ', result.hash)
//     });

task("borrowETH", "borrow ETH")
    .setAction(async ({}, hre) => {
        if (hre.network.name !== hre.userConfig.defaultNetwork) {
            console.log('\x1b[31m%s\x1b[0m', '\n--------> Wrong network <--------\n')
            return;
        }
        const deployer = (await hre.ethers.getSigners())[0].address;

        let result
        const kETHAddress = (await hre.deployments.get('kSEI')).address

        const unitrollerAddress = (await hre.deployments.get('Unitroller')).address
        const Comptroller = await hre.ethers.getContractAt('Comptroller', unitrollerAddress)
        const currentAssetsIn = await Comptroller.getAssetsIn(deployer)
        if (!currentAssetsIn.includes(kETHAddress)) {
            console.log('Enabling collateral...')
            result = await Comptroller.enterMarkets([kETHAddress])
            await result.wait(1)
        } else {
            console.log('Collateral already enabled.')
        }

        console.log('Borrowing ETH...')
        const kETH = await hre.ethers.getContractAt('KErc20Delegator', kETHAddress)
        result = await kETH.borrow('1000000000')
        await result.wait(1);
        console.log('tx hash: ', result.hash)
    });

task("repayETH", "repay ETH")
    .setAction(async ({}, hre) => {
        if (hre.network.name !== hre.userConfig.defaultNetwork) {
            console.log('\x1b[31m%s\x1b[0m', '\n--------> Wrong network <--------\n')
            return;
        }
        const deployer = (await hre.ethers.getSigners())[0].address;

        let result
        const WETHRouterAddress = (await hre.deployments.get('WETHRouter')).address

        console.log('Repaying ETH...')
        const WETHRouter = await hre.ethers.getContractAt('WETHRouter', WETHRouterAddress)
        result = await WETHRouter.repayBorrowBehalf(deployer, {value:'1000000000'})
        await result.wait(1);
        console.log('tx hash: ', result.hash)
    });

task("redeemETH", "redeem ETH")
    .setAction(async ({}, hre) => {
        if (hre.network.name !== hre.userConfig.defaultNetwork) {
            console.log('\x1b[31m%s\x1b[0m', '\n--------> Wrong network <--------\n')
            return;
        }
        const deployer = (await hre.ethers.getSigners())[0].address;

        let result
        const kETHAddress = (await hre.deployments.get('kETH')).address
        console.log('Redeeming ETH...')
        const kETH = await hre.ethers.getContractAt('KErc20Delegator', kETHAddress)
        result = await kETH.redeemUnderlying('1000000000')
        await result.wait(1);
        console.log('tx hash: ', result.hash)
    });

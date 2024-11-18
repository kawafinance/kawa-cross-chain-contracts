
import * as ethers from "ethers";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { readFile, readFileSync, existsSync, writeFileSync  } from "fs";
import { getConfig } from '../config'
import { Artifacts } from "../config/types";

// todo change to use wrapper
const func = async function (hre: HardhatRuntimeEnvironment) {

  const NATIVE_SYMBOL = "ETH"
  const { TOKENS } = getConfig(hre.network.name);

  const UNITROLLER_ADDRESS =  (await hre.deployments.get('Unitroller')).address
  const JUMPRATEMODEL_ADDRESS = (await hre.deployments.get('JumpRateModel')).address
  const KWETHDELEGATE_ADDRESS = (await hre.deployments.get('KWethDelegate')).address

  const deployer = (await hre.ethers.getSigners())[0].address;

  const token = TOKENS.find(r => r.symbol == NATIVE_SYMBOL)

  if (!token) {
    console.log(`Missing token config... [${NATIVE_SYMBOL}]`)
    return;
  }

  const initialExchangeRateMantissa = ethers.BigNumber.from("10").pow(token.decimals + 8).mul("2");
  
  console.log(`=== Deploying ${token.kToken.symbol} implementation ===`);


  const deploymentArgs = [
    token.contractAddress,
    UNITROLLER_ADDRESS,
    JUMPRATEMODEL_ADDRESS,
    initialExchangeRateMantissa,
    token.kToken.name,
    token.kToken.symbol,
    ethers.BigNumber.from("8"),
    deployer,
    KWETHDELEGATE_ADDRESS,
    "0x00"]

  const kTokenContract = await hre.deployments.deploy(token.kToken.symbol, {
    from: deployer,
    contract: 'KErc20Delegator',
    args: deploymentArgs,
    log: true,
    deterministicDeployment: false,
  });


  // await hre.run('verify:verify', {
  //   address: kTokenContract.address,
  //   contract: fullyQualifiedName,
  //   constructorArguments: deploymentArgs
  // })

  console.log(`Deployed a ${token.kToken.symbol} at : ${kTokenContract.address}\n`);

}

export default func
func.tags = ['kSEI']
func.dependencies = ['Unitroller', 'JumpRateModel', 'WEthDelegate']



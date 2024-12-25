
import * as ethers from "ethers";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { readFile, readFileSync, existsSync, writeFileSync  } from "fs";
import { getConfig } from '../config'
import { Artifacts } from "../config/types";

// todo change to use wrapper
const func = async function (hre: HardhatRuntimeEnvironment) {

  const { WETH_ADDRESS } = getConfig(hre.network.name);
  const kETHAddress = (await hre.deployments.get('kSEI')).address

  const deployer = (await hre.ethers.getSigners())[0].address;
  
  console.log(`=== Deploying WETHRouter  ===`);

  const deploymentArgs = [
    WETH_ADDRESS,
    kETHAddress
    ]

  const kTokenContract = await hre.deployments.deploy("WETHRouter", {
    from: deployer,
    contract: 'WETHRouter',
    args: deploymentArgs,
    log: true,
    deterministicDeployment: false,
  });

  // await hre.run('verify:verify', {
  //   address: kTokenContract.address,
  //   contract: fullyQualifiedName,
  //   constructorArguments: deploymentArgs
  // })

  console.log(`Deployed WETHRouter at : ${kTokenContract.address}\n`);

}

export default func
func.tags = ['WETHRouter']
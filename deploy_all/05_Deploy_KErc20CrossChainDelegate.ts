
import * as ethers from "ethers";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { readFile, readFileSync, existsSync, writeFileSync  } from "fs";
import { getConfig } from '../config'
import { Artifacts } from "../config/types";

const func = async function (hre: HardhatRuntimeEnvironment) {
  const deployer = (await hre.ethers.getSigners())[0].address;

  console.log("=== Deploying KErc20CrossChainDelegate implementation ===");

  const KErc20CrossChainDelegate = await hre.deployments.deploy('KErc20CrossChainDelegate', {
    from: deployer,
    args: [],
    log: true,
    deterministicDeployment: false,
  });

  // await hre.run('verify:verify', {
  //   address: KErc20CrossChainDelegate.address,
  //   contract: fullyQualifiedName,
  //   constructorArguments: []
  // })

  console.log(`Deployed a KErc20CrossChainDelegate implementation at : ${KErc20CrossChainDelegate.address}\n`);

}

export default func
func.tags = ['KErc20CrossChainDelegate']



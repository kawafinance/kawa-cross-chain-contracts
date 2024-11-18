
import * as ethers from "ethers";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { readFile, readFileSync, existsSync, writeFileSync  } from "fs";
import { getConfig } from '../config'
import { Artifacts } from "../config/types";

const func = async function (hre: HardhatRuntimeEnvironment) {  

  const {WETH_ADDRESS} = getConfig(hre.network.name)
  const deployer = (await hre.ethers.getSigners())[0].address;

  console.log("Deploying WethUnwrapper...");
  const WethUnwrapper = await hre.deployments.deploy('WethUnwrapper', {
    from: deployer,
    args: [WETH_ADDRESS],
    log: true,
    deterministicDeployment: false,
  });
  console.log(`Deployed a WethUnwrapper at : ${WethUnwrapper.address}\n`);

  console.log("=== Deploying KWethDelegate implementation ===");

  const KWethDelegate = await hre.deployments.deploy('KWethDelegate', {
    from: deployer,
    args: [WethUnwrapper.address],
    log: true,
    deterministicDeployment: false,
  });

  // await hre.run('verify:verify', {
  //   address: KWethDelegate.address,
  //   contract: fullyQualifiedName,
  //   constructorArguments: []
  // })

  console.log(`Deployed a KWethDelegate implementation at : ${KWethDelegate.address}\n`);

}

export default func
func.tags = ['WEthDelegate']



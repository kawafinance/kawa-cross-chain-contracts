
import * as ethers from "ethers";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { readFile, readFileSync, existsSync, writeFileSync  } from "fs";
import { getConfig } from '../config'
import { Artifacts } from "../config/types";

const func = async function (hre: HardhatRuntimeEnvironment) {  

  const { MODEL_BASE_RATE_YEAR, MODEL_JUMP_MULTIPLIER_PER_YEAR, MODEL_KINK, MODEL_MULTIPLIER_PER_YEAR } = getConfig(hre.network.name);

  console.log("=== Deploying JumpRateModel interest rate model ===");
  const deployer = (await hre.ethers.getSigners())[0].address;

  const jumpRateModel = await hre.deployments.deploy('JumpRateModel', {
    from: deployer,
    args: [MODEL_BASE_RATE_YEAR,
      MODEL_MULTIPLIER_PER_YEAR,
      MODEL_JUMP_MULTIPLIER_PER_YEAR,
      MODEL_KINK],
    log: true,
    deterministicDeployment: false,
  });

  // await hre.run('verify:verify', {
  //   address: jumpRateModel.address,
  //   contract: fullyQualifiedName,
  //   constructorArguments: [MODEL_BASE_RATE_YEAR,
  //     MODEL_MULTIPLIER_PER_YEAR,
  //     MODEL_JUMP_MULTIPLIER_PER_YEAR,
  //     MODEL_KINK]
  // })

  console.log(`JumpRateModel deployed: ${jumpRateModel.address}\n`);

}

export default func
func.tags = ['JumpRateModel']



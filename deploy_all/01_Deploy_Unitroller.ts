import {  HardhatRuntimeEnvironment } from "hardhat/types";
import { existsSync, writeFileSync } from "fs";
import { Artifacts } from "../config/types";

const func = async function (hre: HardhatRuntimeEnvironment) {

  console.log('Deploying Unitroller...')
  const deployer = (await hre.ethers.getSigners())[0].address;

  const unitrollerContract = await hre.deployments.deploy('Unitroller', {
    from: deployer,
    args: [],
    log: true,
    deterministicDeployment: false,
  });
  console.log('Successfully deployed Unitroller at ' + unitrollerContract.address)

  // const artifact = await hre.artifacts.readArtifact('Unitroller')
  // const fullyQualifiedName = artifact.sourceName + ":" + artifact.contractName
  //
  // console.log('Verifying Unitroller...')
  // await hre.run('verify:verify', {
  //   address: unitrollerContract.address,
  //   contract: fullyQualifiedName,
  //   constructorArguments: []
  // })
}

export default func
func.tags = ['Unitroller']



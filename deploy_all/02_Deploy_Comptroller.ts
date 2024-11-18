
import * as ethers from "ethers";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { readFile, readFileSync, existsSync, writeFileSync  } from "fs";
import { getConfig } from '../config'
import { Artifacts } from "../config/types";

const func = async function (hre: HardhatRuntimeEnvironment) {  

  const { CLOSE_FACTOR, LIQUIDATION_INCENTIVE } = getConfig(hre.network.name);
  const deployer = (await hre.ethers.getSigners())[0].address;

  console.log("=== Deploying Comptroller... ===");

  const comptrollerDeployed = await hre.deployments.deploy('Comptroller', {
    from: deployer,
    args: [],
    log: true,
    deterministicDeployment: false,
  });


  console.log(`Comptroller deployed: ${comptrollerDeployed.address}\n`);

  // await hre.run('verify:verify', {
  //   address: comptrollerDeployed.address,
  //   contract: fullyQualifiedName,
  //   constructorArguments: []
  // })

  const UNITROLLER_ADDRESS =  (await hre.deployments.get('Unitroller')).address
  const unitrollerContract = await hre.ethers.getContractAt('Unitroller', UNITROLLER_ADDRESS)
  const comptrollerContract = await hre.ethers.getContractAt('Comptroller', comptrollerDeployed.address)

  console.log("=== Configuring Unitroller ===");

  console.log("Setting pending implementation")
  const setPendingImplementationResult = await unitrollerContract._setPendingImplementation(comptrollerDeployed.address);
  await setPendingImplementationResult.wait(1);

  console.log("Accepting new implementation")
  const becomeResult = await comptrollerContract._become(UNITROLLER_ADDRESS);
  await becomeResult.wait(1)

  console.log("Proxy configured\n");

  // Save the implementation of Comptroller for output at end of script and
  // connect to Comptroller through the proxy
  const comptroller = await hre.ethers.getContractAt('Comptroller', UNITROLLER_ADDRESS)

  console.log("=== Configuring Comptroller ===");

  console.log("Setting close factor");
  const setCloseFactorResult = await comptroller._setCloseFactor(CLOSE_FACTOR);
  await setCloseFactorResult.wait(1)

  console.log("Setting liquidation incentive\n")
  const setLiquidationIncentive = await comptroller._setLiquidationIncentive(LIQUIDATION_INCENTIVE);
  await setLiquidationIncentive.wait(1)

  console.log("=== Setting Ownerships for Comptroller ===");

  console.log("Pause Guardian:", deployer);

  console.log("Setting borrow cap guardian");
  let setGuardianResult = await comptroller._setBorrowCapGuardian(deployer);
  await setGuardianResult.wait(1)

  console.log("Setting pause guardian");
  setGuardianResult = await comptroller._setPauseGuardian(deployer);
  await setGuardianResult.wait(1)

  const adminAddress = deployer
  console.log("Admin:", adminAddress);

  console.log("Setting pending admin");
  const setAdminResult = await unitrollerContract._setPendingAdmin(adminAddress);
  await setAdminResult.wait(1);
  console.log("")

}

export default func
func.tags = ['Comptroller']
func.dependencies = ['Unitroller']



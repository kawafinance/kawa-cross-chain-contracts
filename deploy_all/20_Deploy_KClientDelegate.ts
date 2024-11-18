import { HardhatRuntimeEnvironment } from "hardhat/types";

const func = async function (hre: HardhatRuntimeEnvironment) {
  const deployer = (await hre.ethers.getSigners())[0].address;

  console.log("=== Deploying KClientDelegate implementation ===");

  const KClientDelegate = await hre.deployments.deploy('KClientDelegate', {
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

  console.log(`Deployed a KClientDelegate implementation at : ${KClientDelegate.address}\n`);

}

export default func
func.tags = ['KClientDelegate']



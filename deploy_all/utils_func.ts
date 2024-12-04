import path from "path";
import {readFileSync} from "fs";

export function getDeploymentAddress(networkName: string, contractName: string) {
    let returnAddress = "0x0000000000000000000000000000000000000000"
    try {
        // Construct the path to the deployment file
        const deploymentPath = path.resolve(
            process.cwd(),
            `deployments/${networkName}/${contractName}.json`
        );

        // Read and parse the deployment file
        const deploymentData = JSON.parse(readFileSync(deploymentPath, "utf-8"));
        returnAddress = deploymentData.address;
    } catch (error) {
        // Return the zero address if deployment data is not found
    }

    return returnAddress;
}
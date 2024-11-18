import * as dotenv from 'dotenv'
import '@nomiclabs/hardhat-ethers'
import '@nomiclabs/hardhat-waffle'
import '@nomiclabs/hardhat-truffle5'
import '@nomiclabs/hardhat-etherscan'
import '@typechain/hardhat'
import '@openzeppelin/hardhat-upgrades'
// import 'hardhat-gas-reporter'
// import 'solidity-coverage'
import 'hardhat-deploy'
import "./tasks";

dotenv.config()

const accountsMainnet = [process.env.PRIVATE_KEY_MAINNET || '']
const accountsTestnet = [process.env.PRIVATE_KEY_TESTNET || '']

const config: any = {
  defaultNetwork: "sepolia",
  solidity: {
    version: '0.8.20',
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      }
    },
  },
  networks: {
    hardhat: {
      chainId: 1337,
      allowUnlimitedContractSize: true,
    },
    local: {
      url: "http://localhost:3050",
      // ethNetwork: "http://localhost:8545",
    },
    mainnet: {
      chainId: 1329,
      url: "https://evm-rpc.sei-apis.com",
      accounts: accountsMainnet
    },
    devnet: {
      chainId: 713715,
      url: "https://evm-rpc-arctic-1.sei-apis.com",
      gas: 8400000,
      // blockGasLimit: 35000000,
      accounts: accountsTestnet
    },
    testnet: {
      chainId: 1328,
      url: "https://evm-rpc-testnet.sei-apis.com",
      accounts: accountsTestnet
    },
    sepolia: {
      chainId: 11155111,
      url: "https://rpc.sepolia.org", //https://rpc.ankr.com/eth_sepolia  https://ethereum-sepolia.publicnode.com https://sepolia.rpc.thirdweb.com
      accounts: accountsTestnet
    },
    bnbTestnet: {
      chainId: 97,
      url: "https://data-seed-prebsc-1-s1.binance.org:8545/",
      accounts: accountsTestnet
    },
    // namedAccounts: {
    //   deployer: {
    //     default: 0
    //   },
    //   // liquidator: {
    //   //   default: 1
    //   // }
    // }
  },
};

export default config;
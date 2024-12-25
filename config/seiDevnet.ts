import { Config } from './types'
import {BigNumber} from "ethers";

export const config: Config = {

  // Jump model parameters
  MODEL_BASE_RATE_YEAR: BigNumber.from("20000000000000000"), // 2%
  MODEL_MULTIPLIER_PER_YEAR: BigNumber.from("100000000000000000"), // 10%
  MODEL_JUMP_MULTIPLIER_PER_YEAR: BigNumber.from("1090000000000000000"), // 109%
  MODEL_KINK: BigNumber.from("800000000000000000"), // 80%

  // Comptroller params
  CLOSE_FACTOR: BigNumber.from("500000000000000000"), // 50%
  LIQUIDATION_INCENTIVE: BigNumber.from("1100000000000000000"), // 110%

  PYTH_ADDRESS: "0xe9d69CdD6Fe41e7B621B4A688C5D1a68cB5c8ADc",

  AXELAR_GATEWAY: "",
  AXELAR_GAS_RECEIVER: "",
  AXELAR_CHAIN_NAME: "",

  WORMHOLE_RELAYER: "",
  WORMHOLE_CHAIN_ID: 0,

  LAYERZERO_ENDPOINT: "0x6EDCE65403992e310A62460808c4b910D972f10f",
  LAYERZERO_CHAINID: 40258,

  WETH_ADDRESS: "0x027D2E627209f1cebA52ADc8A5aFE9318459b44B",

  TOKENS: [
    {
      name: "SEI",
      symbol: "SEI",
      priceFeed: "0x53614f1cb0c031d4af66c04cb9c756234adad0e1cee85303795091499a4084eb",
      decimals: 18,
      contractAddress: "0x027D2E627209f1cebA52ADc8A5aFE9318459b44B",
      kToken: {
        symbol: "kSEI",
        name: "Kawa SEI",
        collateralFactor: 70,
        reserveFactor: 30,
        seizeShare: 3,
        address: null
      },
      adapters: null,
      collateralFactor: 70,
      borrowCap: 0,
      peerChain: null
    },
    {
      name: "ETH",
      symbol: "ETH",
      priceFeed: "0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace",
      decimals: 18,
      contractAddress: null,
      kToken: {
        symbol: "kETH",
        name: "Kawa ETH",
        collateralFactor: 70,
        reserveFactor: 30,
        seizeShare: 3,
        address: null
      },
      collateralFactor: 70,
      borrowCap: 0,
      adapters: {
        axelar:{
          peerChain: "",
        },
        wormhole: {
          peerChain: 0
        },
        layerZero: {
          peerChain: 40161
        }
      },
      peerChain: 'sepolia',
    },
    {
      name: "BNB",
      symbol: "BNB",
      priceFeed: "0x2f95862b045670cd22bee3114c39763a4a08beeb663b145d283c31d7d1101c4f",
      decimals: 18,
      contractAddress: null,
      kToken: {
        symbol: "kBNB",
        name: "Kawa BNB",
        collateralFactor: 70,
        reserveFactor: 30,
        seizeShare: 3,
        address: null
      },
      collateralFactor: 70,
      borrowCap: 0,
      adapters: {
        axelar:{
          peerChain: "binance",
        },
        wormhole: {
          peerChain: 4
        },
        layerZero: {
          peerChain: 40102
        }
      },
      peerChain: 'bscTestnet'
    }
  ]
};


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
  
  PYTH_ADDRESS: "0xDd24F84d36BF92C65F92307595335bdFab5Bbd21",

  AXELAR_GATEWAY: "0xe432150cce91c13a887f7D836923d5597adD8E31",
  AXELAR_GAS_RECEIVER: "0xbE406F0189A0B4cf3A05C286473D23791Dd44Cc6",
  AXELAR_CHAIN_NAME: "ethereum-sepolia",
  
  WETH_ADDRESS: "0x7b79995e5f793a07bc00c21412e50ecae098e7f9",

  TOKENS: [
    {
      name: "ETH",
      symbol: "ETH",
      priceFeed: "0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace",
      decimals: 18,
      contractAddress: "0x7b79995e5f793a07bc00c21412e50ecae098e7f9",
      kToken: {
        symbol: "kETH",
        name: "Kawa ETH",
        collateralFactor: 70,
        reserveFactor: 30,
        seizeShare: 3,
        address: null
      },
      otherChainMessageHub: null,
      otherChain: null,
      collateralFactor: 70,
      borrowCap: 1
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
      otherChainMessageHub: "0x6f6318b3840C875106fDf1569776856022B4b28F",
      otherChain: "binance",
      collateralFactor: 70,
      borrowCap: 1
    }
  ]
};


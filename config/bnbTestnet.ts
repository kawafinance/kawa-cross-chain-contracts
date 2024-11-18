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

  PYTH_ADDRESS: "0x5744Cbf430D99456a0A8771208b674F27f8EF0Fb",

  AXELAR_GATEWAY: "0x4D147dCb984e6affEEC47e44293DA442580A3Ec0",
  AXELAR_GAS_RECEIVER: "0xbE406F0189A0B4cf3A05C286473D23791Dd44Cc6",
  AXELAR_CHAIN_NAME: "binance",
  
  WETH_ADDRESS: "",

  TOKENS: [
    {
      name: "BNB",
      symbol: "BNB",
      priceFeed: "0x2f95862b045670cd22bee3114c39763a4a08beeb663b145d283c31d7d1101c4f",
      decimals: 18,
      contractAddress: "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE",
      kToken: {
        symbol: "kBNB",
        name: "Kawa BNB",
        collateralFactor: 70,
        reserveFactor: 30,
        seizeShare: 3,
        address: null
      },
      otherChainMessageHub: "0xFEaaaf812e5BB9488eA9Ba48818F6b4b46e61993",
      otherChain: "ethereum-sepolia",
      collateralFactor: 70,
      borrowCap: 1
    }
  ]
};


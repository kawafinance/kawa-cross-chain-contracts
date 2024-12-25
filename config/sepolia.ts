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

  WORMHOLE_RELAYER: "0x7B1bD7a6b4E61c2a123AC6BC2cbfC614437D0470",
  WORMHOLE_CHAIN_ID: 10002,

  LAYERZERO_ENDPOINT: "0x6EDCE65403992e310A62460808c4b910D972f10f",
  LAYERZERO_CHAINID: 40161,
  
  WETH_ADDRESS: "0x7b79995e5f793a07bc00c21412e50ecae098e7f9",

  TOKENS: [
    {
      name: "ETH",
      symbol: "ETH",
      priceFeed: "0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace",
      decimals: 18,
      contractAddress: "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE",
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
          peerChain: "",//ethereum-sepolia
        },
        wormhole: {
          peerChain: 0,//10002
        },
        layerZero: {
          peerChain: 40258,
        }
      },
      peerChain: 'seiDevnet'
    }
  ]
};


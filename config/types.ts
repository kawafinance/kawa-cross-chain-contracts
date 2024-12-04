import { BigNumber } from 'ethers'

export type Config = {

  // Jump model parameters
  MODEL_BASE_RATE_YEAR: BigNumber
  MODEL_MULTIPLIER_PER_YEAR: BigNumber
  MODEL_JUMP_MULTIPLIER_PER_YEAR: BigNumber
  MODEL_KINK: BigNumber

  PYTH_ADDRESS: string

  AXELAR_GATEWAY: string,
  AXELAR_GAS_RECEIVER: string,
  AXELAR_CHAIN_NAME: string,

  WORMHOLE_RELAYER: string,
  WORMHOLE_CHAIN_ID: number,

  WETH_ADDRESS: string

  // Comptroller params
  CLOSE_FACTOR: BigNumber
  LIQUIDATION_INCENTIVE: BigNumber
  TOKENS: Array<Token>

}

export type Artifacts = {
  MULTICALL_ADDRESS?: string;
  UNITROLLER_ADDRESS?: string;
  COMPTROLLER_ADDRESS?: string;
  JUMPRATEMODEL_ADDRESS?: string;
  BERC20DELEGATE_ADDRESS?: string;
  BETH_ADDRESS?: string;
  BUSDC_ADDRESS?: string;
  MAXIMILLION_ADDRESS?: string;
  PYTHORACLE_ADDRESS?: string;
  FAUCET_ADDRESS?: string;
  KAWA_ADDRESS?: string;
  PRICE_PROVIDER_ADDRESS?: string
  LOCKER_LIST?: string;
  INCENTIVES_DISTRIBUTOR_ADDRESS?: string
  REWARDS_CONTROLLER_ADDRESS?:string
  INCENTIVES_ELIGIBILITY_ADDRESS?:string
  INCENTIVES_CONTROLLER_ADDRESS?: string
  BOUNTY_MANAGER_ADDRESS?: string
  LOCK_ZAP_ADDRESS?: string
  INCENTIVES_COMPOUNDER_ADDRESS?: string
  SYNCSWAP_LIQUIDATOR_ADDRESS?: string
  MUTE_LIQUIDATOR_ADDRESS?: string
  DRAGONSWAP_LIQUIDATOR_ADDRESS?: string
  TOKENSALE_ADDRESS?: string
  MERKLEDISTRIBUTOR_ADDRESS?: string
}

export type kToken = {
  // Prepopulated Properties
  name: string
  symbol: string
  seizeShare: number
  reserveFactor: number
  collateralFactor: number

  // Populated on deploy
  address: string | null
}

// A token that is being deployed.
export type Token = {
  // Prepopulated Properties
  name: string,
  symbol: string
  decimals: number
  kToken: kToken

  // The address of the contract, or null
  // If null, then a contract will be deployed.
  // TODO(lunar): Refactor to be `address` for consistency
  contractAddress: string | null

  // The address of the Chainlink Price feed, or null
  // If null, the a chainlink price feed will be deployed.
  priceFeed: string | null
  priceFeedBeta?: string | null
  adapters:{
    axelar:{
      peerChain: string
    },
    wormhole: {
      peerChain: number
    }
  } | null
  collateralFactor: number
  borrowCap: number
}

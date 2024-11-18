import { Config } from './types'

export const getConfig = (networkName: string) : Config => {
    return require('./' + networkName).config
}
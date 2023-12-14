import axios from "axios"
import { getValidTokens } from "./tokens.js"

export const getPriceFeed = async (cryptoSlug = false) => {
    if( ! cryptoSlug || ! getValidTokens().includes(cryptoSlug)) return false
    const response = await axios.get(
        `https://benchmarks.pyth.network/v1/price_feeds/?query=${cryptoSlug}&asset_type=crypto`
    )
    if( response.status === 200 ) {
        const priceFeedId = response.data[0].id
        const feedData = await axios.get(
            `https://xc-mainnet.pyth.network/api/latest_vaas?ids[]=${priceFeedId}`
        )
        if( feedData.status === 200) {
            const priceFeed = feedData.data
            return priceFeed.map(e=>"0x" + Buffer.from(e, "base64").toString("hex"))
        }
    }
}
export const getPrice = async (token) => {
    const period = () => {
        let date = parseInt(new Date().getTime() / 1000)
        return `&from=${date-60*5}&to=${date}`
    }
    const resp = await axios.get(`https://api.fulcrom.finance/candle_by_range?token=${token}_usd&period=5m${period()}`)
    return resp.data.prices[0]?.c
}
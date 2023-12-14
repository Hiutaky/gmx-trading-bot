import { BigNumber, ethers } from "ethers"

const TOKENS = [{
    name: 'btc',
    size: '0.0005',
    address: '0x062e66477faf219f25d27dced647bf57c3107d52'
},{
    name: 'eth',
    size: '0.01',
    address: '0xe44fd7fcb2b1581822d0c862b68222998a0c299a'
}]

export const payloadToTuple = (payload) => {
    return Object.keys(payload).map( key => payload[key])
}

export const getOrderSize = (name) => {
    return TOKENS.filter( (a, i) => a.name === name )[0]?.size
}

export const getTokenNameByAddress = (address) => {
    if( ethers.utils.isAddress(address) ) {
        const token = TOKENS.filter( token => token.address.toLocaleLowerCase() === address.toLocaleLowerCase() )[0]
        return token && token.name ? token.name : false
    } else return false
}
export const getValidTokens = () => {
    return TOKENS.map( token => token.name )
}

export const getEventName = (event) => {
    return event[event.length-1].event
}
export const getEventArgs = (event) => {
    const argsI = event.length-1
    const {args: rawArgs} = event[argsI]
    let args = {}
    Object.entries(rawArgs).map( (entry) => {
        if( isNaN( parseInt(entry[0]) ) ) {
            args[entry[0]] = entry[1]
        }
    })
    return args
}


export const dummyTx = [{
    account: '0xd35200d41217b9549b1a5bd7765409ec3bf480b3',
    args: {
        path: ['0x062E66477Faf219F25D27dCED647BF57C3107d52'],
        indexToken: '0x062E66477Faf219F25D27dCED647BF57C3107d52',
        sizeDelta: BigNumber.from('324063306240000000000000000000000'),
        isLong: true,
        acceptablePrice: BigNumber.from('41038762950000000000000000000000000'),
        minOut: BigNumber.from('0'),
        executionFee: BigNumber.from('4000000000000000000'),
        referralCode: '0x0000000000000000000000000000000000000000000000000000000000000000',
        callbackTarget: '0x0000000000000000000000000000000000000000',
        priceData: ["0x0000000000000000000000000000000000000000000000000000000000000000"],
        amountIn: BigNumber.from('100000'),
    }
}]

export default TOKENS
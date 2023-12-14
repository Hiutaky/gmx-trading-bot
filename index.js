/**
 * This script is not suitable for production so
 * USE AT YOUR OWN RISK !
 * 
 * Created by @hiutaky
 */

import ethers, { BigNumber, constants, utils } from "ethers"
import dotenv from 'dotenv';
import PositionRouterAbi from "./abis/PositionRouter.json" assert { type: "json" }
import OrderBookAbi from "./abis/OrderBook.json" assert { type: "json" }
import ERC20Abi from "./abis/ERC20.json" assert { type: "json" }
import ReaderAbi from "./abis/Reader.json" assert { type: "json" }
import TOKENS, { getEventArgs, getEventName, getOrderSize, getTokenNameByAddress, payloadToTuple } from "./src/utils/tokens.js";
dotenv.config()

const BN0 =  BigNumber.from('0')
const CRONOS_RPC = 'https://evm.cronos.org'
const UserToTrack = process.env.ADDRESS_TO_COPY.toLowerCase()

const Fulcrom = {
    addresses: {
        positionRouter: '0x27fb69422c457452d8b6fdcb18899d9b53c3f940',
        reader: '0x3881df9c3115aA4a2E35C080764B5Dd8112dE177',
        valut: '0x8C7Ef34aa54210c76D6d5E475f43e0c11f876098',
        orderBook: '0x1c29aeE30B5B101eDEa936Cd0cAeEc724e3B0045'
    },
    PositionRouter: false,
    Reader: false,
    Valut: false,
    OrderBook: false
}

let Signer = false
let Contracts = {}
let Balances = {}
let Decimals = {}
let Balance = BN0
let Tradable = {}

const initUser = async () => {
    console.log('Loading Account and balances')
    const RPC_Provider = new ethers.providers.JsonRpcProvider(CRONOS_RPC)
    Signer = new ethers.Wallet( process.env.PRIVATE_KEY, RPC_Provider )
    Balance = await Signer.getBalance()
    for( let i = 0; i < TOKENS.length; i++ ) {
        const {name, address} = TOKENS[i]
        Contracts[name] = new ethers.Contract(
            address,
            ERC20Abi,
            Signer
        )
        Balances[name] = await Contracts[name].balanceOf( Signer.address )
        Decimals[name] = await Contracts[name].decimals()
    }
    console.log(`Welcome ${Signer.address} - Balances`)
    console.log(`  Governance: ${ethers.utils.formatEther(Balance)} CRO`)
    Object.keys(Balances).map( (name, i) => {
        const orderSize = utils.parseUnits( TOKENS[i].size, Decimals[name] )
        const enoughBalance = Balances[name].gte( orderSize )
        Tradable[name] = enoughBalance
        console.log( `  ${name.toUpperCase()}: ${ethers.utils.formatUnits(Balances[name], Decimals[name])} - ${ enoughBalance ? `OK` : `You don't have enough balance based on Size Order for ${name}: ${ utils.formatUnits( orderSize, Decimals[name] ) }`  }` )
    })
}

const listenToEvents = async () => {
    console.log('Loading Contracts')
    Fulcrom.PositionRouter = new ethers.Contract(
        Fulcrom.addresses.positionRouter,
        PositionRouterAbi,
        Signer
    )
    Fulcrom.OrderBook = new ethers.Contract(
        Fulcrom.addresses.orderBook,
        OrderBookAbi,
        Signer
    )
    Fulcrom.Reader = new ethers.Contract(
        Fulcrom.addresses.reader,
        ReaderAbi,
        Signer
    )
    console.log('Starting Event Handlers')
    Fulcrom.PositionRouter.on("CreateIncreasePosition", async (...args) => await handleIncreasePosition(args) )
    Fulcrom.PositionRouter.on("CreateDecreasePosition", async (...args) => await handleDecreasePosition(args) )
    //Fulcrom.OrderBook.on("CreateIncreaseOrder", async (...args) => await handleIncreasePosition(args) )
    //Fulcrom.OrderBook.on("CreateDecreaseOrder", async (...args) => await handleDecreasePosition(args))
}

const getUserPostion = async (name, isLong) => {
    const contractAddress = TOKENS.filter( token => token.name === name )[0].address
    return await Fulcrom.Reader.getPositions(
        Fulcrom.addresses.valut,
        Signer.address,
        [contractAddress],
        [contractAddress],
        [isLong]
    )
}

const handleDecreasePosition = async (event) => {
    const args = getEventArgs(event)
    const eventName = getEventName(event)
    const isMarketOrder = eventName === 'CreateDecreasePosition'
    const name = getTokenNameByAddress(args.indexToken)
    if( ! name || args.account.toLowerCase() !== UserToTrack ) return
    const positionRouter = getUserPostion( name, args.isLong )
    if( isMarketOrder ) {
        if( positionRouter.length ) {
            const payload = {
                path: args.path,
                indexToken: args.indexToken,
                collateralDelta: BN0,
                sizeDelta: positionRouter[0],
                isLong: args.isLong,
                receiver: Signer.address,
                acceptablePrice: args.acceptablePrice,
                minOut: BN0,
                executionFee: args.executionFee,
                withdrawETH: false,
                callbackTarget: constants.AddressZero,
                priceData: [] 
            }
            const formatted = payloadToTuple(payload)
            const tx = await Fulcrom.PositionRouter.createDecreasePosition(
                formatted, 
                {
                    value: utils.parseEther('4')
                }
            )
            const recipit = await tx.wait(2)
            console.log(`Position Closed`, recipit)
        }
    } else {
        //Handle Trigger Orders
    }
}

const handleIncreasePosition = async (event) => {
    const args = getEventArgs(event)
    const name = getTokenNameByAddress(args.indexToken)
    const eventName = getEventName(event)
    const isMarketOrder = eventName === 'CreateIncreasePosition'

    if( ! name || args.account.toLowerCase() !== UserToTrack ) return //return if traded token not available in TOKENS or User is differentt than UserToTrack
    if( ! Tradable[name] ) return //return if there's not enough balance based on Token Position Size

    const eventAmountIn = isMarketOrder ? args.amountIn : args.purchaseTokenAmount
    const execPrice = isMarketOrder ? args.acceptablePrice : args.triggerPrice 
    const collateralInUsd = eventAmountIn.mul( execPrice )
    const leverage = args.sizeDelta.mul('10000000000').div(collateralInUsd)

    const personalSize = getOrderSize(name)
    const amountIn =  utils.parseUnits( personalSize, Decimals[name] )
    
    console.log(``)
    console.log(`Valid Incoming ${name.toUpperCase()} ${ args.isLong ? `LONG` : `SHORT` }`, `${leverage / 100}x` )
    let tx = false
    let sizeDelta, acceptablePrice = false
    if( isMarketOrder ) {
        sizeDelta = amountIn.mul(leverage).mul(args.acceptablePrice).div(100).div(10**8)
        const payload = {
            path: args.path,
            indexToken: args.indexToken,
            sizeDelta: sizeDelta,
            isLong: args.isLong,
            acceptablePrice: args.acceptablePrice,
            minOut: args.minOut,
            executionFee: args.executionFee,
            referralCode: constants.HashZero,
            callbackTarget: constants.AddressZero,
            priceData: []//priceData
        }
        const formattedPayload = payloadToTuple(payload)
        tx = await Fulcrom.PositionRouter.createIncreasePosition(
            formattedPayload, 
            amountIn, 
            {
                value: utils.parseEther(`4`)
            }
        )
    } else {
        sizeDelta = amountIn.mul(leverage).mul(args.triggerPrice).div(100).div(10**8)
        tx = await Fulcrom.OrderBook.createIncreaseOrder(
            [args.indexToken], //path
            amountIn, //amountIn
            args.indexToken, //indexToken
            BN0, //minOut
            sizeDelta, //sizeDelta
            args.indexToken, //collateralToken
            args.isLong,//isLong
            args.triggerPrice, //triggerPrice
            args.triggerAboveThreshold, //triggerAboveThreshold,
            args.executionFee,//executionFee
            false,
            {
                value: args.executionFee //executionFee || value, must be the same value
            }
        )
    }
    console.log('Trade Transaction Sent, waiting for confirmation...')
    const recipit = await tx.wait(2)
    console.table([
        {
            action: 'Fetch', 
            margin: `$${utils.formatUnits( collateralInUsd, 38 )}`, 
            size: `$${utils.formatUnits( args.sizeDelta, 30 ) }`,
            leverage: `${leverage / 100}x`
        },{
            action: 'Executed', 
            margin: `$${utils.formatUnits( amountIn.mul(acceptablePrice), 38 )}`, 
            size: `$${utils.formatUnits( sizeDelta, 38 ) }`,
            leverage: `${leverage / 100}x`
        }
    ])
}
const main = async ( ) => {
    await initUser()
    await listenToEvents()
}

try {
    main()
} catch ( e ) {
    console.error(e)
}


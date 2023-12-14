import { ethers, constants, BigNumber } from "ethers"
import { payloadToTuple } from "../utils/tokens.js"

class PositionRouter {
    constructor (
        address = false,
        abi = false,
        signer = false
     ) {
        this.contract = new ethers.Contract(
            address,
            abi,
            signer
        )
        this.signer = signer
    }

    async increasePosition( amountIn, args, decimals ) {
        //tracked user details
        const collateralInUsd = 
            args.amountIn
                .mul( args.acceptablePrice )
        const leverage = 
            args.sizeDelta
                .mul(100)
                .mul(10**decimals)
                .div(collateralInUsd)
        //execute market order - createIncreasePosition
        const sizeDelta = 
            amountIn
                .mul(leverage)
                .mul(args.acceptablePrice)
                .div(100)
                .div(10**decimals)
        //more info about the payload ./contracts/PositionRouter.sol:36
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
            priceData: []//priceData | not needed since we don't want to update the priceFeed and it cost less
        }
        //more info about the request ./contracts/PositionRouter.sol:331
        const tx = await this.contract.createIncreasePosition(
            payloadToTuple(payload),
            amountIn,
            {
                value: args.parseEther(`4`)
            }
        )
        return { 
            leverage: leverage,
            sizeDelta: sizeDelta,
            collateral: sizeDelta.div(leverage),
            eventCollateral: collateralInUsd,
            tx: tx,
        }
    }
    
    async decreasePosition(sizeDelta, args) {
        const payload = {
            path: args.path,
            indexToken: args.indexToken,
            collateralDelta: BigNumber.from('0'),
            sizeDelta: sizeDelta,
            isLong: args.isLong,
            receiver: this.signer.address,
            acceptablePrice: args.acceptablePrice,
            minOut: BigNumber.from('0'),
            executionFee: args.executionFee,
            withdrawETH: false,
            callbackTarget: constants.AddressZero,
            priceData: [] 
        }
        const tx = await this.contract.createDecreasePosition(
            payloadToTuple(payload), 
            {
                value: utils.parseEther('4')
            }
        )
        return {
            tx: tx
        }
    }
}

export default PositionRouter
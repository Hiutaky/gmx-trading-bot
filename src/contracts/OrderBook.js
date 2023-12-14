import { BigNumber, ethers } from "ethers"

class OrderBook {
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

    async increaseOrder (amountIn, args, decimals) {
        const collateralInUsd = 
            args.purchaseTokenAmount
                .mul( args.triggerPrice )
        const leverage = 
            args.sizeDelta
                .mul(100)
                .mul(10**decimals)
                .div(collateralInUsd)
        //execute trigger order - createIncreaseOrder
        const sizeDelta = 
            amountIn
                .mul(leverage)
                .mul(args.triggerPrice)
                .div(100)
                .div(10**decimals)
        //check ./contracts/OrderBook.sol:575
        const tx = await Fulcrom.OrderBook.createIncreaseOrder(
            [args.indexToken], //path
            amountIn, //amountIn
            args.indexToken, //indexToken
            BigNumber.from('0'), //minOut
            sizeDelta, //sizeDelta
            args.indexToken, //collateralToken
            args.isLong,//isLong
            args.triggerPrice, //triggerPrice
            args.triggerAboveThreshold, //triggerAboveThreshold,
            args.executionFee,//executionFee
            false,
            {
                value: args.executionFee //must be the same value of executionFee
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

    async decreaseOrder (sizeDelta, args) {
        const { indexToken } = args
        //check ./contracts/OrderBook.sol:768
        const tx = await this.contract.createDecreaseOrder(
            indexToken,
            sizeDelta,
            indexToken,
            BigNumber.from('0'),
            args.isLong,
            args.triggerPrice,
            args.triggerAboveThreshold
        )
        return {
            tx: tx
        }
    }
}
export default OrderBook
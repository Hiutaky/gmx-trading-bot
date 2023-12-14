## Fulcrom Copy-Trade Bot

  **This Bot is not suitable for PRODUCTION, require more advanced controls over balances, positions management and so on, use at your own risk!**

**Fulcrom Copy-Trade Bot** is a node.js script that aim to introduce Copy-Trading strategies on GMX-like forks Decentralized Leveraged Exchanges.

The script is pretty easy and leverage Smart Contracts Events and methods to track and execute trades seconds after the tracked user operate.
## How it works
Every time an user execute a Market Order ( emit **CreateIncreasePosition** ) or a Trigger Order ( emit **CreateIncreaseOrder** ), the bot will fetch these events and check if the user initializing the request is the same we want to copy trade, if so the Bot will extract trade details like:

- **deltaSize**: leveraged position value in USD
- **amountIn**: amount of collateral used for the trade
- **acceptablePrice**: price at which the trade can be executed ( include slippage )

By using these parameters we can easily get the approximative leverage used by the executor:

    leverage = deltaSize / amountIn / accetablePrice
At this point, we can use this information to prepare our copy-trade. 

Instead of replicating the same trade, that is mainly impossibile since we don't know the amount of collateral needed each time, we can instead define our position size for each Token in the **./src/utils/tokens.js** file:

    const  TOKENS = [{
	    name: 'btc',
	    size: '0.0005',
	    address: '0x062e66477faf219f25d27dced647bf57c3107d52'
    },{
	    name: 'eth',
	    size: '0.01',
	    address: '0xe44fd7fcb2b1581822d0c862b68222998a0c299a'
    }]

The position size will be used to calculate the collateral we want to trade for each operation and also to our deltaSize based on the user's leverage.

Our deltaSize is then calculated using this simple forumla:

    deltaSize = leverage * amountIn * accetablePrice

## Pratical Example:

**Copy-User Position**: 
 - amountIn: 0.005 BTC ( 210 USD )
 - acceptablePrice: 42 000 USD
 - deltaSize: 2100 USD
 - leverage = 2100 / 0.005 / 42 000 = 10

**Our Position**
- amountIn: 0.0005 BTC ( 21 USD )
- acceptablePrice: 42 000 USD ( same )
- leverage: 10x
- deltaSize = 0.0005 * 42 000 * 10 = 210 USD
## How to run the bot
First of all you must configurate your **.env** file, rename **.env.example** to **.env** or create a new one and paste your Signer Account Private Key and the address of the user you want to copy-trade.

I suggest to create a brand new Wallet and transfer only funds you want to use in your trading strategy.
### Configure Position Sizes
Change the values related to the Position Sizes into ./src/utils/tokens.js with the ones your feel comfortable to. Remember that the minimum amount of collateral allowed by Fulcrom is at least 10$. You can also add other supported tokens, right now only WETH and WBTC are available.
### Run the Bot
If it's the first time your start the bot, remember to run the `npm i` command to install all the needed dependencies. 

Once the dependencies are installed, the .env file and tokens.js are succesfully configured you can run the bot launching `npm start` command.

The Bot will first initialize the Signer and then print the balances of the Tokens available in tokens.js. After that the Fulcrom contracts will be attached and the bot will starts to listen to contract's Events.
## To-Do

 - Positions management
 - Improve position close
 - Introduce support for Trigger Orders open/close 
 - Logging system

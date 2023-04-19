var {
    VOID_ETHEREUM_ADDRESS,
    VOID_BYTES32,
    blockchainCall,
    compile,
    deployContract,
    abi,
    MAX_UINT256,
    web3Utils,
    fromDecimals,
    toDecimals,
    sendBlockchainTransaction,
    calculateTransactionFee,
} = require('@ethereansos/multiverse');
var buildOSStuff = require('../../resources/OS/buildOsStuff');
var fs = require('fs');
var misc = require("../misc");
var path = require('path');

// Contracts
var FarmingGen1;
var FarmFactory;
var UniswapV2AMMV1;
var FarmingGen1Extension;
var DFOBasedFarmExtension;
var DFOBasedFarmExtensionFactory;
// Useful variables
var byMint;
var ethItemOrchestrator;
var uniswapV2Router;
var uniswapV2Factory;
var wethToken;
var rewardToken;
var mainToken;
var secondaryToken;
var farmFactory;
var farmMainExtension;
// var pinnedFarmExtension;
var clonedDefaultFarmExtension;
var clonedFarmExtension;
var dfo;
var pinnedDfo;
var farmMainContract;
// var pinnedFarmContract;
var liquidityPool;
var uniswapAMM;
var ethToSpend = 600;
var farmTokenCollection;
var rewardDestination;
var oneHundred;
var extensionOwner = VOID_ETHEREUM_ADDRESS;
var actors = {};
var zeroBlock;
var mainDFO;
var dFOBasedFarmExtensionFactory;



// UTILITIES FUNCTIONS FOR RUN STAGE
async function buyForETH(token, amount, from) {
    var path = [
        wethToken.options.address,
        token.options.address
    ];
    var value = toDecimals(amount.toString(), '18');
    await blockchainCall(
        uniswapV2Router.methods.swapExactETHForTokens,
        "1",
        path,
        (from && (from.from || from)) || accounts[0],
        parseInt((new Date().getTime() / 1000) + 1000),
        { from: (from && (from.from || from)) || accounts[0], value }
    );
};

async function initActor(name, address, unwrap, amount, amountIsLiquidityPool) {
    actors[name] = {
        name,
        address,
        from : address,
        unwrap,
        amount,
        amountIsLiquidityPool
    };

    mainToken !== utilities.voidEthereumAddress && await buyForETH(mainToken, ethToSpend, address);
    secondaryToken !== utilities.voidEthereumAddress && await buyForETH(secondaryToken, ethToSpend, address);
};

async function compileContracts() {
    FarmingGen1 = await misc.compileFarmingContract("FarmingGen1", "gen1/impl");
    FarmingGen1Extension = await misc.compileFarmingContract("FarmingGen1Extension", "gen1/impl");

    // FIXME
    // FarmFactory = await compile('farming/FarmFactory');
    // DFOBasedFarmExtensionFactory = await compile('farming/dfo/DFOBasedFarmExtensionFactory');
    // DFOBasedFarmExtension = await compile('farming/dfo/DFOBasedFarmExtension');

    UniswapV2AMMV1 = misc.compileAmmAggregatorContractImpl("UniswapV2BasedAMMV1");
}





module.exports = async function run() {
    debugger;
    console.log("===========================================================");
    console.log("* MULTIVERSE - run() - started *");

    console.log("");
    console.group("Initializing the environment...");
    console.log("Creating contracts objects...");
    ethItemOrchestrator = misc.deployEthItemOrchestrator();
    uniswapV2Router = misc.deployUniswapV2Router();
    uniswapV2Factory = misc.deployUniswapV2Factory();
    wethToken = misc.deployWethTokenWithUniswapV2(uniswapV2Router);
    console.groupEnd();
    console.log("");


    console.group("Creating accounts...");
    extensionOwner = accounts[0];
    console.log("extensionOwner done...");
    console.groupEnd();
    console.log("");


    console.group("Preparing contracts...");
    console.log("Compiling...");
    await compileContracts();
    console.groupEnd();
    console.log("");

    console.log("* MULTIVERSE - run() - finished *");
    console.log("===========================================================");
};


// UTILITIES FUNCTIONS FOR TEST STAGE


module.exports.test = async function test() {
    console.log("* MULTIVERSE - test() started *");


    console.log("* MULTIVERSE - test() - finished *");
};
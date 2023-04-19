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

var deployDFOAndFactoryDone = false;

var ethItemOrchestrator;
var uniswapV2Factory;
var uniswapV2Router;
var wethToken;

var rewardToken;
var mainToken;
var secondaryToken;

var ethToSpend = 600000;

var UniswapV2AMMV1;
var uniswapAMMV2;
var uniswapAMM;

var FixedInflationFactory;
var fixedInflationFactory;

var FixedInflationExtension;
var fixedInflationExtension;

var DFOBasedFixedInflationExtensionFactory;
var DFOBasedFixedInflationExtension;

var FixedInflation;
var fixedInflation;

var FixedInflationDefaultExtension;
var fixedInflationDefaultExtension;

var liquidityPool;

var dFOBasedFixedInflationExtensionFactory;

var tokens;

var actors = {};

async function compileContracts() {
    FixedInflationFactory = await misc.compileFixedInflationContract("FixedInflationFactory", null);
    console.log("FixedInflationFactory done...");
    FixedInflationDefaultExtension = await misc.compileFixedInflationContract("FixedInflationExtension", null);
    console.log("FixedInflationExtension done...");
    FixedInflation = await compile('fixed-inflation/FixedInflationUniV3');
    console.log("FixedInflationUniV3 done...");

    FixedInflationExtension = await misc.compileFixedInflationContract("DFOBasedFixedInflationExtension", "dfo");
    DFOBasedFixedInflationExtensionFactory = await misc.compileFixedInflationContract("DFOBasedFixedInflationExtensionFactory", "dfo");
    DFOBasedFixedInflationExtension = await misc.compileFixedInflationContract("DFOBasedFixedInflationExtension", "dfo");

    UniswapV2AMMV1 = await misc.compileAmmAggregatorContract("UniswapV2AMMV1", "models/UniswapV2/1");

    uniswapAMM = await deployContract(new web3.eth.Contract(UniswapV2AMMV1.abi), UniswapV2AMMV1.bin, [uniswapV2Router.options.address]);
    uniswapAMMV2 = uniswapAMM;

    tokens = [
        web3.currentProvider.knowledgeBase.wethTokenAddress,
        web3.currentProvider.knowledgeBase.usdtTokenAddress,
        web3.currentProvider.knowledgeBase.chainLinkTokenAddress,
        web3.currentProvider.knowledgeBase.usdcTokenAddress,
        web3.currentProvider.knowledgeBase.daiTokenAddress,
        web3.currentProvider.knowledgeBase.mkrTokenAddress,
        web3.currentProvider.knowledgeBase.buidlTokenAddress,
        web3.currentProvider.knowledgeBase.balTokenAddress,
        web3.currentProvider.knowledgeBase.osTokenAddress
    ].map(it => new web3.eth.Contract(web3.currentProvider.knowledgeBase.IERC20ABI, it));

    await Promise.all(tokens.map(it => misc.buyForETH(it, ethToSpend, null, uniswapAMM)));

    UniswapV3AMMV1 = await compile('amm-aggregator/models/UniswapV3/1/UniswapV3AMMV1');

    uniswapAMM = await deployContract(new web3.eth.Contract(UniswapV3AMMV1.abi), UniswapV3AMMV1.bin,
        [
            web3.currentProvider.knowledgeBase.swapRouterAddress,
            web3.currentProvider.knowledgeBase.uniswapV3NonfungiblePositionManagerAddress,
            web3.currentProvider.knowledgeBase.uniswapV3QuoterAddress,
            "0.00001".toDecimals(18)
        ]
    );
    await buyForETH(tokens[tokens.length - 1], ethToSpend, null, uniswapAMM);

}


async function deployDFOAndFactory() {
    if (deployDFOAndFactoryDone) {
        return;
    }
    deployDFOAndFactoryDone = true;

    var fixedInflationModel = await deployContract(new web3.eth.Contract(FixedInflation.abi), FixedInflation.bin);

    var fixedInflationModel = await deployContract(new web3.eth.Contract(FixedInflationDefaultExtension.abi), FixedInflationDefaultExtension.bin);

    fixedInflationModel = await deployContract(new web3.eth.Contract(FixedInflationFactory.abi), FixedInflationFactory.bin,
        [
            VOID_ETHEREUM_ADDRESS,
            fixedInflationModel.options.address,
            fixedInflationDefaultExtensionModel.options.address,
            toDecimals("0.1", 18)
        ]
    );


    // FIXME
    // await sendBlockchainTransaction(
    //     web3.currentProvider,
    //     accounts[0],
    //     web3.currentProvider.knowledgeBase.wethTokenAddress,
    //     web3.utils.sha3("deposit()").substring(0, 10),
    //     toDecimals(30, 18)
    // );

    // await web3.eth.sendTransaction(blockchainConnection.getSendingOptions({
    //     to: dfo.mvdWalletAddress,
    //     value: utilities.toDecimals(30, 18)
    // }));

    for (var token of tokens) {
        try {
            await token.methods.transfer(dfo.mvdWalletAddress, utilities.toDecimals(1000, await token.methods.decimals().call())).send(blockchainConnection.getSendingOptions());
        } catch (e) {
            var value = utilities.toDecimals(15, await token.methods.decimals().call());
            var balance = await token.methods.balanceOf(accounts[0]).call();
            value = parseInt(value) > parseInt(balance) ? utilities.numberToString(parseInt(parseInt(balance) * 0.8)) : value;
            await token.methods.transfer(dfo.mvdWalletAddress, value).send(blockchainConnection.getSendingOptions());
        }
    }

    await dfo.votingToken.methods.transfer(dfo.mvdWalletAddress, utilities.toDecimals(300000, await dfo.votingToken.methods.decimals().call())).send(blockchainConnection.getSendingOptions());
}

module.exports = async function run() {
    console.log("===========================================================");
    console.log("* MULTIVERSE - run() - started *");

    console.log("");
    console.group("Initializing the environment...");
    console.log("Creating contracts objects...");
    ethItemOrchestrator = misc.deployEthItemOrchestrator();
    uniswapV2Router = misc.deployUniswapV2Router();
    uniswapV2Factory = misc.deployUniswapV2Factory();
    console.groupEnd();
    console.log("");

    console.group("Preparing contracts...");
    console.log("Compiling...");
    await compileContracts();
    console.groupEnd();
    console.log("");

    console.group("Deploying DFO and Factory, then deploying all occurency stuff...");
    console.log("Compiling...");
    await deployDFOAndFactory().then(deployAllOccurencyStuff);
    console.groupEnd();
    console.log("");



    console.log("* MULTIVERSE - run() - finished *");
    console.log("===========================================================");
};





module.exports.test = async function test() {
    console.log("* MULTIVERSE - test() started *");
    console.log("* MULTIVERSE - test() - finished *");
};
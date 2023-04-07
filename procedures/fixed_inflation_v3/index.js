require("../../util/mocha");

var blockchainConnection = require("../../util/blockchainConnection");
var buildOSStuff = require('../../resources/OS/buildOsStuff');
var dfoManager = require('../../util/dfo');
var fs = require('fs');
var misc = require("../misc");
var path = require('path');
var utilities = require("../../util/utilities");


var ethItemOrchestrator;
var uniswapV2Factory;
var uniswapV2Router;
var wethToken;

var rewardToken;
var mainToken;
var secondaryToken;

var ethToSpend = 600000;

var dfo;

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

var mainDFO;

async function compileContracts() {
    FixedInflationFactory = await misc.compileFixedInflationContract("FixedInflationFactory", null);
    console.log("FixedInflationFactory done...");
    FixedInflationExtension = await misc.compileFixedInflationContract("FixedInflationExtension", null);
    console.log("FixedInflationExtension done...");
    FixedInflation = await compile('fixed-inflation/FixedInflationUniV3');
    console.log("FixedInflationUniV3 done...");

    DFOBasedFixedInflationExtensionFactory = await misc.compileFixedInflationContract("DFOBasedFixedInflationExtensionFactory", "dfo");
    DFOBasedFixedInflationExtension = await misc.compileFixedInflationContract("DFOBasedFixedInflationExtension", "dfo");

    // UniswapV2AMMV1 = await misc.compileAmmAggregatorContract("UniswapV2AMMV1", "models/UniswapV2/1");
    // UniswapV3AMMV1 = await misc.compileAmmAggregatorContract("UniswapV3AMMV1", "models/UniswapV3/1");
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


    // FIXME
    console.group("Creating accounts...");
    // mainDFO = await dfoManager.createDFO("MyName", "MySymbol", 10000000, 100, 10);
    console.log("mainDFO done...");
    console.groupEnd();
    console.log("");


    console.log("* MULTIVERSE - run() - finished *");
    console.log("===========================================================");
};





module.exports.test = async function test() {
    console.log("* MULTIVERSE - test() started *");
    console.log("* MULTIVERSE - test() - finished *");
};
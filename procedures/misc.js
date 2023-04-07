require("../util/mocha");
const { compile } = require("@ethereansos/multiverse");

const TIME_SLOTS_IN_SECONDS = 15;

function deployUniswapV2Router() {
    var uniswapV2Router = new web3.eth.Contract(knowledgeBase.uniswapV2RouterABI, knowledgeBase.uniswapV2RouterAddress);
    assert.notStrictEqual(uniswapV2Router, undefined);
    return uniswapV2Router;
}

function deployUniswapV2Factory() {
    var uniswapV2Factory = new web3.eth.Contract(knowledgeBase.uniswapV2FactoryABI, knowledgeBase.uniswapV2FactoryAddress);
    assert.notStrictEqual(uniswapV2Factory, undefined);
    return uniswapV2Factory;
}

function deployUniswapV3Pool(univ3PoolAddress) {
    var uniswapV3Pool = new web3.eth.Contract(knowledgeBase.UniswapV3PoolABI, univ3PoolAddress);
    assert.notStrictEqual(uniswapV3Pool, undefined);
    return uniswapV3Pool;
}

function deploySwapRouter() {
    var swapRouter = new web3.eth.Contract(knowledgeBase.swapRouterABI, knowledgeBase.swapRouterAddress);
    assert.notStrictEqual(swapRouter, undefined);
    return swapRouter;
}

function deployEthItemOrchestrator() {
    var ethItemOrchestrator = new web3.eth.Contract(knowledgeBase.ethItemOrchestratorABI, knowledgeBase.ethItemOrchestratorAddress);
    assert.notStrictEqual(ethItemOrchestrator, undefined);
    return ethItemOrchestrator;
}

function printContractABI(contract) {
    console.log("* " + contract.name + " ABI *");
    console.log(contract.abi);
    console.log("°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°");
}

async function compileFixedInflationContract(filename, subfolders) {
    var subpath = subfolders != null ? subfolders + "/" : "";
    var path = "fixed-inflation/" + subpath + filename;
    const contract = await compile(path);
    return contract;
}

async function compileFarmingContract(filename, subfolders) {
    var subpath = subfolders != null ? subfolders + "/" : "";
    const contract = await compile("farming/" + subpath + filename);
    return contract;
}

async function compileAmmAggregatorContract(filename, subfolders) {
    var subpath = subfolders != null ? subfolders + "/" : "";
    const contract = await compile("amm-aggregator/" + subpath + filename);
    return contract;
}




module.exports = {
    TIME_SLOTS_IN_SECONDS,
    compileAmmAggregatorContract,
    compileFixedInflationContract,
    compileFarmingContract,
    deployEthItemOrchestrator,
    deploySwapRouter,
    deployUniswapV2Factory,
    deployUniswapV2Router,
    deployUniswapV3Pool,
    printContractABI,
    };
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

const TIME_SLOTS_IN_SECONDS = 15;

const EVENTS_SIGNATURE = {
    TRANSFER_WITH_PARAMS : 'Transfer(uint256,address,address)',
}

const EVENT = {
    EMITTED : 'EMITTED',
    NOT_EMITTED : 'NOT_EMITTED',
}

function deployUniswapV2Router() {
    var uniswapV2Router = new web3.eth.Contract(web3.currentProvider.knowledgeBase.uniswapV2RouterABI, web3.currentProvider.knowledgeBase.uniswapV2RouterAddress);
    assert.notStrictEqual(uniswapV2Router, undefined);
    return uniswapV2Router;
}

function deployUniswapV2Factory() {
    var uniswapV2Factory = new web3.eth.Contract(web3.currentProvider.knowledgeBase.uniswapV2FactoryABI, web3.currentProvider.knowledgeBase.uniswapV2FactoryAddress);
    assert.notStrictEqual(uniswapV2Factory, undefined);
    return uniswapV2Factory;
}

async function deployWethTokenWithUniswapV2(uniswapRouter) {
    var wethToken = new web3.eth.Contract(web3.currentProvider.knowledgeBase.IERC20ABI, await blockchainCall(uniswapRouter.methods.WETH));
    assert.notStrictEqual(wethToken, undefined);
    assert.notStrictEqual(wethToken, VOID_ETHEREUM_ADDRESS);
    return wethToken;
}

function deployWethToken(univ3PoolAddress) {
    var uniswapV3Pool = new web3.eth.Contract(web3.currentProvider.knowledgeBase.UniswapV3PoolABI, univ3PoolAddress);
    assert.notStrictEqual(uniswapV3Pool, undefined);
    return uniswapV3Pool;
}

function deploySwapRouter() {
    var swapRouter = new web3.eth.Contract(web3.currentProvider.knowledgeBase.swapRouterABI, web3.currentProvider.knowledgeBase.swapRouterAddress);
    assert.notStrictEqual(swapRouter, undefined);
    return swapRouter;
}

function deployEthItemOrchestrator() {
    var ethItemOrchestrator = new web3.eth.Contract(web3.currentProvider.knowledgeBase.ethItemOrchestratorABI, web3.currentProvider.knowledgeBase.ethItemOrchestratorAddress);
    assert.notStrictEqual(ethItemOrchestrator, undefined);
    return ethItemOrchestrator;
}

function deployUniswapV3Pool(univ3PoolAddress) {
    var uniswapV3Pool = new web3.eth.Contract(web3.currentProvider.knowledgeBase.UniswapV3PoolABI, univ3PoolAddress);
    assert.notStrictEqual(uniswapV3Pool, undefined);
    return uniswapV3Pool;
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

async function compileAmmAggregatorContractImpl(filename) {
    const contract = await compile("amm-aggregator/impl/" + filename);
    return contract;
}


function numberToString(num, locale) {
    if (num === undefined || num === null) {
        num = 0;
    }
    if ((typeof num).toLowerCase() === 'string') {
        return num.split(',').join('');
    }
    let numStr = String(num);

    if (Math.abs(num) < 1.0) {
        let e = parseInt(num.toString().split('e-')[1]);
        if (e) {
            let negative = num < 0;
            if (negative) num *= -1
            num *= Math.pow(10, e - 1);
            numStr = '0.' + (new Array(e)).join('0') + num.toString().substring(2);
            if (negative) numStr = "-" + numStr;
        }
    } else {
        let e = parseInt(num.toString().split('+')[1]);
        if (e > 20) {
            e -= 20;
            num /= Math.pow(10, e);
            numStr = num.toString() + (new Array(e + 1)).join('0');
        }
    }
    if (locale === true) {
        var numStringSplitted = numStr.split(' ').join('').split('.');
        return parseInt(numStringSplitted[0]).toLocaleString() + (numStringSplitted.length === 1 ? '' : (Utils.decimalsSeparator + numStringSplitted[1]))
    }
    return numStr;
}




module.exports = {
    EVENTS_SIGNATURE,
    EVENT,
    TIME_SLOTS_IN_SECONDS,
    compileAmmAggregatorContract,
    compileAmmAggregatorContractImpl,
    compileFixedInflationContract,
    compileFarmingContract,
    deployEthItemOrchestrator,
    deploySwapRouter,
    deployUniswapV2Factory,
    deployUniswapV2Router,
    deployUniswapV3Pool,
    deployWethTokenWithUniswapV2,
    numberToString,
    printContractABI,
};
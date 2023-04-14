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

function deployUniswapV3Pool(univ3PoolAddress) {
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

async function buyForETH(token, amount, receiver, ammPlugin) {
    var value = toDecimals(amount.toString(), '18');
    if (token.options.address === web3.currentProvider.knowledgeBase.wethTokenAddress) {
        return await sendBlockchainTransaction(
            web3.currentProvider,
            accounts[0],
            web3.currentProvider.knowledgeBase.wethTokenAddress,
            web3.utils.sha3("deposit()").substring(0, 10),
            value
        );
    }
    // if (ammPlugin || amm) {
    //     ammPlugin = ammPlugin || amm;
    //     var ethereumAddress = (await ammPlugin.methods.data().call())[0];
    //     var liquidityPoolAddress = (await ammPlugin.methods.byTokens([
    //         ethereumAddress,
    //         token.options.address
    //     ]).call())[2];
    //     if (liquidityPoolAddress === VOID_ETHEREUM_ADDRESS) {
    //         return;
    //     }
    //     await blockchainCall(ammPlugin.methods.swapLiquidity, {
    //         amount: value,
    //         enterInETH: true,
    //         exitInETH: false,
    //         liquidityPoolAddresses: [liquidityPoolAddress],
    //         path: [token.options.address],
    //         inputToken: ethereumAddress,
    //         receiver: receiver || VOID_ETHEREUM_ADDRESS
    //     }, { value: value });
    // }

}


module.exports = {
    TIME_SLOTS_IN_SECONDS,
    buyForETH,
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
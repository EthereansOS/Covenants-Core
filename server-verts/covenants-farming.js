var compile = require('../util/compile');
var context = require("../util/context.json");
var ethers = require('ethers');
var abi = new ethers.utils.AbiCoder();
var { toDecimals } = require('../util/utilities');

async function buyForETH(token, amount, from) {
    var path = [
        context.wethTokenAddress,
        token,
    ];
    console.log(path);
    var value = toDecimals(amount.toString(), '18');
    var uniswapV2Router = new web3.eth.Contract(context.uniswapV2RouterABI, context.uniswapV2RouterAddress);
    await uniswapV2Router.methods.swapExactETHForTokens(value, path, accounts[0], parseInt((new Date().getTime() / 1000) + 1000)).send({from: accounts[0], value,  gasLimit : global.gasLimit});
    console.log('bought');
};

async function main() {

    var sendingOptions = {
        from : accounts[0],
        gasLimit : global.gasLimit
    }

    var FarmMain = await compile('liquidity-mining/FarmMain');
    var FarmExtension = await compile('liquidity-mining/FarmExtension');
    var FarmFactory = await compile('liquidity-mining/FarmFactory');
    var UniswapV2AMMV1 = await compile('amm-aggregator/models/UniswapV2/1/UniswapV2AMMV1');
    var uniswapV2Router = new web3.eth.Contract(context.uniswapV2RouterABI, context.uniswapV2RouterAddress);
    var uniswapV2Factory = new web3.eth.Contract(context.uniswapV2FactoryABI, context.uniswapV2FactoryAddress);
    var wethToken = new web3.eth.Contract(context.IERC20ABI, await uniswapV2Router.methods.WETH().call());

    var uniswapAMM = await new web3.eth.Contract(UniswapV2AMMV1.abi).deploy({data : UniswapV2AMMV1.bin, arguments: [uniswapV2Router.options.address]}).send(sendingOptions);

    var liquidityPool = new web3.eth.Contract(context.uniswapV2PairABI, await uniswapV2Factory.methods.getPair(context.buidlTokenAddress, context.wethTokenAddress).call());

    var farmMain = await new web3.eth.Contract(FarmMain.abi).deploy({data : FarmMain.bin}).send(sendingOptions);
    var farmExtension = await new web3.eth.Contract(FarmExtension.abi).deploy({data : FarmExtension.bin}).send(sendingOptions);
    var farmFactory = await new web3.eth.Contract(FarmFactory.abi).deploy({data : FarmFactory.bin, arguments : [
        "0xF869538e3904778A0cb1FF620C8E83c7df36B946",
        farmMain.options.address,
        farmExtension.options.address,
        0,
        "ipfs://ipfs/Qmbvq6viu7dSSNZidDgA8Zgm2XUjWn7uPaVkAShxxZ526m",
        "ipfs://ipfs/QmXAWCR2g2bD4Kf2B5DGgrYS3mi19EnHyFQrcx5ZU4f1df"
    ]}).send(sendingOptions);

    var rewardToken = new web3.eth.Contract(context.IERC20ABI, context.buidlTokenAddress);

    var transaction = await farmFactory.methods.cloneFarmDefaultExtension().send(sendingOptions);
    var receipt = await web3.eth.getTransactionReceipt(transaction.transactionHash);
    var clonedDefaultFarmExtension = web3.eth.abi.decodeParameter("address", receipt.logs.filter(it => it.topics[0] === web3.utils.sha3('ExtensionCloned(address)'))[0].topics[1])
    console.log(`cloned default farm extension deployed at ${clonedDefaultFarmExtension}`);
    clonedFarmExtension = new web3.eth.Contract(FarmExtension.abi, clonedDefaultFarmExtension);

    var setups = [
        [
            true,
            10,//6000,
            "500000000000000000",
            "1000000000000000000",
            0,
            2,
            uniswapAMM.options.address,
            liquidityPool.options.address,
            context.buidlTokenAddress,
            context.wethTokenAddress,
            true,
            0,
            0,
            0
        ],
        [
            false,
            10,//6000,
            "500000000000000000",
            "1000000000000000000",
            "2500000000000000000000",
            2,
            uniswapAMM.options.address,
            liquidityPool.options.address,
            context.buidlTokenAddress,
            context.wethTokenAddress,
            true,
            0,
            0,
            0
        ]
    ];
    var types = [
        "address",
        "bytes",
        "address",
        "address",
        "bytes",
    ];
    var params = [
        clonedDefaultFarmExtension,//liquidityMiningExtension.options.address,
        "0x",
        context.ethItemOrchestratorAddress,
        context.buidlTokenAddress,
        abi.encode(["tuple(bool,uint256,uint256,uint256,uint256,uint256,address,address,address,address,bool,uint256,uint256,uint256)[]"], [setups]),
    ];

    console.log(setups);
    params[1] = clonedFarmExtension.methods.init(false, accounts[0]).encodeABI()
    var res = await uniswapAMM.methods.byLiquidityPool(liquidityPool.options.address).call();
    console.log(res);

    var payload = web3.utils.sha3(`init(${types.join(',')})`).substring(0, 10) + (web3.eth.abi.encodeParameters(types, params).substring(2));
    //console.log(`gas used ${await farmFactory.methods.deploy(payload).estimateGas(sendingOptions)}`)
    var deployTransaction = await farmFactory.methods.deploy(payload).send(sendingOptions);
    console.log('deployed')
    deployTransaction = await web3.eth.getTransactionReceipt(deployTransaction.transactionHash);
    var farmMainContractAddress = web3.eth.abi.decodeParameter("address", deployTransaction.logs.filter(it => it.topics[0] === web3.utils.sha3("FarmMainDeployed(address,address,bytes)"))[0].topics[1]);
    console.log(`farm main contract address ${farmMainContractAddress}`);
    // put reward in the extension
    await buyForETH(context.buidlTokenAddress, 50);
    await rewardToken.methods.transfer(clonedDefaultFarmExtension, await rewardToken.methods.balanceOf(accounts[0]).call()).send(sendingOptions);
    await buyForETH(context.buidlTokenAddress, 10);

    console.log("\nFarm Factory:", farmFactory.options.address);
}

main().catch(console.error);
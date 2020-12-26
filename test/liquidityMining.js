<<<<<<< HEAD
const LiquidityMiningFactory = artifacts.require("LiquidityMiningFactory");
const LiquidityMining = artifacts.require("LiquidityMining");
const UniswapV2AMMV1 = artifacts.require("UniswapV2AMMV1");
const MainToken = artifacts.require("MainToken");
const RewardToken = artifacts.require("RewardToken");
const SecondaryToken = artifacts.require("SecondaryToken");
=======
var assert = require("assert");
var context = require("../util/context.json");
var compile = require("../util/compile");
var blockchainConnection = require("../util/blockchainConnection");
>>>>>>> origin/vasacchioli

var LiquidityMining;
var LiquidityMiningFactory;
var UniswapV2AMMV1;

<<<<<<< HEAD
contract("LiquidityMining", (accounts) => {
    let liquidityMiningInstance;
    let ammInstance;
    let factoryInstance;
    let mainTokenInstance;
    let secondaryTokenInstance;
    let rewardTokenInstance;
    let uniswapFactoryContract;
    let liquidityPoolTokenAddress = zero;
    it("owner should deploy a new liquidity mining contract", async () => {
        liquidityMiningInstance = await LiquidityMining.deployed();
        rewardTokenInstance = await RewardToken.deployed();
        await liquidityMiningInstance.initialize(accounts[0], web3.utils.hexToBytes(web3.utils.randomHex(32)), orchestratorAddress, "TestCollection1", "TSTC", "test", rewardTokenInstance.address, false, { from: accounts[0] });
        assert.notEqual(liquidityMiningInstance, zero);
    });
    it("should retrieve the correct factory address", async () => {
        factoryIstance = await LiquidityMiningFactory.deployed();
        const factoryAddress = await liquidityMiningInstance.FACTORY.call();
        assert.equal(factoryAddress, factoryIstance.address);
    });
    it("should retrieve the position token collection", async () => {
        const positionTokenCollection = await liquidityMiningInstance._positionTokenCollection.call();
        assert.notEqual(positionTokenCollection, zero);
    });
    it("should get the 0 exit fee", async () => {
        const exitFee = await liquidityMiningInstance._exitFee.call();
        assert.equal(exitFee, 0);
    });
    it("should update the exit fee", async () => {
        await liquidityMiningInstance.setExitFee(1, { from: accounts[0] });
        const exitFee = await liquidityMiningInstance._exitFee.call();
        assert.equal(exitFee, 1);
    });
    it("should not update the exit fee", async () => {
        try {
            await liquidityMiningInstance.setExitFee(0, { from: accounts[1] });
            assert.equal(true, false);
        } catch (error) {
            assert(error, "Only the owner can update the exit fee.");
        }
    });
    it("should set the farming setups", async () => {
        ammInstance = await UniswapV2AMMV1.deployed();
        mainTokenInstance = await MainToken.deployed();
        secondaryTokenInstance = await SecondaryToken.deployed();
        const mainTokenBalance = await mainTokenInstance.balanceOf(accounts[1]);
        const secondaryTokenBalance = await secondaryTokenInstance.balanceOf(accounts[1]);
        mainTokenInstance.approve(liquidityMiningInstance.address, mainTokenBalance, { from: accounts[1] });
        secondaryTokenInstance.approve(liquidityMiningInstance.address, secondaryTokenBalance, { from: accounts[1] });
        uniswapFactoryContract = new web3.eth.Contract(uniswapFactoryAbi.abi, uniswapFactoryAddress);
=======
var zero = "0x0000000000000000000000000000000000000000";
var ethItemOrchestrator;
var uniswapV2Router; 
var uniswapV2Factory;
var wethToken;
var mainToken;
var secondaryToken;
var liquidityMiningFactory;
var liquidityMiningContract;
var liquidityPool;
var uniswapAMM;

before(async () => {
    await blockchainConnection.init;

    LiquidityMining = await compile('liquidity-mining/LiquidityMining');
    LiquidityMiningFactory = await compile('liquidity-mining/LiquidityMiningFactory');
    UniswapV2AMMV1 = await compile('amm-aggregator/models/UniswapV2/1/UniswapV2AMMV1');

    ethItemOrchestrator = new web3.eth.Contract(context.ethItemOrchestratorABI, context.ethItemOrchestratorAddress);
    uniswapV2Router = new web3.eth.Contract(context.uniswapV2RouterABI, context.uniswapV2RouterAddress);
    uniswapV2Factory = new web3.eth.Contract(context.uniswapV2FactoryABI, context.uniswapV2FactoryAddress);

    wethToken = new web3.eth.Contract(context.IERC20ABI, await uniswapV2Router.methods.WETH().call());
    mainToken = new web3.eth.Contract(context.IERC20ABI, context.buidlTokenAddress);
    secondaryToken = new web3.eth.Contract(context.IERC20ABI, context.usdcTokenAddress);

    liquidityPool = new web3.eth.Contract(context.uniswapV2PairABI, await uniswapV2Factory.methods.getPair(mainToken.options.address, secondaryToken.options.address).call());

    await buyForETH(mainToken, 10);
    await buyForETH(secondaryToken, 10);

    await mainToken.methods.approve(uniswapV2Router.options.address, await mainToken.methods.totalSupply().call()).send(blockchainConnection.getSendingOptions());
    await secondaryToken.methods.approve(uniswapV2Router.options.address, await secondaryToken.methods.totalSupply().call()).send(blockchainConnection.getSendingOptions());

    var liquidityMiningModel = await new web3.eth.Contract(LiquidityMining.abi).deploy({data : LiquidityMining.bin, arguments: [zero]}).send(blockchainConnection.getSendingOptions());
    liquidityMiningFactory = await new web3.eth.Contract(LiquidityMiningFactory.abi).deploy({data : LiquidityMiningFactory.bin, arguments : [accounts[0], liquidityMiningModel.options.address]}).send(blockchainConnection.getSendingOptions());

    uniswapAMM = await new web3.eth.Contract(UniswapV2AMMV1.abi).deploy({data : UniswapV2AMMV1.bin, arguments: [uniswapV2Router.options.address]}).send(blockchainConnection.getSendingOptions());
});

var buyForETH = async function buyForETH(token, amount) {
    var path = [
        wethToken.options.address,
        token.options.address
    ];
    var value = web3.utils.toWei(amount.toString(), 'ether');
    await uniswapV2Router.methods.swapExactETHForTokens("1", path, accounts[0], parseInt((new Date().getTime() / 1000) + 1000)).send(blockchainConnection.getSendingOptions({value}));
};

describe("LiquidityMining", () => {
    it("New EthItem Collection", async () => {
        var params = [
            "string",
            "string",
            "bool",
            "string",
            "address",
            "bytes"
        ];
        var values = [
            "LiquidityMiningToken",
            "LMT",
            true,
            "google.com",
            accounts[0],
            "0x"
        ];
        var payload = web3.utils.sha3(`init(${params.join(',')})`).substring(0, 10) + (web3.eth.abi.encodeParameters(params, values).substring(2));
        await ethItemOrchestrator.methods.createNative(payload, "").send(blockchainConnection.getSendingOptions());
    });
    it("New LiquidityMining Contract by Factory", async () => {
        var params = [
            "address",
            "bytes",
            "address",
            "string",
            "string",
            "string",
            "address",
            "bool"
        ];
        var values = [
            accounts[0],
            "0x",
            ethItemOrchestrator.options.address,
            "LiquidityMiningToken",
            "LMT",
            "google.com",
            mainToken.options.address,
            false
        ];
        var payload = web3.utils.sha3(`initialize(${params.join(',')})`).substring(0, 10) + (web3.eth.abi.encodeParameters(params, values).substring(2));
        var deployTransaction = await liquidityMiningFactory.methods.deploy(payload).send(blockchainConnection.getSendingOptions());
        deployTransaction = await web3.eth.getTransactionReceipt(deployTransaction.transactionHash);
        var liquidityMiningContractAddress = web3.eth.abi.decodeParameter("address", deployTransaction.logs.filter(it => it.topics[0] === web3.utils.sha3("LiquidityMiningDeployed(address,address)"))[0].topics[2]);
        liquidityMiningContract = await new web3.eth.Contract((await compile("liquidity-mining/LiquidityMining")).abi, liquidityMiningContractAddress);
        assert.notStrictEqual(liquidityMiningContract.options.address, zero);
    });
    it("Previously created LiquidityMining Contract cannot be initialized more than a time", async() => {
        try {
            await liquidityMiningContract.methods.initialize(accounts[0], "0x", ethItemOrchestrator.options.address, "TestCollection1", "TSTC", "test", ethItemOrchestrator.options.address, false).send(blockchainConnection.getSendingOptions());
        } catch (e) {
            assert.notStrictEqual((e.message || e).toLowerCase().indexOf("already initialized"), -1);
        }
    });
    it("should retrieve the correct factory address", async() => {
        var factoryAddress = await liquidityMiningContract.methods.FACTORY().call();
        assert.strictEqual(factoryAddress, liquidityMiningFactory.options.address);
    });
    it("should retrieve the position token collection", async() => {
        var positionTokenCollection = await liquidityMiningContract.methods._positionTokenCollection().call();
        assert.notStrictEqual(positionTokenCollection, zero);
    });
    it("Exit fee is 0", async() => {
        var exitFee = await liquidityMiningContract.methods._exitFee().call();
        assert.strictEqual(parseInt(exitFee), 0);
    });
    it("Account 0 can update the exit fee to 1", async() => {
        await liquidityMiningContract.methods.setExitFee(1).send(blockchainConnection.getSendingOptions());
        var exitFee = await liquidityMiningContract.methods._exitFee().call();
        assert.strictEqual(parseInt(exitFee), 1);
    });
    it("Another account cannot update the exit fee", async() => {
>>>>>>> origin/vasacchioli
        try {
            await liquidityMiningContract.methods.setExitFee(0).send({...blockchainConnection.getSendingOptions(), from: accounts[1]});
        } catch (e) {
            assert.notStrictEqual((e.message|| e).toLowerCase().indexOf("unauthorized"), -1);
        }
<<<<<<< HEAD
        const startBlock = await web3.eth.getBlockNumber() + 1;
        const endBlock = startBlock + 9999;
        const rewardPerBlock = parseInt(web3.utils.toWei('0.001', 'ether'));
        const setups = [
            {
                ammPlugin: ammInstance.address, 
                liquidityPoolTokenAddress, 
                startBlock: startBlock, 
                endBlock: endBlock, 
                rewardPerBlock: rewardPerBlock, 
                maximumLiquidity: (rewardPerBlock * (endBlock - startBlock)).toString(), 
                totalSupply: 0, 
                lastBlockUpdate: 0, 
                mainTokenAddress: mainTokenInstance.address, 
                secondaryTokenAddresses: [secondaryTokenInstance.address], 
                free: false
            }
        ];
        const result = await liquidityMiningInstance.setFarmingSetups(setups, { from: accounts[0] });
        assert.notEqual(result, null);
=======
>>>>>>> origin/vasacchioli
    });
    it("should set the farming setups", async() => {
        var startBlock = await web3.eth.getBlockNumber() + 1;
        var endBlock = startBlock + 9999;
        var rewardPerBlock = 1500;
        var setups = [{
            ammPlugin: uniswapAMM.options.address,
            liquidityPoolTokenAddress : liquidityPool.options.address,
            startBlock,
            endBlock,
            rewardPerBlock,
            maximumLiquidity: rewardPerBlock * (endBlock - startBlock),
            totalSupply: 0,
            lastBlockUpdate: 0,
            mainTokenAddress: mainToken.options.address,
            secondaryTokenAddresses: [secondaryToken.options.address],
            free: false
        }];
        var result = await liquidityMiningContract.methods.setFarmingSetups(setups).send(blockchainConnection.getSendingOptions());
        assert.notStrictEqual(result, null);
    });
    it("should not set the farming setups", async() => {
        try {
<<<<<<< HEAD
            const setups = [
                {
                    ammPlugin: zero, 
                    liquidityPoolTokenAddress: zero, 
                    startBlock: 0, 
                    endBlock: 1, 
                    rewardPerBlock: 0, 
                    maximumLiquidity: 0, 
                    totalSupply: 0, 
                    lastBlockUpdate: 0, 
                    mainTokenAddress: zero, 
                    secondaryTokenAddresses: [zero], 
                    free: false
                }
            ];            
            await liquidityMiningInstance.setFarmingSetups(setups, { from: accounts[1] });
            assert.equal(true, false);
=======
            var setups = [{
                ammPlugin: zero,
                liquidityPoolTokenAddress: zero,
                startBlock: 0,
                endBlock: 1,
                rewardPerBlock: 0,
                maximumLiquidity: 0,
                totalSupply: 0,
                lastBlockUpdate: 0,
                mainTokenAddress: zero,
                secondaryTokenAddresses: [zero],
                free: false
            }];
            await liquidityMiningContract.methods.setFarmingSetups(setups).send(blockchainConnection.getSendingOptions({from: accounts[1]}));
            throw "Farming Setup done";
>>>>>>> origin/vasacchioli
        } catch (error) {
            assert(error, "Only the owner can set the farming setups.");
        }
    });
<<<<<<< HEAD
    it("should set a new staking position", async () => {
        const mainTokenAmount = web3.utils.toWei('0.001', 'ether');
        const secondaryTokenAmount = web3.utils.toWei('0.001', 'ether');
        const stake = {
=======
    it("should set a new staking position", async() => {
        var mainTokenAmount = web3.utils.toWei('100', 'ether');
        var secondaryTokenAmount = web3.utils.toWei('0.1', 'ether');
        var stake = {
>>>>>>> origin/vasacchioli
            setupIndex: 0,
            secondaryTokenAddress: secondaryToken.options.address,
            liquidityPoolTokenAmount: 0,
            mainTokenAmount,
            secondaryTokenAmount,
            positionOwner: zero,
            mintPositionToken: false,
        };
<<<<<<< HEAD
        const result = await liquidityMiningInstance.stake(stake, { from: accounts[1] });
        assert.notEqual(result, null);
=======
        var result = await liquidityMiningContract.methods.stake(stake).send(blockchainConnection.getSendingOptions());
        assert.notStrictEqual(result, null);
>>>>>>> origin/vasacchioli
    });
})
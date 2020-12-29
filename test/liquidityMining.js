var assert = require("assert");
var utilities = require("../util/utilities");
var context = require("../util/context.json");
var compile = require("../util/compile");
var blockchainConnection = require("../util/blockchainConnection");

var LiquidityMining;
var LiquidityMiningFactory;
var UniswapV2AMMV1;

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

    await buyForETH(mainToken, 25);
    await buyForETH(secondaryToken, 25);

    var liquidityMiningModel = await new web3.eth.Contract(LiquidityMining.abi).deploy({data : LiquidityMining.bin}).send(blockchainConnection.getSendingOptions());
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
        liquidityMiningContract = await new web3.eth.Contract(LiquidityMining.abi, liquidityMiningContractAddress);
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
        try {
            await liquidityMiningContract.methods.setExitFee(0).send({...blockchainConnection.getSendingOptions(), from: accounts[1]});
        } catch (e) {
            assert.notStrictEqual((e.message|| e).toLowerCase().indexOf("unauthorized"), -1);
        }
    });
    it("should set the farming setups", async() => {
        var currentBlock = await web3.eth.getBlockNumber();
        var startBlockLongTerm1 = currentBlock + 1;
        var startBlockLongTerm2 = currentBlock + 6;
        var endBlockLongTerm1 = startBlockLongTerm1 + 29;
        var endBlockLongTerm2 = startBlockLongTerm2 + 49;
        const rewardPerBlockLongTerm1 = web3.utils.toWei('0.003', 'ether');
        const rewardPerBlockLongTerm2 = web3.utils.toWei('0.007', 'ether');
        const rewardPerBlockFree = web3.utils.toWei('0.025', 'ether');
        var longTerm1 = {
            ammPlugin: uniswapAMM.options.address,
            liquidityPoolTokenAddress: liquidityPool.options.address,
            startBlock: startBlockLongTerm1,
            endBlock: endBlockLongTerm1,
            rewardPerBlock: rewardPerBlockLongTerm1,
            maximumLiquidity: web3.utils.toWei('0.09', 'ether'), 
            totalSupply: 0,
            lastBlockUpdate: 0,
            mainTokenAddress: mainToken.options.address,
            secondaryTokenAddresses: [secondaryToken.options.address],
            free: false
        };
        var longTerm2 = {
            ammPlugin: uniswapAMM.options.address,
            liquidityPoolTokenAddress: liquidityPool.options.address,
            startBlock: startBlockLongTerm2,
            endBlock: endBlockLongTerm2,
            rewardPerBlock: rewardPerBlockLongTerm2,
            maximumLiquidity: web3.utils.toWei('0.35', 'ether'), 
            totalSupply: 0,
            lastBlockUpdate: 0,
            mainTokenAddress: mainToken.options.address,
            secondaryTokenAddresses: [secondaryToken.options.address],
            free: false
        };
        var pinnedFree = {
            ammPlugin: uniswapAMM.options.address,
            liquidityPoolTokenAddress : liquidityPool.options.address,
            startBlock: 0,
            endBlock: 0,
            rewardPerBlock: rewardPerBlockFree,
            maximumLiquidity: 0, 
            totalSupply: 0,
            lastBlockUpdate: 0,
            mainTokenAddress: mainToken.options.address,
            secondaryTokenAddresses: [secondaryToken.options.address],
            free: true
        };
        var setups = [pinnedFree, longTerm1, longTerm2];
        var result = await liquidityMiningContract.methods.setFarmingSetups(setups).send(blockchainConnection.getSendingOptions());
        assert.notStrictEqual(result, null);
    });
    it("should not set the farming setups", async() => {
        try {
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
        } catch (error) {
            assert(error, "Only the owner can set the farming setups.");
        }
    });
    let aliceCreationBlock;
    let bobCreationBlock;
    let charlieCreationBlock;
    let donaldCreationBlock;
    it("alice should set a new staking position", async() => {
        await mainToken.methods.approve(liquidityMiningContract.options.address, await mainToken.methods.totalSupply().call()).send(blockchainConnection.getSendingOptions());
        await secondaryToken.methods.approve(liquidityMiningContract.options.address, await secondaryToken.methods.totalSupply().call()).send(blockchainConnection.getSendingOptions());
        var mainTokenAmount = web3.utils.toWei('0.009', 'ether');
        var secondaryTokenAmount = web3.utils.toWei('0.001', utilities.fromDecimalsToCurrency(await secondaryToken.methods.decimals().call()));
        var stake = {
            setupIndex: 1,
            secondaryTokenAddress: secondaryToken.options.address,
            liquidityPoolTokenAmount: 0,
            mainTokenAmount,
            secondaryTokenAmount,
            positionOwner: zero,
            mintPositionToken: false,
        };
        var result = await liquidityMiningContract.methods.stake(stake).send(blockchainConnection.getSendingOptions());
        const { positionKey } = result.events.NewPosition.returnValues;
        const position = await liquidityMiningContract.methods.getPosition(positionKey).call();
        aliceCreationBlock = position.creationBlock;
        assert.notStrictEqual(result, null);
    });
    it("bob should set a new staking position", async() => {
        await mainToken.methods.approve(liquidityMiningContract.options.address, await mainToken.methods.totalSupply().call()).send(blockchainConnection.getSendingOptions());
        await secondaryToken.methods.approve(liquidityMiningContract.options.address, await secondaryToken.methods.totalSupply().call()).send(blockchainConnection.getSendingOptions());
        var mainTokenAmount = web3.utils.toWei('0.35', 'ether');
        var secondaryTokenAmount = web3.utils.toWei('0.001', utilities.fromDecimalsToCurrency(await secondaryToken.methods.decimals().call()));
        var stake = {
            setupIndex: 2,
            secondaryTokenAddress: secondaryToken.options.address,
            liquidityPoolTokenAmount: 0,
            mainTokenAmount,
            secondaryTokenAmount,
            positionOwner: zero,
            mintPositionToken: false,
        };
        var result = await liquidityMiningContract.methods.stake(stake).send(blockchainConnection.getSendingOptions());
        const { positionKey } = result.events.NewPosition.returnValues;
        const position = await liquidityMiningContract.methods.getPosition(positionKey).call();
        bobCreationBlock = position.creationBlock;
        assert.notStrictEqual(result, null);
    });
    it("charlie should set a new staking position", async() => {
        await mainToken.methods.approve(liquidityMiningContract.options.address, await mainToken.methods.totalSupply().call()).send(blockchainConnection.getSendingOptions());
        await secondaryToken.methods.approve(liquidityMiningContract.options.address, await secondaryToken.methods.totalSupply().call()).send(blockchainConnection.getSendingOptions());
        var mainTokenAmount = web3.utils.toWei('0.001', 'ether');
        var secondaryTokenAmount = web3.utils.toWei('0.001', utilities.fromDecimalsToCurrency(await secondaryToken.methods.decimals().call()));
        var stake = {
            setupIndex: 0,
            secondaryTokenAddress: secondaryToken.options.address,
            liquidityPoolTokenAmount: 0,
            mainTokenAmount,
            secondaryTokenAmount,
            positionOwner: zero,
            mintPositionToken: false,
        };
        var result = await liquidityMiningContract.methods.stake(stake).send(blockchainConnection.getSendingOptions());
        const { positionKey } = result.events.NewPosition.returnValues;
        const position = await liquidityMiningContract.methods.getPosition(positionKey).call();
        // console.log(position);
        assert.notStrictEqual(result, null);
    });
    it("donald should set a new staking position", async() => {
        await mainToken.methods.approve(liquidityMiningContract.options.address, await mainToken.methods.totalSupply().call()).send(blockchainConnection.getSendingOptions());
        await secondaryToken.methods.approve(liquidityMiningContract.options.address, await secondaryToken.methods.totalSupply().call()).send(blockchainConnection.getSendingOptions());
        var mainTokenAmount = web3.utils.toWei('0.0017', 'ether');
        var secondaryTokenAmount = web3.utils.toWei('0.001', utilities.fromDecimalsToCurrency(await secondaryToken.methods.decimals().call()));
        var stake = {
            setupIndex: 0,
            secondaryTokenAddress: secondaryToken.options.address,
            liquidityPoolTokenAmount: 0,
            mainTokenAmount,
            secondaryTokenAmount,
            positionOwner: zero,
            mintPositionToken: false,
        };
        var result = await liquidityMiningContract.methods.stake(stake).send(blockchainConnection.getSendingOptions());
        const { positionKey } = result.events.NewPosition.returnValues;
        const position = await liquidityMiningContract.methods.getPosition(positionKey).call();
        // console.log(position);
        assert.notStrictEqual(result, null);
    });
    it("should allow alice to partial reward without unwrapping the pair", async () => {
        var res = await liquidityPool.methods.balanceOf(liquidityMiningContract.options.address).call();
        console.log(`contract liquidity pool token balance is ${res}`);
        var result = await liquidityMiningContract.methods.partialReward(0, 1, aliceCreationBlock, false).send(blockchainConnection.getSendingOptions());
        console.log(result);
        assert.notStrictEqual(result, null);
    });
    it("should allow bob to partial reward unwrapping the pair", async () => {
        var res = await liquidityPool.methods.balanceOf(liquidityMiningContract.options.address).call();
        console.log(`contract liquidity pool token balance is ${res}`);
        var result = await liquidityMiningContract.methods.partialReward(0, 2, bobCreationBlock, true).send(blockchainConnection.getSendingOptions());
        console.log(result);
        assert.notStrictEqual(result, null);
    });
})
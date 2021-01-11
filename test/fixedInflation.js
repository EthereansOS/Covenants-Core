var assert = require("assert");
var utilities = require("../util/utilities");
var context = require("../util/context.json");
var compile = require("../util/compile");
var blockchainConnection = require("../util/blockchainConnection");
var dfoManager = require('../util/dfo');
var ethers = require('ethers');
var abi = new ethers.utils.AbiCoder();
var path = require('path');
var fs = require('fs');

global.formatMoneyDecPlaces = 4;

var ethItemOrchestrator;
var uniswapV2Factory;
var uniswapV2Router;
var wethToken;

var rewardToken;
var mainToken;
var secondaryToken;

var ethToSpend = 600;

var dfo;

var UniswapV2AMMV1;
var uniswapAMM;

var FixedInflationExtension;
var fixedInflationExtension;

var FixedInflation;
var fixedInflation;

var liquidityPool;

var actors = {};

describe("FixedInflation", () => {

    before(async () => {
        await blockchainConnection.init;


        ethItemOrchestrator = new web3.eth.Contract(context.ethItemOrchestratorABI, context.ethItemOrchestratorAddress);
        uniswapV2Router = new web3.eth.Contract(context.uniswapV2RouterABI, context.uniswapV2RouterAddress);
        uniswapV2Factory = new web3.eth.Contract(context.uniswapV2FactoryABI, context.uniswapV2FactoryAddress);

        wethToken = new web3.eth.Contract(context.IERC20ABI, await uniswapV2Router.methods.WETH().call());

        rewardToken = new web3.eth.Contract(context.IERC20ABI, context.daiTokenAddress);
        mainToken = new web3.eth.Contract(context.IERC20ABI, context.buidlTokenAddress);
        secondaryToken = new web3.eth.Contract(context.IERC20ABI, context.usdtTokenAddress);

        liquidityPool = new web3.eth.Contract(context.uniswapV2PairABI, await uniswapV2Factory.methods.getPair(mainToken.options.address, secondaryToken.options.address).call());

        await buyForETH(mainToken, ethToSpend);
        await buyForETH(secondaryToken, ethToSpend);
        await buyForETH(rewardToken, ethToSpend);

        UniswapV2AMMV1 = await compile('amm-aggregator/models/UniswapV2/1/UniswapV2AMMV1');
        uniswapAMM = await new web3.eth.Contract(UniswapV2AMMV1.abi).deploy({data : UniswapV2AMMV1.bin, arguments: [uniswapV2Router.options.address]}).send(blockchainConnection.getSendingOptions());

        FixedInflationExtension = await compile('fixed-inflation/FixedInflationExtension');
        FixedInflation = await compile('fixed-inflation/FixedInflation');

        await initActor("Alice", accounts[1], 0, 30, 1, 0, false, false, 0.09, 0.247, 0.09, 0.003);
        await initActor("Bob", accounts[2], 15, 50, 2, 0, false, true, 3.15, 0.177, 2.45, 0.07);
        await initActor("Charlie", accounts[3], 20, 200, 0, 0, false, false, 30, 0.177, 18.3075);
        await initActor("Donald", accounts[4], 40, 201, 0, 0, false, true, 50, 0.180, 24.8125);
        await initActor("Orbulo", accounts[5], 210, 250, 0, 0, false, true, 0.0001, 0.250, 10, 0, true);
        await initActor("Frank", accounts[6], 259, 304, 3, 0, false, false, 0.315, 0.243, 0.315, 0.007, true);
        await initActor("Vasapower", accounts[7], 259, 304, 3, 0, false, false, 0.315, 0.243, 0.315, 0.007, true);
        await initActor("Dino", accounts[8], 260, 304, 3, 0, false, false, 0.315, 0.236, 0.308, 0.007, false);
        await initActor("Ale", accounts[9], 260, 304, 3, 0, false, false, 0.315, 0.236, 0.308, 0.007, false);
        await initActor("Cavicchioli", accounts[10], 310, 320, 4, 0, false, false, 0.0001, 0.250, 3.75);

    });

    async function initActor(name, address, enterBlock, exitBlock, setupIndex, liquidityPoolAddressIndex, ethInvolved, unwrap, mainTokenAmountPlain, expectedPinnedFreeRewardPerBlock, expectedReward, expectedRewardPerBlock, positionItem) {
        actors[name] = {
            name,
            address,
            from : blockchainConnection.getSendingOptions({from : address}),
            enterBlock,
            exitBlock,
            setupIndex,
            liquidityPoolAddressIndex,
            unwrap,
            mainTokenAmountPlain,
            expectedPinnedFreeRewardPerBlock,
            expectedRewardPerBlock,
            expectedReward,
            positionItem,
            ethInvolved
        };

        await buyForETH(mainToken, ethToSpend, address);
        await buyForETH(secondaryToken, ethToSpend, address);
    }

    async function buyForETH(token, amount, from) {
        var path = [
            wethToken.options.address,
            token.options.address
        ];
        var value = utilities.toDecimals(amount.toString(), '18');
        await uniswapV2Router.methods.swapExactETHForTokens("1", path, (from && (from.from || from)) || accounts[0], parseInt((new Date().getTime() / 1000) + 1000)).send(blockchainConnection.getSendingOptions({from: (from && (from.from || from)) || accounts[0], value}));
    };

    it("Deploy all occurrency stuff", async () => {
        dfo = await dfoManager.createDFO("MyName", "MySymbol", 1000, 100, 10);

        await web3.eth.sendTransaction(blockchainConnection.getSendingOptions({
            to: dfo.mvdWalletAddress,
            value : utilities.toDecimals(30, 18)
        }));

        await rewardToken.methods.transfer(dfo.mvdWalletAddress, await rewardToken.methods.balanceOf(accounts[0]).call()).send(blockchainConnection.getSendingOptions());
        await mainToken.methods.transfer(dfo.mvdWalletAddress, await mainToken.methods.balanceOf(accounts[0]).call()).send(blockchainConnection.getSendingOptions());
        await secondaryToken.methods.transfer(dfo.mvdWalletAddress, await secondaryToken.methods.balanceOf(accounts[0]).call()).send(blockchainConnection.getSendingOptions());

        fixedInflationExtension = await new web3.eth.Contract(FixedInflationExtension.abi).deploy({data : FixedInflationExtension.bin}).send(blockchainConnection.getSendingOptions());

        var code = fs.readFileSync(path.resolve(__dirname, '..', 'contracts/fixed-inflation/dfo/ManageFixedInflationFunctionality.sol'), 'UTF-8').format(fixedInflationExtension.options.address);
        var proposal = await dfoManager.createProposal(dfo, "manageFixedInflation", true, code, "manageFixedInflation(address,uint256,address[],uint256[],uint256[],address)", false, true);
        await dfoManager.finalizeProposal(dfo, proposal);

        fixedInflation = await new web3.eth.Contract(FixedInflation.abi).deploy({data : FixedInflation.bin}).send(blockchainConnection.getSendingOptions());

        var newEntries = [{
            lastBlock : 0,
            blockInterval : 10,
            ammPlugins : [utilities.voidEthereumAddress]
        }];

        var operationSets = [[{
            inputToken : {
                tokenAddress : utilities.voidEthereumAddress,
                amount : utilities.toDecimals("0.01", "18"),
                amountIsPercentage : false,
                amountByMint : false
            },
            receiver : accounts[1],
            liquidityPoolAddresses : [],
            swapPath : [],
            byEarnPercentage : 0,
            rewardToken : {
                tokenAddress : utilities.voidEthereumAddress,
                amount : 0,
                amountIsPercentage : false,
                amountByMint : false
            }
        }]];

        await fixedInflation.methods.init(
            fixedInflationExtension.options.address,
            fixedInflationExtension.methods.init(dfo.doubleProxyAddress).encodeABI(),
            newEntries,
            operationSets
        ).send(blockchainConnection.getSendingOptions());
    });

    it("Cannot re-initialize already initialized contracts", async () => {
        try {
            await fixedInflationExtension.methods.init(dfo.doubleProxyAddress).send(blockchainConnection.getSendingOptions());
            assert(false);
        } catch(e) {
            assert.notStrictEqual((e.message || e).toLowerCase().indexOf("already init"), -1);
        }
        try {
            var newEntries = [{
                lastBlock : 0,
                blockInterval : 10,
                ammPlugins : [utilities.voidEthereumAddress]
            }];

            var operationSets = [[{
                inputToken : {
                    tokenAddress : utilities.voidEthereumAddress,
                    amount : utilities.toDecimals("0.01", "18"),
                    amountIsPercentage : false,
                    amountByMint : false
                },
                receiver : accounts[1],
                liquidityPoolAddresses : [],
                swapPath : [],
                byEarnPercentage : 0,
                rewardToken : {
                    tokenAddress : utilities.voidEthereumAddress,
                    amount : 0,
                    amountIsPercentage : false,
                    amountByMint : false
                }
            }]];
            await fixedInflation.methods.init(
                fixedInflationExtension.options.address,
                fixedInflationExtension.methods.init(dfo.doubleProxyAddress).encodeABI(),
                newEntries,
                operationSets
            ).send(blockchainConnection.getSendingOptions());
            assert(false);
        } catch(e) {
            assert.notStrictEqual((e.message || e).toLowerCase().indexOf("already init"), -1);
        }
    });

    it("Transfer Eth to a wallet", async () => {
        var entryIndex = 0;
        var byEarn = false;
        var operation = (await fixedInflation.methods.entries().call())[1][entryIndex][0];
        var receiver = operation.receiver;
        var balanceOfExpected = await web3.eth.getBalance(receiver);
        balanceOfExpected = web3.utils.toBN(balanceOfExpected).add(web3.utils.toBN(operation.inputToken.amount)).toString();
        balanceOfExpected = utilities.fromDecimals(balanceOfExpected, 18);

        await fixedInflation.methods.call([[entryIndex, byEarn ? 1 : 0]]).send(blockchainConnection.getSendingOptions());

        var balanceOfAfter = await web3.eth.getBalance(receiver);
        balanceOfAfter = utilities.fromDecimals(balanceOfAfter, 18);

        assert.strictEqual(balanceOfAfter, balanceOfExpected);
    });
    it("Cannot be possible to call an already-called fixedInflation", async () => {
        try {
            await fixedInflation.methods.call([[0, 0]]).send(blockchainConnection.getSendingOptions());
            assert(false);
        } catch(e) {
            assert.notStrictEqual((e.message || e).toLowerCase().indexOf("too early to call index"), -1);
        }
    });
    it("Recall the same after past time", async () => {
        var entryIndex = 0;
        var byEarn = false;
        var entries = (await fixedInflation.methods.entries().call());
        var entry = entries[0][entryIndex];
        var operation = entries[1][entryIndex][0];
        var receiver = operation.receiver;
        var balanceOfExpected = await web3.eth.getBalance(receiver);
        balanceOfExpected = web3.utils.toBN(balanceOfExpected).add(web3.utils.toBN(operation.inputToken.amount)).toString();
        balanceOfExpected = utilities.fromDecimals(balanceOfExpected, 18);

        await blockchainConnection.fastForward(entry.blockInterval);
        await fixedInflation.methods.call([[entryIndex, byEarn ? 1 : 0]]).send(blockchainConnection.getSendingOptions());

        var balanceOfAfter = await web3.eth.getBalance(receiver);
        balanceOfAfter = utilities.fromDecimals(balanceOfAfter, 18);

        assert.strictEqual(balanceOfAfter, balanceOfExpected);
    });
});
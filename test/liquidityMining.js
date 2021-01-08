var assert = require("assert");
var utilities = require("../util/utilities");
var context = require("../util/context.json");
var compile = require("../util/compile");
var blockchainConnection = require("../util/blockchainConnection");
var dfoManager = require('../util/dfo');
var path = require('path');
var fs = require('fs');

global.formatMoneyDecPlaces = 4;

var LiquidityMining;
var LiquidityMiningFactory;
var LiquidityMiningExtension;
var UniswapV2AMMV1;

var ethItemOrchestrator;
var uniswapV2Router;
var uniswapV2Factory;
var wethToken;
var rewardToken;
var mainToken;
var secondaryToken;
var liquidityMiningFactory;
var liquidityMiningExtension;
var dfo;
var liquidityMiningContract;
var liquidityPool;
var uniswapAMM;
var ethToSpend = 600;
var positionTokenCollection;

var actors = {};

var zeroBlock;

describe("LiquidityMining", () => {

    before(async () => {
        await blockchainConnection.init;
        LiquidityMining = await compile('liquidity-mining/LiquidityMining');
        LiquidityMiningFactory = await compile('liquidity-mining/LiquidityMiningFactory');
        LiquidityMiningExtension = await compile('liquidity-mining/LiquidityMiningExtension');
        UniswapV2AMMV1 = await compile('amm-aggregator/models/UniswapV2/1/UniswapV2AMMV1');

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

        uniswapAMM = await new web3.eth.Contract(UniswapV2AMMV1.abi).deploy({data : UniswapV2AMMV1.bin, arguments: [uniswapV2Router.options.address]}).send(blockchainConnection.getSendingOptions());

        await initActor("Alice", accounts[1], 0, 30, 1, false, 0.09, 0.247, 0.09, 0.003);
        await initActor("Bob", accounts[2], 15, 50, 2, true, 3.15, 0.177, 2.45, 0.07);
        await initActor("Charlie", accounts[3], 20, 200, 0, false, 30, 0.177, 18.3075);
        await initActor("Donald", accounts[4], 40, 201, 0, true, 50, 0.180, 24.8125);
        await initActor("Orbulo", accounts[5], 210, 250, 0, true, 0.0001, 0.250, 10, 0, true);
        await initActor("Frank", accounts[6], 259, 304, 3, false, 0.315, 0.243, 0.245, 0.007, true);
        // await initActor("Vasapower", accounts[7], 253, 0, 3, false, 0.315, 0.236, 0.245, 0.007, true);

    });

    async function initActor(name, address, enterBlock, exitBlock, setupIndex, unwrap, mainTokenAmountPlain, expectedPinnedFreeRewardPerBlock, expectedReward, expectedRewardPerBlock, positionItem) {
        actors[name] = {
            name,
            address,
            from : blockchainConnection.getSendingOptions({from : address}),
            enterBlock,
            exitBlock,
            setupIndex,
            unwrap,
            mainTokenAmountPlain,
            expectedPinnedFreeRewardPerBlock,
            expectedRewardPerBlock,
            expectedReward,
            positionItem
        };

        await buyForETH(mainToken, ethToSpend, address);
        await buyForETH(secondaryToken, ethToSpend, address);

        await mainToken.methods.approve(uniswapAMM.options.address, await mainToken.methods.totalSupply().call()).send(actors[name].from);
        await secondaryToken.methods.approve(uniswapAMM.options.address, await secondaryToken.methods.totalSupply().call()).send(actors[name].from);
    }

    async function buyForETH(token, amount, from) {
        var path = [
            wethToken.options.address,
            token.options.address
        ];
        var value = utilities.toDecimals(amount.toString(), '18');
        await uniswapV2Router.methods.swapExactETHForTokens("1", path, (from && (from.from || from)) || accounts[0], parseInt((new Date().getTime() / 1000) + 1000)).send(blockchainConnection.getSendingOptions({from: (from && (from.from || from)) || accounts[0], value}));
    };

    async function logData(blockNumber) {
        const setupUpdateBlocks = [];
        for (let i = 0; i < 10000; i++) {
            try {
                const res = await liquidityMiningContract.methods._setupUpdateBlocks(0, i).call();
                setupUpdateBlocks.push(res);
            } catch (e) {
                break;
            }
        }
        console.log('setup update blocks: ', setupUpdateBlocks);
        const rewardPerToken = await liquidityMiningContract.methods._rewardPerTokenPerSetupPerBlock(0, blockNumber).call();
        console.log(`reward per token at block ${blockNumber} is ${rewardPerToken}`);
    }

    async function logSetups() {
        const setups = [];
        for (let i = 0; i < 10000; i++) {
            try {
                const setup = await liquidityMiningContract.methods._farmingSetups(i).call();
                setups.push(setup);
            } catch (e) {
                break
            }
        }
        console.log('setups:', setups);
    }

    it("New LiquidityMining Contract by Factory by extension", async () => {

        dfo = await dfoManager.createDFO("MyName", "MySymbol", 1000, 100, 10);

        await rewardToken.methods.transfer(dfo.mvdWalletAddress, await rewardToken.methods.balanceOf(accounts[0]).call()).send(blockchainConnection.getSendingOptions());

        var liquidityMiningModel = await new web3.eth.Contract(LiquidityMining.abi).deploy({data : LiquidityMining.bin}).send(blockchainConnection.getSendingOptions());
        liquidityMiningFactory = await new web3.eth.Contract(LiquidityMiningFactory.abi).deploy({data : LiquidityMiningFactory.bin, arguments : [dfo.doubleProxyAddress, liquidityMiningModel.options.address]}).send(blockchainConnection.getSendingOptions());

        liquidityMiningExtension = await new web3.eth.Contract(LiquidityMiningExtension.abi).deploy({data : LiquidityMiningExtension.bin}).send(blockchainConnection.getSendingOptions());

        var code = fs.readFileSync(path.resolve(__dirname, '..', 'contracts/liquidity-mining/dfo/ManageLiquidityMiningFunctionality.sol'), 'UTF-8').format(liquidityMiningExtension.options.address);
        var proposal = await dfoManager.createProposal(dfo, "manageLiquidityMining", true, code, "manageLiquidityMining(address,uint256,bool,address,address,uint256,bool)", false, true);
        await dfoManager.finalizeProposal(dfo, proposal);

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
            liquidityMiningExtension.options.address,
            liquidityMiningExtension.methods.init(dfo.doubleProxyAddress).encodeABI(),
            ethItemOrchestrator.options.address,
            "LiquidityMiningToken",
            "LMT",
            "google.com",
            rewardToken.options.address,
            false
        ];
        var payload = web3.utils.sha3(`initialize(${params.join(',')})`).substring(0, 10) + (web3.eth.abi.encodeParameters(params, values).substring(2));
        var deployTransaction = await liquidityMiningFactory.methods.deploy(payload).send(blockchainConnection.getSendingOptions());
        deployTransaction = await web3.eth.getTransactionReceipt(deployTransaction.transactionHash);
        var liquidityMiningContractAddress = web3.eth.abi.decodeParameter("address", deployTransaction.logs.filter(it => it.topics[0] === web3.utils.sha3("LiquidityMiningDeployed(address,address)"))[0].topics[2]);
        liquidityMiningContract = await new web3.eth.Contract(LiquidityMining.abi, liquidityMiningContractAddress);
        assert.notStrictEqual(liquidityMiningContract.options.address, utilities.voidEthereumAddress);

        assert.strictEqual(await liquidityMiningContract.methods._owner().call(), liquidityMiningExtension.options.address);
    });
    it("Previously created LiquidityMining Contract cannot be initialized more than a time", async() => {
        try {
            await liquidityMiningContract.methods.initialize(accounts[0], "0x", ethItemOrchestrator.options.address, "TestCollection1", "TSTC", "test", ethItemOrchestrator.options.address, false).send(blockchainConnection.getSendingOptions());
        } catch (e) {
            assert.notStrictEqual((e.message || e).toLowerCase().indexOf("already initialized"), -1);
        }
    });
    it("should retrieve the correct factory address", async() => {
        var factoryAddress = await liquidityMiningContract.methods._factory().call();
        assert.strictEqual(factoryAddress, liquidityMiningFactory.options.address);
    });
    it("should retrieve the position token collection", async() => {
        positionTokenCollection = await liquidityMiningContract.methods._positionTokenCollection().call();
        assert.notStrictEqual(positionTokenCollection, utilities.voidEthereumAddress);
        positionTokenCollection = new web3.eth.Contract(context.ethItemNativeABI, positionTokenCollection);
    });
    it("Exit fee is 0", async() => {
        var exitFee = await liquidityMiningFactory.methods._exitFee().call();
        assert.strictEqual(parseInt(exitFee), 0);
    });
    it("DFO can update the exit fee to 1", async() => {
        var exitFeeExpected = 1;
        var code = fs.readFileSync(path.resolve(__dirname, '..', 'resources/LiquidityMiningSetFeeProposal.sol'), 'UTF-8').format(liquidityMiningFactory.options.address, exitFeeExpected);
        var proposal = await dfoManager.createProposal(dfo, "", true, code, "callOneTime(address)");
        await dfoManager.finalizeProposal(dfo, proposal);
        var exitFee = await liquidityMiningFactory.methods._exitFee().call();
        assert.strictEqual(parseInt(exitFee), exitFeeExpected);
    });
    it("Another account cannot update the exit fee", async() => {
        try {
            await liquidityMiningFactory.methods.updateExitFee(0).send(blockchainConnection.getSendingOptions({from: accounts[1]}));
        } catch (e) {
            assert.notStrictEqual((e.message|| e).toLowerCase().indexOf("unauthorized"), -1);
        }
    });
    it("should not set the farming setups", async() => {
        try {
            var setups = [{
                ammPlugin: utilities.voidEthereumAddress,
                liquidityPoolTokenAddress: utilities.voidEthereumAddress,
                startBlock: 0,
                endBlock: 1,
                rewardPerBlock: 0,
                currentRewardPerBlock: 0,
                maximumLiquidity: 0,
                totalSupply: 0,
                lastBlockUpdate: 0,
                mainTokenAddress: utilities.voidEthereumAddress,
                secondaryTokenAddresses: [utilities.voidEthereumAddress],
                free: false,
                renewable: true,
            }];
            await liquidityMiningContract.methods.setFarmingSetups(setups, [0], false, 0).send(blockchainConnection.getSendingOptions({from: accounts[1]}));
            throw "Farming Setup done";
        } catch (error) {
            assert(error, "Only the owner can set the farming setups.");
        }
    });
    it("should set the farming setups", async() => {
        zeroBlock = (await web3.eth.getBlockNumber()) + 4;

        Object.values(actors).forEach(it => {
            it.enterBlock += zeroBlock;
            it.exitBlock += zeroBlock;
        });

        var longTerm1SetupStartBlock = zeroBlock;
        var longTerm1SetupDuration = 30;
        longTerm1SetupEndBlock = longTerm1SetupStartBlock + longTerm1SetupDuration;
        var longTerm1SetupRewardPerBlockPlain = 0.03;
        var longTerm1SetupRewardPerBlock = utilities.toDecimals(longTerm1SetupRewardPerBlockPlain, await rewardToken.methods.decimals().call());
        var longTerm1Setup = {
            ammPlugin: uniswapAMM.options.address,
            liquidityPoolTokenAddress: liquidityPool.options.address,
            startBlock: longTerm1SetupStartBlock,
            endBlock: longTerm1SetupEndBlock,
            rewardPerBlock: longTerm1SetupRewardPerBlock,
            currentRewardPerBlock: 0,
            maximumLiquidity: utilities.toDecimals(longTerm1SetupRewardPerBlockPlain * longTerm1SetupDuration, await rewardToken.methods.decimals().call()),
            totalSupply: 0,
            lastBlockUpdate: 0,
            mainTokenAddress: mainToken.options.address,
            secondaryTokenAddresses: [secondaryToken.options.address],
            free: false,
            renewable: true,
            penaltyFee: 1,
        };

        var longTerm2SetupStartBlock = zeroBlock + 5;
        var longTerm2SetupDuration = 45;
        longTerm2SetupEndBlock = longTerm2SetupStartBlock + longTerm2SetupDuration;
        var longTerm2SetupRewardPerBlockPlain = 0.07;
        var longTerm2SetupRewardPerBlock = utilities.toDecimals(longTerm2SetupRewardPerBlockPlain, await rewardToken.methods.decimals().call());
        var longTerm2Setup = {
            ammPlugin: uniswapAMM.options.address,
            liquidityPoolTokenAddress: liquidityPool.options.address,
            startBlock: longTerm2SetupStartBlock,
            endBlock: longTerm2SetupEndBlock,
            rewardPerBlock: longTerm2SetupRewardPerBlock,
            currentRewardPerBlock: 0,
            maximumLiquidity: utilities.toDecimals(longTerm2SetupRewardPerBlockPlain * longTerm2SetupDuration, await rewardToken.methods.decimals().call()),
            totalSupply: 0,
            lastBlockUpdate: 0,
            mainTokenAddress: mainToken.options.address,
            secondaryTokenAddresses: [secondaryToken.options.address],
            free: false,
            renewable: false,
            penaltyFee: 1,
        };

        var freeRewardPerBlockPlain = 0.25;
        var freeRewardPerBlock = utilities.toDecimals(freeRewardPerBlockPlain, await rewardToken.methods.decimals().call());
        var pinnedFreeSetup = {
            ammPlugin: uniswapAMM.options.address,
            liquidityPoolTokenAddress : liquidityPool.options.address,
            startBlock: 0,
            endBlock: 0,
            rewardPerBlock: freeRewardPerBlock,
            currentRewardPerBlock: freeRewardPerBlock,
            maximumLiquidity: 0,
            totalSupply: 0,
            lastBlockUpdate: 0,
            mainTokenAddress: mainToken.options.address,
            secondaryTokenAddresses: [secondaryToken.options.address],
            free: true,
            renewable: false,
            penaltyFee: 0,
        };

        var farmingSetups = [pinnedFreeSetup, longTerm1Setup, longTerm2Setup];
        var farmingSetupsCode = farmingSetups.map((it, i) => `farmingSetups[${i}] = FarmingSetup(${it.ammPlugin}, ${it.liquidityPoolTokenAddress}, ${it.startBlock}, ${it.endBlock}, ${it.rewardPerBlock}, ${it.currentRewardPerBlock}, ${it.maximumLiquidity}, ${it.totalSupply}, ${it.lastBlockUpdate}, ${it.mainTokenAddress}, secondaryTokenAddresses, ${it.free}, ${it.renewable}, ${it.penaltyFee});`).join('\n        ');
        var code = fs.readFileSync(path.resolve(__dirname, '..', 'resources/LiquidityMiningSetFarmingSetupsProposal.sol'), 'UTF-8').format(secondaryToken.options.address, farmingSetups.length, farmingSetupsCode, liquidityMiningExtension.options.address, liquidityMiningContract.options.address);

        var proposal = await dfoManager.createProposal(dfo, "", true, code, "callOneTime(address)");
        await dfoManager.finalizeProposal(dfo, proposal);
    });
    async function createNewStakingPosition(actor) {

        var {from, setupIndex, enterBlock, mainTokenAmountPlain, expectedRewardPerBlock, positionItem} = actor;

        await blockchainConnection.jumpToBlock(enterBlock, true);

        var mainTokenAmount = utilities.toDecimals(mainTokenAmountPlain, await mainToken.methods.decimals().call());

        var setup = await liquidityMiningContract.methods._farmingSetups(setupIndex).call();
        console.log("chosen setup is", setup);
        var expectedRemainingRewardPerBlock = web3.utils.toBN(setup.rewardPerBlock);
        expectedRemainingRewardPerBlock = expectedRemainingRewardPerBlock.sub(web3.utils.toBN(utilities.toDecimals(expectedRewardPerBlock), await rewardToken.methods.decimals().call())).toString();
        expectedRemainingRewardPerBlock = utilities.fromDecimals(expectedRemainingRewardPerBlock, await rewardToken.methods.decimals().call());

        var expectedReward = expectedRewardPerBlock * (actor.exitBlock - enterBlock);

        expectedRemainingRewardPerBlock = utilities.formatMoney(expectedRemainingRewardPerBlock);

        var pinnedFreeSetupIndex = await liquidityMiningContract.methods._pinnedSetupIndex().call();
        var pinnedFreeSetup = await liquidityMiningContract.methods._farmingSetups(pinnedFreeSetupIndex).call();
        var expectedPinnedFreeRewardPerBlock = pinnedFreeSetup.rewardPerBlock;

        if(!setup.free) {
            expectedPinnedFreeRewardPerBlock = web3.utils.toBN(expectedPinnedFreeRewardPerBlock).sub(web3.utils.toBN(utilities.toDecimals(expectedRewardPerBlock, await rewardToken.methods.decimals().call()))).toString();
        }

        expectedPinnedFreeRewardPerBlock = utilities.fromDecimals(expectedPinnedFreeRewardPerBlock, await rewardToken.methods.decimals().call());

        var ammPlugin = new web3.eth.Contract(UniswapV2AMMV1.abi, setup.ammPlugin);

        var tokens = await ammPlugin.methods.tokens(setup.liquidityPoolTokenAddress).call();

        var secondaryTokenIndex = tokens[0] === secondaryToken.options.address ? 0 : 1;

        var amounts = await ammPlugin.methods.byTokenAmount(setup.liquidityPoolTokenAddress, mainToken.options.address, mainTokenAmount).call();

        var liquidityPoolTokenAmount = amounts[0];

        var secondaryTokenAmount = amounts[1][secondaryTokenIndex];

        var stake = {
            setupIndex,
            secondaryTokenAddress: secondaryToken.options.address,
            liquidityPoolTokenAmount,
            mainTokenAmount,
            secondaryTokenAmount,
            positionOwner: utilities.voidEthereumAddress,
            mintPositionToken: positionItem ? true : false,
        };
        var result = await liquidityMiningContract.methods.stake(stake).send(blockchainConnection.getSendingOptions(from));
        await logSetups();
        var { positionKey } = result.events.NewPosition.returnValues;
        var position = await liquidityMiningContract.methods.getPosition(positionKey).call();
        console.log(position);
        actor.enterBlock = position.creationBlock;
        actor.positionKey = positionKey;
        var balance = 0;
        if (stake.mintPositionToken) {
            actor.objectId = position.objectId;
            balance = await liquidityMiningContract.methods.balanceOf(positionKey).call(actor.from);
            assert.strictEqual(parseInt(balance), 1);
        }

        !position.setup.free && assert.strictEqual(utilities.fromDecimals(position.lockedRewardPerBlock, await rewardToken.methods.decimals().call()), utilities.formatMoney(expectedRewardPerBlock));
        !position.setup.free && assert.strictEqual(utilities.fromDecimals(position.reward, await rewardToken.methods.decimals().call()), utilities.formatMoney(expectedReward));

        setup = await liquidityMiningContract.methods._farmingSetups(setupIndex).call();
        var remainingRewardPerBlock = utilities.fromDecimals(setup.rewardPerBlock, await rewardToken.methods.decimals().call());
        assert.strictEqual(remainingRewardPerBlock, expectedRemainingRewardPerBlock);

        pinnedFreeSetup = await liquidityMiningContract.methods._farmingSetups(pinnedFreeSetupIndex).call();
        var pinnedFreeRewardPerBlock = utilities.fromDecimals(pinnedFreeSetup.rewardPerBlock, await rewardToken.methods.decimals().call());
        assert.strictEqual(pinnedFreeRewardPerBlock, expectedPinnedFreeRewardPerBlock);

        console.log(actor.name, actor.enterBlock - zeroBlock, "stake - ", pinnedFreeRewardPerBlock, "free rpb - ", position.liquidityPoolTokenAmount, " lpt amount - ", balance, " token balance");

        return position;
    }
    it("alice should set a new staking position", () => {
        return createNewStakingPosition(actors.Alice);
    });
    it("bob should set a new staking position", () => {
        return createNewStakingPosition(actors.Bob);
    });
    it("charlie should set a new staking position", () => {
        return createNewStakingPosition(actors.Charlie);
    });
    it("should allow alice to partial reward", async () => {
        var actor = actors.Alice;
        var balanceOf = await rewardToken.methods.balanceOf(actor.address).call();
        var blockNumber = ((await web3.eth.getBlockNumber()) + 1) - actor.enterBlock;
        var expectedReward = utilities.toDecimals(actor.expectedRewardPerBlock, await rewardToken.methods.decimals().call());
        expectedReward = web3.utils.toBN(expectedReward).mul(web3.utils.toBN(blockNumber.toString())).toString();
        var expectedBalanceOf = utilities.fromDecimals(web3.utils.toBN(expectedReward).add(web3.utils.toBN(balanceOf)).toString(), await rewardToken.methods.decimals().call());

        await liquidityMiningContract.methods.partialReward(actor.positionKey, 1).send(actor.from);
        balanceOf = await rewardToken.methods.balanceOf(actor.address).call();
        balanceOf = utilities.fromDecimals(balanceOf, await rewardToken.methods.decimals().call());

        assert.strictEqual(expectedBalanceOf, balanceOf);

        actor.expectedReward -= parseFloat(utilities.fromDecimals(expectedReward, await rewardToken.methods.decimals().call(), true));
    });
    async function unlockStakingPosition(actor) {
        var position = await liquidityMiningContract.methods.getPosition(actor.positionKey).call();

        var liquidityPoolTokenAmount = web3.utils.toBN(position.liquidityPoolTokenAmount);
        var exitFee = await liquidityMiningFactory.methods._exitFee().call();
        if(parseInt(exitFee) > 0) {
            exitFee = web3.utils.toBN(exitFee);
            var oneE18 = web3.utils.toBN(1e18);
            var hundred = web3.utils.toBN(100);
            var diff = liquidityPoolTokenAmount.mul(exitFee.mul(oneE18).div(hundred)).div(oneE18);
            liquidityPoolTokenAmount = liquidityPoolTokenAmount.sub(diff);
        }

        liquidityPoolTokenAmount = liquidityPoolTokenAmount.toString();

        var rewardBalance = await rewardToken.methods.balanceOf(actor.address).call();
        var mainBalance = await mainToken.methods.balanceOf(actor.address).call();
        var secondaryBalance = await secondaryToken.methods.balanceOf(actor.address).call();
        var liquidityPoolBalance = await liquidityPool.methods.balanceOf(actor.address).call();

        var tokens = await uniswapAMM.methods.tokens(liquidityPool.options.address).call();
        var mainTokenIndex = tokens[0] === mainToken.options.address ? 0 : 1;
        var secondaryTokenIndex = tokens[0] === secondaryToken.options.address ? 0 : 1;
        var amounts = await uniswapAMM.methods.byLiquidityPoolAmount(liquidityPool.options.address, liquidityPoolTokenAmount).call();

        var expectedRewardBalance = utilities.fromDecimals(web3.utils.toBN(rewardBalance).add(web3.utils.toBN(await utilities.toDecimals(actor.expectedReward, await rewardToken.methods.decimals().call()))).toString(), await rewardToken.methods.decimals().call());
        var expectedMainBalance = utilities.fromDecimals(web3.utils.toBN(mainBalance).add(web3.utils.toBN(amounts[mainTokenIndex])).toString(), await mainToken.methods.decimals().call());
        var expectedSecondaryBalance = utilities.fromDecimals(web3.utils.toBN(secondaryBalance).add(web3.utils.toBN(amounts[secondaryTokenIndex])).toString(), await secondaryToken.methods.decimals().call());
        var expectedLiquidityPoolBalance = utilities.fromDecimals(web3.utils.toBN(liquidityPoolBalance).add(web3.utils.toBN(liquidityPoolTokenAmount)).toString(), await liquidityPool.methods.decimals().call());

        await liquidityMiningContract.methods.unlock(actor.positionKey, actor.setupIndex, actor.unwrap).send(actor.from);

        var rewardBalance = utilities.fromDecimals(await rewardToken.methods.balanceOf(actor.address).call(), await rewardToken.methods.decimals().call());
        var mainBalance = utilities.fromDecimals(await mainToken.methods.balanceOf(actor.address).call(), await mainToken.methods.decimals().call());
        var secondaryBalance = utilities.fromDecimals(await secondaryToken.methods.balanceOf(actor.address).call(), await secondaryToken.methods.decimals().call());
        var liquidityPoolBalance = utilities.fromDecimals(await liquidityPool.methods.balanceOf(actor.address).call(), await liquidityPool.methods.decimals().call());

        if(actor.partialReward) {
            expectedRewardBalance = 0.01393;
            assert.strictEqual(rewardBalance, expectedRewardBalance);
        }

        if(actor.unwrap) {
            assert.strictEqual(mainBalance, expectedMainBalance);
            assert.strictEqual(secondaryBalance, expectedSecondaryBalance);
        } else {
            assert.strictEqual(liquidityPoolBalance, expectedLiquidityPoolBalance);
        }
    };
    async function withdrawStakingPosition(actor) {

        if (actor.name !== "Bob") {
            await blockchainConnection.jumpToBlock(actor.exitBlock, true);
        }

        var position = await liquidityMiningContract.methods.getPosition(actor.positionKey).call();

        var liquidityPoolTokenAmount = web3.utils.toBN(position.liquidityPoolTokenAmount);
        var exitFee = await liquidityMiningFactory.methods._exitFee().call();
        if(parseInt(exitFee) > 0) {
            exitFee = web3.utils.toBN(exitFee);
            var oneE18 = web3.utils.toBN(1e18);
            var hundred = web3.utils.toBN(100);
            var diff = liquidityPoolTokenAmount.mul(exitFee.mul(oneE18).div(hundred)).div(oneE18);
            liquidityPoolTokenAmount = liquidityPoolTokenAmount.sub(diff);
        }

        liquidityPoolTokenAmount = liquidityPoolTokenAmount.toString();

        var rewardBalance = await rewardToken.methods.balanceOf(actor.address).call();
        var mainBalance = await mainToken.methods.balanceOf(actor.address).call();
        var secondaryBalance = await secondaryToken.methods.balanceOf(actor.address).call();
        var liquidityPoolBalance = await liquidityPool.methods.balanceOf(actor.address).call();

        var tokens = await uniswapAMM.methods.tokens(liquidityPool.options.address).call();
        var mainTokenIndex = tokens[0] === mainToken.options.address ? 0 : 1;
        var secondaryTokenIndex = tokens[0] === secondaryToken.options.address ? 0 : 1;
        var amounts = await uniswapAMM.methods.byLiquidityPoolAmount(liquidityPool.options.address, liquidityPoolTokenAmount).call();

        var expectedRewardBalance = utilities.fromDecimals(web3.utils.toBN(rewardBalance).add(web3.utils.toBN(await utilities.toDecimals(actor.expectedReward, await rewardToken.methods.decimals().call()))).toString(), await rewardToken.methods.decimals().call());
        var expectedMainBalance = utilities.fromDecimals(web3.utils.toBN(mainBalance).add(web3.utils.toBN(amounts[mainTokenIndex])).toString(), await mainToken.methods.decimals().call());
        var expectedSecondaryBalance = utilities.fromDecimals(web3.utils.toBN(secondaryBalance).add(web3.utils.toBN(amounts[secondaryTokenIndex])).toString(), await secondaryToken.methods.decimals().call());
        var expectedLiquidityPoolBalance = utilities.fromDecimals(web3.utils.toBN(liquidityPoolBalance).add(web3.utils.toBN(liquidityPoolTokenAmount)).toString(), await liquidityPool.methods.decimals().call());
        
        // await positionTokenCollection.methods.setApprovalForAll(liquidityMiningContract.options.address, true).send(actor.from);
        await liquidityMiningContract.methods.withdraw(actor.positionKey, actor.setupIndex, actor.unwrap).send(actor.from);

        var rewardBalance = utilities.fromDecimals(await rewardToken.methods.balanceOf(actor.address).call(), await rewardToken.methods.decimals().call());
        var mainBalance = utilities.fromDecimals(await mainToken.methods.balanceOf(actor.address).call(), await mainToken.methods.decimals().call());
        var secondaryBalance = utilities.fromDecimals(await secondaryToken.methods.balanceOf(actor.address).call(), await secondaryToken.methods.decimals().call());
        var liquidityPoolBalance = utilities.fromDecimals(await liquidityPool.methods.balanceOf(actor.address).call(), await liquidityPool.methods.decimals().call());
        await logData(actor.exitBlock);
        // await logSetups();
        console.log(actor.name, rewardBalance, expectedRewardBalance);
        assert.strictEqual(rewardBalance, expectedRewardBalance);

        if(actor.unwrap) {
            assert.strictEqual(mainBalance, expectedMainBalance);
            assert.strictEqual(secondaryBalance, expectedSecondaryBalance);
        } else {
            assert.strictEqual(liquidityPoolBalance, expectedLiquidityPoolBalance);
        }
    }
    it("should not allow alice to unlock without unwrapping the pair", async () => {
        try {
            await unlockStakingPosition(actors.Alice);
            assert(false);
        } catch (e) {
            assert.notStrictEqual((e.message|| e).toLowerCase().indexOf("transferfrom_failed"), -1);
        }
    });
    it("should allow alice to withdraw without unwrapping the pair", async () => {
        return await withdrawStakingPosition(actors.Alice);
    });
    it("donald should set a new staking position", async () => {
        await createNewStakingPosition(actors.Donald);
    });
    it("should not allow charlie to withdraw bob position", async () => {
        try {
            await liquidityMiningContract.methods.withdraw(actors.Bob.positionKey, actors.Bob.setupIndex, true).send(actors.Charlie.from);
            assert(false);
        } catch (e) {
            assert.notStrictEqual((e.message || e).toLowerCase().indexOf("invalid"), -1);
        }
    });
    /*
    it("should allow bob to unlock unwrapping the pair", async () => {
        return await unlockStakingPosition(actors.Bob);
    });
    */
    it("should rebalance the free position token", async () => {
        await blockchainConnection.jumpToBlock(actors.Bob.exitBlock, true);
        await liquidityMiningContract.methods.rebalancePinnedSetup([2]).send(actors.Bob.from);
        await logData(actors.Bob.exitBlock);
        await logSetups();
    });
    it("should allow bob to withdraw unwrapping the pair", async () => {
        return await withdrawStakingPosition(actors.Bob);
    });
    it("should allow charlie to withdraw its position without unwrapping the pair", async () => {
        return await withdrawStakingPosition(actors.Charlie);
    });
    it("should allow donald to withdraw its position unwrapping the pair", async () => {
        return await withdrawStakingPosition(actors.Donald);
    });
    it("orbulo should set a new staking position with a position token", async () => {
        await createNewStakingPosition(actors.Orbulo);
    });
    it("should allow orbulo to withdraw its position unwrapping the pair", async () => {
        return await withdrawStakingPosition(actors.Orbulo);
    });
    it("should set a new locked farming setup", async() => {
        zeroBlock = (await web3.eth.getBlockNumber()) + 4;
        
        var longTerm3SetupStartBlock = zeroBlock + 5;
        var longTerm3SetupDuration = 45;
        longTerm3SetupEndBlock = longTerm3SetupStartBlock + longTerm3SetupDuration;
        var longTerm3SetupRewardPerBlockPlain = 0.07;
        var longTerm3SetupRewardPerBlock = utilities.toDecimals(longTerm3SetupRewardPerBlockPlain, await rewardToken.methods.decimals().call());
        var longTerm3Setup = {
            ammPlugin: uniswapAMM.options.address,
            liquidityPoolTokenAddress: liquidityPool.options.address,
            startBlock: longTerm3SetupStartBlock,
            endBlock: longTerm3SetupEndBlock,
            rewardPerBlock: longTerm3SetupRewardPerBlock,
            currentRewardPerBlock: 0,
            maximumLiquidity: utilities.toDecimals(longTerm3SetupRewardPerBlockPlain * longTerm3SetupDuration, await rewardToken.methods.decimals().call()),
            totalSupply: 0,
            lastBlockUpdate: 0,
            mainTokenAddress: mainToken.options.address,
            secondaryTokenAddresses: [secondaryToken.options.address],
            free: false,
            renewable: false,
            penaltyFee: 1,
        };

        var farmingSetups = [longTerm3Setup];
        var farmingSetupsCode = farmingSetups.map((it, i) => `farmingSetups[${i}] = FarmingSetup(${it.ammPlugin}, ${it.liquidityPoolTokenAddress}, ${it.startBlock}, ${it.endBlock}, ${it.rewardPerBlock}, ${it.currentRewardPerBlock}, ${it.maximumLiquidity}, ${it.totalSupply}, ${it.lastBlockUpdate}, ${it.mainTokenAddress}, secondaryTokenAddresses, ${it.free}, ${it.renewable}, ${it.penaltyFee});`).join('\n        ');
        var code = fs.readFileSync(path.resolve(__dirname, '..', 'resources/LiquidityMiningSetFarmingSetupsProposal.sol'), 'UTF-8').format(secondaryToken.options.address, farmingSetups.length, farmingSetupsCode, liquidityMiningExtension.options.address, liquidityMiningContract.options.address);
        var proposal = await dfoManager.createProposal(dfo, "", true, code, "callOneTime(address)");
        await dfoManager.finalizeProposal(dfo, proposal);
    });
    it("frank should set a new staking position with a position token", async () => {
        await createNewStakingPosition(actors.Frank);
    });
    it("frank should partial reward without unwrapping the pair", async () => {
        var actor = actors.Frank;
        var balanceOf = await rewardToken.methods.balanceOf(actor.address).call();
        var blockNumber = ((await web3.eth.getBlockNumber()) + 1) - actor.enterBlock;
        var expectedReward = utilities.toDecimals(actor.expectedRewardPerBlock, await rewardToken.methods.decimals().call());
        expectedReward = web3.utils.toBN(expectedReward).mul(web3.utils.toBN(blockNumber.toString())).toString();
        var expectedBalanceOf = utilities.fromDecimals(web3.utils.toBN(expectedReward).add(web3.utils.toBN(balanceOf)).toString(), await rewardToken.methods.decimals().call());

        await liquidityMiningContract.methods.partialReward(actor.positionKey, 3).send(actor.from);
        balanceOf = await rewardToken.methods.balanceOf(actor.address).call();
        balanceOf = utilities.fromDecimals(balanceOf, await rewardToken.methods.decimals().call());

        assert.strictEqual(balanceOf, expectedBalanceOf);

        actor.expectedReward -= parseFloat(utilities.fromDecimals(expectedReward, await rewardToken.methods.decimals().call(), true));
        actors.Frank.partialReward = true;
    });
    it("frank should unlock without unwrapping the pair", async () => {
        var balanceOf = await rewardToken.methods.balanceOf(actors.Frank.address).call();
        console.log(`frank balance before transfer: ${balanceOf}`);
        await rewardToken.methods.transfer(actors.Frank.address, 6999999999999999).send(blockchainConnection.getSendingOptions());
        balanceOf = await rewardToken.methods.balanceOf(actors.Frank.address).call();
        balanceOf = utilities.fromDecimals(balanceOf, await rewardToken.methods.decimals().call());
        console.log(`frank balance after transfer: ${balanceOf}`);
        await rewardToken.methods.approve(liquidityMiningContract.options.address, await rewardToken.methods.totalSupply().call()).send(actors.Frank.from);
        return await unlockStakingPosition(actors.Frank);
    });
});
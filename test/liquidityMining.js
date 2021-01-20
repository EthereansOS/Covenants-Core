var assert = require("assert");
var utilities = require("../util/utilities");
var context = require("../util/context.json");
var compile = require("../util/compile");
var blockchainConnection = require("../util/blockchainConnection");
var dfoManager = require('../util/dfo');var ethers = require('ethers');
var abi = new ethers.utils.AbiCoder();
var path = require('path');
var fs = require('fs');

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
        try {
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
            //rewardToken = utilities.voidEthereumAddress;
            mainToken = new web3.eth.Contract(context.IERC20ABI, context.buidlTokenAddress);
            mainToken = utilities.voidEthereumAddress;
            secondaryToken = new web3.eth.Contract(context.IERC20ABI, context.usdtTokenAddress);

            liquidityPool = new web3.eth.Contract(context.uniswapV2PairABI, await uniswapV2Factory.methods.getPair(mainToken != utilities.voidEthereumAddress ? mainToken.options.address : wethToken.options.address, secondaryToken != utilities.voidEthereumAddress ? secondaryToken.options.address : wethToken.options.address).call());

            if (mainToken !== utilities.voidEthereumAddress) await buyForETH(mainToken, ethToSpend);
            if (secondaryToken !== utilities.voidEthereumAddress) await buyForETH(secondaryToken, ethToSpend);
            if (rewardToken !== utilities.voidEthereumAddress) await buyForETH(rewardToken, ethToSpend);

            uniswapAMM = await new web3.eth.Contract(UniswapV2AMMV1.abi).deploy({data : UniswapV2AMMV1.bin, arguments: [uniswapV2Router.options.address]}).send(blockchainConnection.getSendingOptions());

            await initActor("Alice", accounts[1], 0, 30, 1, 0, (mainToken === utilities.voidEthereumAddress || secondaryToken === utilities.voidEthereumAddress), false, 0.09, 0.247, 0.09, 0.003);
            await initActor("Bob", accounts[2], 15, 50, 2, 0, (mainToken === utilities.voidEthereumAddress || secondaryToken === utilities.voidEthereumAddress), true, 3.15, 0.177, 2.45, 0.07, false, true);
            await initActor("Charlie", accounts[3], 20, 200, 0, 0, (mainToken === utilities.voidEthereumAddress || secondaryToken === utilities.voidEthereumAddress), false, 30, 0.177, 12.2699);
            await initActor("Donald", accounts[4], 40, 201, 0, 0, (mainToken === utilities.voidEthereumAddress || secondaryToken === utilities.voidEthereumAddress), true, 50, 0.180, 15.1499);
            await initActor("Orbulo", accounts[5], 210, 250, 0, 0, (mainToken === utilities.voidEthereumAddress || secondaryToken === utilities.voidEthereumAddress), true, 0.0001, 0.150, 6, 0, true);
            await initActor("Frank", accounts[6], 259, 304, 3, 0, (mainToken === utilities.voidEthereumAddress || secondaryToken === utilities.voidEthereumAddress), false, 0.315, 0.243, 0.315, 0.007, true);
            await initActor("Vasapower", accounts[7], 259, 304, 3, 0, (mainToken === utilities.voidEthereumAddress || secondaryToken === utilities.voidEthereumAddress), false, 0.315, 0.243, 0.315, 0.007, true);
            await initActor("Dino", accounts[8], 260, 304, 3, 0, (mainToken === utilities.voidEthereumAddress || secondaryToken === utilities.voidEthereumAddress), false, 0.315, 0.236, 0.308, 0.007, false);
            await initActor("Ale", accounts[9], 260, 304, 3, 0, (mainToken === utilities.voidEthereumAddress || secondaryToken === utilities.voidEthereumAddress), false, 0.315, 0.236, 0.308, 0.007, false, true);
            await initActor("Cavicchioli", accounts[10], 310, 320, 4, 0, (mainToken === utilities.voidEthereumAddress || secondaryToken === utilities.voidEthereumAddress), false, 0.0001, 0.250, 4.5);

        } catch (error) {
            console.error(error);
            throw new Error();
        }

    });

    async function initActor(name, address, enterBlock, exitBlock, setupIndex, liquidityPoolAddressIndex, involvingETH, unwrap, mainTokenAmountPlain, expectedPinnedFreeRewardPerBlock, expectedReward, expectedRewardPerBlock, positionItem, amountIsLiquidityPool) {
        actors[name] = {
            name,
            address,
            from : blockchainConnection.getSendingOptions({from : address}),
            enterBlock,
            exitBlock,
            setupIndex : setupIndex + 1,
            liquidityPoolAddressIndex,
            unwrap,
            mainTokenAmountPlain,
            expectedPinnedFreeRewardPerBlock,
            expectedRewardPerBlock,
            expectedReward,
            originalReward : expectedReward,
            positionItem,
            involvingETH,
            amountIsLiquidityPool
        };

        if (mainToken !== utilities.voidEthereumAddress) await buyForETH(mainToken, ethToSpend, address);
        if (secondaryToken !== utilities.voidEthereumAddress) await buyForETH(secondaryToken, ethToSpend, address);
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
        for (let i = 0; i < setupUpdateBlocks.length; i++) {
            setupUpdateBlocks[i] = { rewardPerToken: await liquidityMiningContract.methods._rewardPerTokenPerSetupPerBlock(0, setupUpdateBlocks[i]).call(), block: setupUpdateBlocks[i] };
        }
        console.log(`exit block: ${blockNumber} - setup update blocks: `, setupUpdateBlocks);
    }

    async function logSetups() {
        console.log('setups:', await liquidityMiningContract.methods.setups().call());
    }

    it("New LiquidityMining Contract by Factory by extension", async () => {

        dfo = await dfoManager.createDFO("MyName", "MySymbol", 1000, 100, 10);

        if (rewardToken != utilities.voidEthereumAddress) {
            await rewardToken.methods.transfer(dfo.mvdWalletAddress, await rewardToken.methods.balanceOf(accounts[0]).call()).send(blockchainConnection.getSendingOptions());
        } else {
            await web3.eth.sendTransaction(blockchainConnection.getSendingOptions({
                to: dfo.mvdWalletAddress,
                value : utilities.toDecimals(1000, 18)
            }));
        }

        var liquidityMiningModel = await new web3.eth.Contract(LiquidityMining.abi).deploy({data : LiquidityMining.bin}).send(blockchainConnection.getSendingOptions());
        liquidityMiningFactory = await new web3.eth.Contract(LiquidityMiningFactory.abi).deploy({data : LiquidityMiningFactory.bin, arguments : [dfo.doubleProxyAddress, liquidityMiningModel.options.address, 0]}).send(blockchainConnection.getSendingOptions());

        liquidityMiningExtension = await new web3.eth.Contract(LiquidityMiningExtension.abi).deploy({data : LiquidityMiningExtension.bin}).send(blockchainConnection.getSendingOptions());

        var code = fs.readFileSync(path.resolve(__dirname, '..', 'contracts/liquidity-mining/dfo/ManageLiquidityMiningFunctionality.sol'), 'UTF-8').format(liquidityMiningExtension.options.address);
        var proposal = await dfoManager.createProposal(dfo, "manageLiquidityMining", true, code, "manageLiquidityMining(address,uint256,bool,address,address,uint256,bool)", false, true);
        await dfoManager.finalizeProposal(dfo, proposal);

        var setups = [[
            uniswapAMM.options.address,
            [liquidityPool.options.address],
            mainToken != utilities.voidEthereumAddress ? mainToken.options.address : wethToken.options.address,
            0,
            1,
            5,
            0,
            0,
            0,
            true,
            0,
            0
        ]];

        var types = [
            "address",
            "bytes",
            "address",
            "string",
            "string",
            "string",
            "address",
            "bytes",
            "bool",
            "uint256"
        ];
        var params = [
            liquidityMiningExtension.options.address,
            liquidityMiningExtension.methods.init(dfo.doubleProxyAddress, false).encodeABI(),
            ethItemOrchestrator.options.address,
            "LiquidityMiningToken",
            "LMT",
            "google.com",
            rewardToken != utilities.voidEthereumAddress ? rewardToken.options.address : utilities.voidEthereumAddress,
            abi.encode(["tuple(address,address[],address,uint256,uint256,uint256,uint256,uint256,uint256,bool,uint256,uint256)[]"], [setups]),
            false,
            0
        ];
        var payload = web3.utils.sha3(`init(${types.join(',')})`).substring(0, 10) + (web3.eth.abi.encodeParameters(types, params).substring(2));

        var deployTransaction = await liquidityMiningFactory.methods.deploy(payload).send(blockchainConnection.getSendingOptions());
        deployTransaction = await web3.eth.getTransactionReceipt(deployTransaction.transactionHash);
        var liquidityMiningContractAddress = web3.eth.abi.decodeParameter("address", deployTransaction.logs.filter(it => it.topics[0] === web3.utils.sha3("LiquidityMiningDeployed(address,address,bytes)"))[0].topics[1]);
        liquidityMiningContract = await new web3.eth.Contract(LiquidityMining.abi, liquidityMiningContractAddress);
        assert.notStrictEqual(liquidityMiningContract.options.address, utilities.voidEthereumAddress);

        assert.strictEqual(await liquidityMiningContract.methods._extension().call(), liquidityMiningExtension.options.address);

        for(var actor of Object.values(actors)) {
            if (mainToken != utilities.voidEthereumAddress) await mainToken.methods.approve(liquidityMiningContract.options.address, await mainToken.methods.totalSupply().call()).send(actor.from);
            if (secondaryToken != utilities.voidEthereumAddress) await secondaryToken.methods.approve(liquidityMiningContract.options.address, await secondaryToken.methods.totalSupply().call()).send(actor.from);
        }
    });
    it("Previously created LiquidityMining Contract cannot be initialized more than a time", async() => {
        try {
            var setups = [[
                uniswapAMM.options.address,
                [liquidityPool.options.address],
                mainToken != utilities.voidEthereumAddress ? mainToken.options.address : wethToken.options.address,
                0,
                1,
                5,
                0,
                0,
                0,
                false,
                0,
                1
            ]];
            await liquidityMiningContract.methods.init(accounts[0], "0x", ethItemOrchestrator.options.address, "TestCollection1", "TSTC", "test", ethItemOrchestrator.options.address,
            abi.encode(["tuple(address,address[],address,uint256,uint256,uint256,uint256,uint256,uint256,bool,uint256,uint256)[]"], [setups]),
            false,
            0).send(blockchainConnection.getSendingOptions());
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
        var exitFee = (await liquidityMiningFactory.methods.feePercentageInfo().call())[0];
        assert.strictEqual(parseInt(exitFee), 0);
    });
    it("DFO can update the exit fee to 1", async() => {
        var exitFeeExpected = 1;
        var code = fs.readFileSync(path.resolve(__dirname, '..', 'resources/LiquidityMiningSetFeeProposal.sol'), 'UTF-8').format(liquidityMiningFactory.options.address, exitFeeExpected);
        var proposal = await dfoManager.createProposal(dfo, "", true, code, "callOneTime(address)");
        await dfoManager.finalizeProposal(dfo, proposal);
        var exitFee = (await liquidityMiningFactory.methods.feePercentageInfo().call())[0];
        assert.strictEqual(parseInt(exitFee), exitFeeExpected);
    });
    it("Another account cannot update the exit fee", async() => {
        try {
            await liquidityMiningFactory.methods.updateFeePercentage(0).send(blockchainConnection.getSendingOptions({from: accounts[1]}));
        } catch (e) {
            assert.notStrictEqual((e.message|| e).toLowerCase().indexOf("unauthorized"), -1);
        }
    });
    it("should not set the liquidity mining setups", async() => {
        try {
            var setups = [{
                ammPlugin: utilities.voidEthereumAddress,
                liquidityPoolTokenAddress: utilities.voidEthereumAddress,
                startBlock: 0,
                endBlock: 1,
                rewardPerBlock: 0,
                currentRewardPerBlock: 0,
                totalSupply: 0,
                lastBlockUpdate: 0,
                mainTokenAddress: utilities.voidEthereumAddress,
                liquidityPoolTokenAddresses: [utilities.voidEthereumAddress],
                free: false,
                renewTimes: 1,
            }];
            await liquidityMiningContract.methods.setLiquidityMiningSetups(setups, [0], false, 0).send(blockchainConnection.getSendingOptions({from: accounts[1]}));
            throw "LiquidityMining Setup done";
        } catch (error) {
            assert(error, "Only the owner can set the liquidity mining setups.");
        }
    });
    it("should set the liquidity mining setups", async() => {

        zeroBlock = (await web3.eth.getBlockNumber()) + 5;

        Object.values(actors).forEach(it => {
            it.enterBlock += zeroBlock;
            it.exitBlock += zeroBlock;
        });

        var longTerm1SetupStartBlock = zeroBlock;
        var longTerm1SetupDuration = 30;
        longTerm1SetupEndBlock = longTerm1SetupStartBlock + longTerm1SetupDuration;
        var longTerm1SetupRewardPerBlockPlain = 0.03;
        var longTerm1SetupRewardPerBlock = utilities.toDecimals(longTerm1SetupRewardPerBlockPlain, rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.decimals().call() : 18);
        var longTerm1Setup = {
            add : true,
            ammPlugin: uniswapAMM.options.address,
            liquidityPoolTokenAddress: liquidityPool.options.address,
            startBlock: longTerm1SetupStartBlock,
            endBlock: longTerm1SetupEndBlock,
            rewardPerBlock: longTerm1SetupRewardPerBlock,
            currentRewardPerBlock: 0,
            totalSupply: 0,
            lastBlockUpdate: 0,
            mainTokenAddress: mainToken != utilities.voidEthereumAddress ? mainToken.options.address : wethToken.options.address,
            liquidityPoolTokenAddresses: [liquidityPool.options.address],
            free: false,
            renewTimes: 0,
            penaltyFee: 1,
        };

        var longTerm2SetupStartBlock = zeroBlock + 5;
        var longTerm2SetupDuration = 45;
        longTerm2SetupEndBlock = longTerm2SetupStartBlock + longTerm2SetupDuration;
        var longTerm2SetupRewardPerBlockPlain = 0.07;
        var longTerm2SetupRewardPerBlock = utilities.toDecimals(longTerm2SetupRewardPerBlockPlain, rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.decimals().call() : 18);
        var longTerm2Setup = {
            add : true,
            ammPlugin: uniswapAMM.options.address,
            liquidityPoolTokenAddress: liquidityPool.options.address,
            startBlock: longTerm2SetupStartBlock,
            endBlock: longTerm2SetupEndBlock,
            rewardPerBlock: longTerm2SetupRewardPerBlock,
            currentRewardPerBlock: 0,
            totalSupply: 0,
            lastBlockUpdate: 0,
            mainTokenAddress: mainToken != utilities.voidEthereumAddress ? mainToken.options.address : wethToken.options.address,
            liquidityPoolTokenAddresses: [liquidityPool.options.address],
            free: false,
            renewTimes: 0,
            penaltyFee: 1,
        };

        var freeRewardPerBlockPlain = 0.15;
        var freeRewardPerBlock = utilities.toDecimals(freeRewardPerBlockPlain, rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.decimals().call() : 18);
        var pinnedFreeSetup = {
            add : true,
            ammPlugin: uniswapAMM.options.address,
            startBlock: 0,
            endBlock: 0,
            rewardPerBlock: freeRewardPerBlock,
            currentRewardPerBlock: freeRewardPerBlock,
            totalSupply: 0,
            lastBlockUpdate: 0,
            mainTokenAddress: mainToken != utilities.voidEthereumAddress ? mainToken.options.address : wethToken.options.address,
            liquidityPoolTokenAddresses: [liquidityPool.options.address],
            free: true,
            renewTimes: 0,
            penaltyFee: 0,
        };

        var liquidityMiningSetups = [pinnedFreeSetup, longTerm1Setup, longTerm2Setup];

        var expectedLength = (await liquidityMiningContract.methods.setups().call()).length + liquidityMiningSetups.length;

        var currentBlock = await web3.eth.getBlockNumber();
        var expectedPinnedFreeSetupRewardPerBlock = web3.utils.toBN("0");
        liquidityMiningSetups.filter(it => !it.free && it.rewardPerBlock !== '0' && currentBlock >= it.startBlock && currentBlock <= it.endBlock).forEach(it => expectedPinnedFreeSetupRewardPerBlock = expectedPinnedFreeSetupRewardPerBlock.add(web3.utils.toBN(it.rewardPerBlock)));
        expectedPinnedFreeSetupRewardPerBlock = utilities.fromDecimals(expectedPinnedFreeSetupRewardPerBlock.add(web3.utils.toBN(pinnedFreeSetup.rewardPerBlock)).toString(), rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.decimals().call() : 18);

        var liquidityMiningSetupsCode = liquidityMiningSetups.map((it, i) => `liquidityMiningSetups[${i}] = LiquidityMiningSetupConfiguration(${it.add || false}, ${it.setupIndex || 0}, LiquidityMiningSetup(${it.ammPlugin}, liquidityPoolTokenAddresses, ${it.mainTokenAddress}, ${it.startBlock}, ${it.endBlock}, ${it.rewardPerBlock}, ${it.currentRewardPerBlock}, ${it.totalSupply}, ${it.lastBlockUpdate}, ${it.free}, ${it.renewTimes}, ${it.penaltyFee}));`).join('\n        ');
        var code = fs.readFileSync(path.resolve(__dirname, '..', 'resources/LiquidityMiningSetLiquidityMiningSetupsProposal.sol'), 'UTF-8').format(liquidityPool.options.address, liquidityMiningSetups.length, liquidityMiningSetupsCode, liquidityMiningExtension.options.address, liquidityMiningContract.options.address, false, true, 1);
        var proposal = await dfoManager.createProposal(dfo, "", true, code, "callOneTime(address)");
        await dfoManager.finalizeProposal(dfo, proposal);

        assert.strictEqual((await liquidityMiningContract.methods.setups().call()).length, expectedLength);

        assert(await liquidityMiningContract.methods._hasPinned().call());

        var pinnedSetupIndex = await liquidityMiningContract.methods._pinnedSetupIndex().call();
        assert.strictEqual(pinnedSetupIndex, "1");

        var setup = (await liquidityMiningContract.methods.setups().call())[pinnedSetupIndex];
        var currentPinnedFreeSetupRewardPerBlock = utilities.fromDecimals(setup.rewardPerBlock, rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.decimals().call() : 18);

        console.log(currentPinnedFreeSetupRewardPerBlock, expectedPinnedFreeSetupRewardPerBlock);
        assert.strictEqual(currentPinnedFreeSetupRewardPerBlock, expectedPinnedFreeSetupRewardPerBlock);
    });
    it("should rebalance the pinned setup after the setups have been set", async () => {
        await liquidityMiningContract.methods.rebalancePinnedSetup().send(blockchainConnection.getSendingOptions());
    });
    async function createNewStakingPosition(actor) {

        var {address, from, setupIndex, enterBlock, liquidityPoolAddressIndex, mainTokenAmountPlain, expectedRewardPerBlock, positionItem, involvingETH, amountIsLiquidityPool} = actor;

        var mainTokenAmount = utilities.toDecimals(mainTokenAmountPlain, mainToken != utilities.voidEthereumAddress ? await mainToken.methods.decimals().call() : 18);

        var setup = (await liquidityMiningContract.methods.setups().call())[setupIndex];

        var expectedRemainingRewardPerBlock = web3.utils.toBN(setup.rewardPerBlock);
        expectedRemainingRewardPerBlock = expectedRemainingRewardPerBlock.sub(web3.utils.toBN(utilities.toDecimals(expectedRewardPerBlock), rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.decimals().call() : 18)).toString();
        expectedRemainingRewardPerBlock = utilities.fromDecimals(expectedRemainingRewardPerBlock, rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.decimals().call() : 18);

        var expectedReward = expectedRewardPerBlock * (actor.exitBlock - enterBlock);

        expectedRemainingRewardPerBlock = utilities.formatMoney(expectedRemainingRewardPerBlock);

        var pinnedFreeSetupIndex = await liquidityMiningContract.methods._pinnedSetupIndex().call();
        var pinnedFreeSetup = (await liquidityMiningContract.methods.setups().call())[pinnedFreeSetupIndex];
        var expectedPinnedFreeRewardPerBlock = pinnedFreeSetup.rewardPerBlock;

        if(!setup.free) {
            expectedPinnedFreeRewardPerBlock = web3.utils.toBN(expectedPinnedFreeRewardPerBlock).sub(web3.utils.toBN(utilities.toDecimals(expectedRewardPerBlock, rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.decimals().call() : 18))).toString();
        }

        expectedPinnedFreeRewardPerBlock = utilities.fromDecimals(expectedPinnedFreeRewardPerBlock, rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.decimals().call() : 18);

        var ammPlugin = new web3.eth.Contract(UniswapV2AMMV1.abi, setup.ammPlugin);

        var liquidityPoolTokenAddress = setup.liquidityPoolTokenAddresses[liquidityPoolAddressIndex];

        var tokens = (await ammPlugin.methods.byLiquidityPool(liquidityPoolTokenAddress).call())[2];

        var secondaryTokenIndex = tokens[0] === (secondaryToken != utilities.voidEthereumAddress ? secondaryToken.options.address : wethToken.options.address) ? 0 : 1;

        var amounts = await ammPlugin.methods.byTokenAmount(liquidityPoolTokenAddress, mainToken != utilities.voidEthereumAddress ? mainToken.options.address : wethToken.options.address, mainTokenAmount).call();

        var secondaryTokenAmount = amounts[1][secondaryTokenIndex];
        var liquidityPoolTokenAmount = 0;
        if (amountIsLiquidityPool) {
            if (mainToken != utilities.voidEthereumAddress) await mainToken.methods.approve(uniswapV2Router.options.address, await mainToken.methods.totalSupply().call()).send(actor.from);
            if (secondaryToken != utilities.voidEthereumAddress) await secondaryToken.methods.approve(uniswapV2Router.options.address, await secondaryToken.methods.totalSupply().call()).send(actor.from);  
            if(mainToken != utilities.voidEthereumAddress) {
                await uniswapV2Router.methods.addLiquidity(
                    mainToken != utilities.voidEthereumAddress ? mainToken.options.address : wethToken.options.address,
                    secondaryToken != utilities.voidEthereumAddress ? secondaryToken.options.address : wethToken.options.address,
                    mainTokenAmount,
                    secondaryTokenAmount,
                    1,
                    1,
                    address,
                    (await web3.eth.getBlock(await web3.eth.getBlockNumber())).timestamp + 10000
                ).send(from);
            } else {
                await uniswapV2Router.methods.addLiquidityETH(
                    secondaryToken != utilities.voidEthereumAddress ? secondaryToken.options.address : wethToken.options.address,
                    secondaryTokenAmount,
                    1,
                    1,
                    address,
                    (await web3.eth.getBlock(await web3.eth.getBlockNumber())).timestamp + 10000
                ).send({...from, value : mainTokenAmount});
            }
            console.log('add liquidity done.');
            var liquidityPoolTokenContract = new web3.eth.Contract(context.IERC20ABI, liquidityPoolTokenAddress);
            console.log(`lp token balance is ${await liquidityPoolTokenContract.methods.balanceOf(address).call()}`);
            await liquidityPoolTokenContract.methods.approve(liquidityMiningContract.options.address, await liquidityPoolTokenContract.methods.totalSupply().call()).send(from);
            liquidityPoolTokenAmount = await liquidityPoolTokenContract.methods.balanceOf(address).call();
        }

        var stake = {
            setupIndex,
            secondaryTokenAddress: secondaryToken != utilities.voidEthereumAddress ? secondaryToken.options.address : utilities.voidEthereumAddress,
            liquidityPoolTokenAmount,
            liquidityPoolAddressIndex,
            mainTokenAmount,
            amount : amountIsLiquidityPool ? liquidityPoolTokenAmount : mainTokenAmount,
            amountIsLiquidityPool : amountIsLiquidityPool || false,
            secondaryTokenAmount,
            positionOwner: utilities.voidEthereumAddress,
            mintPositionToken: positionItem ? true : false,
            involvingETH
        };

        await blockchainConnection.jumpToBlock(enterBlock, true);
        var result = await liquidityMiningContract.methods.openPosition(stake).send({...from, value: (stake.involvingETH && !stake.amountIsLiquidityPool) ? mainToken === utilities.voidEthereumAddress ? mainTokenAmount : secondaryTokenAmount : 0});
        await logSetups();
        var { positionId } = result.events.Transfer.returnValues;
        var position = await liquidityMiningContract.methods.position(positionId).call();
        console.log(position);
        actor.enterBlock = position.creationBlock;
        actor.positionId = positionId;
        var balance = 0;
        if (stake.mintPositionToken) {
            balance = await positionTokenCollection.methods.balanceOf(actor.address, actor.positionId).call();
            assert.strictEqual(parseInt(balance), 1);
        }

        !position.free && assert.strictEqual(utilities.fromDecimals(position.lockedRewardPerBlock, rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.decimals().call() : 18), utilities.formatMoney(expectedRewardPerBlock));
        !position.free && assert.strictEqual(utilities.fromDecimals(position.reward, rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.decimals().call() : 18), utilities.formatMoney(expectedReward));

        setup = (await liquidityMiningContract.methods.setups().call())[setupIndex];
        var remainingRewardPerBlock = utilities.fromDecimals(setup.rewardPerBlock, rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.decimals().call() : 18);
        assert.strictEqual(remainingRewardPerBlock, expectedRemainingRewardPerBlock);

        pinnedFreeSetup = (await liquidityMiningContract.methods.setups().call())[pinnedFreeSetupIndex];
        var pinnedFreeRewardPerBlock = utilities.fromDecimals(pinnedFreeSetup.rewardPerBlock, rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.decimals().call() : 18);
        assert.strictEqual(pinnedFreeRewardPerBlock, expectedPinnedFreeRewardPerBlock);

        console.log(actor.name, actor.enterBlock - zeroBlock, "stake - ", pinnedFreeRewardPerBlock, "free rpb - ", position.liquidityPoolTokenAmount, " lpt amount - ", balance, " token balance");

        return position;
    }
    it("alice should set a new staking position", () => createNewStakingPosition(actors.Alice));
    it("bob should set a new staking position", () => createNewStakingPosition(actors.Bob));
    it("should rebalance the pinned setup", async () => {
        await liquidityMiningContract.methods.rebalancePinnedSetup().send(blockchainConnection.getSendingOptions());
    });
    it("charlie should set a new staking position", () => createNewStakingPosition(actors.Charlie));
    it("should allow alice to partial reward", async () => {
        var actor = actors.Alice;
        var balanceOf = rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.balanceOf(actor.address).call() : await web3.eth.getBalance(actor.address);
        var blockNumber = ((await web3.eth.getBlockNumber()) + 1) - actor.enterBlock;
        var expectedReward = utilities.toDecimals(actor.expectedRewardPerBlock, rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.decimals().call() : 18);
        expectedReward = web3.utils.toBN(expectedReward).mul(web3.utils.toBN(blockNumber.toString())).toString();

        var transactionResult = await liquidityMiningContract.methods.partialReward(actor.positionId).send(actor.from);

        rewardToken === utilities.voidEthereumAddress && (balanceOf = web3.utils.toBN(balanceOf).sub(web3.utils.toBN(await blockchainConnection.calculateTransactionFee(transactionResult))).toString());

        var expectedBalanceOf = utilities.fromDecimals(web3.utils.toBN(expectedReward).add(web3.utils.toBN(balanceOf)).toString(), rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.decimals().call() : 18);

        balanceOf = rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.balanceOf(actor.address).call() : await web3.eth.getBalance(actor.address);
        balanceOf = utilities.fromDecimals(balanceOf, rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.decimals().call() : 18);

        assert.strictEqual(expectedBalanceOf, balanceOf);

        actor.expectedReward -= parseFloat(utilities.fromDecimals(expectedReward, rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.decimals().call() : 18, true));
    });
    async function unlockStakingPosition(actor) {
        var position = await liquidityMiningContract.methods.position(actor.positionId).call();
        var liquidityPoolTokenAmount = web3.utils.toBN(position.liquidityPoolData.amount);
        var exitFee = (await liquidityMiningFactory.methods.feePercentageInfo().call())[0];
        if(parseInt(exitFee) > 0) {
            exitFee = web3.utils.toBN(exitFee);
            var oneE18 = web3.utils.toBN(1e18);
            var hundred = web3.utils.toBN(10000);
            var diff = liquidityPoolTokenAmount.mul(exitFee.mul(oneE18).div(hundred)).div(oneE18);
            liquidityPoolTokenAmount = liquidityPoolTokenAmount.sub(diff);
        }

        liquidityPoolTokenAmount = liquidityPoolTokenAmount.toString();

        var setup = (await liquidityMiningContract.methods.setups().call())[position.setupIndex];
        var penaltyFee = setup.penaltyFee || '0';
        if(parseInt(penaltyFee) > 0) {
            penaltyFee = web3.utils.toBN(penaltyFee);
            var oneE18 = web3.utils.toBN(1e18);
            var hundred = web3.utils.toBN(10000);
            penaltyFee = web3.utils.toBN(position.reward).mul(penaltyFee.mul(oneE18).div(hundred)).div(oneE18);
        }

        var rewardBalance = rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.balanceOf(actor.address).call() : await web3.eth.getBalance(actor.address);
        var mainBalance = mainToken != utilities.voidEthereumAddress ? await mainToken.methods.balanceOf(actor.address).call() : await web3.eth.getBalance(actor.address);
        var secondaryBalance = secondaryToken != utilities.voidEthereumAddress ? await secondaryToken.methods.balanceOf(actor.address).call() : await web3.eth.getBalance(actor.address);
        var liquidityPoolBalance = await liquidityPool.methods.balanceOf(actor.address).call();

        var tokens = (await uniswapAMM.methods.byLiquidityPool(liquidityPool.options.address).call())[2];
        var mainTokenIndex = tokens[0] === (mainToken != utilities.voidEthereumAddress ? mainToken.options.address : utilities.voidEthereumAddress) ? 0 : 1;
        var secondaryTokenIndex = tokens[0] === (secondaryToken != utilities.voidEthereumAddress ? secondaryToken.options.address : utilities.voidEthereumAddress) ? 0 : 1;
        var amounts = (await uniswapAMM.methods.byLiquidityPoolAmount(liquidityPool.options.address, liquidityPoolTokenAmount).call())[0];

        var expectedRewardBalance = web3.utils.toBN(rewardBalance);
        var expectedMainBalance = web3.utils.toBN(mainBalance).add(web3.utils.toBN(amounts[mainTokenIndex])).toString();
        var expectedSecondaryBalance = utilities.fromDecimals(web3.utils.toBN(secondaryBalance).add(web3.utils.toBN(amounts[secondaryTokenIndex])).toString(), secondaryToken != utilities.voidEthereumAddress ? await secondaryToken.methods.decimals().call() : 18);
        var expectedLiquidityPoolBalance = utilities.fromDecimals(web3.utils.toBN(liquidityPoolBalance).add(web3.utils.toBN(liquidityPoolTokenAmount)).toString(), await liquidityPool.methods.decimals().call());

        var rewardToGiveBack = web3.utils.toBN(utilities.toDecimals(actor.originalReward, 18)).sub(web3.utils.toBN(utilities.toDecimals(actor.expectedReward, 18))).add(penaltyFee).toString();
        expectedRewardBalance = web3.utils.toBN(expectedRewardBalance).sub(web3.utils.toBN(rewardToGiveBack)).toString();

        var transaction = await liquidityMiningContract.methods.unlock(actor.positionId, actor.unwrap).send({value : rewardToGiveBack, ...actor.from });

        rewardToken === utilities.voidEthereumAddress && (expectedRewardBalance = web3.utils.toBN(expectedRewardBalance).sub(web3.utils.toBN(await blockchainConnection.calculateTransactionFee(transaction))).toString());
        expectedRewardBalance = utilities.fromDecimals(expectedRewardBalance, rewardToken != utilities.voidEthereumAddress ? await rewardToken.methods.decimals().call() : 18);

        mainToken === utilities.voidEthereumAddress && (expectedMainBalance = web3.utils.toBN(expectedMainBalance).sub(web3.utils.toBN(await blockchainConnection.calculateTransactionFee(transaction))).toString());
        expectedMainBalance = utilities.fromDecimals(expectedMainBalance, mainToken != utilities.voidEthereumAddress ? await mainToken.methods.decimals().call() : 18);

        var rewardBalance = utilities.fromDecimals(rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.balanceOf(actor.address).call() : await web3.eth.getBalance(actor.address), rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.decimals().call() : 18);
        var mainBalance = utilities.fromDecimals(mainToken != utilities.voidEthereumAddress ? await mainToken.methods.balanceOf(actor.address).call() : await web3.eth.getBalance(actor.address), mainToken != utilities.voidEthereumAddress ? await mainToken.methods.decimals().call() : 18);
        var secondaryBalance = utilities.fromDecimals(secondaryToken != utilities.voidEthereumAddress ? await secondaryToken.methods.balanceOf(actor.address).call() : await web3.eth.getBalance(actor.address), secondaryToken != utilities.voidEthereumAddress ? await secondaryToken.methods.decimals().call() : 18);
        var liquidityPoolBalance = utilities.fromDecimals(await liquidityPool.methods.balanceOf(actor.address).call(), await liquidityPool.methods.decimals().call());

        assert.strictEqual(liquidityPoolBalance, expectedLiquidityPoolBalance);

        assert.strictEqual(rewardBalance, expectedRewardBalance);

        if(actor.unwrap) {
            assert.strictEqual(mainBalance, expectedMainBalance);
            assert.strictEqual(secondaryBalance, expectedSecondaryBalance);
        }
    };
    async function withdrawStakingPosition(actor) {

        if (actor.name !== 'Bob') {
            await blockchainConnection.jumpToBlock(actor.exitBlock, true);
        }

        var position = await liquidityMiningContract.methods.position(actor.positionId).call();

        var liquidityPoolTokenAmount = web3.utils.toBN(position.liquidityPoolData.amount);
        var exitFee = (await liquidityMiningFactory.methods.feePercentageInfo().call())[0];
        if(parseInt(exitFee) > 0) {
            exitFee = web3.utils.toBN(exitFee);
            var oneE18 = web3.utils.toBN(1e18);
            var hundred = web3.utils.toBN(await liquidityMiningContract.methods.ONE_HUNDRED().call());
            var diff = liquidityPoolTokenAmount.mul(exitFee.mul(oneE18).div(hundred)).div(oneE18);
            liquidityPoolTokenAmount = liquidityPoolTokenAmount.sub(diff);
        }

        liquidityPoolTokenAmount = liquidityPoolTokenAmount.toString();

        var rewardBalance = rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.balanceOf(actor.address).call() : await web3.eth.getBalance(actor.address);
        var mainBalance = mainToken != utilities.voidEthereumAddress ? await mainToken.methods.balanceOf(actor.address).call() : await web3.eth.getBalance(actor.address);
        var secondaryBalance = secondaryToken != utilities.voidEthereumAddress ? await secondaryToken.methods.balanceOf(actor.address).call() : await web3.eth.getBalance(actor.address);
        var liquidityPoolBalance = await liquidityPool.methods.balanceOf(actor.address).call();

        var tokens = (await uniswapAMM.methods.byLiquidityPool(liquidityPool.options.address).call())[2];
        var mainTokenIndex = tokens[0] ===(mainToken != utilities.voidEthereumAddress ? mainToken.options.address : utilities.voidEthereumAddress) ? 0 : 1;
        var secondaryTokenIndex = tokens[0] === (secondaryToken != utilities.voidEthereumAddress ? secondaryToken.options.address : utilities.voidEthereumAddress) ? 0 : 1;
        var amounts = (await uniswapAMM.methods.byLiquidityPoolAmount(liquidityPool.options.address, liquidityPoolTokenAmount).call())[0];

        var expectedRewardBalance = web3.utils.toBN(rewardBalance).add(web3.utils.toBN(await utilities.toDecimals(actor.expectedReward, rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.decimals().call() : 18))).toString();
        var expectedMainBalance = web3.utils.toBN(mainBalance).add(web3.utils.toBN(amounts[mainTokenIndex])).toString();
        var expectedSecondaryBalance = utilities.fromDecimals(web3.utils.toBN(secondaryBalance).add(web3.utils.toBN(amounts[secondaryTokenIndex])).toString(), secondaryToken != utilities.voidEthereumAddress ? await secondaryToken.methods.decimals().call() : 18);
        var expectedLiquidityPoolBalance = utilities.fromDecimals(web3.utils.toBN(liquidityPoolBalance).add(web3.utils.toBN(liquidityPoolTokenAmount)).toString(), await liquidityPool.methods.decimals().call());

        var transaction = await liquidityMiningContract.methods.withdraw(actor.positionId, actor.unwrap).send(actor.from);

        rewardToken === utilities.voidEthereumAddress && (expectedRewardBalance = web3.utils.toBN(expectedRewardBalance).sub(web3.utils.toBN(await blockchainConnection.calculateTransactionFee(transaction))).toString());
        expectedRewardBalance = utilities.fromDecimals(expectedRewardBalance, rewardToken != utilities.voidEthereumAddress ? await rewardToken.methods.decimals().call() : 18);

        mainToken === utilities.voidEthereumAddress && (expectedMainBalance = web3.utils.toBN(expectedMainBalance).sub(web3.utils.toBN(await blockchainConnection.calculateTransactionFee(transaction))).toString());
        expectedMainBalance = utilities.fromDecimals(expectedMainBalance, mainToken != utilities.voidEthereumAddress ? await mainToken.methods.decimals().call() : 18);

        var rewardBalance = utilities.fromDecimals(rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.balanceOf(actor.address).call() : await web3.eth.getBalance(actor.address), rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.decimals().call() : 18);
        var mainBalance = utilities.fromDecimals(mainToken != utilities.voidEthereumAddress ? await mainToken.methods.balanceOf(actor.address).call() : await web3.eth.getBalance(actor.address), mainToken != utilities.voidEthereumAddress ? await mainToken.methods.decimals().call() : 18);
        var secondaryBalance = utilities.fromDecimals(secondaryToken != utilities.voidEthereumAddress ? await secondaryToken.methods.balanceOf(actor.address).call() : await web3.eth.getBalance(actor.address), secondaryToken != utilities.voidEthereumAddress ? await secondaryToken.methods.decimals().call() : 18);
        var liquidityPoolBalance = utilities.fromDecimals(await liquidityPool.methods.balanceOf(actor.address).call(), await liquidityPool.methods.decimals().call());
        await logData(actor.exitBlock);
        // await logSetups();
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
            console.log(e);
            assert.notStrictEqual((e.message|| e).toLowerCase().indexOf(rewardToken !== utilities.voidEthereumAddress ? "insufficient-balance" : "invalid sent amount"), -1);
        }
    });
    /*
    it("should update liquidity mining setup at index 1", async () => {
        var setupIndex = 1;

        var setupIndexLengthExpected = (await liquidityMiningContract.methods.setups().call()).length;
        var longTerm1SetupResult = (await liquidityMiningContract.methods.setups().call())[setupIndex];

        var longTerm1Setup = {};

        Object.entries(longTerm1SetupResult).forEach(it => longTerm1Setup[it[0]] = it[1]);

        var zeroBlock = (await web3.eth.getBlockNumber()) + 4;
        var longTerm1SetupStartBlock = zeroBlock;
        var longTerm1SetupDuration = 30;
        var longTerm1SetupEndBlock = longTerm1SetupStartBlock + longTerm1SetupDuration;
        var longTerm1SetupRewardPerBlockPlain = 0.06;
        var longTerm1SetupRewardPerBlock = utilities.toDecimals(longTerm1SetupRewardPerBlockPlain, rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.decimals().call() : 18);

        longTerm1Setup.startBlock = longTerm1SetupStartBlock;
        longTerm1Setup.endBlock = longTerm1SetupEndBlock;
        longTerm1Setup.maximumLiquidity = utilities.toDecimals(longTerm1SetupRewardPerBlockPlain * longTerm1SetupDuration, rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.decimals().call() : 18);
        longTerm1Setup.renewTimes = false;
        longTerm1Setup.penaltyFee = 10;
        longTerm1Setup.rewardPerBlock = longTerm1SetupRewardPerBlock;
        longTerm1Setup.setupIndex = setupIndex;

        var liquidityMiningSetups = [longTerm1Setup];
        var liquidityMiningSetupsCode = liquidityMiningSetups.map((it, i) => `liquidityMiningSetups[${i}] = LiquidityMiningSetupConfiguration(${it.add || false}, ${it.setupIndex || 0}, LiquidityMiningSetup(${it.ammPlugin}, liquidityPoolTokenAddresses, ${mainToken.options.address}, ${it.startBlock}, ${it.endBlock}, ${it.rewardPerBlock}, ${it.currentRewardPerBlock}, ${it.maximumLiquidity}, ${it.totalSupply}, ${it.lastBlockUpdate}, ${it.free}, ${it.renewTimes}, ${it.penaltyFee}));`).join('\n        ');
        var code = fs.readFileSync(path.resolve(__dirname, '..', 'resources/LiquidityMiningSetLiquidityMiningSetupsProposal.sol'), 'UTF-8').format(liquidityPool.options.address, liquidityMiningSetups.length, liquidityMiningSetupsCode, liquidityMiningExtension.options.address, liquidityMiningContract.options.address, false, false, 0);

        var proposal = await dfoManager.createProposal(dfo, "", true, code, "callOneTime(address)");
        await dfoManager.finalizeProposal(dfo, proposal);

        var setupIndexLengthAfter = (await liquidityMiningContract.methods.setups().call()).length;
        assert.strictEqual(setupIndexLengthExpected, setupIndexLengthAfter);

        const setup = (await liquidityMiningContract.methods.setups().call())[setupIndex];
        assert.strictEqual(setup.renewTimes, longTerm1Setup.renewTimes);
        assert.strictEqual(parseInt(setup.penaltyFee), longTerm1Setup.penaltyFee);
        assert.strictEqual(setup.rewardPerBlock, longTerm1Setup.rewardPerBlock);
        assert.notStrictEqual(parseInt(setup.endBlock), longTerm1Setup.endBlock);
        assert.notStrictEqual(parseInt(setup.startBlock), longTerm1Setup.startBlock);
    });
    */
    it("should allow alice to withdraw without unwrapping the pair", () => withdrawStakingPosition(actors.Alice));
    it("donald should set a new staking position", () => createNewStakingPosition(actors.Donald));
    it("should not allow charlie to withdraw bob position", async () => {
        try {
            await liquidityMiningContract.methods.withdraw(actors.Bob.positionId, actors.Bob.setupIndex, true).send(actors.Charlie.from);
            assert(false);
        } catch (e) {
            assert.notStrictEqual((e.message || e).toLowerCase().indexOf("invalid"), -1);
        }
    });

    //it("should allow bob to unlock unwrapping the pair", () => unlockStakingPosition(actors.Bob));
    it("should rebalance the free farming setup", async () => {
        await blockchainConnection.jumpToBlock(actors.Bob.exitBlock, true);
        await liquidityMiningContract.methods.rebalancePinnedSetup().send(actors.Bob.from);
        await logSetups();
    });
    it("should allow bob to withdraw unwrapping the pair", () => withdrawStakingPosition(actors.Bob));
    it("should allow charlie to withdraw its position without unwrapping the pair", () => withdrawStakingPosition(actors.Charlie));
    it("should allow donald to withdraw its position unwrapping the pair", () => withdrawStakingPosition(actors.Donald));
    it("orbulo should set a new staking position with a position token", () => createNewStakingPosition(actors.Orbulo));
    it("should allow orbulo to withdraw its position unwrapping the pair", () => withdrawStakingPosition(actors.Orbulo));
    it("should set a new locked liquidity mining setup", async() => {

        var setupIndexLengthExpected = (await liquidityMiningContract.methods.setups().call()).length + 1;

        zeroBlock = (await web3.eth.getBlockNumber()) + 4;

        var longTerm3SetupStartBlock = zeroBlock + 5;
        var longTerm3SetupDuration = 45;
        longTerm3SetupEndBlock = longTerm3SetupStartBlock + longTerm3SetupDuration;
        var longTerm3SetupRewardPerBlockPlain = 0.07;
        var longTerm3SetupRewardPerBlock = utilities.toDecimals(longTerm3SetupRewardPerBlockPlain, rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.decimals().call() : 18);
        var longTerm3Setup = {
            ammPlugin: uniswapAMM.options.address,
            liquidityPoolTokenAddress: liquidityPool.options.address,
            startBlock: longTerm3SetupStartBlock,
            endBlock: longTerm3SetupEndBlock,
            rewardPerBlock: longTerm3SetupRewardPerBlock,
            currentRewardPerBlock: 0,
            totalSupply: 0,
            lastBlockUpdate: 0,
            mainTokenAddress: mainToken != utilities.voidEthereumAddress ? mainToken.options.address : wethToken.options.address,
            liquidityPoolTokenAddresses: [liquidityPool.options.address],
            free: false,
            renewTimes: 0,
            penaltyFee: 1,
            add : true
        };

        var liquidityMiningSetups = [longTerm3Setup];
        var liquidityMiningSetupsCode = liquidityMiningSetups.map((it, i) => `liquidityMiningSetups[${i}] = LiquidityMiningSetupConfiguration(${it.add || false}, ${it.setupIndex || 0}, LiquidityMiningSetup(${it.ammPlugin}, liquidityPoolTokenAddresses, ${it.mainTokenAddress}, ${it.startBlock}, ${it.endBlock}, ${it.rewardPerBlock}, ${it.currentRewardPerBlock}, ${it.totalSupply}, ${it.lastBlockUpdate}, ${it.free}, ${it.renewTimes}, ${it.penaltyFee}));`).join('\n        ');
        var code = fs.readFileSync(path.resolve(__dirname, '..', 'resources/LiquidityMiningSetLiquidityMiningSetupsProposal.sol'), 'UTF-8').format(liquidityPool.options.address, liquidityMiningSetups.length, liquidityMiningSetupsCode, liquidityMiningExtension.options.address, liquidityMiningContract.options.address, false, false, 0);
        var proposal = await dfoManager.createProposal(dfo, "", true, code, "callOneTime(address)");
        await dfoManager.finalizeProposal(dfo, proposal);

        var setupIndexLengthAfter = (await liquidityMiningContract.methods.setups().call()).length;
        assert.strictEqual(setupIndexLengthExpected, setupIndexLengthAfter);
    });
    it("frank should set a new staking position with a position token", () => createNewStakingPosition(actors.Frank));
    it("dino should set a new staking position without a position token", () => createNewStakingPosition(actors.Dino));
    it("frank should transfer its position token to vasapower", async () => {
        await positionTokenCollection.methods.safeTransferFrom(actors.Frank.address, actors.Vasapower.address, actors.Frank.positionId, 1, 0x0).send(actors.Frank.from);

        actors.Vasapower.positionId = actors.Frank.positionId;
        actors.Vasapower.positionId = actors.Frank.positionId;
        actors.Vasapower.enterBlock = actors.Frank.enterBlock;
        actors.Vasapower.expectedRewardPerBlock = actors.Frank.expectedRewardPerBlock;
        var vasapowerBalance = await positionTokenCollection.methods.balanceOf(actors.Vasapower.address, actors.Vasapower.positionId).call();
        assert.strictEqual(parseInt(vasapowerBalance), 1);
    });
    it("dino should transfer its position ownership to ale", async () => {
        var result = await liquidityMiningContract.methods.transfer(actors.Ale.address, actors.Dino.positionId).send(actors.Dino.from);
        var { positionId } = result.events.Transfer.returnValues;
        console.log("ale position id:", positionId);
        actors.Ale.positionId = positionId;
        actors.Ale.enterBlock = actors.Dino.enterBlock;
        actors.Ale.expectedRewardPerBlock = actors.Dino.expectedRewardPerBlock;
        var position = await liquidityMiningContract.methods._positions(actors.Ale.positionId).call();
        assert.strictEqual(actors.Ale.address, position.uniqueOwner);
    })
    it("vasapower should partial reward without unwrapping the pair", async () => {
        var actor = actors.Vasapower;
        var balanceOf = rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.balanceOf(actor.address).call() : await web3.eth.getBalance(actor.address);
        var blockNumber = ((await web3.eth.getBlockNumber()) + 1) - actor.enterBlock;
        var expectedReward = utilities.toDecimals(actor.expectedRewardPerBlock, rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.decimals().call() : 18);
        expectedReward = web3.utils.toBN(expectedReward).mul(web3.utils.toBN(blockNumber.toString())).toString();
        var expectedBalanceOf = web3.utils.toBN(expectedReward).add(web3.utils.toBN(balanceOf)).toString();

        var transaction = await liquidityMiningContract.methods.partialReward(actor.positionId).send(actor.from);

        rewardToken === utilities.voidEthereumAddress && (expectedBalanceOf = web3.utils.toBN(expectedBalanceOf).sub(web3.utils.toBN(await blockchainConnection.calculateTransactionFee(transaction))).toString());
        expectedBalanceOf = utilities.fromDecimals(expectedBalanceOf, rewardToken != utilities.voidEthereumAddress ? await rewardToken.methods.decimals().call() : 18);

        balanceOf = rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.balanceOf(actor.address).call() : await web3.eth.getBalance(actor.address);
        balanceOf = utilities.fromDecimals(balanceOf, rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.decimals().call() : 18);

        assert.strictEqual(balanceOf, expectedBalanceOf);

        actor.expectedReward -= parseFloat(utilities.fromDecimals(expectedReward, rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.decimals().call() : 18, true));
        actors.Vasapower.partialReward = true;
    });
    it("vasapower should unlock without unwrapping the pair", async () => {
        var balanceOf = rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.balanceOf(actors.Vasapower.address).call() : await web3.eth.getBalance(actors.Vasapower.address);
        if (rewardToken !== utilities.voidEthereumAddress) {
            await rewardToken.methods.transfer(actors.Vasapower.address, 281000000000000).send(actors.Bob.from);
        }
        balanceOf = rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.balanceOf(actors.Vasapower.address).call() : await web3.eth.getBalance(actors.Vasapower.address);
        balanceOf = utilities.fromDecimals(balanceOf, rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.decimals().call() : 18);
        console.log(`vasapower balance: ${balanceOf}`);
        if (rewardToken !== utilities.voidEthereumAddress) {
            await rewardToken.methods.approve(liquidityMiningContract.options.address, await rewardToken.methods.totalSupply().call()).send(actors.Vasapower.from);
        }
        return await unlockStakingPosition(actors.Vasapower);
    });
    it("should allow ale to add liquidity to its position", () => addLiquidity(actors.Ale));
    it("should not allow dino to withdraw unwrapping the pair", async () => {
        try {
            await withdrawStakingPosition(actors.Dino);
            assert(false);
        } catch (e) {
            assert.notStrictEqual((e.message || e).toLowerCase().indexOf("not owned"), -1);
        }
    });
    it("should not allow bob to withdraw again", async () => {
        try {
            await withdrawStakingPosition(actors.Bob);
            assert(false);
        } catch (e) {
            assert.notStrictEqual((e.message || e).toLowerCase().indexOf("not owned"), -1);
        }
    });
    it("should allow ale to withdraw unwrapping the pair", () => withdrawStakingPosition(actors.Ale));
    it("should set a new free liquidity mining setup", async () => {

        var setupIndexLengthExpected = (await liquidityMiningContract.methods.setups().call()).length + 1;

        var newFreeRewardPerBlockPlain = 0.25;
        var newFreeRewardPerBlock = utilities.toDecimals(newFreeRewardPerBlockPlain, rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.decimals().call() : 18);
        var newFreeSetup = {
            ammPlugin: uniswapAMM.options.address,
            startBlock: 0,
            endBlock: 0,
            rewardPerBlock: newFreeRewardPerBlock,
            currentRewardPerBlock: newFreeRewardPerBlock,
            totalSupply: 0,
            lastBlockUpdate: 0,
            mainTokenAddress: mainToken != utilities.voidEthereumAddress ? mainToken.options.address : wethToken.options.address,
            liquidityPoolTokenAddresses: [liquidityPool.options.address],
            free: true,
            renewTimes: 0,
            penaltyFee: 0,
            add : true
        };

        var liquidityMiningSetups = [newFreeSetup];
        var liquidityMiningSetupsCode = liquidityMiningSetups.map((it, i) => `liquidityMiningSetups[${i}] = LiquidityMiningSetupConfiguration(${it.add || false}, ${it.setupIndex || 0}, LiquidityMiningSetup(${it.ammPlugin}, liquidityPoolTokenAddresses, ${it.mainTokenAddress}, ${it.startBlock}, ${it.endBlock}, ${it.rewardPerBlock}, ${it.currentRewardPerBlock}, ${it.totalSupply}, ${it.lastBlockUpdate}, ${it.free}, ${it.renewTimes}, ${it.penaltyFee}));`).join('\n        ');
        var code = fs.readFileSync(path.resolve(__dirname, '..', 'resources/LiquidityMiningSetLiquidityMiningSetupsProposal.sol'), 'UTF-8').format(liquidityPool.options.address, liquidityMiningSetups.length, liquidityMiningSetupsCode, liquidityMiningExtension.options.address, liquidityMiningContract.options.address, false, false, 0);
        var proposal = await dfoManager.createProposal(dfo, "", true, code, "callOneTime(address)");
        await dfoManager.finalizeProposal(dfo, proposal);

        var setupIndexLengthAfter = (await liquidityMiningContract.methods.setups().call()).length;
        assert.strictEqual(setupIndexLengthExpected, setupIndexLengthAfter);
    });
    it("cavicchioli should set a new staking position without a position token", () => createNewStakingPosition(actors.Cavicchioli));
    it("should update liquidity mining setup at index 4", async () => {

        var setupIndexLengthExpected = (await liquidityMiningContract.methods.setups().call()).length;

        var setupIndex = 4;

        var newFreeRewardPerBlockPlain = 0.5;
        var newFreeRewardPerBlock = utilities.toDecimals(newFreeRewardPerBlockPlain, rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.decimals().call() : 18);
        var newFreeSetup = {
            ammPlugin: uniswapAMM.options.address,
            startBlock: 0,
            endBlock: 0,
            rewardPerBlock: newFreeRewardPerBlock,
            currentRewardPerBlock: newFreeRewardPerBlock,
            totalSupply: 0,
            lastBlockUpdate: 0,
            mainTokenAddress: mainToken != utilities.voidEthereumAddress ? mainToken.options.address : utilities.voidEthereumAddress,
            liquidityPoolTokenAddresses: [liquidityPool.options.address],
            free: true,
            renewTimes: 0,
            penaltyFee: 0,
            setupIndex
        };

        var liquidityMiningSetups = [newFreeSetup];
        var liquidityMiningSetupsCode = liquidityMiningSetups.map((it, i) => `liquidityMiningSetups[${i}] = LiquidityMiningSetupConfiguration(${it.add || false}, ${it.setupIndex || 0}, LiquidityMiningSetup(${it.ammPlugin}, liquidityPoolTokenAddresses, ${mainToken != utilities.voidEthereumAddress ? mainToken.options.address : utilities.voidEthereumAddress}, ${it.startBlock}, ${it.endBlock}, ${it.rewardPerBlock}, ${it.currentRewardPerBlock}, ${it.totalSupply}, ${it.lastBlockUpdate}, ${it.free}, ${it.renewTimes}, ${it.penaltyFee}));`).join('\n        ');
        var code = fs.readFileSync(path.resolve(__dirname, '..', 'resources/LiquidityMiningSetLiquidityMiningSetupsProposal.sol'), 'UTF-8').format(liquidityPool.options.address, liquidityMiningSetups.length, liquidityMiningSetupsCode, liquidityMiningExtension.options.address, liquidityMiningContract.options.address, false, false, 0);

        var proposal = await dfoManager.createProposal(dfo, "", true, code, "callOneTime(address)");
        await dfoManager.finalizeProposal(dfo, proposal);
        await logSetups();
        const setup = (await liquidityMiningContract.methods.setups().call())[setupIndex];
        assert.strictEqual(setup.rewardPerBlock, newFreeSetup.rewardPerBlock);

        var setupIndexLengthAfter = (await liquidityMiningContract.methods.setups().call()).length;
        assert.strictEqual(setupIndexLengthExpected, setupIndexLengthAfter);
    });
    async function addLiquidity(actor) {

        var {from, address, setupIndex, enterBlock, liquidityPoolAddressIndex, mainTokenAmountPlain, expectedRewardPerBlock, positionItem, involvingETH, positionId, amountIsLiquidityPool } = actor;

        var mainTokenAmount = utilities.toDecimals(mainTokenAmountPlain, mainToken != utilities.voidEthereumAddress ? await mainToken.methods.decimals().call() : 18);
        var balanceOf = rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.balanceOf(address).call() : await web3.eth.getBalance(address);
        console.log(`starting balance ${balanceOf}`);

        var setup = (await liquidityMiningContract.methods.setups().call())[setupIndex];

        var ammPlugin = new web3.eth.Contract(UniswapV2AMMV1.abi, setup.ammPlugin);

        var liquidityPoolTokenAddress = setup.liquidityPoolTokenAddresses[liquidityPoolAddressIndex];

        var tokens = (await uniswapAMM.methods.byLiquidityPool(liquidityPool.options.address).call())[2];

        var secondaryTokenIndex = tokens[0] === (secondaryToken != utilities.voidEthereumAddress ? secondaryToken.options.address : utilities.voidEthereumAddress) ? 0 : 1;

        var amounts = await ammPlugin.methods.byTokenAmount(liquidityPoolTokenAddress, mainToken != utilities.voidEthereumAddress ? mainToken.options.address : utilities.voidEthereumAddress, mainTokenAmount).call();
        var secondaryTokenAmount = amounts[1][secondaryTokenIndex];
        var liquidityPoolTokenAmount = 0;
        if (amountIsLiquidityPool) {
            if (mainToken != utilities.voidEthereumAddress) await mainToken.methods.approve(uniswapV2Router.options.address, await mainToken.methods.totalSupply().call()).send(actor.from);
            if (secondaryToken != utilities.voidEthereumAddress) await secondaryToken.methods.approve(uniswapV2Router.options.address, await secondaryToken.methods.totalSupply().call()).send(actor.from);
            var liquidityPoolTokenContract = new web3.eth.Contract(context.IERC20ABI, liquidityPoolTokenAddress); 
            const startingBalance = parseInt(await liquidityPoolTokenContract.methods.balanceOf(address).call());
            await uniswapV2Router.methods.addLiquidity(
                mainToken != utilities.voidEthereumAddress ? mainToken.options.address : utilities.voidEthereumAddress,
                secondaryToken != utilities.voidEthereumAddress ? secondaryToken.options.address : utilities.voidEthereumAddress,
                mainTokenAmount,
                secondaryTokenAmount,
                1,
                1,
                address,
                (await web3.eth.getBlock(await web3.eth.getBlockNumber())).timestamp + 10000
            ).send(from);
            console.log('add liquidity done.');
            console.log(`lp token balance is ${await liquidityPoolTokenContract.methods.balanceOf(address).call()}`);
            await liquidityPoolTokenContract.methods.approve(liquidityMiningContract.options.address, await liquidityPoolTokenContract.methods.totalSupply().call()).send(from);
            liquidityPoolTokenAmount = parseInt(await liquidityPoolTokenContract.methods.balanceOf(address).call()) - startingBalance;
        }

        var stake = {
            setupIndex,
            secondaryTokenAddress: secondaryToken != utilities.voidEthereumAddress ? secondaryToken.options.address : utilities.voidEthereumAddress,
            liquidityPoolTokenAmount,
            liquidityPoolAddressIndex,
            mainTokenAmount,
            amount : amountIsLiquidityPool ? liquidityPoolTokenAmount : mainTokenAmount,
            amountIsLiquidityPool : amountIsLiquidityPool || false,
            secondaryTokenAmount,
            positionOwner: utilities.voidEthereumAddress,
            mintPositionToken: positionItem ? true : false,
            involvingETH
        };
        await blockchainConnection.jumpToBlock(enterBlock, true);
        var oldPosition = await liquidityMiningContract.methods.position(positionId).call();
        console.log(oldPosition);
        await liquidityMiningContract.methods.addLiquidity(positionId, stake).send({...from, value: (stake.involvingETH && !stake.amountIsLiquidityPool) ? mainToken === utilities.voidEthereumAddress ? mainTokenAmount : secondaryTokenAmount : 0});
        await logSetups();
        var updateBlock = await web3.eth.getBlockNumber();
        var position = await liquidityMiningContract.methods.position(positionId).call();
        console.log(position);

        if (setup.free) {
            var newBalanceOf = rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.balanceOf(address).call() : await web3.eth.getBalance(address);
            assert.notStrictEqual(balanceOf, newBalanceOf);
            actor.expectedReward -= parseFloat(utilities.fromDecimals(newBalanceOf, rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.decimals().call() : 18, true));
        } else {
            var expectedReward = (parseInt(setup.endBlock) - parseInt(updateBlock)) * (parseFloat(utilities.fromDecimals(position.lockedRewardPerBlock, rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.decimals().call() : 18, true)) - parseFloat(utilities.fromDecimals(oldPosition.lockedRewardPerBlock, rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.decimals().call() : 18, true))) + parseFloat(utilities.fromDecimals(oldPosition.reward, rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.decimals().call() : 18, true));
            assert.strictEqual(expectedReward, parseFloat(utilities.fromDecimals(position.reward, rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.decimals().call() : 18, true)));
            actor.expectedReward = expectedReward;
            console.log(`expected reward is ${actor.expectedReward}`);
        }

        var position = await liquidityMiningContract.methods.position(positionId).call();
        console.log(position);

    };
    it("should allow cavicchioli to add liquidity to its position", () => addLiquidity(actors.Cavicchioli));
    it("should allow cavicchioli to withdraw without unwrapping the pair", () => withdrawStakingPosition(actors.Cavicchioli));
});
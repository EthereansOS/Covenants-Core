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

var byMint;
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
var rewardDestination;
var oneHundred;

var extensionOwner = utilities.voidEthereumAddress;

var actors = {};

var zeroBlock;

describe("LiquidityMining", () => {

    before(async () => {
        try {
            await blockchainConnection.init;
            LiquidityMining = await compile('liquidity-mining/LiquidityMining');
            LiquidityMiningFactory = await compile('liquidity-mining/LiquidityMiningFactory');
            LiquidityMiningExtension = await compile('liquidity-mining/DFOBasedLiquidityMiningExtension');
            LiquidityMiningDefaultExtension = await compile('liquidity-mining/LiquidityMiningExtension');
            UniswapV2AMMV1 = await compile('amm-aggregator/models/UniswapV2/1/UniswapV2AMMV1');

            ethItemOrchestrator = new web3.eth.Contract(context.ethItemOrchestratorABI, context.ethItemOrchestratorAddress);
            uniswapV2Router = new web3.eth.Contract(context.uniswapV2RouterABI, context.uniswapV2RouterAddress);
            uniswapV2Factory = new web3.eth.Contract(context.uniswapV2FactoryABI, context.uniswapV2FactoryAddress);

            wethToken = new web3.eth.Contract(context.IERC20ABI, await uniswapV2Router.methods.WETH().call());

            extensionOwner = accounts[0];

            dfo = await dfoManager.createDFO("MyName", "MySymbol", 10000000, 100, 10);

            var rewardTokenAddress = context.daiTokenAddress;//dfo.votingTokenAddress;

            rewardToken = new web3.eth.Contract(context.IERC20ABI, rewardTokenAddress);
            // rewardToken = utilities.voidEthereumAddress;

            mainToken = new web3.eth.Contract(context.IERC20ABI, context.buidlTokenAddress);
            // mainToken = utilities.voidEthereumAddress;
            // secondaryToken = new web3.eth.Contract(context.IERC20ABI, context.usdtTokenAddress);
            secondaryToken = utilities.voidEthereumAddress;

            liquidityPool = new web3.eth.Contract(context.uniswapV2PairABI, await uniswapV2Factory.methods.getPair(mainToken != utilities.voidEthereumAddress ? mainToken.options.address : wethToken.options.address, secondaryToken != utilities.voidEthereumAddress ? secondaryToken.options.address : wethToken.options.address).call());

            mainToken !== utilities.voidEthereumAddress && await buyForETH(mainToken, ethToSpend);
            secondaryToken !== utilities.voidEthereumAddress && await buyForETH(secondaryToken, ethToSpend);
            rewardToken !== utilities.voidEthereumAddress && rewardToken.options.address !== dfo.votingTokenAddress && await buyForETH(rewardToken, ethToSpend);

            uniswapAMM = await new web3.eth.Contract(UniswapV2AMMV1.abi).deploy({data : UniswapV2AMMV1.bin, arguments: [uniswapV2Router.options.address]}).send(blockchainConnection.getSendingOptions());

            await initActor("Alice", accounts[1], 0, 30, 1, 0, mainToken === utilities.voidEthereumAddress || secondaryToken === utilities.voidEthereumAddress, false, 0.09, 0.247, 0.09, 0.003);
            await initActor("Bob", accounts[2], 15, 50, 2, 0, mainToken === utilities.voidEthereumAddress || secondaryToken === utilities.voidEthereumAddress, true, 3.15, 0.177, 2.45, 0.07, false, true);
            await initActor("Charlie", accounts[3], 19, 200, 0, 0, mainToken === utilities.voidEthereumAddress || secondaryToken === utilities.voidEthereumAddress, false, 30, 0.177, 12.474);
            await initActor("Donald", accounts[4], 40, 201, 0, 0, mainToken === utilities.voidEthereumAddress || secondaryToken === utilities.voidEthereumAddress, true, 50, 0.180, 15.15);
            await initActor("Eve", accounts[5], 210, 250, 0, 0, mainToken === utilities.voidEthereumAddress || secondaryToken === utilities.voidEthereumAddress, true, 0.0001, 0.150, 6, 0, false);
            await initActor("Faith", accounts[6], 259, 304, 3, 0, mainToken === utilities.voidEthereumAddress || secondaryToken === utilities.voidEthereumAddress, false, 0.315, 0.243, 0.315, 0.007, false);
            await initActor("Grace", accounts[7], 259, 304, 3, 0, mainToken === utilities.voidEthereumAddress || secondaryToken === utilities.voidEthereumAddress, true, 0.315, 0.243, 0.315, 0.007, false);
            await initActor("Heidi", accounts[8], 260, 304, 3, 0, mainToken === utilities.voidEthereumAddress || secondaryToken === utilities.voidEthereumAddress, false, 0.315, 0.236, 0.308, 0.006999, false);
            await initActor("Isaac", accounts[9], 260, 304, 3, 0, mainToken === utilities.voidEthereumAddress || secondaryToken === utilities.voidEthereumAddress, false, 0.315, 0.236, 0.308, 0.006999, false, true);
            await initActor("Justin", accounts[10], 315, 325, 4, 0, mainToken === utilities.voidEthereumAddress || secondaryToken === utilities.voidEthereumAddress, false, 0.0001, 0.250, 4.75);
            await initActor("Mallory", accounts[13], 316, 359, 5, 0, mainToken === utilities.voidEthereumAddress || secondaryToken === utilities.voidEthereumAddress, false, 0.1575, 0.250, 0.1505, 0.0035);
            await initActor("Nick", accounts[14], 318, 361, 5, 0, mainToken === utilities.voidEthereumAddress || secondaryToken === utilities.voidEthereumAddress, false, 0.1575, 0.250, 0.07175, 0.00175);
            await initActor("Olivia", accounts[11], 325, 345, 4, 0, mainToken === utilities.voidEthereumAddress || secondaryToken === utilities.voidEthereumAddress, false, 0.0001, 0.5, 5);
            await initActor("Penny", accounts[12], 326, 346, 4, 0, mainToken === utilities.voidEthereumAddress || secondaryToken === utilities.voidEthereumAddress, false, 0.0001, 0.5, 4.8333);
        } catch (error) {
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
            setupIndex : setupIndex + 2,
            liquidityPoolAddressIndex,
            unwrap,
            mainTokenAmountPlain,
            expectedPinnedFreeRewardPerBlock,
            expectedRewardPerBlock,
            expectedReward,
            originalReward : expectedReward,
            positionItem,
            involvingETH,
            amountIsLiquidityPool,
        };

        mainToken !== utilities.voidEthereumAddress && await buyForETH(mainToken, ethToSpend, address);
        secondaryToken !== utilities.voidEthereumAddress && await buyForETH(secondaryToken, ethToSpend, address);
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
    }

    async function logSetups() {
    }

    it("New LiquidityMining Contract by Factory by extension", async () => {

        rewardDestination = dfo.mvdWalletAddress;

        var liquidityMiningModel = await new web3.eth.Contract(LiquidityMining.abi).deploy({data : LiquidityMining.bin}).send(blockchainConnection.getSendingOptions());

        var liquidityMiningDefaultExtensionModel = await new web3.eth.Contract(LiquidityMiningDefaultExtension.abi).deploy({data : LiquidityMiningDefaultExtension.bin}).send(blockchainConnection.getSendingOptions());

        liquidityMiningFactory = await new web3.eth.Contract(LiquidityMiningFactory.abi).deploy({data : LiquidityMiningFactory.bin, arguments : [dfo.doubleProxyAddress, liquidityMiningModel.options.address, liquidityMiningDefaultExtensionModel.options.address, 0, "google.com", "google.com"]}).send(blockchainConnection.getSendingOptions());

        liquidityMiningExtension = await new web3.eth.Contract(LiquidityMiningExtension.abi).deploy({data : LiquidityMiningExtension.bin}).send(blockchainConnection.getSendingOptions());

        var code = fs.readFileSync(path.resolve(__dirname, '..', 'contracts/liquidity-mining/dfo/ManageLiquidityMiningFunctionality.sol'), 'UTF-8').format(liquidityMiningExtension.options.address);
        var proposal = await dfoManager.createProposal(dfo, "manageLiquidityMining", true, code, "manageLiquidityMining(address,uint256,bool,address,address,uint256,bool)", false, true);
        await dfoManager.finalizeProposal(dfo, proposal);

        var transaction = await liquidityMiningFactory.methods.cloneLiquidityMiningDefaultExtension().send(blockchainConnection.getSendingOptions());

        var receipt = await web3.eth.getTransactionReceipt(transaction.transactionHash);
        var clonedDefaultLiquidityMiningAddress = web3.eth.abi.decodeParameter("address", receipt.logs.filter(it => it.topics[0] === web3.utils.sha3('ExtensionCloned(address)'))[0].topics[1])

        var setups = [[
            uniswapAMM.options.address,
            0,
            liquidityPool.options.address,
            mainToken != utilities.voidEthereumAddress ? mainToken.options.address : wethToken.options.address,
            0,
            1,
            5,
            0,
            0,
            0,
            0,
            0,
            true,
            0,
            0,
            mainToken == utilities.voidEthereumAddress || secondaryToken == utilities.voidEthereumAddress
        ],
        [
            uniswapAMM.options.address,
            0,
            liquidityPool.options.address,
            mainToken != utilities.voidEthereumAddress ? mainToken.options.address : wethToken.options.address,
            0,
            (await web3.eth.getBlockNumber()) + 10,
            "500000000000000000",
            0,
            0,
            0,
            "10000000000000000000",
            0,
            false,
            0,
            0,
            mainToken == utilities.voidEthereumAddress || secondaryToken == utilities.voidEthereumAddress
        ]];

        var types = [
            "address",
            "bytes",
            "address",
            "address",
            "bytes",
            "bool",
            "uint256"
        ];
        var params = [
            clonedDefaultLiquidityMiningAddress,//liquidityMiningExtension.options.address,
            "0x",
            ethItemOrchestrator.options.address,
            rewardToken != utilities.voidEthereumAddress ? rewardToken.options.address : utilities.voidEthereumAddress,
            abi.encode(["tuple(address,uint256,address,address,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256,bool,uint256,uint256,bool)[]"], [setups]),
            true,
            0
        ];

        byMint = (params[0] !== clonedDefaultLiquidityMiningAddress && (rewardToken.options && rewardToken.options.address === dfo.votingTokenAddress)) || false;

        params[1] = liquidityMiningExtension.methods.init(byMint, params[0] === clonedDefaultLiquidityMiningAddress ? extensionOwner : dfo.doubleProxyAddress).encodeABI()

        var payload = web3.utils.sha3(`init(${types.join(',')})`).substring(0, 10) + (web3.eth.abi.encodeParameters(types, params).substring(2));

        var deployTransaction = await liquidityMiningFactory.methods.deploy(payload).send(blockchainConnection.getSendingOptions());
        
        deployTransaction = await web3.eth.getTransactionReceipt(deployTransaction.transactionHash);
        var liquidityMiningContractAddress = web3.eth.abi.decodeParameter("address", deployTransaction.logs.filter(it => it.topics[0] === web3.utils.sha3("LiquidityMiningDeployed(address,address,bytes)"))[0].topics[1]);
        liquidityMiningContract = await new web3.eth.Contract(LiquidityMining.abi, liquidityMiningContractAddress);
        
        assert.notStrictEqual(liquidityMiningContract.options.address, utilities.voidEthereumAddress);
        oneHundred = await liquidityMiningContract.methods.ONE_HUNDRED().call();

        params[0] === clonedDefaultLiquidityMiningAddress && (liquidityMiningExtension = new web3.eth.Contract(LiquidityMiningExtension.abi, await liquidityMiningContract.methods._extension().call()));

        rewardDestination = params[0] === clonedDefaultLiquidityMiningAddress ? liquidityMiningExtension.options.address : rewardDestination;

        assert.strictEqual(await liquidityMiningContract.methods._extension().call(), liquidityMiningExtension.options.address);
        assert.notStrictEqual(await liquidityMiningContract.methods._extension().call(), utilities.voidEthereumAddress);

        var setups = await liquidityMiningContract.methods.setups().call();
        assert.strictEqual(setups[0].rewardPerBlock, "500000000000000005");

        for(var actor of Object.values(actors)) {
            if (mainToken != utilities.voidEthereumAddress) await mainToken.methods.approve(liquidityMiningContract.options.address, await mainToken.methods.totalSupply().call()).send(actor.from);
            if (secondaryToken != utilities.voidEthereumAddress) await secondaryToken.methods.approve(liquidityMiningContract.options.address, await secondaryToken.methods.totalSupply().call()).send(actor.from);
        }

        if (rewardToken != utilities.voidEthereumAddress) {
            !byMint && await rewardToken.methods.transfer(rewardDestination, utilities.toDecimals(1000, await rewardToken.methods.decimals().call())).send(blockchainConnection.getSendingOptions());
        } else {
            await web3.eth.sendTransaction(blockchainConnection.getSendingOptions({
                to: rewardDestination,
                value : utilities.toDecimals(1000, 18)
            }));
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
            await liquidityMiningContract.methods.init(accounts[0], "0x", ethItemOrchestrator.options.address, ethItemOrchestrator.options.address,
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
        positionTokenCollection = await liquidityMiningContract.methods._liquidityFarmTokenCollection().call();
        assert.notStrictEqual(positionTokenCollection, utilities.voidEthereumAddress);
        positionTokenCollection = new web3.eth.Contract(context.ethItemNativeABI, positionTokenCollection);
    });
    it("Exit fee is 0", async() => {
        var exitFee = (await liquidityMiningFactory.methods.feePercentageInfo().call())[0];
        assert.strictEqual(parseInt(exitFee), 0);
    });
    it("Change URI", async () => {
        assert.strictEqual(await positionTokenCollection.methods.uri().call(), "google.com");
        assert.strictEqual(await liquidityMiningFactory.methods.liquidityFarmTokenCollectionURI().call(), "google.com");
        assert.strictEqual(await liquidityMiningFactory.methods.liquidityFarmTokenURI().call(), "google.com");
        var newUri = "mino.com";
        var code = fs.readFileSync(path.resolve(__dirname, '..', 'resources/LiquidityMiningSetCollectionAndItemURI.sol'), 'UTF-8').format(liquidityMiningFactory.options.address, newUri, newUri);
        var proposal = await dfoManager.createProposal(dfo, "", true, code, "callOneTime(address)");
        await dfoManager.finalizeProposal(dfo, proposal);
        assert.strictEqual(await positionTokenCollection.methods.uri().call(), "google.com");
        assert.strictEqual(await liquidityMiningFactory.methods.liquidityFarmTokenCollectionURI().call(), newUri);
        assert.strictEqual(await liquidityMiningFactory.methods.liquidityFarmTokenURI().call(), newUri);
        try {
            await liquidityMiningFactory.methods.updateLiquidityFarmTokenCollectionURI("mauro.eth").send(blockchainConnection.getSendingOptions());
            assert(false);
        } catch(e) {
            assert.notStrictEqual(e.message.indexOf("Unauthorized"), -1);
        }
        try {
            await liquidityMiningFactory.methods.updateLiquidityFarmTokenURI("mauro.eth").send(blockchainConnection.getSendingOptions());
            assert(false);
        } catch(e) {
            assert.notStrictEqual(e.message.indexOf("Unauthorized"), -1);
        }
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
            maximumLiquidity: utilities.toDecimals(longTerm1SetupRewardPerBlockPlain * longTerm1SetupDuration, rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.decimals().call() : 18),
            currentStakedLiquidity: 0, 
            mainTokenAddress: mainToken != utilities.voidEthereumAddress ? mainToken.options.address : wethToken.options.address,
            liquidityPoolTokenAddresses: liquidityPool.options.address,
            free: false,
            renewTimes: 0,
            penaltyFee: 1,
            objectId: 0,
            involvingETH: mainToken == utilities.voidEthereumAddress || secondaryToken == utilities.voidEthereumAddress
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
            maximumLiquidity: utilities.toDecimals(longTerm2SetupRewardPerBlockPlain * longTerm2SetupDuration, rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.decimals().call() : 18),
            currentStakedLiquidity: 0, 
            mainTokenAddress: mainToken != utilities.voidEthereumAddress ? mainToken.options.address : wethToken.options.address,
            liquidityPoolTokenAddress: liquidityPool.options.address,
            free: false,
            renewTimes: 0,
            penaltyFee: 1,
            objectId: 0,
            involvingETH: mainToken == utilities.voidEthereumAddress || secondaryToken == utilities.voidEthereumAddress
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
            maximumLiquidity: 0,
            currentStakedLiquidity: 0, 
            mainTokenAddress: mainToken != utilities.voidEthereumAddress ? mainToken.options.address : wethToken.options.address,
            liquidityPoolTokenAddress: liquidityPool.options.address,
            free: true,
            renewTimes: 0,
            penaltyFee: 0,
            objectId: 0,
            involvingETH: mainToken == utilities.voidEthereumAddress || secondaryToken == utilities.voidEthereumAddress
        };

        var liquidityMiningSetups = [pinnedFreeSetup, longTerm1Setup, longTerm2Setup];

        var expectedLength = (await liquidityMiningContract.methods.setups().call()).length + liquidityMiningSetups.length;

        var currentBlock = await web3.eth.getBlockNumber();
        var expectedPinnedFreeSetupRewardPerBlock = web3.utils.toBN("0");
        liquidityMiningSetups.filter(it => !it.free && it.rewardPerBlock !== '0' && currentBlock >= it.startBlock && currentBlock <= it.endBlock).forEach(it => expectedPinnedFreeSetupRewardPerBlock = expectedPinnedFreeSetupRewardPerBlock.add(web3.utils.toBN(it.rewardPerBlock)));
        expectedPinnedFreeSetupRewardPerBlock = utilities.fromDecimals(expectedPinnedFreeSetupRewardPerBlock.add(web3.utils.toBN(pinnedFreeSetup.rewardPerBlock)).toString(), rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.decimals().call() : 18);

        if(rewardDestination === dfo.mvdWalletAddress) {
            var liquidityMiningSetupsCode = liquidityMiningSetups.map((it, i) => `liquidityMiningSetups[${i}] = LiquidityMiningSetupConfiguration(${it.add || false}, ${it.index || it.setupIndex || 0}, LiquidityMiningSetup(${it.ammPlugin}, ${it.objectId}, ${it.liquidityPoolTokenAddress}, ${it.mainTokenAddress}, ${it.startBlock}, ${it.endBlock}, ${it.rewardPerBlock}, ${it.currentRewardPerBlock}, ${it.totalSupply}, ${it.lastBlockUpdate}, ${it.maximumLiquidity}, ${it.currentStakedLiquidity}, ${it.free}, ${it.renewTimes}, ${it.penaltyFee}, ${it.involvingETH}));`).join('\n        ');
            var code = fs.readFileSync(path.resolve(__dirname, '..', 'resources/LiquidityMiningSetLiquidityMiningSetupsProposal.sol'), 'UTF-8').format(liquidityMiningSetups.length, liquidityMiningSetupsCode, liquidityMiningExtension.options.address, false, true, 2);
            var proposal = await dfoManager.createProposal(dfo, "", true, code, "callOneTime(address)");
            await dfoManager.finalizeProposal(dfo, proposal);
        } else {
            await liquidityMiningExtension.methods.setLiquidityMiningSetups(liquidityMiningSetups.map(data => {
                return {
                    add : data.add || false,
                    index : data.index || 0,
                    data
                }
            }), false, true, 2).send(blockchainConnection.getSendingOptions());
        }
        assert.strictEqual((await liquidityMiningContract.methods.setups().call()).length, expectedLength);

        assert(await liquidityMiningContract.methods._hasPinned().call());

        var pinnedSetupIndex = await liquidityMiningContract.methods._pinnedSetupIndex().call();
        assert.strictEqual(pinnedSetupIndex, "2");

        var setup = (await liquidityMiningContract.methods.setups().call())[pinnedSetupIndex];
        var currentPinnedFreeSetupRewardPerBlock = utilities.fromDecimals(setup.rewardPerBlock, rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.decimals().call() : 18);

        
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

        expectedRemainingRewardPerBlock = utilities.formatMoney(expectedRemainingRewardPerBlock);

        var pinnedFreeSetupIndex = await liquidityMiningContract.methods._pinnedSetupIndex().call();
        var pinnedFreeSetup = (await liquidityMiningContract.methods.setups().call())[pinnedFreeSetupIndex];
        var expectedPinnedFreeRewardPerBlock = pinnedFreeSetup.rewardPerBlock;

        if(!setup.free) {
            expectedPinnedFreeRewardPerBlock = web3.utils.toBN(expectedPinnedFreeRewardPerBlock).sub(web3.utils.toBN(utilities.toDecimals(expectedRewardPerBlock, rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.decimals().call() : 18))).toString();
        }

        expectedPinnedFreeRewardPerBlock = utilities.fromDecimals(expectedPinnedFreeRewardPerBlock, rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.decimals().call() : 18);

        var ammPlugin = new web3.eth.Contract(UniswapV2AMMV1.abi, setup.ammPlugin);

        var liquidityPoolTokenAddress = setup.liquidityPoolTokenAddress;

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
            
            var liquidityPoolTokenContract = new web3.eth.Contract(context.IERC20ABI, liquidityPoolTokenAddress);
            
            await liquidityPoolTokenContract.methods.approve(liquidityMiningContract.options.address, await liquidityPoolTokenContract.methods.totalSupply().call()).send(from);
            liquidityPoolTokenAmount = await liquidityPoolTokenContract.methods.balanceOf(address).call();
        }

        var stake = {
            setupIndex,
            secondaryTokenAddress: secondaryToken != utilities.voidEthereumAddress ? secondaryToken.options.address : utilities.voidEthereumAddress,
            liquidityPoolTokenAmount,
            mainTokenAmount,
            amount : amountIsLiquidityPool ? liquidityPoolTokenAmount : mainTokenAmount,
            amountIsLiquidityPool : amountIsLiquidityPool || false,
            secondaryTokenAmount,
            positionOwner: utilities.voidEthereumAddress,
        };

        await blockchainConnection.jumpToBlock(enterBlock, true);
        var result = await liquidityMiningContract.methods.openPosition(stake).send({...from, value: (!stake.amountIsLiquidityPool) ? mainToken === utilities.voidEthereumAddress ? mainTokenAmount : secondaryTokenAmount : 0});
        
        await logSetups();
        var { positionId } = result.events.Transfer.returnValues;
        var position = await liquidityMiningContract.methods.position(positionId).call();
        
        actor.position = position;
        actor.enterBlock = position.creationBlock;
        actor.positionId = positionId;

        
        var expectedReward = setup.free ? 0 : expectedRewardPerBlock * (setup.endBlock - actor.enterBlock);

        var balance = 0;
        if (stake.mintPositionToken) {
            balance = await positionTokenCollection.methods.balanceOf(actor.address, actor.positionId).call();
            assert.strictEqual(parseInt(balance), 1);
        }

        actor.hasLiquidityItems = !setup.free;
        actor.hasPositionOwnership = true;
        
        !position.free && assert.strictEqual(utilities.fromDecimals(position.lockedRewardPerBlock, rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.decimals().call() : 18), utilities.formatMoney(expectedRewardPerBlock));
        !position.free && assert.strictEqual(utilities.fromDecimals(position.reward, rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.decimals().call() : 18), utilities.formatMoney(expectedReward));

        setup = (await liquidityMiningContract.methods.setups().call())[setupIndex];
        actor.objectId = setup.objectId;
        var remainingRewardPerBlock = utilities.fromDecimals(setup.rewardPerBlock, rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.decimals().call() : 18);
        assert.strictEqual(remainingRewardPerBlock, expectedRemainingRewardPerBlock);

        pinnedFreeSetup = (await liquidityMiningContract.methods.setups().call())[pinnedFreeSetupIndex];
        var pinnedFreeRewardPerBlock = utilities.fromDecimals(pinnedFreeSetup.rewardPerBlock, rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.decimals().call() : 18);
        assert.strictEqual(pinnedFreeRewardPerBlock, expectedPinnedFreeRewardPerBlock);

        if(!setup.free) {
            console.log("Name:", await positionTokenCollection.methods.name(setup.objectId).call(), "Symbol:", await positionTokenCollection.methods.symbol(setup.objectId).call(), "Uri:", await positionTokenCollection.methods.uri(setup.objectId).call());
            assert.strictEqual(await positionTokenCollection.methods.uri(setup.objectId).call(), await liquidityMiningFactory.methods.liquidityFarmTokenURI().call());
        }

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
        var position = await liquidityMiningContract.methods.position(actor.positionId).call()
        var transactionResult = await liquidityMiningContract.methods.withdrawReward(actor.positionId).send(actor.from);

        rewardToken === utilities.voidEthereumAddress && (balanceOf = web3.utils.toBN(balanceOf).sub(web3.utils.toBN(await blockchainConnection.calculateTransactionFee(transactionResult))).toString());

        var expectedBalanceOf = utilities.fromDecimals(web3.utils.toBN(expectedReward).add(web3.utils.toBN(balanceOf)).toString(), rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.decimals().call() : 18);

        balanceOf = rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.balanceOf(actor.address).call() : await web3.eth.getBalance(actor.address);
        balanceOf = utilities.fromDecimals(balanceOf, rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.decimals().call() : 18);

        assert.strictEqual(expectedBalanceOf, balanceOf);
        var updatedPosition = await liquidityMiningContract.methods.position(actor.positionId).call();
        actor.position = updatedPosition;
        actor.lastPartialRewardBlock = updatedPosition.creationBlock;
        assert.notStrictEqual(position.creationBlock, actor.lastPartialRewardBlock);
        actor.expectedReward -= parseFloat(utilities.fromDecimals(expectedReward, rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.decimals().call() : 18, true));
    });
    it("should allow alice to partial reward again", async () => {
        var actor = actors.Alice;
        var balanceOf = rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.balanceOf(actor.address).call() : await web3.eth.getBalance(actor.address);
        var blockNumber = ((await web3.eth.getBlockNumber()) + 1) - actor.lastPartialRewardBlock;
        var expectedReward = utilities.toDecimals(actor.expectedRewardPerBlock, rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.decimals().call() : 18);
        expectedReward = web3.utils.toBN(expectedReward).mul(web3.utils.toBN(blockNumber.toString())).toString();
        var position = await liquidityMiningContract.methods.position(actor.positionId).call()
        var transactionResult = await liquidityMiningContract.methods.withdrawReward(actor.positionId).send(actor.from);

        rewardToken === utilities.voidEthereumAddress && (balanceOf = web3.utils.toBN(balanceOf).sub(web3.utils.toBN(await blockchainConnection.calculateTransactionFee(transactionResult))).toString());

        var expectedBalanceOf = utilities.fromDecimals(web3.utils.toBN(expectedReward).add(web3.utils.toBN(balanceOf)).toString(), rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.decimals().call() : 18);

        balanceOf = rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.balanceOf(actor.address).call() : await web3.eth.getBalance(actor.address);
        balanceOf = utilities.fromDecimals(balanceOf, rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.decimals().call() : 18);

        assert.strictEqual(expectedBalanceOf, balanceOf);
        var updatedPosition = await liquidityMiningContract.methods.position(actor.positionId).call();
        actor.position = updatedPosition;
        actor.lastPartialRewardBlock = updatedPosition.creationBlock;
        assert.notStrictEqual(position.creationBlock, actor.lastPartialRewardBlock);
        actor.expectedReward -= parseFloat(utilities.fromDecimals(expectedReward, rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.decimals().call() : 18, true));
    });
    async function unlockStakingPosition(actor, dontPassReward) {
        var position = await liquidityMiningContract.methods.position(actor.positionId).call();
        var liquidityPoolTokenAmount = web3.utils.toBN(position.liquidityPoolTokenAmount);
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

        var rewardToGiveBack = dontPassReward ? "0" : web3.utils.toBN(await liquidityMiningContract.methods._partiallyRedeemed(actor.positionId).call()).add(penaltyFee).toString();

        if (rewardToken !== utilities.voidEthereumAddress) {
            var balance = await rewardToken.methods.balanceOf(actor.address).call();
            
            if(parseInt(balance) < parseInt(rewardToGiveBack)) {
                await buyForETH(rewardToken, 100, actor.address);
            }
            balance = await rewardToken.methods.balanceOf(actor.address).call();
            
            await rewardToken.methods.approve(liquidityMiningContract.options.address, rewardToGiveBack).send(actors.Grace.from);
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
    async function withdrawStakingPosition(actor, removedLiquidity) {
        await blockchainConnection.jumpToBlock(actor.exitBlock, true);
        var position = await liquidityMiningContract.methods.position(actor.positionId).call();
        var removesAllLiquidity = removedLiquidity === undefined;
        if (removesAllLiquidity) { 
            removedLiquidity = position.liquidityPoolTokenAmount;
        }

        var liquidityPoolTokenAmount = web3.utils.toBN(position.liquidityPoolTokenAmount);
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
        var mainTokenIndex = tokens[0] === (mainToken != utilities.voidEthereumAddress ? mainToken.options.address : wethToken.options.address) ? 0 : 1;
        var secondaryTokenIndex = tokens[0] === (secondaryToken != utilities.voidEthereumAddress ? secondaryToken.options.address : wethToken.options.address) ? 0 : 1;
        var amounts = (await uniswapAMM.methods.byLiquidityPoolAmount(liquidityPool.options.address, liquidityPoolTokenAmount).call())[0];

        var expectedRewardBalance = web3.utils.toBN(rewardBalance).add(web3.utils.toBN(await utilities.toDecimals(actor.expectedReward, rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.decimals().call() : 18))).toString();
        var expectedMainBalance = web3.utils.toBN(mainBalance).add(web3.utils.toBN(amounts[mainTokenIndex])).toString();
        var expectedSecondaryBalance = utilities.fromDecimals(web3.utils.toBN(secondaryBalance).add(web3.utils.toBN(amounts[secondaryTokenIndex])).toString(), secondaryToken != utilities.voidEthereumAddress ? await secondaryToken.methods.decimals().call() : 18);
        var expectedLiquidityPoolBalance = utilities.fromDecimals(web3.utils.toBN(liquidityPoolBalance).add(web3.utils.toBN(liquidityPoolTokenAmount)).toString(), await liquidityPool.methods.decimals().call());
        await logSetups();
        var setup = (await liquidityMiningContract.methods.setups().call())[position.setupIndex];
        if (!removesAllLiquidity || actor.hasPartiallyWithdrawn) {
            if (!actor.hasPartiallyWithdrawn) {
                actor.hasPartiallyWithdrawn = true;
            } else {
                var calculatedFreeReward = await liquidityMiningContract.methods.calculateFreeLiquidityMiningSetupReward(actor.positionId, true).call();
                
                
                expectedRewardBalance = web3.utils.toBN(rewardBalance).add(web3.utils.toBN(calculatedFreeReward)).toString();
                
            }
        }
        
        var transaction = null;
        if (removesAllLiquidity) {
            if (!setup.free) {
                transaction = await liquidityMiningContract.methods.withdrawReward(actor.positionId).send(actor.from);
            }
            
        }
        var transaction2 = await liquidityMiningContract.methods.withdrawLiquidity(actor.position.free ? actor.positionId : 0, setup.objectId, actor.unwrap, removedLiquidity).send(actor.from);    
        await logSetups();
        
        
        var updatedPosition = await liquidityMiningContract.methods.position(actor.positionId).call();
        actor.position = updatedPosition;
        rewardToken === utilities.voidEthereumAddress && (expectedRewardBalance = web3.utils.toBN(expectedRewardBalance).sub(web3.utils.toBN(transaction ? await blockchainConnection.calculateTransactionFee(transaction) : '0')).sub(transaction2 ? web3.utils.toBN(await blockchainConnection.calculateTransactionFee(transaction2)) : web3.utils.toBN('0')).toString());
        expectedRewardBalance = utilities.fromDecimals(expectedRewardBalance, rewardToken != utilities.voidEthereumAddress ? await rewardToken.methods.decimals().call() : 18);

        mainToken === utilities.voidEthereumAddress && (expectedMainBalance = web3.utils.toBN(expectedMainBalance).sub(web3.utils.toBN(transaction ? await blockchainConnection.calculateTransactionFee(transaction) : '0')).sub(transaction2 ? web3.utils.toBN(await blockchainConnection.calculateTransactionFee(transaction2)) : web3.utils.toBN('0')).toString());
        expectedMainBalance = utilities.fromDecimals(expectedMainBalance, mainToken != utilities.voidEthereumAddress ? await mainToken.methods.decimals().call() : 18);

        var rewardBalance = utilities.fromDecimals(rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.balanceOf(actor.address).call() : await web3.eth.getBalance(actor.address), rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.decimals().call() : 18);

        var mainBalance = utilities.fromDecimals(mainToken != utilities.voidEthereumAddress ? await mainToken.methods.balanceOf(actor.address).call() : await web3.eth.getBalance(actor.address), mainToken != utilities.voidEthereumAddress ? await mainToken.methods.decimals().call() : 18);
        var secondaryBalance = utilities.fromDecimals(secondaryToken != utilities.voidEthereumAddress ? await secondaryToken.methods.balanceOf(actor.address).call() : await web3.eth.getBalance(actor.address), secondaryToken != utilities.voidEthereumAddress ? await secondaryToken.methods.decimals().call() : 18);
        var liquidityPoolBalance = utilities.fromDecimals(await liquidityPool.methods.balanceOf(actor.address).call(), await liquidityPool.methods.decimals().call());

        if (!removesAllLiquidity) {
            assert.strictEqual(position.liquidityPoolTokenAmount - removedLiquidity, parseInt(updatedPosition.liquidityPoolTokenAmount));
        } else {
            assert.strictEqual(parseInt(updatedPosition.liquidityPoolTokenAmount), 0);
        }
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
            await unlockStakingPosition(actors.Alice, true);
            assert(false);
        } catch (e) {
            
            assert.notStrictEqual((e.message|| e).toLowerCase().indexOf(rewardToken !== utilities.voidEthereumAddress ? rewardToken.options.address === dfo.votingTokenAddress ? "transfer amount exceeds balance" : "insufficient-" : "invalid sent amount"), -1);
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
        var code = fs.readFileSync(path.resolve(__dirname, '..', 'resources/LiquidityMiningSetLiquidityMiningSetupsProposal.sol'), 'UTF-8').format(liquidityPool.options.address, liquidityMiningSetups.length, liquidityMiningSetupsCode, liquidityMiningExtension.options.address, false, false, 0);

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
            await liquidityMiningContract.methods.withdrawReward(actors.Bob.positionId).send(actors.Charlie.from);
            assert(false);
        } catch (e) {
            
            assert.notStrictEqual((e.message || e).toLowerCase().indexOf("not owned"), -1);
        }
    });

    //it("should allow bob to unlock unwrapping the pair", () => unlockStakingPosition(actors.Bob));
   /*
    it("should rebalance the free farming setup", async () => {
        await blockchainConnection.jumpToBlock(actors.Bob.exitBlock - 1, true);
        await liquidityMiningContract.methods.rebalancePinnedSetup().send(blockchainConnection.getSendingOptions());
        await logSetups();
    });
    */
    it("should allow bob to withdraw unwrapping the pair", () => withdrawStakingPosition(actors.Bob));
    it("should allow charlie to withdraw its position without unwrapping the pair", () => withdrawStakingPosition(actors.Charlie));
    it("should allow donald to withdraw its position unwrapping the pair", () => withdrawStakingPosition(actors.Donald));
    it("eve should set a new staking position", () => createNewStakingPosition(actors.Eve));
    it("should allow eve to withdraw its position unwrapping the pair", () => withdrawStakingPosition(actors.Eve));
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
            maximumLiquidity: utilities.toDecimals(longTerm3SetupRewardPerBlockPlain * longTerm3SetupDuration, rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.decimals().call() : 18),
            currentStakedLiquidity: 0, 
            currentRewardPerBlock: 0,
            totalSupply: 0,
            lastBlockUpdate: 0,
            mainTokenAddress: mainToken != utilities.voidEthereumAddress ? mainToken.options.address : wethToken.options.address,
            free: false,
            renewTimes: 0,
            penaltyFee: 1,
            add : true,
            objectId: 0,
            involvingETH: mainToken == utilities.voidEthereumAddress || secondaryToken == utilities.voidEthereumAddress
        };

        var liquidityMiningSetups = [longTerm3Setup];

        if(rewardDestination === dfo.mvdWalletAddress) {
            var liquidityMiningSetupsCode = liquidityMiningSetups.map((it, i) => `liquidityMiningSetups[${i}] = LiquidityMiningSetupConfiguration(${it.add || false}, ${it.index || it.setupIndex || 0}, LiquidityMiningSetup(${it.ammPlugin}, ${it.objectId}, ${it.liquidityPoolTokenAddress}, ${it.mainTokenAddress}, ${it.startBlock}, ${it.endBlock}, ${it.rewardPerBlock}, ${it.currentRewardPerBlock}, ${it.totalSupply}, ${it.lastBlockUpdate}, ${it.maximumLiquidity}, ${it.currentStakedLiquidity}, ${it.free}, ${it.renewTimes}, ${it.penaltyFee}, ${it.involvingETH}));`).join('\n        ');
            var code = fs.readFileSync(path.resolve(__dirname, '..', 'resources/LiquidityMiningSetLiquidityMiningSetupsProposal.sol'), 'UTF-8').format(liquidityMiningSetups.length, liquidityMiningSetupsCode, liquidityMiningExtension.options.address, false, false, 0);
            var proposal = await dfoManager.createProposal(dfo, "", true, code, "callOneTime(address)");
            await dfoManager.finalizeProposal(dfo, proposal);
        } else {
            await liquidityMiningExtension.methods.setLiquidityMiningSetups(liquidityMiningSetups.map(data => {
                return {
                    add : data.add || false,
                    index : data.index || 0,
                    data
                }
            }), false, false, 0).send(blockchainConnection.getSendingOptions());
        }

        var setupIndexLengthAfter = (await liquidityMiningContract.methods.setups().call()).length;
        assert.strictEqual(setupIndexLengthExpected, setupIndexLengthAfter);
    });
    it("faith should set a new staking position", () => createNewStakingPosition(actors.Faith));
    it("heidi should set a new staking position", () => createNewStakingPosition(actors.Heidi));
    it("faith should transfer its item tokens to grace", async () => {
        var setups = await liquidityMiningContract.methods.setups().call()
        var objectId = setups[actors.Faith.setupIndex].objectId;
        var faithBalance = await positionTokenCollection.methods.balanceOf(actors.Faith.address, objectId).call();
        await positionTokenCollection.methods.safeTransferFrom(actors.Faith.address, actors.Grace.address, objectId, faithBalance, 0x0).send(actors.Faith.from);

        var graceBalance = await positionTokenCollection.methods.balanceOf(actors.Grace.address, objectId).call();
        assert.strictEqual(graceBalance, faithBalance);
        actors.Faith.transferedLiquidity = true;
        actors.Grace.objectId = actors.Faith.objectId;
    });
    it("heidi should transfer its position ownership to isaac", async () => {
        var result = await liquidityMiningContract.methods.transfer(actors.Isaac.address, actors.Heidi.positionId).send(actors.Heidi.from);
        var { positionId } = result.events.Transfer.returnValues;
        
        actors.Isaac.positionId = positionId;
        actors.Isaac.enterBlock = actors.Heidi.enterBlock;
        actors.Isaac.expectedRewardPerBlock = actors.Heidi.expectedRewardPerBlock;
        var position = await liquidityMiningContract.methods._positions(actors.Isaac.positionId).call();
        assert.strictEqual(actors.Isaac.address, position.uniqueOwner);
        actors.Isaac = { ...actors.Heidi, address: actors.Isaac.address, name: actors.Isaac.name, from: actors.Isaac.from };

        var setups = await liquidityMiningContract.methods.setups().call()
        var objectId = setups[actors.Heidi.position.setupIndex].objectId;
        var heidiBalance = await positionTokenCollection.methods.balanceOf(actors.Heidi.address, objectId).call();
        await positionTokenCollection.methods.safeTransferFrom(actors.Heidi.address, actors.Isaac.address, objectId, heidiBalance, 0x0).send(actors.Heidi.from);

        /*
        actors.Grace.positionId = actors.Faith.positionId;
        actors.Grace.positionId = actors.Faith.positionId;
        actors.Grace.enterBlock = actors.Faith.enterBlock;
        actors.Grace.expectedRewardPerBlock = actors.Faith.expectedRewardPerBlock;
        */
        var isaacBalance = await positionTokenCollection.methods.balanceOf(actors.Isaac.address, objectId).call();
        assert.strictEqual(isaacBalance, heidiBalance);
        actors.Heidi.transferedLiquidity = true;
    });
    it("faith should partial reward without unwrapping the pair", async () => {
        var actor = actors.Faith;
        var balanceOf = rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.balanceOf(actor.address).call() : await web3.eth.getBalance(actor.address);
        var blockNumber = ((await web3.eth.getBlockNumber()) + 1) - actor.enterBlock;
        var expectedReward = utilities.toDecimals(actor.expectedRewardPerBlock, rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.decimals().call() : 18);
        expectedReward = web3.utils.toBN(expectedReward).mul(web3.utils.toBN(blockNumber.toString())).toString();
        var expectedBalanceOf = web3.utils.toBN(expectedReward).add(web3.utils.toBN(balanceOf)).toString();

        var transaction = await liquidityMiningContract.methods.withdrawReward(actor.positionId).send(actor.from);

        rewardToken === utilities.voidEthereumAddress && (expectedBalanceOf = web3.utils.toBN(expectedBalanceOf).sub(web3.utils.toBN(await blockchainConnection.calculateTransactionFee(transaction))).toString());
        expectedBalanceOf = utilities.fromDecimals(expectedBalanceOf, rewardToken != utilities.voidEthereumAddress ? await rewardToken.methods.decimals().call() : 18);

        balanceOf = rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.balanceOf(actor.address).call() : await web3.eth.getBalance(actor.address);
        balanceOf = utilities.fromDecimals(balanceOf, rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.decimals().call() : 18);

        assert.strictEqual(balanceOf, expectedBalanceOf);

        actor.expectedReward -= parseFloat(utilities.fromDecimals(expectedReward, rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.decimals().call() : 18, true));
        actors.Faith.partialReward = true;
    });
    /*it("should allow faith to add liquidity to its position", () => addLiquidity(actors.Faith));*/
    it("faith should not be able to unlock without unwrapping the pair", async () => {
        try {
            unlockStakingPosition(actors.Faith);
        } catch (error) {
            
        }
    });
    it("grace should not be able to withdraw reward using faith posotion token", async () => {
        try {
            await liquidityMiningContract.methods.withdrawReward(actors.Faith.positionId).send(actors.Grace.from);
        } catch (e) {
            
            assert.notStrictEqual((e.message || e).toLowerCase().indexOf("not owned"), -1);
        }
    });
    it("should not allow heidi to withdraw unwrapping the pair", async () => {
        try {
            await withdrawStakingPosition(actors.Heidi);
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
            
            assert.notStrictEqual((e.message || e).toLowerCase().indexOf("revert"), -1);
        }
    });
    it("should allow isaac to withdraw unwrapping the pair", () => withdrawStakingPosition(actors.Isaac));
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
            maximumLiquidity:  0,
            currentStakedLiquidity: 0, 
            mainTokenAddress: mainToken != utilities.voidEthereumAddress ? mainToken.options.address : wethToken.options.address,
            liquidityPoolTokenAddress: liquidityPool.options.address,
            free: true,
            renewTimes: 0,
            penaltyFee: 0,
            add : true,
            objectId: 0,
            involvingETH: mainToken == utilities.voidEthereumAddress || secondaryToken == utilities.voidEthereumAddress
        };

        var liquidityMiningSetups = [newFreeSetup];

        if(rewardDestination === dfo.mvdWalletAddress) {
            var liquidityMiningSetupsCode = liquidityMiningSetups.map((it, i) => `liquidityMiningSetups[${i}] = LiquidityMiningSetupConfiguration(${it.add || false}, ${it.index || it.setupIndex || 0}, LiquidityMiningSetup(${it.ammPlugin}, ${it.objectId}, ${it.liquidityPoolTokenAddress}, ${it.mainTokenAddress}, ${it.startBlock}, ${it.endBlock}, ${it.rewardPerBlock}, ${it.currentRewardPerBlock}, ${it.totalSupply}, ${it.lastBlockUpdate}, ${it.maximumLiquidity}, ${it.currentStakedLiquidity}, ${it.free}, ${it.renewTimes}, ${it.penaltyFee}, ${it.involvingETH}));`).join('\n        ');
            var code = fs.readFileSync(path.resolve(__dirname, '..', 'resources/LiquidityMiningSetLiquidityMiningSetupsProposal.sol'), 'UTF-8').format(liquidityMiningSetups.length, liquidityMiningSetupsCode, liquidityMiningExtension.options.address, false, false, 0);
            var proposal = await dfoManager.createProposal(dfo, "", true, code, "callOneTime(address)");
            await dfoManager.finalizeProposal(dfo, proposal);
        } else {
            await liquidityMiningExtension.methods.setLiquidityMiningSetups(liquidityMiningSetups.map(data => {
                return {
                    add : data.add || false,
                    index : data.index || 0,
                    data
                }
            }), false, false, 0).send(blockchainConnection.getSendingOptions());
        }
        var setupIndexLengthAfter = (await liquidityMiningContract.methods.setups().call()).length;
        assert.strictEqual(setupIndexLengthExpected, setupIndexLengthAfter);
    });
    it("grace should be able to withdraw liquidity using faith transferred tokens", async () => {
        var setup = (await liquidityMiningContract.methods.setups().call())[actors.Grace.setupIndex];
        var graceBalance = await positionTokenCollection.methods.balanceOf(actors.Grace.address, actors.Grace.objectId).call();
        var graceMainTokenBalance = mainToken !== utilities.voidEthereumAddress ? await mainToken.methods.balanceOf(actors.Grace.address).call() : await web3.eth.getBalance(actors.Grace.address);
        var graceSecondaryTokenBalance = secondaryToken !== utilities.voidEthereumAddress ? await secondaryToken.methods.balanceOf(actors.Grace.address).call() : await web3.eth.getBalance(actors.Grace.address);
        await liquidityMiningContract.methods.withdrawLiquidity(0, actors.Grace.objectId, actors.Grace.unwrap, graceBalance).send(actors.Grace.from);
        var updatedGraceBalance = await positionTokenCollection.methods.balanceOf(actors.Grace.address, actors.Grace.objectId).call();
        var updatedGraceMainTokenBalance = mainToken !== utilities.voidEthereumAddress ? await mainToken.methods.balanceOf(actors.Grace.address).call() : await web3.eth.getBalance(actors.Grace.address);
        var updatedGraceSecondaryTokenBalance = secondaryToken !== utilities.voidEthereumAddress ? await secondaryToken.methods.balanceOf(actors.Grace.address).call() : await web3.eth.getBalance(actors.Grace.address);
            
        assert.notStrictEqual(graceMainTokenBalance, updatedGraceMainTokenBalance);
        assert.notStrictEqual(graceSecondaryTokenBalance, updatedGraceSecondaryTokenBalance);
        assert.notStrictEqual(graceBalance, updatedGraceBalance);
        assert.strictEqual(updatedGraceBalance, '0');

    })
    it("justin should set a new staking position", async() => createNewStakingPosition(actors.Justin));
    it("should update liquidity mining setup at index 6", async () => {

        var setupIndexLengthExpected = (await liquidityMiningContract.methods.setups().call()).length + 1;
        var oldPinnedSetupIndex = await liquidityMiningContract.methods._pinnedSetupIndex().call();
        var oldPinnedSetup = (await liquidityMiningContract.methods.setups().call())[oldPinnedSetupIndex];

        var setupIndex = 6;

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
            maximumLiquidity: 0,
            currentStakedLiquidity: 0, 
            mainTokenAddress: mainToken != utilities.voidEthereumAddress ? mainToken.options.address : utilities.voidEthereumAddress,
            liquidityPoolTokenAddress: liquidityPool.options.address,
            free: true,
            renewTimes: 0,
            penaltyFee: 0,
            setupIndex,
            objectId: 0,
            involvingETH: mainToken == utilities.voidEthereumAddress || secondaryToken == utilities.voidEthereumAddress
        };

        zeroBlock = (await web3.eth.getBlockNumber());

        var longTerm5SetupStartBlock = zeroBlock;
        var longTerm5SetupDuration = 45;
        longTerm5SetupEndBlock = longTerm5SetupStartBlock + longTerm5SetupDuration;
        var longTerm5SetupRewardPerBlockPlain = 0.07;
        var longTerm5SetupRewardPerBlock = utilities.toDecimals(longTerm5SetupRewardPerBlockPlain, rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.decimals().call() : 18);
        var longTerm5Setup = {
            ammPlugin: uniswapAMM.options.address,
            liquidityPoolTokenAddress: liquidityPool.options.address,
            startBlock: longTerm5SetupStartBlock,
            endBlock: longTerm5SetupEndBlock,
            rewardPerBlock: longTerm5SetupRewardPerBlock,
            maximumLiquidity: utilities.toDecimals(longTerm5SetupRewardPerBlockPlain * longTerm5SetupDuration, rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.decimals().call() : 18),
            currentStakedLiquidity: 0, 
            currentRewardPerBlock: 0,
            totalSupply: 0,
            lastBlockUpdate: 0,
            mainTokenAddress: mainToken != utilities.voidEthereumAddress ? mainToken.options.address : wethToken.options.address,
            liquidityPoolTokenAddress: liquidityPool.options.address,
            free: false,
            renewTimes: 0,
            penaltyFee: 1,
            add : true,
            objectId: 0,
            involvingETH: mainToken == utilities.voidEthereumAddress || secondaryToken == utilities.voidEthereumAddress
        };

        var liquidityMiningSetups = [newFreeSetup, longTerm5Setup];

        if(rewardDestination === dfo.mvdWalletAddress) {
            var liquidityMiningSetupsCode = liquidityMiningSetups.map((it, i) => `liquidityMiningSetups[${i}] = LiquidityMiningSetupConfiguration(${it.add || false}, ${it.index || it.setupIndex || 0}, LiquidityMiningSetup(${it.ammPlugin}, ${it.objectId}, ${it.liquidityPoolTokenAddress}, ${it.mainTokenAddress}, ${it.startBlock}, ${it.endBlock}, ${it.rewardPerBlock}, ${it.currentRewardPerBlock}, ${it.totalSupply}, ${it.lastBlockUpdate}, ${it.maximumLiquidity}, ${it.currentStakedLiquidity}, ${it.free}, ${it.renewTimes}, ${it.penaltyFee}, ${it.involvingETH}));`).join('\n        ');
            var code = fs.readFileSync(path.resolve(__dirname, '..', 'resources/LiquidityMiningSetLiquidityMiningSetupsProposal.sol'), 'UTF-8').format(liquidityMiningSetups.length, liquidityMiningSetupsCode, liquidityMiningExtension.options.address, false, true, 2);
            var proposal = await dfoManager.createProposal(dfo, "", true, code, "callOneTime(address)");
            await dfoManager.finalizeProposal(dfo, proposal);
            var elapsedBlocks = (await web3.eth.getBlockNumber()) - zeroBlock - 1;
            
            actors.Justin.expectedReward -= (actors.Justin.expectedPinnedFreeRewardPerBlock * elapsedBlocks);
        } else {
            await liquidityMiningExtension.methods.setLiquidityMiningSetups(liquidityMiningSetups.map(data => {
                return {
                    add : data.add || false,
                    index : data.index || data.setupIndex || 0,
                    data
                }
            }), false, true, 2).send(blockchainConnection.getSendingOptions());
        }
        await logSetups();
        var newPinnedIndex = await liquidityMiningContract.methods._pinnedSetupIndex().call();
        var newPinnedSetup = (await liquidityMiningContract.methods.setups().call())[newPinnedIndex];
        assert.strictEqual(parseInt(newPinnedIndex), 2);

        var setup = (await liquidityMiningContract.methods.setups().call())[setupIndex];
        assert.strictEqual(setup.rewardPerBlock, newFreeSetup.rewardPerBlock);
        assert.strictEqual(parseInt(newPinnedSetup.rewardPerBlock), parseInt(oldPinnedSetup.rewardPerBlock) + parseInt(longTerm5SetupRewardPerBlock));
        var setupIndexLengthAfter = (await liquidityMiningContract.methods.setups().call()).length;
        assert.strictEqual(setupIndexLengthExpected, setupIndexLengthAfter);

    });
    it("mallory should set a new staking position", () => createNewStakingPosition(actors.Mallory));

    it("should update liquidity mining setup at index 7", async () => {

        var setupIndexLengthExpected = (await liquidityMiningContract.methods.setups().call()).length;

        zeroBlock = (await web3.eth.getBlockNumber());

        var longTerm5SetupStartBlock = zeroBlock;
        var longTerm5SetupDuration = 45;
        longTerm5SetupEndBlock = longTerm5SetupStartBlock + longTerm5SetupDuration;
        var longTerm5SetupRewardPerBlockPlain = 0.035;
        var longTerm5SetupRewardPerBlock = utilities.toDecimals(longTerm5SetupRewardPerBlockPlain, rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.decimals().call() : 18);
        var longTerm5Setup = {
            ammPlugin: uniswapAMM.options.address,
            liquidityPoolTokenAddress: liquidityPool.options.address,
            startBlock: longTerm5SetupStartBlock,
            endBlock: longTerm5SetupEndBlock,
            rewardPerBlock: longTerm5SetupRewardPerBlock,
            maximumLiquidity: utilities.toDecimals(longTerm5SetupRewardPerBlockPlain * longTerm5SetupDuration, rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.decimals().call() : 18),
            currentStakedLiquidity: 0, 
            currentRewardPerBlock: 0,
            totalSupply: 0,
            lastBlockUpdate: 0,
            mainTokenAddress: mainToken != utilities.voidEthereumAddress ? mainToken.options.address : wethToken.options.address,
            liquidityPoolTokenAddress: liquidityPool.options.address,
            free: false,
            renewTimes: 0,
            penaltyFee: 1,
            add : false,
            setupIndex: 7,
            objectId: 0,
            involvingETH: mainToken == utilities.voidEthereumAddress || secondaryToken == utilities.voidEthereumAddress
        };

        var liquidityMiningSetups = [longTerm5Setup];

        if(rewardDestination === dfo.mvdWalletAddress) {
            var liquidityMiningSetupsCode = liquidityMiningSetups.map((it, i) => `liquidityMiningSetups[${i}] = LiquidityMiningSetupConfiguration(${it.add || false}, ${it.index || it.setupIndex || 0}, LiquidityMiningSetup(${it.ammPlugin}, ${it.objectId}, ${it.liquidityPoolTokenAddress}, ${it.mainTokenAddress}, ${it.startBlock}, ${it.endBlock}, ${it.rewardPerBlock}, ${it.currentRewardPerBlock}, ${it.totalSupply}, ${it.lastBlockUpdate}, ${it.maximumLiquidity}, ${it.currentStakedLiquidity}, ${it.free}, ${it.renewTimes}, ${it.penaltyFee}, ${it.involvingETH}));`).join('\n        ');
            var code = fs.readFileSync(path.resolve(__dirname, '..', 'resources/LiquidityMiningSetLiquidityMiningSetupsProposal.sol'), 'UTF-8').format(liquidityMiningSetups.length, liquidityMiningSetupsCode, liquidityMiningExtension.options.address, false, false, 0);
            var proposal = await dfoManager.createProposal(dfo, "", true, code, "callOneTime(address)");
            await dfoManager.finalizeProposal(dfo, proposal);
        } else {
            await liquidityMiningExtension.methods.setLiquidityMiningSetups(liquidityMiningSetups.map(data => {
                return {
                    add : data.add || false,
                    index : data.index || data.setupIndex || 0,
                    data
                }
            }), false, false, 0).send(blockchainConnection.getSendingOptions());
        }
        await logSetups();

        var setup = (await liquidityMiningContract.methods.setups().call())[7];
        assert.strictEqual(setup.rewardPerBlock, longTerm5Setup.rewardPerBlock);
        var setupIndexLengthAfter = (await liquidityMiningContract.methods.setups().call()).length;
        assert.strictEqual(setupIndexLengthExpected, setupIndexLengthAfter);

    });
    it("nick should set a new staking position", () => createNewStakingPosition(actors.Nick));
    async function addLiquidity(actor) {

        var {from, address, setupIndex, enterBlock, liquidityPoolAddressIndex, mainTokenAmountPlain, expectedRewardPerBlock, positionItem, involvingETH, positionId, amountIsLiquidityPool } = actor;

        var mainTokenAmount = utilities.toDecimals(mainTokenAmountPlain, mainToken != utilities.voidEthereumAddress ? await mainToken.methods.decimals().call() : 18);
        var balanceOf = rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.balanceOf(address).call() : await web3.eth.getBalance(address);
        
        
        var setup = (await liquidityMiningContract.methods.setups().call())[setupIndex];

        var ammPlugin = new web3.eth.Contract(UniswapV2AMMV1.abi, setup.ammPlugin);

        var liquidityPoolTokenAddress = setup.liquidityPoolTokenAddress;

        var tokens = (await uniswapAMM.methods.byLiquidityPool(liquidityPool.options.address).call())[2];

        var secondaryTokenIndex = tokens[0] === (secondaryToken != utilities.voidEthereumAddress ? secondaryToken.options.address : wethToken.options.address) ? 0 : 1;

        var amounts = await ammPlugin.methods.byTokenAmount(liquidityPoolTokenAddress, mainToken != utilities.voidEthereumAddress ? mainToken.options.address : wethToken.options.address, mainTokenAmount).call();
        var secondaryTokenAmount = amounts[1][secondaryTokenIndex];
        var liquidityPoolTokenAmount = 0;
        if (amountIsLiquidityPool) {
            if (mainToken != utilities.voidEthereumAddress) await mainToken.methods.approve(uniswapV2Router.options.address, await mainToken.methods.totalSupply().call()).send(actor.from);
            if (secondaryToken != utilities.voidEthereumAddress) await secondaryToken.methods.approve(uniswapV2Router.options.address, await secondaryToken.methods.totalSupply().call()).send(actor.from);
            var liquidityPoolTokenContract = new web3.eth.Contract(context.IERC20ABI, liquidityPoolTokenAddress); 
            const startingBalance = parseInt(await liquidityPoolTokenContract.methods.balanceOf(address).call());
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
            
            
            await liquidityPoolTokenContract.methods.approve(liquidityMiningContract.options.address, await liquidityPoolTokenContract.methods.totalSupply().call()).send(from);
            liquidityPoolTokenAmount = parseInt(await liquidityPoolTokenContract.methods.balanceOf(address).call()) - startingBalance;
        }

        var stake = {
            setupIndex,
            secondaryTokenAddress: secondaryToken != utilities.voidEthereumAddress ? secondaryToken.options.address : utilities.voidEthereumAddress,
            liquidityPoolTokenAmount,
            mainTokenAmount,
            amount : amountIsLiquidityPool ? liquidityPoolTokenAmount : mainTokenAmount,
            amountIsLiquidityPool : amountIsLiquidityPool || false,
            secondaryTokenAmount,
            positionOwner: utilities.voidEthereumAddress,
        };
        
        var oldPosition = await liquidityMiningContract.methods.position(positionId).call();
        
        var transaction = await liquidityMiningContract.methods.addLiquidity(positionId, stake).send({...from, value: (!stake.amountIsLiquidityPool) ? mainToken === utilities.voidEthereumAddress ? mainTokenAmount : secondaryTokenAmount : 0});
        await logSetups();
        var updateBlock = await web3.eth.getBlockNumber();
        var position = await liquidityMiningContract.methods.position(positionId).call();
        

        if (setup.free) {
            var newBalanceOf = rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.balanceOf(address).call() : await web3.eth.getBalance(address);
            if (parseInt(position.creationBlock) - parseInt(oldPosition.creationBlock) <= 1) {
                assert.strictEqual(balanceOf, newBalanceOf);
            } else {
                assert.notStrictEqual(balanceOf, newBalanceOf);
            }
            var rewardToDecrease = web3.utils.toBN(newBalanceOf).sub(web3.utils.toBN(balanceOf)).toString();
            rewardToken === utilities.voidEthereumAddress && (rewardToDecrease = web3.utils.toBN(rewardToDecrease).add(web3.utils.toBN(await blockchainConnection.calculateTransactionFee(transaction))).toString());
            rewardToDecrease = utilities.fromDecimals(rewardToDecrease, rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.decimals().call() : 18, true);
            rewardToDecrease = parseFloat(rewardToDecrease);
            actor.expectedReward -= rewardToDecrease;
        } else {
            var expectedReward = (parseInt(setup.endBlock) - parseInt(updateBlock)) * (parseFloat(utilities.fromDecimals(position.lockedRewardPerBlock, rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.decimals().call() : 18, true)) - parseFloat(utilities.fromDecimals(oldPosition.lockedRewardPerBlock, rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.decimals().call() : 18, true))) + parseFloat(utilities.fromDecimals(oldPosition.reward, rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.decimals().call() : 18, true));
            assert.strictEqual(expectedReward, parseFloat(utilities.fromDecimals(position.reward, rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.decimals().call() : 18, true)));
            actor.expectedReward = expectedReward;
            //rewardToken === utilities.voidEthereumAddress && (actor.expectedReward -= parseFloat(utilities.fromDecimals(await blockchainConnection.calculateTransactionFee(transaction), 18, true)));
            
        }

        var position = await liquidityMiningContract.methods.position(positionId).call();
        

    };
    it("should allow justin to add liquidity to its position", () => addLiquidity(actors.Justin));
    it("should allow justin to withdraw without unwrapping the pair", () => withdrawStakingPosition(actors.Justin));
    it("should allow olivia to create a new position", () => createNewStakingPosition(actors.Olivia));
    it("should allow penny to create a new position", () => createNewStakingPosition(actors.Penny));
    it("should allow olivia to withdraw 50% of the liquidity pool token amount", async () => {
        await withdrawStakingPosition(actors.Olivia, parseInt(actors.Olivia.position.liquidityPoolTokenAmount / 2));
        actors.Olivia.exitBlock = actors.Olivia.exitBlock + 20;
    });
    it("should allow penny to withdraw 25% of the liquidity pool token amount", async () => {
        await withdrawStakingPosition(actors.Penny, parseInt(actors.Penny.position.liquidityPoolTokenAmount / 4));
        actors.Penny.exitBlock = actors.Penny.exitBlock + 20;
    });
    it("should allow penny to withdraw the remaining 75% of liquidity pool token amount", () => withdrawStakingPosition(actors.Penny));
    it("should allow olivia to withdraw 33% of the remaining liquidity pool token amount", async () => {
        await withdrawStakingPosition(actors.Olivia, parseInt(actors.Olivia.position.liquidityPoolTokenAmount / 3));
        actors.Olivia.exitBlock = actors.Olivia.exitBlock + 20;
    });
    it("should allow olivia to withdraw the remaining liquidity pool token amount", () => withdrawStakingPosition(actors.Olivia));
    it("should clear the pinned setup", async () => {
        var pinnedIndex = await liquidityMiningContract.methods._pinnedSetupIndex().call();
        var pinnedSetup = (await liquidityMiningContract.methods.setups().call())[pinnedIndex];
        var hasPinned = await liquidityMiningContract.methods._hasPinned().call();
        if(rewardDestination === dfo.mvdWalletAddress) {
            var code = fs.readFileSync(path.resolve(__dirname, '..', 'resources/LiquidityMiningSetLiquidityMiningSetupsProposal.sol'), 'UTF-8').format(0, "", liquidityMiningExtension.options.address, true, false, 0);
            var proposal = await dfoManager.createProposal(dfo, "", true, code, "callOneTime(address)");
            await dfoManager.finalizeProposal(dfo, proposal);
        } else {
            await liquidityMiningExtension.methods.setLiquidityMiningSetups([], true, false, 0).send(blockchainConnection.getSendingOptions());
        }
        var updatedSetup = (await liquidityMiningContract.methods.setups().call())[pinnedIndex];
        var updatedHasPinned = await liquidityMiningContract.methods._hasPinned().call();
        assert.notStrictEqual(hasPinned, updatedHasPinned);
        assert.notStrictEqual(pinnedSetup.rewardPerBlock, updatedSetup.rewardPerBlock);
        assert.strictEqual(updatedSetup.rewardPerBlock, updatedSetup.currentRewardPerBlock);
    })
    it("should allow mallory to withdraw the position", () => withdrawStakingPosition(actors.Mallory));
    it("should allow nick to withdraw the position", () => withdrawStakingPosition(actors.Nick));
});
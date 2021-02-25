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

// Contracts
var SimpleFarmMain;
// var PinnedFarmMain;
var FarmFactory;
var UniswapV2AMMV1;
var FarmExtension;
var DFOBasedFarmExtension;
var DFOBasedFarmExtensionFactory;
// Useful variables
var byMint;
var ethItemOrchestrator;
var uniswapV2Router;
var uniswapV2Factory;
var wethToken;
var rewardToken;
var mainToken;
var secondaryToken;
var farmFactory;
var simpleFarmExtension;
// var pinnedFarmExtension;
var clonedDefaultFarmExtension;
var dfo;
var pinnedDfo;
var simpleFarmContract;
// var pinnedFarmContract;
var liquidityPool;
var uniswapAMM;
var ethToSpend = 600;
var farmTokenCollection;
var rewardDestination;
var oneHundred;
var extensionOwner = utilities.voidEthereumAddress;
var actors = {};
var zeroBlock;
var mainDFO;
var dFOBasedFarmExtensionFactory;

describe("Farming", () => {
    
    async function buyForETH(token, amount, from) {
        var path = [
            wethToken.options.address,
            token.options.address
        ];
        var value = utilities.toDecimals(amount.toString(), '18');
        await uniswapV2Router.methods.swapExactETHForTokens("1", path, (from && (from.from || from)) || accounts[0], parseInt((new Date().getTime() / 1000) + 1000)).send(blockchainConnection.getSendingOptions({from: (from && (from.from || from)) || accounts[0], value}));
    };

    async function initActor(name, address, unwrap, amount, amountIsLiquidityPool) {
        actors[name] = {
            name,
            address,
            from : blockchainConnection.getSendingOptions({from : address}),
            unwrap,
            amount,
            amountIsLiquidityPool
        };

        mainToken !== utilities.voidEthereumAddress && await buyForETH(mainToken, ethToSpend, address);
        secondaryToken !== utilities.voidEthereumAddress && await buyForETH(secondaryToken, ethToSpend, address);

    };

    async function createStakingPosition(actor, setupIndex) {
        (mainToken != utilities.voidEthereumAddress) && await mainToken.methods.approve(simpleFarmContract.options.address, await mainToken.methods.totalSupply().call()).send(actor.from);
        (secondaryToken != utilities.voidEthereumAddress) && await secondaryToken.methods.approve(simpleFarmContract.options.address, await secondaryToken.methods.totalSupply().call()).send(actor.from);

        var mainTokenAmount = utilities.toDecimals(actor.amount, mainToken != utilities.voidEthereumAddress ? await mainToken.methods.decimals().call() : 18);
        var stake = {
            setupIndex,
            amount : mainTokenAmount,
            amountIsLiquidityPool : actor.amountIsLiquidityPool || false,
            positionOwner: utilities.voidEthereumAddress,
        };

        var setup = (await simpleFarmContract.methods.setups().call())[setupIndex];
        var setupInfo = await simpleFarmContract.methods._setupsInfo(setup.infoIndex).call();
        var ammPlugin = new web3.eth.Contract(UniswapV2AMMV1.abi, setupInfo.ammPlugin);
        var liquidityPoolTokenAddress = setupInfo.liquidityPoolTokenAddress;
        var tokens = (await ammPlugin.methods.byLiquidityPool(liquidityPoolTokenAddress).call())[2];
        var secondaryTokenIndex = tokens[0] === (secondaryToken != utilities.voidEthereumAddress ? secondaryToken.options.address : wethToken.options.address) ? 0 : 1;
        var amounts = await ammPlugin.methods.byTokenAmount(liquidityPoolTokenAddress, mainToken != utilities.voidEthereumAddress ? mainToken.options.address : wethToken.options.address, mainTokenAmount).call();
        var secondaryTokenAmount = amounts[1][secondaryTokenIndex];

        var startingBalance = await rewardToken.methods.balanceOf(simpleFarmContract.options.address).call();

        var result = await simpleFarmContract.methods.openPosition(stake).send({...actor.from, value: (!stake.amountIsLiquidityPool) ? mainToken === utilities.voidEthereumAddress ? mainTokenAmount : secondaryTokenAmount : 0});
        var { positionId } = result.events.Transfer.returnValues;
        var position = await simpleFarmContract.methods.position(positionId).call();
        actor.setupIndex = setupIndex;
        actor.position = position;
        actor.positionId = positionId;
        console.log(actor.position.reward);

        var diffBalance = parseInt(startingBalance) - parseInt(await rewardToken.methods.balanceOf(simpleFarmContract.options.address).call());

        if (!setupInfo.free) {
            assert.strictEqual(parseInt(position.reward), parseInt(position.lockedRewardPerBlock) * (parseInt(setup.endBlock) - parseInt(position.creationBlock)));
        }
        var lastBlockUpdate = setup.lastUpdateBlock === 0 ? setup.lastUpdateBlock : setup.startBlock;
        assert.strictEqual(utilities.formatMoney(utilities.fromDecimals(diffBalance, rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.decimals().call() : 18), 4), utilities.formatMoney(utilities.fromDecimals(((parseInt(position.creationBlock) - parseInt(lastBlockUpdate)) * parseInt(setup.rewardPerBlock)).toString(), rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.decimals().call() : 18), 4));
    }

    async function withdrawReward(actor) {
        var setup = (await simpleFarmContract.methods.setups().call())[actor.setupIndex];
        await blockchainConnection.jumpToBlock(parseInt(setup.endBlock));
        var startingBalance = await rewardToken.methods.balanceOf(actor.address).call();
        await simpleFarmContract.methods.withdrawReward(actor.positionId).send(actor.from);
        var resultBalance = await rewardToken.methods.balanceOf(actor.address).call();
        console.log(`started at ${startingBalance} and ended up at ${resultBalance}`);
        var availableSetups = await simpleFarmContract.methods.setups().call();
        await Promise.all(availableSetups.map(async (setup) => {
            console.log(setup);
        }))
    }

    before(async () => {
        try {
            await blockchainConnection.init;
            SimpleFarmMain = await compile('liquidity-mining/SimpleFarmMain');
            // PinnedFarmMain = await compile('liquidity-mining/PinnedFarmMain');
            FarmFactory = await compile('liquidity-mining/FarmFactory');
            
            DFOBasedFarmExtensionFactory = await compile('liquidity-mining/dfo/DFOBasedFarmExtensionFactory');
            DFOBasedFarmExtension = await compile('liquidity-mining/dfo/DFOBasedFarmExtension');
            FarmExtension = await compile('liquidity-mining/FarmExtension');

            UniswapV2AMMV1 = await compile('amm-aggregator/models/UniswapV2/1/UniswapV2AMMV1');

            ethItemOrchestrator = new web3.eth.Contract(context.ethItemOrchestratorABI, context.ethItemOrchestratorAddress);
            uniswapV2Router = new web3.eth.Contract(context.uniswapV2RouterABI, context.uniswapV2RouterAddress);
            uniswapV2Factory = new web3.eth.Contract(context.uniswapV2FactoryABI, context.uniswapV2FactoryAddress);
            wethToken = new web3.eth.Contract(context.IERC20ABI, await uniswapV2Router.methods.WETH().call());

            extensionOwner = accounts[0];

            mainDFO = await dfoManager.createDFO("MyName", "MySymbol", 10000000, 100, 10);
            dfo = await dfoManager.createDFO("MyName", "MySymbol", 10000000, 100, 10);
            // pinnedDfo = await dfoManager.createDFO("MyName", "MySymbol", 10000000, 100, 10);

            var rewardTokenAddress = context.daiTokenAddress;//dfo.votingTokenAddress;
            rewardToken = new web3.eth.Contract(context.IERC20ABI, rewardTokenAddress);
            // rewardToken = utilities.voidEthereumAddress;
            mainToken = new web3.eth.Contract(context.IERC20ABI, context.buidlTokenAddress);
            // mainToken = utilities.voidEthereumAddress;
            secondaryToken = new web3.eth.Contract(context.IERC20ABI, context.usdcTokenAddress);
            // secondaryToken = utilities.voidEthereumAddress;

            liquidityPool = new web3.eth.Contract(context.uniswapV2PairABI, await uniswapV2Factory.methods.getPair(mainToken != utilities.voidEthereumAddress ? mainToken.options.address : wethToken.options.address, secondaryToken != utilities.voidEthereumAddress ? secondaryToken.options.address : wethToken.options.address).call());

            mainToken !== utilities.voidEthereumAddress && await buyForETH(mainToken, ethToSpend);
            secondaryToken !== utilities.voidEthereumAddress && await buyForETH(secondaryToken, ethToSpend);
            rewardToken !== utilities.voidEthereumAddress && rewardToken.options.address !== dfo.votingTokenAddress && await buyForETH(rewardToken, ethToSpend);

            uniswapAMM = await new web3.eth.Contract(UniswapV2AMMV1.abi).deploy({data : UniswapV2AMMV1.bin, arguments: [uniswapV2Router.options.address]}).send(blockchainConnection.getSendingOptions());

            global.tokens = [dfo.votingToken, mainToken, rewardToken, liquidityPool];

            await initActor("Cavicchioli", accounts[1], true, 1250, false);
            await initActor("Cappello", accounts[2], true, 100, false);
        } catch (error) {
            console.error(error);
        }
    });
    it("should deploy farm factory, extensions and finalize proposals", async () => {
        try {
            rewardDestination = dfo.mvdWalletAddress;
            var simpleFarmModel = await new web3.eth.Contract(SimpleFarmMain.abi).deploy({data : SimpleFarmMain.bin}).send(blockchainConnection.getSendingOptions());
            console.log(`simple farm model deployed at ${simpleFarmModel.options.address}`);
            // var pinnedFarmModel = await new web3.eth.Contract(PinnedFarmMain.abi).deploy({data : PinnedFarmMain.bin}).send(blockchainConnection.getSendingOptions());  
            var farmExtensionModel = await new web3.eth.Contract(FarmExtension.abi).deploy({data : FarmExtension.bin}).send(blockchainConnection.getSendingOptions());
            console.log(`farm extension model deployed at ${farmExtensionModel.options.address}`);
    
            farmFactory = await new web3.eth.Contract(FarmFactory.abi).deploy({data : FarmFactory.bin, arguments : [dfo.doubleProxyAddress, simpleFarmModel.options.address, utilities.voidEthereumAddress, farmExtensionModel.options.address, 0, "google.com", "google.com"]}).send(blockchainConnection.getSendingOptions());
            console.log(`farm factory deployed at ${farmFactory.options.address}`);

            var dfoFarmExtensionModel = await new web3.eth.Contract(DFOBasedFarmExtension.abi).deploy({data : DFOBasedFarmExtension.bin}).send(blockchainConnection.getSendingOptions());
            console.log(`dfo farm extension model deployed at ${dfoFarmExtensionModel.options.address}`);
            dFOBasedFarmExtensionFactory = await new web3.eth.Contract(DFOBasedFarmExtensionFactory.abi).deploy({data : DFOBasedFarmExtensionFactory.bin, arguments : [mainDFO.doubleProxyAddress, dfoFarmExtensionModel.options.address]}).send(blockchainConnection.getSendingOptions());
            console.log(`dfo based farm extension factory deployed at ${dFOBasedFarmExtensionFactory.options.address}`);

            var transaction = await dFOBasedFarmExtensionFactory.methods.cloneModel().send(blockchainConnection.getSendingOptions());
            var receipt = await web3.eth.getTransactionReceipt(transaction.transactionHash);
            var simpleFarmExtensionAddress = web3.eth.abi.decodeParameter("address", receipt.logs.filter(it => it.topics[0] === web3.utils.sha3('ExtensionCloned(address,address)'))[0].topics[1])
            simpleFarmExtension = new web3.eth.Contract(FarmExtension.abi, simpleFarmExtensionAddress);
            console.log(`simple farm extension deployed at ${simpleFarmExtension.options.address}`);
            /*
            transaction = await dFOBasedFarmExtensionFactory.methods.cloneModel().send(blockchainConnection.getSendingOptions());
            receipt = await web3.eth.getTransactionReceipt(transaction.transactionHash);
            var pinnedFarmExtensionAddress = web3.eth.abi.decodeParameter("address", receipt.logs.filter(it => it.topics[0] === web3.utils.sha3('ExtensionCloned(address,address)'))[0].topics[1])
            pinnedFarmExtension = new web3.eth.Contract(FarmExtension.abi, pinnedFarmExtensionAddress);
    */
            var code = fs.readFileSync(path.resolve(__dirname, '..', 'contracts/liquidity-mining/dfo/ManageLiquidityMiningFunctionality.sol'), 'UTF-8').format(simpleFarmExtension.options.address);
            var proposal = await dfoManager.createProposal(dfo, "manageLiquidityMining", true, code, "manageLiquidityMining(address,uint256,bool,address,address,uint256,bool)", false, true);
            await dfoManager.finalizeProposal(dfo, proposal);
    /*
            code = fs.readFileSync(path.resolve(__dirname, '..', 'contracts/liquidity-mining/dfo/ManageLiquidityMiningFunctionality.sol'), 'UTF-8').format(pinnedFarmExtension.options.address);
            proposal = await dfoManager.createProposal(pinnedDfo, "manageLiquidityMining", true, code, "manageLiquidityMining(address,uint256,bool,address,address,uint256,bool)", false, true);
            await dfoManager.finalizeProposal(dfo, proposal);
    */
            transaction = await farmFactory.methods.cloneFarmDefaultExtension().send(blockchainConnection.getSendingOptions());
            receipt = await web3.eth.getTransactionReceipt(transaction.transactionHash);
            clonedDefaultFarmExtension = web3.eth.abi.decodeParameter("address", receipt.logs.filter(it => it.topics[0] === web3.utils.sha3('ExtensionCloned(address)'))[0].topics[1])
            console.log(`cloned default farm extension deployed at ${clonedDefaultFarmExtension}`);

        } catch (error) {
            console.error(`error is`, error);
        }
    });
    it("should deploy simple farm main contract", async () => {
        try {

            var setups = [
                [
                    true,
                    50,
                    "500000000000000000",
                    "1000000000000000000",
                    0,
                    2,
                    uniswapAMM.options.address,
                    liquidityPool.options.address,
                    mainToken !== utilities.voidEthereumAddress ? mainToken.options.address : wethToken.options.address,
                    wethToken.options.address,
                    mainToken === utilities.voidEthereumAddress,
                    0,
                    0,
                    0
                ],
                [
                    false,
                    50,
                    "500000000000000000",
                    "1000000000000000000",
                    "2500000000000000000000",
                    2,
                    uniswapAMM.options.address,
                    liquidityPool.options.address,
                    mainToken !== utilities.voidEthereumAddress ? mainToken.options.address : wethToken.options.address,
                    wethToken.options.address,
                    mainToken === utilities.voidEthereumAddress,
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
                ethItemOrchestrator.options.address,
                rewardToken != utilities.voidEthereumAddress ? rewardToken.options.address : utilities.voidEthereumAddress,
                abi.encode(["tuple(bool,uint256,uint256,uint256,uint256,uint256,address,address,address,address,bool,uint256,uint256,uint256)[]"], [setups]),
            ];

            byMint = params[0] !== clonedDefaultFarmExtension;
            params[1] = simpleFarmExtension.methods.init(byMint, params[0] === clonedDefaultFarmExtension ? extensionOwner : dfo.doubleProxyAddress).encodeABI()

            var payload = web3.utils.sha3(`init(${types.join(',')})`).substring(0, 10) + (web3.eth.abi.encodeParameters(types, params).substring(2));
            var deployTransaction = await farmFactory.methods.deploy(payload, true).send(blockchainConnection.getSendingOptions());
            deployTransaction = await web3.eth.getTransactionReceipt(deployTransaction.transactionHash);
            var simpleFarmContractAddress = web3.eth.abi.decodeParameter("address", deployTransaction.logs.filter(it => it.topics[0] === web3.utils.sha3("FarmMainDeployed(address,address,bool,bytes)"))[0].topics[1]);

            simpleFarmContract = await new web3.eth.Contract(SimpleFarmMain.abi, simpleFarmContractAddress);
            assert.notStrictEqual(simpleFarmContract.options.address, utilities.voidEthereumAddress);
            oneHundred = await simpleFarmContract.methods.ONE_HUNDRED().call();

            var availableSetups = await simpleFarmContract.methods.setups().call()
            assert.strictEqual(availableSetups.length, setups.length);

            // put reward in the extension
            await buyForETH(rewardToken, 6000);
            await rewardToken.methods.transfer(clonedDefaultFarmExtension, utilities.toDecimals("6000", '18')).send(blockchainConnection.getSendingOptions());
            var extension = new web3.eth.Contract(FarmExtension.abi, clonedDefaultFarmExtension);
            await extension.methods.setActive(true).send(blockchainConnection.getSendingOptions());
        } catch (error) {
            console.error(error);
        }
    });
    it("should activate both the setups", async () => {
        await simpleFarmContract.methods.activateSetup(0).send(blockchainConnection.getSendingOptions());
        await simpleFarmContract.methods.activateSetup(1).send(blockchainConnection.getSendingOptions());
        var availableSetups = await simpleFarmContract.methods.setups().call();
        await Promise.all(availableSetups.map(async (setup) => {
            console.log(setup);
            assert.strictEqual(setup.active, true);
        }))
    });
    it("should not activate a non existing setup info", async () => {
        try {
            await simpleFarmContract.methods.activateSetup(2).send(blockchainConnection.getSendingOptions());
            assert.strictEqual(true, false);
        } catch (error) {
            assert.strictEqual(true, true);
        }
    });
    it("should allow cavicchioli to open a new staking position", async () => {
        await createStakingPosition(actors.Cavicchioli, 1);
    });
    it("should allow cappello to open a new staking position", async () => {
        await createStakingPosition(actors.Cappello, 0);
    });
    it("should allow cavicchioli to partial withdraw", async () => {
        await withdrawReward(actors.Cavicchioli);
    })
    it("should allow cappello to partial withdraw", async () => {
        await withdrawReward(actors.Cappello);
    })
})
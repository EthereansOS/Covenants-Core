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
var FarmMain;
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
var farmMainExtension;
// var pinnedFarmExtension;
var clonedDefaultFarmExtension;
var clonedFarmExtension;
var dfo;
var pinnedDfo;
var farmMainContract;
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
        (mainToken !== utilities.voidEthereumAddress) && await mainToken.methods.approve(farmMainContract.options.address, await mainToken.methods.totalSupply().call()).send(actor.from);
        (secondaryToken !== utilities.voidEthereumAddress) && await secondaryToken.methods.approve(farmMainContract.options.address, await secondaryToken.methods.totalSupply().call()).send(actor.from);

        var mainTokenAmount = utilities.toDecimals(actor.amount, mainToken !== utilities.voidEthereumAddress ? await mainToken.methods.decimals().call() : 18);
        var stake = {
            setupIndex,
            amount : mainTokenAmount,
            amountIsLiquidityPool : actor.amountIsLiquidityPool || false,
            positionOwner: utilities.voidEthereumAddress,
        };

        var setups = await farmMainContract.methods.setups().call();
        console.log(setups);
        var setup = setups[setupIndex];
        var setupInfo = (await farmMainContract.methods.setup(setup.infoIndex).call())[1];
        console.log(setupInfo);
        var ammPlugin = new web3.eth.Contract(UniswapV2AMMV1.abi, setupInfo.ammPlugin);
        var liquidityPoolTokenAddress = setupInfo.liquidityPoolTokenAddress;
        var tokens = (await ammPlugin.methods.byLiquidityPool(liquidityPoolTokenAddress).call())[2];
        var secondaryTokenIndex = tokens[0] === (secondaryToken != utilities.voidEthereumAddress ? secondaryToken.options.address : wethToken.options.address) ? 0 : 1;
        var amounts = await ammPlugin.methods.byTokenAmount(liquidityPoolTokenAddress, mainToken !== utilities.voidEthereumAddress ? mainToken.options.address : wethToken.options.address, mainTokenAmount).call();
        var secondaryTokenAmount = amounts[1][secondaryTokenIndex];

        if (actor.amountIsLiquidityPool) {
            if (mainToken !== utilities.voidEthereumAddress) await mainToken.methods.approve(uniswapV2Router.options.address, await mainToken.methods.totalSupply().call()).send(actor.from);
            if (secondaryToken !== utilities.voidEthereumAddress) await secondaryToken.methods.approve(uniswapV2Router.options.address, await secondaryToken.methods.totalSupply().call()).send(actor.from);  
            if (mainToken !== utilities.voidEthereumAddress && secondaryToken !== utilities.voidEthereumAddress) {
                try {
                    await uniswapV2Router.methods.addLiquidity(
                        mainToken !== utilities.voidEthereumAddress ? mainToken.options.address : wethToken.options.address,
                        secondaryToken !== utilities.voidEthereumAddress ? secondaryToken.options.address : wethToken.options.address,
                        mainTokenAmount,
                        secondaryTokenAmount,
                        1,
                        1,
                        actor.address,
                        (await web3.eth.getBlock(await web3.eth.getBlockNumber())).timestamp + 10000
                    ).send(actor.from);
                } catch (error) {
                    console.error(error);
                }
            } else {
                await uniswapV2Router.methods.addLiquidityETH(
                    secondaryToken !== utilities.voidEthereumAddress ? secondaryToken.options.address : mainToken.options.address,
                    secondaryToken !== utilities.voidEthereumAddress ? secondaryTokenAmount : mainTokenAmount,
                    1,
                    1,
                    actor.address,
                    (await web3.eth.getBlock(await web3.eth.getBlockNumber())).timestamp + 10000
                ).send({...actor.from, value : secondaryToken !== utilities.voidEthereumAddress ? mainTokenAmount : secondaryTokenAmount});
            }

            var liquidityPoolTokenContract = new web3.eth.Contract(context.IERC20ABI, liquidityPoolTokenAddress);
            await liquidityPoolTokenContract.methods.approve(farmMainContract.options.address, await liquidityPoolTokenContract.methods.totalSupply().call()).send(actor.from);
            stake.amount = await liquidityPoolTokenContract.methods.balanceOf(actor.address).call();
        }

        var result = await farmMainContract.methods.openPosition(stake).send({...actor.from, value: (!stake.amountIsLiquidityPool && setupInfo.involvingETH) ? mainToken === setupInfo.ethereumAddress ? mainTokenAmount : secondaryTokenAmount : 0});
        var { positionId } = result.events.Transfer.returnValues;
        var position = await farmMainContract.methods.position(positionId).call();

        actor.free = setupInfo.free;
        actor.setupIndex = setupIndex;
        actor.position = position;
        actor.positionId = positionId;
        console.log("POSITION CREATED FOR ", actor.name);

        if (!setupInfo.free) {
            assert.strictEqual(parseInt(position.reward), parseInt(position.lockedRewardPerBlock) * (parseInt(setup.endBlock) - parseInt(position.creationBlock)));
        }

        setup = (await farmMainContract.methods.setups().call())[setupIndex];
        actor.objectId = setup.objectId;
        assert.strictEqual(setup.lastUpdateBlock, position.creationBlock);  
    }

    async function addLiquidity(actor) {

        var startingSetup = (await farmMainContract.methods.setups().call())[actor.setupIndex];
        var startingPosition = await farmMainContract.methods.position(actor.positionId).call();

        var mainTokenAmount = utilities.toDecimals(actor.amount, mainToken != utilities.voidEthereumAddress ? await mainToken.methods.decimals().call() : 18);
        var {'0': _, '1': setupInfo} = await farmMainContract.methods.setup(actor.setupIndex).call();
        var ammPlugin = new web3.eth.Contract(UniswapV2AMMV1.abi, setupInfo.ammPlugin);
        var liquidityPoolTokenAddress = setupInfo.liquidityPoolTokenAddress;
        var tokens = (await ammPlugin.methods.byLiquidityPool(liquidityPoolTokenAddress).call())[2];
        var secondaryTokenIndex = tokens[0] === (secondaryToken != utilities.voidEthereumAddress ? secondaryToken.options.address : wethToken.options.address) ? 0 : 1;
        var amounts = await ammPlugin.methods.byTokenAmount(liquidityPoolTokenAddress, mainToken != utilities.voidEthereumAddress ? mainToken.options.address : wethToken.options.address, mainTokenAmount).call();
        var secondaryTokenAmount = amounts[1][secondaryTokenIndex];

        var stake = {
            setupIndex: actor.setupIndex,
            amount : mainTokenAmount,
            amountIsLiquidityPool : actor.amountIsLiquidityPool || false,
            positionOwner: utilities.voidEthereumAddress,
        };
        await farmMainContract.methods.addLiquidity(actor.positionId, stake).send({...actor.from, value: (!stake.amountIsLiquidityPool && setupInfo.involvingETH) ? mainToken === utilities.voidEthereumAddress ? mainTokenAmount : secondaryTokenAmount : 0});
        var endingSetup = (await farmMainContract.methods.setups().call())[actor.setupIndex];
        var endingPosition = await farmMainContract.methods.position(actor.positionId).call();
        assert.strictEqual(utilities.fromDecimals(parseInt(startingPosition.liquidityPoolTokenAmount) * 2, 4).slice(0, -1), utilities.fromDecimals(parseInt(endingPosition.liquidityPoolTokenAmount), 4).slice(0, -1));
        assert.strictEqual(parseInt(endingSetup.totalSupply), parseInt(startingSetup.totalSupply) + (parseInt(endingPosition.liquidityPoolTokenAmount) - parseInt(startingPosition.liquidityPoolTokenAmount)));
        actor.position = endingPosition;
    }

    async function withdrawReward(actor, blocks, isPartial) {

        var balance = rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.balanceOf(farmMainContract.options.address).call() : await web3.eth.getBalance(farmMainContract.options.address);;
        console.log(`farm main balance is ${balance}`);
        var setup = (await farmMainContract.methods.setups().call())[actor.setupIndex];
        var currentBlock = await web3.eth.getBlockNumber();
        await blockchainConnection.jumpToBlock(parseInt(currentBlock) + blocks || parseInt(setup.endBlock));
        var startingBalance = rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.balanceOf(actor.address).call() : await web3.eth.getBalance(actor.address);
        var result = await farmMainContract.methods.withdrawReward(actor.positionId).send(actor.from);
        var fee = await blockchainConnection.calculateTransactionFee(result);
        console.log(fee);
        setup = (await farmMainContract.methods.setups().call())[actor.setupIndex];
        var resultBalance = rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.balanceOf(actor.address).call() : await web3.eth.getBalance(actor.address);
        console.log(`exit block is ${setup.lastUpdateBlock}`);
        console.log(`starting balance is ${startingBalance}`);
        console.log(`result balance is ${resultBalance}`);
        console.log(actor.position);
        if (!actor.free) {
            var diffBalance = parseInt(resultBalance) - parseInt(startingBalance);
            var reward = actor.position.reward;
            if (isPartial) {
                reward = (parseInt(currentBlock) + blocks + 1 - parseInt(actor.position.creationBlock)) * parseInt(actor.position.lockedRewardPerBlock);
                if (rewardToken === utilities.voidEthereumAddress) {
                    diffBalance += parseInt(fee);
                } 
                var position = await farmMainContract.methods.position(actor.positionId).call();
                actor.position = position;
            } else {
                reward = (parseInt(setup.endBlock) - parseInt(actor.position.creationBlock))  * parseInt(actor.position.lockedRewardPerBlock);
            }
            assert.strictEqual(utilities.formatMoney(utilities.fromDecimals(diffBalance, rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.decimals().call() : 18), 4), utilities.formatMoney(utilities.fromDecimals(reward, rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.decimals().call() : 18), 4))
        }
    }

    async function withdrawLiquidity(actor, amount, jump) {
        var positionLiquidityPoolTokenAmount = actor.position.liquidityPoolTokenAmount;
        if (!amount) amount = positionLiquidityPoolTokenAmount;
        var startingFarmTokenBalance = actor.free ? 0 : await farmTokenCollection.methods.balanceOf(actor.address, actor.objectId).call();
        if (jump) {
            var setup = (await farmMainContract.methods.setups().call())[actor.setupIndex];
            await blockchainConnection.jumpToBlock(parseInt(setup.endBlock) + 1);
        }
        await farmMainContract.methods.withdrawLiquidity(actor.free ? actor.positionId : 0, !actor.free ? actor.objectId : 0, actor.unwrap, amount).send(actor.from);
        var endFarmTokenBalance = actor.free ? 0 : await farmTokenCollection.methods.balanceOf(actor.address, actor.objectId).call();
        if (amount === actor.position.liquidityPoolTokenAmount || actor.free) {
            var position = await farmMainContract.methods.position(actor.positionId).call();
            if (actor.free && amount === actor.position.liquidityPoolTokenAmount) {
                assert.strictEqual(parseInt(position.creationBlock), 0);
            } else if (actor.free) {
                assert.strictEqual(utilities.fromDecimals(parseInt(position.liquidityPoolTokenAmount), 18), utilities.fromDecimals(parseInt(positionLiquidityPoolTokenAmount) - parseInt(amount), 18));
                actor.position = position;
            }
            assert.strictEqual(parseInt(endFarmTokenBalance), 0);
        } else {
            assert.strictEqual(parseInt(endFarmTokenBalance), parseInt(startingFarmTokenBalance) - parseInt(amount));
        }
    }

    async function unlockPosition(actor) {
        try {
            var setup = (await farmMainContract.methods.setups().call())[actor.setupIndex];
            console.log(setup);
            var position = await farmMainContract.methods.position(actor.positionId).call();
            console.log(position);
            var balance = rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.balanceOf(farmMainContract.options.address).call() : await web3.eth.getBalance(farmMainContract.options.address);
            console.log(`farm main balance is ${balance}`);
            rewardToken !== utilities.voidEthereumAddress && await rewardToken.methods.approve(farmMainContract.options.address, await rewardToken.methods.totalSupply().call()).send(actor.from);
            await farmMainContract.methods.unlock(actor.positionId, actor.unwrap).send(actor.from);
            var farmTokenBalance = await farmTokenCollection.methods.balanceOf(actor.address, actor.objectId).call();
            assert.strictEqual(parseInt(farmTokenBalance), 0);
            position = await farmMainContract.methods.position(actor.positionId).call();
            console.log(position);
            setup = (await farmMainContract.methods.setups().call())[actor.setupIndex];
            console.log(setup);
            balance = rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.balanceOf(farmMainContract.options.address).call() : await web3.eth.getBalance(farmMainContract.options.address);
            console.log(`farm main balance is ${balance}`);
        } catch (error) {
            console.log(error);
        }
    }

    async function transferPosition(from, to) {
        try {
            const result = await farmMainContract.methods.transferPosition(to.address, from.positionId).send(from.from);
            var { positionId } = result.events.Transfer.returnValues;
            assert.notStrictEqual(from.positionId, positionId);
            const oldPosition = await farmMainContract.methods.position(from.positionId).call();
            const transferedPosition = await farmMainContract.methods.position(positionId).call();
            assert.strictEqual(oldPosition.creationBlock, "0");
            assert.strictEqual(transferedPosition.creationBlock, from.position.creationBlock);
            assert.strictEqual(transferedPosition.reward, from.position.reward);
            assert.notStrictEqual(transferedPosition.uniqueOwner, from.position.uniqueOwner);
            actors[to.name] = {
                ...actors[to.name],
                free: from.free,
                setupIndex: from.setupIndex,
                position: transferedPosition,
                positionId,
                objectId: from.objectId,
            }
            console.log(actors);
        } catch (error) {
            console.error(error);
        }
    }

    before(async () => {
        try {
            await blockchainConnection.init;
            FarmMain = await compile('farming/FarmMain');
            // PinnedFarmMain = await compile('farming/PinnedFarmMain');
            FarmFactory = await compile('farming/FarmFactory');
            DFOBasedFarmExtensionFactory = await compile('farming/dfo/DFOBasedFarmExtensionFactory');
            DFOBasedFarmExtension = await compile('farming/dfo/DFOBasedFarmExtension');
            FarmExtension = await compile('farming/FarmExtension');

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

            liquidityPool = new web3.eth.Contract(context.uniswapV2PairABI, await uniswapV2Factory.methods.getPair(mainToken !== utilities.voidEthereumAddress ? mainToken.options.address : wethToken.options.address, secondaryToken != utilities.voidEthereumAddress ? secondaryToken.options.address : wethToken.options.address).call());

            mainToken !== utilities.voidEthereumAddress && await buyForETH(mainToken, ethToSpend);
            secondaryToken !== utilities.voidEthereumAddress && await buyForETH(secondaryToken, ethToSpend);
            rewardToken !== utilities.voidEthereumAddress && rewardToken.options.address !== dfo.votingTokenAddress && await buyForETH(rewardToken, ethToSpend);

            uniswapAMM = await new web3.eth.Contract(UniswapV2AMMV1.abi).deploy({data : UniswapV2AMMV1.bin, arguments: [uniswapV2Router.options.address]}).send(blockchainConnection.getSendingOptions());

            var res = await uniswapAMM.methods.byLiquidityPool(liquidityPool.options.address).call();
            console.log(res);

            global.tokens = [dfo.votingToken, mainToken, rewardToken, liquidityPool];

            await initActor("Cavicchioli", accounts[1], true, 500, false);
            await initActor("Cappello", accounts[2], true, 100, false);
            await initActor("Bestiadidio", accounts[3], false, 500, false);
            await initActor("Canedicristo", accounts[4], false, 50, false);
            await initActor("Madonnacagna", accounts[5], false, 75, false);
            await initActor("Porco", accounts[6], false, 50, false);
            await initActor("Ladro", accounts[7], false, 50, false);
            await initActor("Cane", accounts[8], false, 50, false);
            await initActor("Sporco", accounts[9], false, 50, false);
            await initActor("Verme", accounts[10], false, 50, false);
        } catch (error) {
            console.error(error);
        }
    });
    it("should deploy farm factory, extensions and finalize proposals", async () => {
        try {
            rewardDestination = dfo.mvdWalletAddress;
            var farmMainModel = await new web3.eth.Contract(FarmMain.abi).deploy({data : FarmMain.bin}).send(blockchainConnection.getSendingOptions());
            console.log(`simple farm model deployed at ${farmMainModel.options.address}`);
            // var pinnedFarmModel = await new web3.eth.Contract(PinnedFarmMain.abi).deploy({data : PinnedFarmMain.bin}).send(blockchainConnection.getSendingOptions());  
            var farmExtensionModel = await new web3.eth.Contract(FarmExtension.abi).deploy({data : FarmExtension.bin}).send(blockchainConnection.getSendingOptions());
            console.log(`farm extension model deployed at ${farmExtensionModel.options.address}`);
    
            farmFactory = await new web3.eth.Contract(FarmFactory.abi).deploy({data : FarmFactory.bin, arguments : [dfo.doubleProxyAddress, farmMainModel.options.address, farmExtensionModel.options.address, 0, "google.com", "google.com"]}).send(blockchainConnection.getSendingOptions());
            console.log(`farm factory deployed at ${farmFactory.options.address}`);

            var dfoFarmExtensionModel = await new web3.eth.Contract(DFOBasedFarmExtension.abi).deploy({data : DFOBasedFarmExtension.bin}).send(blockchainConnection.getSendingOptions());
            console.log(`dfo farm extension model deployed at ${dfoFarmExtensionModel.options.address}`);
            dFOBasedFarmExtensionFactory = await new web3.eth.Contract(DFOBasedFarmExtensionFactory.abi).deploy({data : DFOBasedFarmExtensionFactory.bin, arguments : [mainDFO.doubleProxyAddress, dfoFarmExtensionModel.options.address]}).send(blockchainConnection.getSendingOptions());
            console.log(`dfo based farm extension factory deployed at ${dFOBasedFarmExtensionFactory.options.address}`);

            var transaction = await dFOBasedFarmExtensionFactory.methods.cloneModel().send(blockchainConnection.getSendingOptions());
            var receipt = await web3.eth.getTransactionReceipt(transaction.transactionHash);
            var farmMainExtensionAddress = web3.eth.abi.decodeParameter("address", receipt.logs.filter(it => it.topics[0] === web3.utils.sha3('ExtensionCloned(address,address)'))[0].topics[1])
            farmMainExtension = new web3.eth.Contract(FarmExtension.abi, farmMainExtensionAddress);
            console.log(`simple farm extension deployed at ${farmMainExtension.options.address}`);

            var code = fs.readFileSync(path.resolve(__dirname, '..', 'contracts/farming/dfo/ManageFarmingFunctionality.sol'), 'UTF-8').format(farmMainExtension.options.address);
            var proposal = await dfoManager.createProposal(dfo, "manageFarming", true, code, "manageFarming(address,uint256,bool,address,address,uint256,bool)", false, true);
            await dfoManager.finalizeProposal(dfo, proposal);

            transaction = await farmFactory.methods.cloneFarmDefaultExtension().send(blockchainConnection.getSendingOptions());
            receipt = await web3.eth.getTransactionReceipt(transaction.transactionHash);
            clonedDefaultFarmExtension = web3.eth.abi.decodeParameter("address", receipt.logs.filter(it => it.topics[0] === web3.utils.sha3('ExtensionCloned(address)'))[0].topics[1])
            console.log(`cloned default farm extension deployed at ${clonedDefaultFarmExtension}`);
            clonedFarmExtension = new web3.eth.Contract(FarmExtension.abi, clonedDefaultFarmExtension);
        } catch (error) {
            console.error(`error is`, error);
        }
    });
    it("should deploy simple farm main contract", async () => {
        try {

            var setups = [
                [
                    true,
                    100,
                    "500000000000000000",
                    "1000000000000000000",
                    0,
                    0,
                    uniswapAMM.options.address,
                    liquidityPool.options.address,
                    mainToken !== utilities.voidEthereumAddress ? mainToken.options.address : wethToken.options.address,
                    wethToken.options.address,
                    mainToken === utilities.voidEthereumAddress || secondaryToken === utilities.voidEthereumAddress,
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
                    0,
                    uniswapAMM.options.address,
                    liquidityPool.options.address,
                    mainToken !== utilities.voidEthereumAddress ? mainToken.options.address : wethToken.options.address,
                    wethToken.options.address,
                    mainToken === utilities.voidEthereumAddress || secondaryToken === utilities.voidEthereumAddress,
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
                rewardToken !== utilities.voidEthereumAddress ? rewardToken.options.address : utilities.voidEthereumAddress,
                abi.encode(["tuple(bool,uint256,uint256,uint256,uint256,uint256,address,address,address,address,bool,uint256,uint256,uint256)[]"], [setups]),
            ];

            byMint = params[0] !== clonedDefaultFarmExtension;
            params[1] = farmMainExtension.methods.init(byMint, params[0] === clonedDefaultFarmExtension ? extensionOwner : dfo.doubleProxyAddress, params[0] === clonedDefaultFarmExtension ? utilities.voidEthereumAddress : dfo.doubleProxyAddress).encodeABI()

            var payload = web3.utils.sha3(`init(${types.join(',')})`).substring(0, 10) + (web3.eth.abi.encodeParameters(types, params).substring(2));
            console.log(`gas used ${await farmFactory.methods.deploy(payload).estimateGas(blockchainConnection.getSendingOptions())}`)
            var deployTransaction = await farmFactory.methods.deploy(payload).send(blockchainConnection.getSendingOptions());
            deployTransaction = await web3.eth.getTransactionReceipt(deployTransaction.transactionHash);
            var farmMainContractAddress = web3.eth.abi.decodeParameter("address", deployTransaction.logs.filter(it => it.topics[0] === web3.utils.sha3("FarmMainDeployed(address,address,bytes)"))[0].topics[1]);

            farmMainContract = await new web3.eth.Contract(FarmMain.abi, farmMainContractAddress);
            assert.notStrictEqual(farmMainContract.options.address, utilities.voidEthereumAddress);
            oneHundred = await farmMainContract.methods.ONE_HUNDRED().call();

            var availableSetups = await farmMainContract.methods.setups().call()
            assert.strictEqual(availableSetups.length, setups.length);

            // put reward in the extension
            if (rewardToken !== utilities.voidEthereumAddress) {
                await buyForETH(rewardToken, 20000);
                await rewardToken.methods.transfer(clonedDefaultFarmExtension, utilities.toDecimals("15000", '18')).send(blockchainConnection.getSendingOptions());
            } else {
                await web3.eth.sendTransaction(blockchainConnection.getSendingOptions({
                    to: clonedDefaultFarmExtension,
                    value : utilities.toDecimals(20000, 18)
                }));
            }
            farmTokenCollection = new web3.eth.Contract(context.INativeV1ABI, await farmMainContract.methods._farmTokenCollection().call());
        } catch (error) {
            console.error(error);
        }
    });
    it("should activate both the setups", async () => {
        await farmMainContract.methods.activateSetup(0).send(blockchainConnection.getSendingOptions());
        await farmMainContract.methods.activateSetup(1).send(blockchainConnection.getSendingOptions());
        var availableSetups = await farmMainContract.methods.setups().call();
        await Promise.all(availableSetups.map(async (setup) => {
            console.log(setup);
            assert.strictEqual(setup.active, true);
        }))
    });
    it("should not activate a non existing setup info", async () => {
        try {
            await farmMainContract.methods.activateSetup(2).send(blockchainConnection.getSendingOptions());
            assert.strictEqual(true, false);
        } catch (error) {
            assert.strictEqual(true, true);
        }
    });
    it("should allow cavicchioli to open a new staking position", async () => {
        await createStakingPosition(actors.Cavicchioli, 1);
    });
    it("should allow bestiadidio to open a new staking position", async () => {
        await createStakingPosition(actors.Bestiadidio, 1);
    });
    it("should allow sporco to open a new staking position", async () => {
        await createStakingPosition(actors.Sporco, 1);
    });
    it("should allow sporco to transfer its position to verme", async () => {
        await transferPosition(actors.Sporco, actors.Verme);
    });
    it("should allow cappello to open a new staking position", async () => {
        await createStakingPosition(actors.Cappello, 0);
    });
    it("should allow canedicristo to open a new staking position", async () => {
        await createStakingPosition(actors.Canedicristo, 0);
    });
    it("should allow madonnacagna to open a new staking position", async () => {
        await createStakingPosition(actors.Madonnacagna, 0);
    });
    it("should allow bestiadidio to partial withdraw", async () => {
        await withdrawReward(actors.Bestiadidio, 5, true);
    });
    it("should allow cavicchioli to unlock", async () => {
        try {
            await unlockPosition(actors.Cavicchioli);
        } catch (error) {
            console.log(error);
        }
    })
    it("should allow the host to disable the locked setup", async () => {
        var updatedSetups = [
            {
                add: false,
                disable: true,
                index: 1,
                info: {
                    free: false,
                    blockDuration: 0,
                    originalRewardPerBlock: 0,
                    minStakeable: 0,
                    maxStakeable: 0,
                    renewTimes: 0,
                    ammPlugin: utilities.voidEthereumAddress,
                    liquidityPoolTokenAddress: utilities.voidEthereumAddress,
                    mainTokenAddress: utilities.voidEthereumAddress,
                    ethereumAddress: utilities.voidEthereumAddress,
                    involvingETH: false,
                    penaltyFee: 0,
                    setupsCount: 0,
                    lastSetupIndex: 0,
                }
            }
        ];
        await clonedFarmExtension.methods.setFarmingSetups(updatedSetups).send(blockchainConnection.getSendingOptions());
        var setups = await farmMainContract.methods.setups().call();
        var setup = setups[1];
        assert.strictEqual(setup.active, false);
    });
    it("should allow madonnacagna to add liquidity", async () => {
        await addLiquidity(actors.Madonnacagna);
    })
    it("should allow the host to disable the free setup", async () => {
        var updatedSetups = [
            {
                add: false,
                disable: true,
                index: 0,
                info: {
                    free: false,
                    blockDuration: 0,
                    originalRewardPerBlock: 0,
                    minStakeable: 0,
                    maxStakeable: 0,
                    renewTimes: 0,
                    ammPlugin: utilities.voidEthereumAddress,
                    liquidityPoolTokenAddress: utilities.voidEthereumAddress,
                    mainTokenAddress: utilities.voidEthereumAddress,
                    ethereumAddress: utilities.voidEthereumAddress,
                    involvingETH: false,
                    penaltyFee: 0,
                    setupsCount: 0,
                    lastSetupIndex: 0,
                }
            }
        ];
        await clonedFarmExtension.methods.setFarmingSetups(updatedSetups).send(blockchainConnection.getSendingOptions());
        var setups = await farmMainContract.methods.setups().call();
        var setup = setups[0];
        assert.strictEqual(setup.active, false);
    });
    it("should allow the host to add a new free setup", async () => {
        var startingInfoCount = await farmMainContract.methods._farmingSetupsInfoCount().call();
        var updatedSetups = [
            {
                add: true,
                disable: false,
                index: 0,
                info: {
                    free: true,
                    blockDuration: 100,
                    originalRewardPerBlock: "500000000000000000",
                    minStakeable: "1000000000000000000",
                    maxStakeable: 0,
                    renewTimes: 2,
                    ammPlugin:  uniswapAMM.options.address,
                    liquidityPoolTokenAddress: liquidityPool.options.address,
                    mainTokenAddress: mainToken !== utilities.voidEthereumAddress ? mainToken.options.address : wethToken.options.address,
                    ethereumAddress: wethToken.options.address,
                    involvingETH: mainToken === utilities.voidEthereumAddress || secondaryToken === utilities.voidEthereumAddress,
                    penaltyFee: 0,
                    setupsCount: 0,
                    lastSetupIndex: 0,
                }
            }
        ];
        await clonedFarmExtension.methods.setFarmingSetups(updatedSetups).send(blockchainConnection.getSendingOptions());
        var infoCount = await farmMainContract.methods._farmingSetupsInfoCount().call();
        assert.strictEqual(parseInt(infoCount), parseInt(startingInfoCount) + 1);
    });
    /*
    it("should allow cavicchioli to withdraw", async () => {
        await withdrawReward(actors.Cavicchioli);
    })
    */
    it("should activate the new setup", async () => {
        await farmMainContract.methods.activateSetup(2).send(blockchainConnection.getSendingOptions());
        var setups = await farmMainContract.methods.setups().call();
        var setup = setups[2];
        assert.strictEqual(setup.active, true);
    });
    it("should allow bestiadidio to withdraw", async () => {
        await withdrawReward(actors.Bestiadidio);
    })
    it("should allow cappello to withdraw", async () => {
        await withdrawReward(actors.Cappello);
    })
    it("should allow madonnacagna to withdraw", async () => {
        await withdrawReward(actors.Madonnacagna);
    })
    it("should allow canedicristo to withdraw", async () => {
        await withdrawReward(actors.Canedicristo);
    })
    /*
    it("should allow cavicchioli to withdraw liquidity", async () => {
        await withdrawLiquidity(actors.Cavicchioli);
    })
    */
    it("should not allow sporco withdraw its reward", async () => {
        try {
            await withdrawReward(actors.Sporco);
            assert.notStrictEqual(false, true);
        } catch (error) {
            console.error(error);
            assert.strictEqual(true, true);
        }
    });
    it("should allow verme to withdraw reward", async () => {
        await withdrawReward(actors.Verme);
    })
    it("should allow sporco to withdraw liquidity", async () => {
        await withdrawLiquidity(actors.Sporco); 
    })
    it("should not allow verme to withdraw liquidity", async () => {
        try {
            await withdrawLiquidity(actors.Verme);
            assert.notStrictEqual(false, true);
        } catch (error) {
            console.error(error);
            assert.strictEqual(true, true);
        }
    })
    it("should allow bestiadidio to withdraw liquidity", async () => {
        await withdrawLiquidity(actors.Bestiadidio);
    })
    it("should allow madonnacagna to withdraw liquidity", async () => {
        await withdrawLiquidity(actors.Madonnacagna);
    })
    it("should allow canedicristo to withdraw liquidity", async () => {
        await withdrawLiquidity(actors.Canedicristo);
    })
    it("should allow cappello to withdraw liquidity", async () => {
        await withdrawLiquidity(actors.Cappello, utilities.numberToString(parseInt(parseInt(actors.Cappello.position.liquidityPoolTokenAmount) / 2)));
    });
    it("should allow cappello to withdraw liquidity again", async () => {
        await withdrawLiquidity(actors.Cappello);
    });
    it("should allow porco to open a new staking position", async () => {
        await createStakingPosition(actors.Porco, 2);
    });
    it("should allow porco to withdraw liquidity", async () => {
        await withdrawLiquidity(actors.Porco, undefined, true);
    });
    it("should allow cane to open a new staking position", async () => {
        await createStakingPosition(actors.Cane, 3);
    });
    it("should allow the host to increase the reward per block", async () => {
        var updatedSetups = [
            {
                add: false,
                disable: false,
                index: 3,
                info: {
                    free: true,
                    blockDuration: 100,
                    originalRewardPerBlock: "550000000000000000",
                    minStakeable: "1000000000000000000",
                    maxStakeable: 0,
                    renewTimes: 1,
                    ammPlugin:  uniswapAMM.options.address,
                    liquidityPoolTokenAddress: liquidityPool.options.address,
                    mainTokenAddress: mainToken !== utilities.voidEthereumAddress ? mainToken.options.address : wethToken.options.address,
                    ethereumAddress: wethToken.options.address,
                    involvingETH: mainToken === utilities.voidEthereumAddress,
                    penaltyFee: 0,
                    setupsCount: 0,
                    lastSetupIndex: 0,
                }
            }
        ];
        await clonedFarmExtension.methods.setFarmingSetups(updatedSetups).send(blockchainConnection.getSendingOptions());
        var setups = await farmMainContract.methods.setups().call();
        var {'0': setup, '1': setupInfo} = await farmMainContract.methods.setup(3).call();
        assert.strictEqual(setupInfo.originalRewardPerBlock, "550000000000000000");
        assert.strictEqual(setup.rewardPerBlock, "550000000000000000");
    });
    it("should allow cane to withdraw liquidity", async () => {
        await withdrawLiquidity(actors.Cane, undefined, true);
    });
    it("should allow ladro to open a new staking position", async () => {
        await createStakingPosition(actors.Ladro, 4);
    });
    it("should allow the host to decrease the reward per block", async () => {
        var startingInfoCount = await farmMainContract.methods._farmingSetupsInfoCount().call();
        var updatedSetups = [
            {
                add: false,
                disable: false,
                index: 4,
                info: {
                    free: true,
                    blockDuration: 100,
                    originalRewardPerBlock: "450000000000000000",
                    minStakeable: "1000000000000000000",
                    maxStakeable: 0,
                    renewTimes: 0,
                    ammPlugin:  uniswapAMM.options.address,
                    liquidityPoolTokenAddress: liquidityPool.options.address,
                    mainTokenAddress: mainToken !== utilities.voidEthereumAddress ? mainToken.options.address : wethToken.options.address,
                    ethereumAddress: wethToken.options.address,
                    involvingETH: mainToken === utilities.voidEthereumAddress,
                    penaltyFee: 0,
                    setupsCount: 0,
                    lastSetupIndex: 0,
                }
            }
        ];
        await clonedFarmExtension.methods.setFarmingSetups(updatedSetups).send(blockchainConnection.getSendingOptions());
        var setups = await farmMainContract.methods.setups().call();
        var {'0': setup, '1': setupInfo} = await farmMainContract.methods.setup(4).call();
        assert.strictEqual(setupInfo.originalRewardPerBlock, "450000000000000000");
        assert.strictEqual(setup.rewardPerBlock, "450000000000000000");
    });
    it("should allow ladro to withdraw liquidity", async () => {
        await withdrawLiquidity(actors.Ladro, undefined, true);
    });
    it("should have 0 reward tokens in the contract", async () => {
        var balance = rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.balanceOf(farmMainContract.options.address).call() : await web3.eth.getBalance(farmMainContract.options.address);
        assert.strictEqual(parseInt(balance), 0);
        var setups = await farmMainContract.methods.setups().call();
        await Promise.all(setups.map(async (setup, i) => {
            var rewardReceived = await farmMainContract.methods._rewardReceived(i).call();
            var rewardPaid = await farmMainContract.methods._rewardPaid(i).call();
            console.log(`setup ${i} - received: ${rewardReceived} - paid: ${rewardPaid}`);
            assert.strictEqual(setup.active, false);
        }))
    })
})
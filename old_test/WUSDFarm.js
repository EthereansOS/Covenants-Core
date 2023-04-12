var assert = require("assert");
var utilities = require("../util/utilities");

var compile = require("../util/compile");
var blockchainConnection = require("../util/blockchainConnection");
var dfoManager = require('../util/dfo');
var dfoHubManager = require('../util/dfoHub');
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
var wUSDFarmingExtension;
var wUSDExtensionController;
var usdCollection;
var usdObjectId;
var USDT;
var USDC;
var DAI;
var wusdInteroperable;

describe("WUSDFarm", () => {

    async function buyForETH(token, amount, from) {
        var path = [
            wethToken.options.address,
            token.options.address
        ];
        var value = utilities.toDecimals(amount.toString(), '18');
        await uniswapV2Router.methods.swapExactETHForTokens("1", path, (from && (from.from || from)) || accounts[0], parseInt((new Date().getTime() / 1000) + 1000)).send(blockchainConnection.getSendingOptions({ from: (from && (from.from || from)) || accounts[0], value }));
    };

    async function initActor(name, address, unwrap, amount, amountIsLiquidityPool) {
        actors[name] = {
            name,
            address,
            from: blockchainConnection.getSendingOptions({ from: address }),
            unwrap,
            amount,
            amountIsLiquidityPool
        };

        mainToken !== utilities.voidEthereumAddress && await buyForETH(mainToken, ethToSpend, address);
        secondaryToken !== utilities.voidEthereumAddress && await buyForETH(secondaryToken, ethToSpend, address);

    };

    function fromTokenToStable(amount, decimals) {
        if (utilities.formatNumber(decimals) === 18) {
            return amount;
        }
        return utilities.toDecimals(amount, 18 - utilities.formatNumber(decimals));
    }

    function fromStableToToken(amount, decimals) {
        if (utilities.formatNumber(decimals) === 18) {
            return amount;
        }
        return utilities.fromDecimals(amount, 18 - utilities.formatNumber(decimals));
    }

    async function tokenData(token, method) {
        try {
            return await token.methods[method]().call();
        } catch (e) {}
        var name;
        try {
            var to = token.options ? token.options.address : token;
            var raw = await web3.eth.call({
                to,
                data: web3.utils.sha3(`${method}()`).substring(0, 10)
            });
            name = web3.utils.toUtf8(raw);
        } catch (e) {
            name = "";
        }
        name = name.trim();
        if (name) {
            return name;
        }
        if (!token.options || !token.options.address) {
            return "ETH";
        }
    }

    async function calculatePercentage(totalAmount, percentage) {
        var ONE_HUNDRED = await wUSDExtensionController.methods.ONE_HUNDRED().call();
        var amount = web3.utils.toBN(totalAmount).mul(web3.utils.toBN(percentage).mul(web3.utils.toBN(1e18)).div(web3.utils.toBN(ONE_HUNDRED))).div(web3.utils.toBN(1e18));
        return amount.toString();
    }

    async function createStakingPosition(actor, setupIndex) {
        (mainToken !== utilities.voidEthereumAddress) && await mainToken.methods.approve(farmMainContract.options.address, await mainToken.methods.totalSupply().call()).send(actor.from);
        (secondaryToken !== utilities.voidEthereumAddress) && await secondaryToken.methods.approve(farmMainContract.options.address, await secondaryToken.methods.totalSupply().call()).send(actor.from);

        var mainTokenAmount = utilities.toDecimals(actor.amount, mainToken !== utilities.voidEthereumAddress ? await mainToken.methods.decimals().call() : 18);
        var stake = {
            setupIndex,
            amount: mainTokenAmount,
            amountIsLiquidityPool: actor.amountIsLiquidityPool || false,
            positionOwner: utilities.voidEthereumAddress,
        };

        var setups = await farmMainContract.methods.setups().call();
        console.log(setups);
        var setup = setups[setupIndex];
        var setupInfo = await farmMainContract.methods._setupsInfo(setup.infoIndex).call();
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
                ).send({...actor.from, value: secondaryToken !== utilities.voidEthereumAddress ? mainTokenAmount : secondaryTokenAmount });
            }

            var liquidityPoolTokenContract = new web3.eth.Contract(context.IERC20ABI, liquidityPoolTokenAddress);
            await liquidityPoolTokenContract.methods.approve(farmMainContract.options.address, await liquidityPoolTokenContract.methods.totalSupply().call()).send(actor.from);
            stake.amount = await liquidityPoolTokenContract.methods.balanceOf(actor.address).call();
        }

        var result = await farmMainContract.methods.openPosition(stake).send({...actor.from, value: (!stake.amountIsLiquidityPool) ? mainToken === utilities.voidEthereumAddress ? mainTokenAmount : secondaryTokenAmount : 0 });
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
        var setupInfo = await farmMainContract.methods._setupsInfo(startingSetup.infoIndex).call();
        var ammPlugin = new web3.eth.Contract(UniswapV2AMMV1.abi, setupInfo.ammPlugin);
        var liquidityPoolTokenAddress = setupInfo.liquidityPoolTokenAddress;
        var tokens = (await ammPlugin.methods.byLiquidityPool(liquidityPoolTokenAddress).call())[2];
        var secondaryTokenIndex = tokens[0] === (secondaryToken != utilities.voidEthereumAddress ? secondaryToken.options.address : wethToken.options.address) ? 0 : 1;
        var amounts = await ammPlugin.methods.byTokenAmount(liquidityPoolTokenAddress, mainToken != utilities.voidEthereumAddress ? mainToken.options.address : wethToken.options.address, mainTokenAmount).call();
        var secondaryTokenAmount = amounts[1][secondaryTokenIndex];

        var stake = {
            setupIndex: actor.setupIndex,
            amount: mainTokenAmount,
            amountIsLiquidityPool: actor.amountIsLiquidityPool || false,
            positionOwner: utilities.voidEthereumAddress,
        };
        await farmMainContract.methods.addLiquidity(actor.positionId, stake).send({...actor.from, value: (!stake.amountIsLiquidityPool) ? mainToken === utilities.voidEthereumAddress ? mainTokenAmount : secondaryTokenAmount : 0 });
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

    async function getUSD(ammPosition, liquidityPoolPosition, maxAmountPerToken, byLiquidityPool) {
        var allowed = await wUSDExtensionController.methods.allowedAMMs().call();

        var usdBalanceBefore = await usdCollection.methods.balanceOf(accounts[0], usdObjectId).call();

        var amm = new web3.eth.Contract((await compile("amm-aggregator/common/IAMM")).abi, allowed[ammPosition][0]);

        var liquidityPoolAddress = allowed[ammPosition][1][liquidityPoolPosition];
        var maxuSDExpected = maxAmountPerToken * 2;
        var value = utilities.toDecimals(maxuSDExpected, 18);
        maxuSDExpected = web3.utils.toBN(value).add(web3.utils.toBN(usdBalanceBefore)).toString();

        maxuSDExpected = utilities.fromDecimals(maxuSDExpected, 18);
        usdBalanceBefore = parseFloat(utilities.fromDecimals(usdBalanceBefore, "18", true));

        var liquidityPoolData = await amm.methods.byLiquidityPool(liquidityPoolAddress).call();

        var liquidityPoolTokens = liquidityPoolData[2].map(it => new web3.eth.Contract(context.IERC20ABI, it));
        var token0 = parseInt(fromTokenToStable(liquidityPoolData[1][0], await liquidityPoolTokens[0].methods.decimals().call()));
        var token1 = parseInt(fromTokenToStable(liquidityPoolData[1][1], await liquidityPoolTokens[1].methods.decimals().call()));
        var ratio = token0 / token1;
        var firstTokenUsD = (utilities.formatNumber(value) * ratio) / 2;
        firstTokenUsD = await fromStableToToken(firstTokenUsD, await liquidityPoolTokens[0].methods.decimals().call());
        firstTokenUsD = utilities.numberToString(firstTokenUsD).split('.').join('');

        var byTokenAmount = await amm.methods.byTokenAmount(liquidityPoolAddress, liquidityPoolTokens[0].options.address, utilities.numberToString(firstTokenUsD)).call();

        var secondTokenValue = byTokenAmount[1][1];

        var firstTokenStable = fromTokenToStable(firstTokenUsD, await liquidityPoolTokens[0].methods.decimals().call());
        var secondTokenStable = fromTokenToStable(secondTokenValue, await liquidityPoolTokens[1].methods.decimals().call());

        var stableCoinOutput = utilities.formatNumber(web3.utils.toBN(firstTokenStable).add(web3.utils.toBN(secondTokenStable)).toString());

        var rate = utilities.formatNumber(value) / stableCoinOutput;

        firstTokenUsD = utilities.numberToString(utilities.formatNumber(firstTokenUsD) * rate).split('.')[0];
        secondTokenValue = utilities.numberToString(utilities.formatNumber(secondTokenValue) * rate).split('.')[0];

        byTokenAmount = await amm.methods.byTokenAmount(liquidityPoolAddress, liquidityPoolTokens[0].options.address, firstTokenUsD).call();

        liquidityPoolAmount = byTokenAmount[0];

        var byLiquidityPoolData = await amm.methods.byLiquidityPoolAmount(liquidityPoolAddress, liquidityPoolAmount).call();

        var exactAmountIndex = 0;
        var otherAmountIndex = 1;

        var amountsPlain = [
            utilities.formatNumber(utilities.fromDecimals(byLiquidityPoolData[0][0], await liquidityPoolTokens[0].methods.decimals().call())),
            utilities.formatNumber(utilities.fromDecimals(byLiquidityPoolData[0][1], await liquidityPoolTokens[1].methods.decimals().call())),
        ]

        var expectedUsdBalance = utilities.formatMoney(usdBalanceBefore + amountsPlain[0] + amountsPlain[1]);

        var exactBalanceOfBefore = await liquidityPoolTokens[exactAmountIndex].methods.balanceOf(accounts[0]).call();
        exactBalanceOfBefore = utilities.fromDecimals(exactBalanceOfBefore, await liquidityPoolTokens[exactAmountIndex].methods.decimals().call(), true);
        console.log(exactBalanceOfBefore, await tokenData(liquidityPoolTokens[exactAmountIndex], "symbol"));
        exactBalanceOfBefore = parseFloat(exactBalanceOfBefore);

        var exactBalanceOfExpected = exactBalanceOfBefore - amountsPlain[exactAmountIndex];
        exactBalanceOfExpected = utilities.formatMoney(exactBalanceOfExpected);

        var otherBalanceOfBefore = await liquidityPoolTokens[otherAmountIndex].methods.balanceOf(accounts[0]).call();
        otherBalanceOfBefore = utilities.fromDecimals(otherBalanceOfBefore, await liquidityPoolTokens[otherAmountIndex].methods.decimals().call(), true);
        console.log(otherBalanceOfBefore, await tokenData(liquidityPoolTokens[otherAmountIndex], "symbol"));
        otherBalanceOfBefore = parseFloat(otherBalanceOfBefore);

        var otherBalanceOfExpected = otherBalanceOfBefore - amountsPlain[otherAmountIndex];
        otherBalanceOfExpected = utilities.formatMoney(otherBalanceOfExpected);

        console.log(amountsPlain);

        try {
            await liquidityPoolTokens[0].methods.approve(byLiquidityPool ? amm.options.address : wUSDExtensionController.options.address, await liquidityPoolTokens[0].methods.totalSupply().call()).send(blockchainConnection.getSendingOptions());
        } catch (e) {}
        try {
            await liquidityPoolTokens[1].methods.approve(byLiquidityPool ? amm.options.address : wUSDExtensionController.options.address, await liquidityPoolTokens[1].methods.totalSupply().call()).send(blockchainConnection.getSendingOptions());
        } catch (e) {}

        if (byLiquidityPool) {
            await amm.methods.addLiquidity({
                liquidityPoolAddress,
                amount: liquidityPoolAmount,
                tokenAddress: utilities.voidEthereumAddress,
                amountIsLiquidityPool: true,
                involvingETH: false,
                receiver: accounts[0]
            }).send(blockchainConnection.getSendingOptions());

            var pair = new web3.eth.Contract(context.IERC20ABI, liquidityPoolAddress);
            liquidityPoolAmount = await pair.methods.balanceOf(accounts[0]).call();
            await pair.methods.approve(wUSDExtensionController.options.address, await pair.methods.totalSupply().call()).send(blockchainConnection.getSendingOptions());
        }

        await wUSDExtensionController.methods.addLiquidity(ammPosition, liquidityPoolPosition, liquidityPoolAmount, byLiquidityPool).send(blockchainConnection.getSendingOptions());

        var usdBalanceAfter = await usdCollection.methods.balanceOf(accounts[0], usdObjectId).call();
        usdBalanceAfter = utilities.formatMoney(parseFloat(utilities.fromDecimals(usdBalanceAfter, "18", true)));

        var exactBalanceOfAfter = await liquidityPoolTokens[exactAmountIndex].methods.balanceOf(accounts[0]).call();
        exactBalanceOfAfter = utilities.fromDecimals(exactBalanceOfAfter, await liquidityPoolTokens[exactAmountIndex].methods.decimals().call(), true);
        exactBalanceOfAfter = parseFloat(exactBalanceOfAfter);
        exactBalanceOfAfter = utilities.formatMoney(exactBalanceOfAfter);

        console.log(exactBalanceOfAfter, exactBalanceOfExpected);
        try {
            assert.strictEqual(exactBalanceOfAfter, exactBalanceOfExpected);
        } catch (e) {
            console.error(e.message);
        }

        var otherBalanceOfAfter = await liquidityPoolTokens[otherAmountIndex].methods.balanceOf(accounts[0]).call();
        otherBalanceOfAfter = utilities.fromDecimals(otherBalanceOfAfter, await liquidityPoolTokens[otherAmountIndex].methods.decimals().call(), true);
        otherBalanceOfAfter = parseFloat(otherBalanceOfAfter);
        otherBalanceOfAfter = utilities.formatMoney(otherBalanceOfAfter);

        console.log(otherBalanceOfAfter, otherBalanceOfExpected);
        try {
            assert.strictEqual(otherBalanceOfAfter, otherBalanceOfExpected);
        } catch (e) {
            console.error(e.message);
        }

        console.log(utilities.formatNumber(maxuSDExpected), utilities.formatNumber(usdBalanceAfter), utilities.formatNumber(expectedUsdBalance));
        try {
            assert(utilities.formatNumber(maxuSDExpected) >= utilities.formatNumber(usdBalanceAfter) && utilities.formatNumber(usdBalanceAfter) >= utilities.formatNumber(expectedUsdBalance));
        } catch (e) {
            console.error(e.message);
        }
    };

    before(async() => {
        try {
            await blockchainConnection.init;
            await dfoHubManager.init;

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

            var rewardTokenAddress = context.daiTokenAddress; //dfo.votingTokenAddress;
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

            uniswapAMM = await new web3.eth.Contract(UniswapV2AMMV1.abi, context.uniswapAmmAddress);

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

            USDT = new web3.eth.Contract(context.IERC20ABI, context.usdtTokenAddress);
            USDC = new web3.eth.Contract(context.IERC20ABI, context.usdcTokenAddress);
            DAI = new web3.eth.Contract(context.IERC20ABI, context.daiTokenAddress);
    
            await buyForETH(USDT, 50);
            await buyForETH(USDC, 50);
            await buyForETH(DAI, 50);
        } catch (error) {
            console.error(error);
        }
    });

    it("should deploy farm factory, extensions and finalize proposals", async() => {
        try {

            farmFactory = new web3.eth.Contract(FarmFactory.abi, "0x6BC8530fecc0001b9FC0bf5DAA17873e847616ed");
            console.log(`farm factory deployed at ${farmFactory.options.address}`);

            dFOBasedFarmExtensionFactory = new web3.eth.Contract(DFOBasedFarmExtensionFactory.abi, "0x7ee9297dabB036cAa6F526dD0459315c7237e017");
            console.log(`dfo based farm extension factory deployed at ${dFOBasedFarmExtensionFactory.options.address}`);

            var transaction = await dFOBasedFarmExtensionFactory.methods.cloneModel().send(blockchainConnection.getSendingOptions());
            var receipt = await web3.eth.getTransactionReceipt(transaction.transactionHash);
            var farmMainExtensionAddress = web3.eth.abi.decodeParameter("address", receipt.logs.filter(it => it.topics[0] === web3.utils.sha3('ExtensionCloned(address,address)'))[0].topics[1])
            farmMainExtension = new web3.eth.Contract(FarmExtension.abi, farmMainExtensionAddress);
            console.log(`simple farm extension deployed at ${farmMainExtension.options.address}`);

            var WUSDFarmingExtension = await compile('WUSD/WUSDFarmingExtension');
            wUSDFarmingExtension = await new web3.eth.Contract(WUSDFarmingExtension.abi, "0xc90825B09B1F31D2872788CdaBb1A259F110D30F");

            var WUSDExtensionController = await compile("WUSD/WUSDExtensionController");
            wUSDExtensionController = new web3.eth.Contract(WUSDExtensionController.abi, context.wusdExtensionControllerAddress);

            var data = await wUSDExtensionController.methods.wusdInfo().call();
            usdCollection = new web3.eth.Contract(context.ethItemNativeABI, data[0]);
            usdObjectId = data[1];

            wusdInteroperable = new web3.eth.Contract(context.IERC20ABI, data[2]);

        } catch (error) {
            console.error(`error is`, error);
        }
    });

    async function getInfos() {

        var wusdETH = (await uniswapAMM.methods.byTokens([context.wusdInteroperableAddress, context.wethTokenAddress]).call())[2];
        var wusdUSDC = (await uniswapAMM.methods.byTokens([context.wusdInteroperableAddress, context.usdcTokenAddress]).call())[2];

        var infos = [
            {
                free: true,
                blockDuration: 192000,
                originalRewardPerBlock: 0,
                minStakeable: 0,
                maxStakeable: 0,
                renewTimes: 0,
                ammPlugin: uniswapAMM.options.address,
                liquidityPoolTokenAddress: wusdETH,
                mainTokenAddress: context.wusdInteroperableAddress,
                ethereumAddress: utilities.voidEthereumAddress,
                involvingETH: true,
                penaltyFee: 0,
                setupsCount: 0,
                lastSetupIndex: 0
            }, {
                free: true,
                blockDuration: 192000,
                originalRewardPerBlock: 0,
                minStakeable: 0,
                maxStakeable: 0,
                renewTimes: 0,
                ammPlugin: uniswapAMM.options.address,
                liquidityPoolTokenAddress: wusdUSDC,
                mainTokenAddress: context.wusdInteroperableAddress,
                ethereumAddress: utilities.voidEthereumAddress,
                involvingETH: false,
                penaltyFee: 0,
                setupsCount: 0,
                lastSetupIndex: 0
            }
        ];

        var percentages = [utilities.toDecimals("0.4", 18)];

        return {infos, percentages};
    }

    it("should deploy simple farm main contract", async() => {

        var {infos, percentages} = await getInfos();

        console.log(infos, percentages);

        console.log(dfoHubManager.dfos.covenants.doubleProxyAddress, context.wusdExtensionControllerAddress, ethItemOrchestrator.options.address, context.wusdInteroperableAddress);

        var extensionPayload = wUSDFarmingExtension.methods.init(
            dfoHubManager.dfos.covenants.doubleProxyAddress,
            context.wusdExtensionControllerAddress,
            infos,
            percentages,
            utilities.toDecimals("0.867", 18)
        ).encodeABI();

        var types = [
            "address",
            "bytes",
            "address",
            "address",
            "bytes",
        ];

        var params = [
            wUSDFarmingExtension.options.address,
            extensionPayload,
            ethItemOrchestrator.options.address,
            context.wusdInteroperableAddress,
            "0x",
        ];

        var payload = web3.utils.sha3(`init(${types.join(',')})`).substring(0, 10) + (web3.eth.abi.encodeParameters(types, params).substring(2));

        console.log(payload);

        var deployTransaction = await farmFactory.methods.deploy(payload).send(blockchainConnection.getSendingOptions());
        deployTransaction = await web3.eth.getTransactionReceipt(deployTransaction.transactionHash);
        var farmMainContractAddress = web3.eth.abi.decodeParameter("address", deployTransaction.logs.filter(it => it.topics[0] === web3.utils.sha3("FarmMainDeployed(address,address,bytes)"))[0].topics[1]);

        farmMainContract = await new web3.eth.Contract(FarmMain.abi, farmMainContractAddress);
    });

    it("WUSD Extension Controller update Proposal", async () => {
        var rebalanceByCreditReceivers = `rebalanceByCreditReceivers[0] = ${web3.utils.toChecksumAddress(wUSDFarmingExtension.options.address)};` 
        var rebalanceByCreditPercentages = `rebalanceByCreditPercentages[0] = ${utilities.toDecimals("0.4", 18)};` 
        var length = 1;
        var currentPercentage = (await wUSDExtensionController.methods.rebalanceByCreditReceiversInfo().call())[2];
        currentPercentage = 0;
        console.log(await wUSDExtensionController.methods.rebalanceByCreditReceiversInfo().call());
        console.log(utilities.fromDecimals((await wUSDExtensionController.methods.rebalanceByCreditReceiversInfo().call())[2], 18));
        console.log(utilities.fromDecimals((await wUSDExtensionController.methods.wusdNote2Info().call())[4], 18));
        console.log(utilities.fromDecimals((await wUSDExtensionController.methods.wusdNote5Info().call())[4], 18));
        var fileName = '2';
        var code = fs.readFileSync(path.resolve(__dirname, '..', `resources/WUSDNewRebalanceTimeAndFarmingExtension${fileName}.sol`), 'UTF-8').format(context.wusdExtensionControllerAddress, 192000, length, rebalanceByCreditReceivers, rebalanceByCreditPercentages, currentPercentage, wUSDFarmingExtension.options.address);
        console.log(code);
        var proposal;
        if(fileName) {
            proposal = await dfoHubManager.createProposal("covenants", "manageFarming", true, code, "manageFarming(address,uint256,bool,address,address,uint256,bool)", false, true, "manageFarming");
        } else {
            proposal = await dfoHubManager.createProposal("covenants", "", true, code, "callOneTime(address)");
        }
        await dfoHubManager.finalizeProposal(proposal);
        console.log(await wUSDExtensionController.methods.rebalanceByCreditReceiversInfo().call());
    });

    async function rebalanceByCredit() {
        await getUSD(0, 0, 10000 , false);

        await usdCollection.methods.burn(usdObjectId, utilities.toDecimals(8000, 18)).send(blockchainConnection.getSendingOptions());

        var differences = await wUSDExtensionController.methods.differences().call();
        var credit = differences[0];
        console.log(credit);
        console.log(utilities.fromDecimals(credit, 18));

        var rebalanceByCreditReceiversInfo = await wUSDExtensionController.methods.rebalanceByCreditReceiversInfo().call();

        var receivers = rebalanceByCreditReceiversInfo[0].map(it => it);
        receivers.push(accounts[0]);

        var percentages = rebalanceByCreditReceiversInfo[1].map(it => it);
        percentages.push(rebalanceByCreditReceiversInfo[2]);

        var noteInfo = await wUSDExtensionController.methods.wusdNote2Info().call();
        receivers.push(noteInfo[3]);
        percentages.push(noteInfo[4]);

        noteInfo = await wUSDExtensionController.methods.wusdNote5Info().call();
        receivers.push(noteInfo[3]);
        percentages.push(noteInfo[4]);

        receivers.push(rebalanceByCreditReceiversInfo[3]);

        var totalPercentage = '0';
        percentages.forEach(it => totalPercentage = web3.utils.toBN(totalPercentage).add(web3.utils.toBN(it)).toString());
        percentages.push(web3.utils.toBN(await wUSDExtensionController.methods.ONE_HUNDRED().call()).sub(web3.utils.toBN(totalPercentage)).toString());

        var adds = [];
        for (var percentage of percentages) {
            adds.push(await calculatePercentage(credit, percentage));
        }

        var sum = '0';
        adds.forEach(it => sum = web3.utils.toBN(sum).add(web3.utils.toBN(it)).toString());

        credit = await utilities.fromDecimals(credit, 18);
        sum = await utilities.fromDecimals(sum, 18);

        assert.strictEqual(credit, sum);

        var expecteds = [];
        for (var i in receivers) {
            var balance = await usdCollection.methods.balanceOf(receivers[i], usdObjectId).call();
            balance = web3.utils.toBN(balance).add(web3.utils.toBN(adds[i])).toString();
            expecteds.push(utilities.fromDecimals(balance, 18));
        }

        await wUSDExtensionController.methods.rebalanceByCredit().send(blockchainConnection.getSendingOptions());

        for (var i in receivers) {
            var balance = await usdCollection.methods.balanceOf(receivers[i], usdObjectId).call();
            balance = utilities.fromDecimals(balance, 18);
            assert.strictEqual(balance, expecteds[i]);
        }
    }

    async function logSetups() {
        var length = await farmMainContract.methods._farmingSetupsCount().call();
        for(var i = 0; i < length; i++) {
            console.log(await farmMainContract.methods.setup(i).call());
        }
    }

    it("Cannot rebalance", async () => {
        try {
            await wUSDFarmingExtension.methods.rebalanceRewardsPerBlock().send(blockchainConnection.getSendingOptions());
            assert(false);
        } catch(e) {
            assert.notStrictEqual((e.message || e).indexOf("Invalid block"), -1);
        }
    });

    it("Rebalance By Credit by Burn 1", rebalanceByCredit);

    it("Rebalance Farm 1", async () => {
        var expectedBalance = await wusdInteroperable.methods.balanceOf(wUSDFarmingExtension.options.address).call();
        var expectedDFOBalance = await wusdInteroperable.methods.balanceOf(dfoHubManager.dfos.covenants.mvdWalletAddress).call();
        var percentage = await wUSDFarmingExtension.methods.rewardCreditPercentage().call();
        var amount = await calculatePercentage(expectedDFOBalance, percentage);
        console.log("Before:", expectedBalance, expectedDFOBalance, amount);
        expectedBalance = web3.utils.toBN(expectedBalance).add(web3.utils.toBN(amount)).toString();
        expectedDFOBalance = web3.utils.toBN(expectedDFOBalance).sub(web3.utils.toBN(amount)).toString();
        console.log("After:", expectedBalance, expectedDFOBalance);
        await wUSDFarmingExtension.methods.rebalanceRewardsPerBlock().send(blockchainConnection.getSendingOptions());
        var balance = await wusdInteroperable.methods.balanceOf(wUSDFarmingExtension.options.address).call();
        var dFOBalance = await wusdInteroperable.methods.balanceOf(dfoHubManager.dfos.covenants.mvdWalletAddress).call();
        expectedBalance = utilities.fromDecimals(expectedBalance, 18);
        expectedDFOBalance = utilities.fromDecimals(expectedDFOBalance, 18);
        balance = utilities.fromDecimals(balance, 18);
        dFOBalance = utilities.fromDecimals(dFOBalance, 18);

        console.log(balance, expectedBalance);
        console.log(dFOBalance, expectedDFOBalance);
        assert.strictEqual(balance, expectedBalance);
        assert.strictEqual(dFOBalance, expectedDFOBalance);
    });

    it("Fair", async () => {
        try {
            await wUSDFarmingExtension.methods.rebalanceRewardsPerBlock().send(blockchainConnection.getSendingOptions());
            assert(false);
        } catch(e) {
            assert.notStrictEqual((e.message || e).indexOf("Invalid block"), -1);
        }
    });

    it("should activate both the setup 1", async () => {
        await farmMainContract.methods.activateSetup(0).send(blockchainConnection.getSendingOptions());
    });

    it("Change Models", async () => {

        console.log(await wUSDFarmingExtension.methods.models().call());

        var {infos, percentages} = await getInfos();

        infos.splice(0, 1);
        percentages = [];

        var infosCode = infos.map((it, i) => `        farmingSetups[${i}] = FarmingSetupInfo(${it.free}, ${it.blockDuration}, ${it.originalRewardPerBlock}, ${it.minStakeable}, ${it.maxStakeable}, ${it.renewTimes}, ${it.ammPlugin}, ${it.liquidityPoolTokenAddress}, ${it.mainTokenAddress}, ${it.ethereumAddress}, ${it.involvingETH}, ${it.penaltyFee}, ${it.setupsCount}, ${it.lastSetupIndex});`).join('\n').trim('');
        var percentagesCode = percentages.map((it, i) => `rebalancePercentages[${i}] = ${utilities.numberToString(it)};`).join('\n').trim();

        var code = fs.readFileSync(path.resolve(__dirname, '..', `resources/WUSDSetModelsAndPercentages.sol`), 'UTF-8').format(infos.length, infosCode, percentages.length, percentagesCode, wUSDFarmingExtension.options.address);
        console.log(code);
        var proposal = await dfoHubManager.createProposal("covenants", "", true, code, "callOneTime(address)");
        await dfoHubManager.finalizeProposal(proposal);

        console.log(await wUSDFarmingExtension.methods.models().call());
    });

    it("Change Models 2", async() => {

        console.log(await wUSDFarmingExtension.methods.models().call());

        var {infos, percentages} = await getInfos();

        var infosCode = infos.map((it, i) => `        farmingSetups[${i}] = FarmingSetupInfo(${it.free}, ${it.blockDuration}, ${it.originalRewardPerBlock}, ${it.minStakeable}, ${it.maxStakeable}, ${it.renewTimes}, ${it.ammPlugin}, ${it.liquidityPoolTokenAddress}, ${it.mainTokenAddress}, ${it.ethereumAddress}, ${it.involvingETH}, ${it.penaltyFee}, ${it.setupsCount}, ${it.lastSetupIndex});`).join('\n').trim('');
        var percentagesCode = percentages.map((it, i) => `rebalancePercentages[${i}] = ${utilities.numberToString(it)};`).join('\n').trim();

        var code = fs.readFileSync(path.resolve(__dirname, '..', `resources/WUSDSetModelsAndPercentages.sol`), 'UTF-8').format(infos.length, infosCode, percentages.length, percentagesCode, wUSDFarmingExtension.options.address);
        console.log(code);
        var proposal = await dfoHubManager.createProposal("covenants", "", true, code, "callOneTime(address)");
        await dfoHubManager.finalizeProposal(proposal);

        console.log(await wUSDFarmingExtension.methods.models().call());
    });

    it("Rebalance By Credit by Burn 2", async () => {
        await blockchainConnection.fastForward(await wUSDExtensionController.methods.rebalanceByCreditBlockInterval().call());
        await rebalanceByCredit();
    });

    it("Rebalance Farm 2", async () => {
        var expectedBalance = await wusdInteroperable.methods.balanceOf(wUSDFarmingExtension.options.address).call();
        var expectedDFOBalance = await wusdInteroperable.methods.balanceOf(dfoHubManager.dfos.covenants.mvdWalletAddress).call();
        var percentage = await wUSDFarmingExtension.methods.rewardCreditPercentage().call();
        var amount = await calculatePercentage(expectedDFOBalance, percentage);
        console.log("Before:", expectedBalance, expectedDFOBalance, amount);
        expectedBalance = web3.utils.toBN(expectedBalance).add(web3.utils.toBN(amount)).toString();
        expectedDFOBalance = web3.utils.toBN(expectedDFOBalance).sub(web3.utils.toBN(amount)).toString();
        console.log("After:", expectedBalance, expectedDFOBalance);
        await wUSDFarmingExtension.methods.rebalanceRewardsPerBlock().send(blockchainConnection.getSendingOptions());
        var balance = await wusdInteroperable.methods.balanceOf(wUSDFarmingExtension.options.address).call();
        var dFOBalance = await wusdInteroperable.methods.balanceOf(dfoHubManager.dfos.covenants.mvdWalletAddress).call();
        expectedBalance = utilities.fromDecimals(expectedBalance, 18);
        expectedDFOBalance = utilities.fromDecimals(expectedDFOBalance, 18);
        balance = utilities.fromDecimals(balance, 18);
        dFOBalance = utilities.fromDecimals(dFOBalance, 18);

        console.log(balance, expectedBalance);
        console.log(dFOBalance, expectedDFOBalance);
        assert.strictEqual(balance, expectedBalance);
        assert.strictEqual(dFOBalance, expectedDFOBalance);
    });

    it("should activate both the setups 2", async () => {
        await farmMainContract.methods.activateSetup(1).send(blockchainConnection.getSendingOptions());
        await farmMainContract.methods.activateSetup(2).send(blockchainConnection.getSendingOptions());
    });

    it("Rebalance By Credit by Burn 3", async () => {
        await blockchainConnection.fastForward(await wUSDExtensionController.methods.rebalanceByCreditBlockInterval().call());
        await rebalanceByCredit();
    });

    it("Rebalance Farm 3", async () => {
        var expectedBalance = await wusdInteroperable.methods.balanceOf(wUSDFarmingExtension.options.address).call();
        var expectedDFOBalance = await wusdInteroperable.methods.balanceOf(dfoHubManager.dfos.covenants.mvdWalletAddress).call();
        var percentage = await wUSDFarmingExtension.methods.rewardCreditPercentage().call();
        var amount = await calculatePercentage(expectedDFOBalance, percentage);
        console.log("Before:", expectedBalance, expectedDFOBalance, amount);
        expectedBalance = web3.utils.toBN(expectedBalance).add(web3.utils.toBN(amount)).toString();
        expectedDFOBalance = web3.utils.toBN(expectedDFOBalance).sub(web3.utils.toBN(amount)).toString();
        console.log("After:", expectedBalance, expectedDFOBalance);
        await wUSDFarmingExtension.methods.rebalanceRewardsPerBlock().send(blockchainConnection.getSendingOptions());
        var balance = await wusdInteroperable.methods.balanceOf(wUSDFarmingExtension.options.address).call();
        var dFOBalance = await wusdInteroperable.methods.balanceOf(dfoHubManager.dfos.covenants.mvdWalletAddress).call();
        expectedBalance = utilities.fromDecimals(expectedBalance, 18);
        expectedDFOBalance = utilities.fromDecimals(expectedDFOBalance, 18);
        balance = utilities.fromDecimals(balance, 18);
        dFOBalance = utilities.fromDecimals(dFOBalance, 18);

        console.log(balance, expectedBalance);
        console.log(dFOBalance, expectedDFOBalance);
        assert.strictEqual(balance, expectedBalance);
        assert.strictEqual(dFOBalance, expectedDFOBalance);
    });

    it("should activate both the setups 3", async () => {
        await farmMainContract.methods.activateSetup(3).send(blockchainConnection.getSendingOptions());
        await farmMainContract.methods.activateSetup(4).send(blockchainConnection.getSendingOptions());
    });

    it("Rebalance Farm 4", async () => {
        await blockchainConnection.fastForward(await wUSDExtensionController.methods.rebalanceByCreditBlockInterval().call());
        await rebalanceByCredit();
        await blockchainConnection.fastForward(await wUSDExtensionController.methods.rebalanceByCreditBlockInterval().call());
        await rebalanceByCredit();
        await rebalanceFarm();
    });

    async function rebalanceFarm() {
        var expectedBalance = await wusdInteroperable.methods.balanceOf(wUSDFarmingExtension.options.address).call();
        var expectedDFOBalance = await wusdInteroperable.methods.balanceOf(dfoHubManager.dfos.covenants.mvdWalletAddress).call();
        var percentage = await wUSDFarmingExtension.methods.rewardCreditPercentage().call();
        var amount = await calculatePercentage(expectedDFOBalance, percentage);
        console.log("Before:", expectedBalance, expectedDFOBalance, amount);
        expectedBalance = web3.utils.toBN(expectedBalance).add(web3.utils.toBN(amount)).toString();
        expectedDFOBalance = web3.utils.toBN(expectedDFOBalance).sub(web3.utils.toBN(amount)).toString();
        console.log("After:", expectedBalance, expectedDFOBalance);
        await wUSDFarmingExtension.methods.rebalanceRewardsPerBlock().send(blockchainConnection.getSendingOptions());
        var balance = await wusdInteroperable.methods.balanceOf(wUSDFarmingExtension.options.address).call();
        var dFOBalance = await wusdInteroperable.methods.balanceOf(dfoHubManager.dfos.covenants.mvdWalletAddress).call();
        expectedBalance = utilities.fromDecimals(expectedBalance, 18);
        expectedDFOBalance = utilities.fromDecimals(expectedDFOBalance, 18);
        balance = utilities.fromDecimals(balance, 18);
        dFOBalance = utilities.fromDecimals(dFOBalance, 18);

        console.log(balance, expectedBalance);
        console.log(dFOBalance, expectedDFOBalance);
        assert.strictEqual(balance, expectedBalance);
        assert.strictEqual(dFOBalance, expectedDFOBalance);
    }

    it("should activate both the setups 4", async () => {
        await farmMainContract.methods.activateSetup(5).send(blockchainConnection.getSendingOptions());
        await farmMainContract.methods.activateSetup(6).send(blockchainConnection.getSendingOptions());
        await farmMainContract.methods.activateSetup(7).send(blockchainConnection.getSendingOptions());
        try {
            await farmMainContract.methods.activateSetup(8).send(blockchainConnection.getSendingOptions());
            assert(false);
        } catch(e) {
            assert.notStrictEqual((e.message || e).indexOf("Invalid toggle"), -1);
        }
    });
})
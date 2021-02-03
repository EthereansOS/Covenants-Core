var assert = require("assert");
var utilities = require("../util/utilities");
var context = require("../util/context.json");
var compile = require("../util/compile");
var blockchainConnection = require("../util/blockchainConnection");
var dfoManager = require("../util/dfo");
var ethers = require('ethers');
var abi = new ethers.utils.AbiCoder();
var path = require('path');
var fs = require('fs');

describe("WUSD", () => {

    var WUSDExtensionController;
    var WUSDExtension;
    var UniswapV2AMMV1;
    var WUSDNoteController;

    var ethItemOrchestrator;
    var ethItemKnowledgeBase;
    var ethItemERC20Wrapper;
    var uniswapV2Router;
    var uniswapV2Factory;
    var wethToken;
    var USDC;
    var USDT;
    var DAI;
    var USDCItemObjectId;
    var USDTItemObjectId;
    var DAIItemObjectId;
    var uniswapAMM;
    var dfo;
    var allowedAMMS;
    var wusdNote2Controller;
    var wusdNote5Controller;
    var usdController;
    var usdCollection;
    var usdObjectId;
    var usdCreditObjectId;

    async function encodeRealAMMV2Params() {
        allowedAMMS = [
            [
                web3.utils.toChecksumAddress("0xFC1665BD717dB247CDFB3a08b1d496D1588a6340"), [
                    await uniswapV2Factory.methods.getPair(DAI.options.address, USDC.options.address).call()
                ]
            ]
        ];
        var types = ['tuple(address,address[])[]'];
        var params = [allowedAMMS];
        var encoded = abi.encode(types, params);
        return encoded;
    };

    async function encodeRealWUSDControllerInitializer() {
        var wUSDInitializer = {
            doubleProxyAddress : web3.utils.toChecksumAddress("0xF869538e3904778A0cb1FF620C8E83c7df36B946"),
            rebalanceByCreditReceivers : [],
            rebalanceByCreditPercentages : [],
            rebalanceByCreditPercentageForCaller : utilities.toDecimals("0.02", 18),
            rebalanceByCreditBlockInterval : 90000,
            allowedAMMsBytes : await encodeRealAMMV2Params(),
            wusdExtension : utilities.voidEthereumAddress,
            wusdNote2ObjectId : 0,
            wusdNote2Controller : utilities.voidEthereumAddress,
            wusdNote2Percentage : utilities.toDecimals("0.2", 18),
            wusdNote5ObjectId : 0,
            wusdNote5Controller : utilities.voidEthereumAddress,
            wusdNote5Percentage : utilities.toDecimals("0.1", 18),
            orchestratorAddress : web3.utils.toChecksumAddress("0x86ab19d36c38aa81f092eab4b1a8a4b553612465"),
            names : ["Covenants Wrapped USD", "Wrapped USD"],
            symbols : ["WUSD", "WUSD"],
            uris : ["ipfs://ipfs/Qmf6yWyuaazY7CSvf64Q3anFoPQH9MThxGoGgZV5TYqgQv", "ipfs://ipfs/QmTj9k7vq8DqLFuS3TrGGNDaacHL2cTgLjJ6Tu8ZbKwTHm"]
        };
        var wusdInitializerBytes = encodeWUSDInitializer(wUSDInitializer);
        console.log("====");
        console.log(wusdInitializerBytes);
        console.log("====");
    }

    before(async() => {

        await blockchainConnection.init;

        WUSDExtension = await compile('WUSD/WUSDExtension');
        WUSDExtensionController = await compile('WUSD/WUSDExtensionController');
        UniswapV2AMMV1 = await compile('amm-aggregator/models/UniswapV2/1/UniswapV2AMMV1');
        WUSDNoteController = await compile('WUSD/WUSDNoteController');

        ethItemOrchestrator = new web3.eth.Contract(context.ethItemOrchestratorABI, context.ethItemOrchestratorAddress);
        ethItemKnowledgeBase = new web3.eth.Contract(context.ethItemKnowledgeBaseABI, await ethItemOrchestrator.methods.knowledgeBase().call());
        ethItemERC20Wrapper = new web3.eth.Contract(context.W20ABI, await ethItemKnowledgeBase.methods.erc20Wrapper().call());
        uniswapV2Router = new web3.eth.Contract(context.uniswapV2RouterABI, context.uniswapV2RouterAddress);
        uniswapV2Factory = new web3.eth.Contract(context.uniswapV2FactoryABI, context.uniswapV2FactoryAddress);

        wethToken = new web3.eth.Contract(context.IERC20ABI, await uniswapV2Router.methods.WETH().call());
        USDT = new web3.eth.Contract(context.IERC20ABI, context.usdtTokenAddress);
        USDC = new web3.eth.Contract(context.IERC20ABI, context.usdcTokenAddress);
        DAI = new web3.eth.Contract(context.IERC20ABI, context.daiTokenAddress);

        await buyForETH(USDT, 50);
        await buyForETH(USDC, 50);
        await buyForETH(DAI, 50);

        USDCItemObjectId = await wrapInItemAndReturnObjectId(USDC, 1000);
        USDTItemObjectId = await wrapInItemAndReturnObjectId(USDT, 1000);
        DAIItemObjectId = await wrapInItemAndReturnObjectId(DAI, 1000);

        uniswapAMM = await new web3.eth.Contract(UniswapV2AMMV1.abi).deploy({ data: UniswapV2AMMV1.bin, arguments: [uniswapV2Router.options.address] }).send(blockchainConnection.getSendingOptions());

        dfo = await dfoManager.createDFO("MyName", "MySymbol", 1000, 100, 10);
    });

    async function buyForETH(token, valuePlain) {
        var path = [
            wethToken.options.address,
            token.options.address
        ];
        var value = utilities.toDecimals(valuePlain.toString(), '18');
        await uniswapV2Router.methods.swapExactETHForTokens("1", path, accounts[0], parseInt((new Date().getTime() / 1000) + 1000)).send(blockchainConnection.getSendingOptions({ value }));
    }

    async function wrapInItemAndReturnObjectId(token, valuePlain) {
        await token.methods.approve(ethItemERC20Wrapper.options.address, await token.methods.totalSupply().call()).send(blockchainConnection.getSendingOptions());
        var value = utilities.toDecimals(valuePlain.toString(), await token.methods.decimals().call());
        await ethItemERC20Wrapper.methods["mint(address,uint256)"](token.options.address, value).send(blockchainConnection.getSendingOptions());
        return await ethItemERC20Wrapper.methods.object(token.options.address).call();
    }

    async function encodeAMMV2Params() {
        allowedAMMS = [
            [
                uniswapAMM.options.address, [
                    await uniswapV2Factory.methods.getPair(DAI.options.address, USDC.options.address).call(),
                    await uniswapV2Factory.methods.getPair(USDT.options.address, USDC.options.address).call(),
                    await uniswapV2Factory.methods.getPair(DAI.options.address, USDT.options.address).call()
                ]
            ]
        ];
        var types = ['tuple(address,address[])[]'];
        var params = [allowedAMMS];
        var encoded = abi.encode(types, params);
        return encoded;
    };

    async function calculatePercentage(totalAmount, percentage) {
        var ONE_HUNDRED = await usdController.methods.ONE_HUNDRED().call();
        var amount = web3.utils.toBN(totalAmount).mul(web3.utils.toBN(percentage).mul(web3.utils.toBN(1e18)).div(web3.utils.toBN(ONE_HUNDRED))).div(web3.utils.toBN(1e18));
        return amount.toString();
    }

    function encodeWUSDInitializer(wUSDInitializer) {
        var types = [
            "address",
            "address[]",
            "uint256[]",
            "uint256",
            "uint256",
            "bytes",
            "address",
            "uint256",
            "address",
            "uint256",
            "uint256",
            "address",
            "uint256",
            "address",
            "string[]",
            "string[]",
            "string[]"
        ];
        types = [`tuple(${types.join(',')})`];
        var params = [[
            wUSDInitializer.doubleProxyAddress,
            wUSDInitializer.rebalanceByCreditReceivers,
            wUSDInitializer.rebalanceByCreditPercentages,
            wUSDInitializer.rebalanceByCreditPercentageForCaller,
            wUSDInitializer.rebalanceByCreditBlockInterval,
            wUSDInitializer.allowedAMMsBytes,
            wUSDInitializer.wusdExtension,
            wUSDInitializer.wusdNote2ObjectId,
            wUSDInitializer.wusdNote2Controller,
            wUSDInitializer.wusdNote2Percentage,
            wUSDInitializer.wusdNote5ObjectId,
            wUSDInitializer.wusdNote5Controller,
            wUSDInitializer.wusdNote5Percentage,
            wUSDInitializer.orchestratorAddress,
            wUSDInitializer.names,
            wUSDInitializer.symbols,
            wUSDInitializer.uris]
        ];
        var encoded = abi.encode(types, params);
        return encoded;
    }

    it("Controller Creation", async() => {
        encodeRealWUSDControllerInitializer();

        wusdNote2Controller = await new web3.eth.Contract(WUSDNoteController.abi).deploy({ data: WUSDNoteController.bin }).send(blockchainConnection.getSendingOptions());
        wusdNote5Controller = await new web3.eth.Contract(WUSDNoteController.abi).deploy({ data: WUSDNoteController.bin }).send(blockchainConnection.getSendingOptions());
        var wUSDInitializer = {
            doubleProxyAddress : dfo.doubleProxyAddress,
            rebalanceByCreditReceivers : [],
            rebalanceByCreditPercentages : [],
            rebalanceByCreditPercentageForCaller : utilities.toDecimals("0.02", 18),
            rebalanceByCreditBlockInterval : 0,
            allowedAMMsBytes : await encodeAMMV2Params(),
            wusdExtension : utilities.voidEthereumAddress,
            wusdNote2ObjectId : 0,
            wusdNote2Controller : wusdNote2Controller.options.address,
            wusdNote2Percentage : utilities.toDecimals("0.125", 18),
            wusdNote5ObjectId : 0,
            wusdNote5Controller : wusdNote5Controller.options.address,
            wusdNote5Percentage : utilities.toDecimals("0.195", 18),
            orchestratorAddress : ethItemOrchestrator.options.address,
            names : ["Wrapped USD", "Wrapped USD"],
            symbols : ["WUSD", "WUSD"],
            uris : ["google.com", "google.com"]
        };
        var wusdInitializerBytes = encodeWUSDInitializer(wUSDInitializer);
        usdController = await new web3.eth.Contract(WUSDExtensionController.abi).deploy({ data: WUSDExtensionController.bin, arguments: [wusdInitializerBytes] }).send(blockchainConnection.getSendingOptions());
        await usdController.methods.initNotes(
            [wusdNote2Controller.options.address, wusdNote5Controller.options.address],
            ["Wrapped USD Note x2", "Wrapped USD Note x5"],
            ["nWUSD2", "nWUSD5"],
            ["google.com", "google.com"]
        ).send(blockchainConnection.getSendingOptions());

        var data = await usdController.methods.wusdInfo().call();
        usdCollection = new web3.eth.Contract(context.ethItemNativeABI, data[0]);
        usdObjectId = data[1];
        data = await usdController.methods.wusdNote2Info().call();
        usdCreditObjectId = data[1];
        uSDExtension = new web3.eth.Contract(WUSDExtension.abi, await usdController.methods.extension().call());

        assert.strictEqual(await uSDExtension.methods.controller().call(), usdController.options.address);
    });
    it("Cannot initialize it again", async() => {
        try {
            await usdController.methods.initNotes(
                [wusdNote2Controller.options.address, wusdNote5Controller.options.address],
                ["Wrapped USD Note x2", "Wrapped USD Note x5"],
                ["nWUSD2", "nWUSD5"],
                ["google.com", "google.com"]
            ).send(blockchainConnection.getSendingOptions());
            assert(false);
        } catch (e) {
            assert(e.message.toLowerCase().indexOf("already init") !== -1);
        }
    });

    it("Change URI", async () => {
        assert.strictEqual(await usdCollection.methods.uri().call(), "google.com")
        assert.strictEqual(await usdCollection.methods.uri(usdObjectId).call(), "google.com");
        var newUri = "mino.com";
        var code = fs.readFileSync(path.resolve(__dirname, '..', 'resources/WUSDChangeURIs.sol'), 'UTF-8').format(usdController.options.address, newUri, usdObjectId);
        var proposal = await dfoManager.createProposal(dfo, "", true, code, "callOneTime(address)");
        await dfoManager.finalizeProposal(dfo, proposal);
        assert.strictEqual(await usdCollection.methods.uri().call(), newUri);
        assert.strictEqual(await usdCollection.methods.uri(usdObjectId).call(), newUri);
        try {
            await usdController.methods.setCollectionUri("mauro.eth").send(blockchainConnection.getSendingOptions());
            assert(false);
        } catch(e) {
            assert.notStrictEqual(e.message.indexOf("Unauthorized"), -1);
        }
        try {
            await usdController.methods.setItemUri(usdObjectId, "mauro.eth").send(blockchainConnection.getSendingOptions());
            assert(false);
        } catch(e) {
            assert.notStrictEqual(e.message.indexOf("Unauthorized"), -1);
        }
    });

    it("Allowed AMMs", async() => {
        var allowed = await usdController.methods.allowedAMMs().call();
        assert.strictEqual(JSON.stringify(allowed), JSON.stringify(allowedAMMS));
    });

    async function getUSD(liquidityPoolPosition, maxAmountPerToken, byLiquidityPool) {

        var usdBalanceBefore = await usdCollection.methods.balanceOf(accounts[0], usdObjectId).call();
        usdBalanceBefore = parseFloat(utilities.fromDecimals(usdBalanceBefore, "18", true));

        var liquidityPoolAddress = allowedAMMS[0][1][liquidityPoolPosition];
        var maxuSDExpected = maxAmountPerToken * 2;
        maxuSDExpected += usdBalanceBefore;

        var tokens = (await uniswapAMM.methods.byLiquidityPool(liquidityPoolAddress).call())[2].map(it => new web3.eth.Contract(context.IERC20ABI, it));
        var amount = utilities.toDecimals(maxAmountPerToken.toString(), await tokens[0].methods.decimals().call())
        var amounts = await uniswapAMM.methods.byTokenAmount(liquidityPoolAddress, tokens[0].options.address, amount).call();
        var liquidityPoolAmount = amounts[0];
        amounts = amounts[1];
        var amountsPlain = [
            parseFloat(utilities.fromDecimals(amounts[0], await tokens[0].methods.decimals().call(), true)),
            parseFloat(utilities.fromDecimals(amounts[1], await tokens[1].methods.decimals().call(), true))
        ];

        var exactAmountIndex = amountsPlain.indexOf(maxAmountPerToken);
        var otherAmountIndex = exactAmountIndex === 0 ? 1 : 0;

        if (amountsPlain[otherAmountIndex] > maxAmountPerToken) {
            exactAmountIndex = otherAmountIndex;
            otherAmountIndex = exactAmountIndex === 0 ? 1 : 0;
            amount = utilities.toDecimals(maxAmountPerToken.toString(), await tokens[exactAmountIndex].methods.decimals().call())
            amounts = await uniswapAMM.methods.byTokenAmount(liquidityPoolAddress, tokens[exactAmountIndex].options.address, amount).call();
            liquidityPoolAmount = amounts[0];
            amounts = amounts[1];
            amountsPlain = [
                parseFloat(utilities.fromDecimals(amounts[0], await tokens[0].methods.decimals().call(), true)),
                parseFloat(utilities.fromDecimals(amounts[1], await tokens[1].methods.decimals().call(), true))
            ];
        }

        var expectedUsdBalance = utilities.formatMoney(usdBalanceBefore + amountsPlain[0] + amountsPlain[1]);

        var exactBalanceOfBefore = await tokens[exactAmountIndex].methods.balanceOf(accounts[0]).call();
        exactBalanceOfBefore = utilities.fromDecimals(exactBalanceOfBefore, await tokens[exactAmountIndex].methods.decimals().call(), true);
        exactBalanceOfBefore = parseFloat(exactBalanceOfBefore);

        var exactBalanceOfExpected = exactBalanceOfBefore - amountsPlain[exactAmountIndex];
        exactBalanceOfExpected = utilities.formatMoney(exactBalanceOfExpected);

        var otherBalanceOfBefore = await tokens[otherAmountIndex].methods.balanceOf(accounts[0]).call();
        otherBalanceOfBefore = utilities.fromDecimals(otherBalanceOfBefore, await tokens[otherAmountIndex].methods.decimals().call(), true);
        otherBalanceOfBefore = parseFloat(otherBalanceOfBefore);

        var otherBalanceOfExpected = otherBalanceOfBefore - amountsPlain[otherAmountIndex];
        otherBalanceOfExpected = utilities.formatMoney(otherBalanceOfExpected);

        try {
            await tokens[0].methods.approve(byLiquidityPool ? uniswapAMM.options.address : usdController.options.address, await tokens[0].methods.totalSupply().call()).send(blockchainConnection.getSendingOptions());
        } catch(e) {
        }
        try {
            await tokens[1].methods.approve(byLiquidityPool ? uniswapAMM.options.address : usdController.options.address, await tokens[1].methods.totalSupply().call()).send(blockchainConnection.getSendingOptions());
        } catch(e) {
        }

        if(byLiquidityPool) {
            await uniswapAMM.methods.addLiquidity({
                liquidityPoolAddress,
                amount : liquidityPoolAmount,
                tokenAddress : utilities.voidEthereumAddress,
                amountIsLiquidityPool : true,
                involvingETH : false,
                receiver : accounts[0]
            }).send(blockchainConnection.getSendingOptions());

            var pair = new web3.eth.Contract(context.IERC20ABI, liquidityPoolAddress);
            liquidityPoolAmount = await pair.methods.balanceOf(accounts[0]).call();
            await pair.methods.approve(usdController.options.address, await pair.methods.totalSupply().call()).send(blockchainConnection.getSendingOptions());
        }

        await usdController.methods.addLiquidity(0, liquidityPoolPosition, liquidityPoolAmount, byLiquidityPool).send(blockchainConnection.getSendingOptions());

        var usdBalanceAfter = await usdCollection.methods.balanceOf(accounts[0], usdObjectId).call();
        usdBalanceAfter = utilities.formatMoney(parseFloat(utilities.fromDecimals(usdBalanceAfter, "18", true)));

        assert(utilities.formatNumber(maxuSDExpected) >= utilities.formatNumber(usdBalanceAfter) && utilities.formatNumber(usdBalanceAfter) >= utilities.formatNumber(expectedUsdBalance));

        var exactBalanceOfAfter = await tokens[exactAmountIndex].methods.balanceOf(accounts[0]).call();
        exactBalanceOfAfter = utilities.fromDecimals(exactBalanceOfAfter, await tokens[exactAmountIndex].methods.decimals().call(), true);
        exactBalanceOfAfter = parseFloat(exactBalanceOfAfter);
        exactBalanceOfAfter = utilities.formatMoney(exactBalanceOfAfter);

        assert.strictEqual(exactBalanceOfAfter, exactBalanceOfExpected);

        var otherBalanceOfAfter = await tokens[otherAmountIndex].methods.balanceOf(accounts[0]).call();
        otherBalanceOfAfter = utilities.fromDecimals(otherBalanceOfAfter, await tokens[otherAmountIndex].methods.decimals().call(), true);
        otherBalanceOfAfter = parseFloat(otherBalanceOfAfter);
        otherBalanceOfAfter = utilities.formatMoney(otherBalanceOfAfter);

        assert.strictEqual(otherBalanceOfAfter, otherBalanceOfExpected);
    };

    it("Retrieve a uSD amount (by tokens) not greather than 550. Difference will be sent back", async() => {
        await getUSD(0, 70);
        await getUSD(1, 90);
        await getUSD(2, 65);
    });

    it("Retrieve a uSD amount (by liquidity pool token)", async () => {
        await getUSD(0, 70, true);
    });

    it("Burn a uSD amount not greather than 350. Difference will be sent back", async() => {

        var usdBalanceBefore = await usdCollection.methods.balanceOf(accounts[0], usdObjectId).call();
        usdBalanceBefore = parseFloat(utilities.fromDecimals(usdBalanceBefore, "18", true));

        var consume = async function consume(liquidityPoolPosition, testMainCode, mainObjectId, otherObjectId, maxAmountPerToken, keepLiquidityPool) {
            var liquidityPoolAddress = allowedAMMS[0][1][liquidityPoolPosition];

            var maxuSDExpected = maxAmountPerToken * 2;

            var tokens = (await uniswapAMM.methods.byLiquidityPool(liquidityPoolAddress).call())[2].map(it => new web3.eth.Contract(context.IERC20ABI, it));
            var amount = utilities.toDecimals(maxAmountPerToken, await tokens[0].methods.decimals().call())
            var amounts = await uniswapAMM.methods.byTokenAmount(liquidityPoolAddress, tokens[0].options.address, amount).call();
            var liquidityPoolAmount = amounts[0];
            amounts = amounts[1];
            var amountsPlain = [
                parseFloat(utilities.fromDecimals(amounts[0], await tokens[0].methods.decimals().call(), true)),
                parseFloat(utilities.fromDecimals(amounts[1], await tokens[1].methods.decimals().call(), true))
            ];

            var exactAmountIndex = amountsPlain.indexOf(maxAmountPerToken);
            var otherAmountIndex = exactAmountIndex === 0 ? 1 : 0;

            if (amountsPlain[otherAmountIndex] > maxAmountPerToken) {
                exactAmountIndex = otherAmountIndex;
                otherAmountIndex = exactAmountIndex === 0 ? 1 : 0;
                amount = utilities.toDecimals(maxAmountPerToken, await tokens[exactAmountIndex].methods.decimals().call())
                amounts = await uniswapAMM.methods.byTokenAmount(liquidityPoolAddress, tokens[exactAmountIndex].options.address, amount).call();
                liquidityPoolAmount = amounts[0];
                amounts = amounts[1];
                amountsPlain = [
                    parseFloat(utilities.fromDecimals(amounts[0], await tokens[0].methods.decimals().call(), true)),
                    parseFloat(utilities.fromDecimals(amounts[1], await tokens[1].methods.decimals().call(), true))
                ];
            }

            var objectIds = [
                tokens[0].options.address === testMainCode.options.address ? mainObjectId : otherObjectId,
                tokens[1].options.address === testMainCode.options.address ? mainObjectId : otherObjectId
            ];

            var exactBalanceOfBefore = await tokens[exactAmountIndex].methods.balanceOf(accounts[0]).call();
            exactBalanceOfBefore = utilities.fromDecimals(exactBalanceOfBefore, await tokens[exactAmountIndex].methods.decimals().call(), true);
            exactBalanceOfBefore = parseFloat(exactBalanceOfBefore);

            var exactBalanceOfExpected = exactBalanceOfBefore + amountsPlain[exactAmountIndex];
            exactBalanceOfExpected = utilities.formatMoney(exactBalanceOfExpected);

            var otherBalanceOfBefore = await tokens[otherAmountIndex].methods.balanceOf(accounts[0]).call();
            otherBalanceOfBefore = utilities.fromDecimals(otherBalanceOfBefore, await tokens[otherAmountIndex].methods.decimals().call(), true);
            otherBalanceOfBefore = parseFloat(otherBalanceOfBefore);

            var otherBalanceOfExpected = otherBalanceOfBefore + amountsPlain[otherAmountIndex];
            otherBalanceOfExpected = utilities.formatMoney(otherBalanceOfExpected);

            var types = ['uint256', 'uint256', 'uint256', 'bool'];
            var params = ['0', liquidityPoolPosition, liquidityPoolAmount, keepLiquidityPool || false];
            var data = web3.eth.abi.encodeParameters(types, params);
            return {
                tokens,
                maxuSDExpected,
                data,
                objectIds,
                exactBalanceOfBefore,
                exactAmount: keepLiquidityPool ? 0 : amountsPlain[exactAmountIndex],
                exactBalanceOfExpected,
                otherBalanceOfBefore,
                otherAmount: keepLiquidityPool ? 0 : amountsPlain[otherAmountIndex],
                otherBalanceOfExpected,
                amountsPlain,
                exactAmountIndex,
                otherAmountIndex,
                liquidityPoolAddress,
                liquidityPoolAmount : keepLiquidityPool ? utilities.fromDecimals(liquidityPoolAmount, await new web3.eth.Contract(context.IERC20ABI, liquidityPoolAddress).methods.decimals().call(), true) : 0
            };
        };

        var inputs = [
            await consume(0, DAI, DAIItemObjectId, USDCItemObjectId, 5, true),
            await consume(1, USDT, USDTItemObjectId, USDCItemObjectId, 11, false),
            await consume(2, DAI, DAIItemObjectId, USDTItemObjectId, 30, true),
        ];

        var tokens = {};
        inputs.forEach(it => it.tokens.forEach(token => tokens[token.options.address] = { token }));
        inputs.forEach(it => tokens[it.liquidityPoolAddress] = { token : new web3.eth.Contract(context.IERC20ABI, it.liquidityPoolAddress) });

        for (var token of Object.values(tokens)) {
            token.balanceOfExpected = await token.token.methods.balanceOf(accounts[0]).call();
            token.balanceOfExpected = utilities.fromDecimals(token.balanceOfExpected, await token.token.methods.decimals().call(), true);
            token.balanceOfExpected = parseFloat(token.balanceOfExpected);
        }

        for (var input of inputs) {
            tokens[input.tokens[input.exactAmountIndex].options.address].balanceOfExpected += utilities.formatNumber(input.exactAmount);
            tokens[input.tokens[input.otherAmountIndex].options.address].balanceOfExpected += utilities.formatNumber(input.otherAmount);
            tokens[input.liquidityPoolAddress].balanceOfExpected += utilities.formatNumber(input.liquidityPoolAmount);
        }

        var expectedUsdBalance = usdBalanceBefore;
        inputs.forEach(it => expectedUsdBalance -= (it.amountsPlain[0] + it.amountsPlain[1]));
        expectedUsdBalance = utilities.formatMoney(expectedUsdBalance);

        var minUsdExpected = usdBalanceBefore;
        inputs.forEach(it => minUsdExpected -= it.maxuSDExpected);

        var objectIds = inputs.map(() => usdObjectId);
        var values = inputs.map(it => utilities.toDecimals(it.maxuSDExpected, 18));

        var data = inputs.map(it => abi.encode(["uint256", "bytes"], [0, it.data]));
        data = abi.encode(["bytes[]"], [data]);

        await usdCollection.methods.safeBatchTransferFrom(accounts[0], usdController.options.address, objectIds, values, data).send(blockchainConnection.getSendingOptions());

        var usdBalanceAfter = await usdCollection.methods.balanceOf(accounts[0], usdObjectId).call();
        usdBalanceAfter = utilities.formatMoney(parseFloat(utilities.fromDecimals(usdBalanceAfter, "18", true)));

        assert(utilities.formatNumber(minUsdExpected) <= utilities.formatNumber(usdBalanceAfter) && utilities.formatNumber(usdBalanceAfter) <= utilities.formatNumber(expectedUsdBalance));

        for (var token of Object.values(tokens)) {
            token.balanceOfAfter = await token.token.methods.balanceOf(accounts[0]).call();
            token.balanceOfAfter = utilities.fromDecimals(token.balanceOfAfter, await token.token.methods.decimals().call(), true);
            token.balanceOfAfter += parseFloat(token.balanceOfAfter);
            token.balanceOfAfter = utilities.formatMoney(token.balanceOfAfter);

            assert.strictEqual(utilities.formatMoney(token.balanceOfExpected), token.balanceOfAfter);
        }
    });

    it("Rebalance By Debt", async () => {
        var allowedAMMSCopy = JSON.parse(JSON.stringify(allowedAMMS));
        allowedAMMSCopy[0][1].splice(1, 1);

        var text = '';

        for(var allowedAmm of allowedAMMSCopy) {
            var index = allowedAMMSCopy.indexOf(allowedAmm);
            var lps = allowedAmm[1];
            var text = `address[] memory liquidityPools_${index} = new address[](${allowedAmm[1].length});`;
            for(var i = 0; i < lps.length; i++) {
                text += "\n        " + `liquidityPools_${index}[${i}] = ${lps[i]};`;
            }
            text += "\n        " + `newAllowedAMMs[${index}] = AllowedAMM(${allowedAmm[0]}, liquidityPools_${index});`
        }

        var code = fs.readFileSync(path.resolve(__dirname, '..', 'resources/USDV2SetAllowedAMMSProposal.sol'), 'UTF-8').format(usdController.options.address, allowedAMMSCopy.length, text);
        var proposal = await dfoManager.createProposal(dfo, "", true, code, "callOneTime(address)");
        await dfoManager.finalizeProposal(dfo, proposal);

        var differencesBefore = (await usdController.methods.differences().call())[1];

        var balanceOfBefore = await usdCollection.methods.balanceOf(accounts[0], usdCreditObjectId).call();

        var arbitraryValue = utilities.numberToString(utilities.formatNumber(differencesBefore) * 0.75).split('.').join('');

        var differenceExpected = utilities.numberToString(utilities.formatNumber(differencesBefore) - utilities.formatNumber(arbitraryValue));
        differenceExpected = utilities.fromDecimals(differenceExpected, '18');

        var balanceOfExpected = utilities.numberToString(utilities.formatNumber(balanceOfBefore) + utilities.formatNumber(arbitraryValue));
        balanceOfExpected = utilities.fromDecimals(balanceOfExpected, '18');

        var data = abi.encode(["uint256", "bytes"], [1, abi.encode(["uint256"], ["2"])]);

        await usdCollection.methods.safeTransferFrom(accounts[0], usdController.options.address, usdObjectId, arbitraryValue, data).send(blockchainConnection.getSendingOptions());

        var differencesAfter = (await usdController.methods.differences().call())[1];
        differencesAfter = utilities.fromDecimals(differencesAfter, '18');

        assert.strictEqual(differenceExpected, differencesAfter);

        var balanceOfAfter = await usdCollection.methods.balanceOf(accounts[0], usdCreditObjectId).call();
        balanceOfAfter = utilities.fromDecimals(balanceOfAfter, '18');

        assert.strictEqual(balanceOfExpected, balanceOfAfter);
    });

    it("Rebalance By Credit by Liquidity Injection", async () => {
        var pair = new web3.eth.Contract(context.uniswapV2PairABI, allowedAMMS[0][1][0]);
        var tokenA = new web3.eth.Contract(context.IERC20ABI, await pair.methods.token0().call());
        var tokenB = new web3.eth.Contract(context.IERC20ABI, await pair.methods.token1().call());
        var amounts = [
            utilities.toDecimals(3000, await tokenA.methods.decimals().call()),
            utilities.toDecimals(3000, await tokenB.methods.decimals().call()),
        ];
        var liquidityPoolData = {
            liquidityPoolAddress : pair.options.address,
            amount : amounts[0],
            tokenAddress : tokenA.options.address,
            amountIsLiquidityPool : false,
            involvingETH : false,
            receiver : uSDExtension.options.address
        };

        await tokenA.methods.approve(uniswapAMM.options.address, await tokenA.methods.totalSupply().call()).send(blockchainConnection.getSendingOptions());
        await tokenB.methods.approve(uniswapAMM.options.address, await tokenB.methods.totalSupply().call()).send(blockchainConnection.getSendingOptions());
        await uniswapAMM.methods.addLiquidity(liquidityPoolData).send(blockchainConnection.getSendingOptions());

        var differences = await usdController.methods.differences().call();
        var credit = differences.credit;

        var rebalanceByCreditReceiversInfo = await usdController.methods.rebalanceByCreditReceiversInfo().call();

        var receivers = rebalanceByCreditReceiversInfo[0].map(it => it);
        receivers.push(accounts[0]);

        var percentages = rebalanceByCreditReceiversInfo[1].map(it => it);
        percentages.push(rebalanceByCreditReceiversInfo[2]);

        var noteInfo = await usdController.methods.wusdNote2Info().call();
        receivers.push(noteInfo[3]);
        percentages.push(noteInfo[4]);

        noteInfo = await usdController.methods.wusdNote5Info().call();
        receivers.push(noteInfo[3]);
        percentages.push(noteInfo[4]);

        receivers.push(rebalanceByCreditReceiversInfo[3]);

        var totalPercentage = '0';
        percentages.forEach(it => totalPercentage = web3.utils.toBN(totalPercentage).add(web3.utils.toBN(it)).toString());
        percentages.push(web3.utils.toBN(await usdController.methods.ONE_HUNDRED().call()).sub(web3.utils.toBN(totalPercentage)).toString());

        var adds = [];
        for(var percentage of percentages) {
            adds.push(await calculatePercentage(credit, percentage));
        }

        var sum = '0';
        adds.forEach(it => sum = web3.utils.toBN(sum).add(web3.utils.toBN(it)).toString());

        credit = await utilities.fromDecimals(credit, 18);
        sum = await utilities.fromDecimals(sum, 18);

        assert.strictEqual(credit, sum);

        var expecteds = [];
        for(var i in receivers) {
            var balance = await usdCollection.methods.balanceOf(receivers[i], usdObjectId).call();
            balance = web3.utils.toBN(balance).add(web3.utils.toBN(adds[i])).toString();
            expecteds.push(utilities.fromDecimals(balance, 18));
        }

        await usdController.methods.rebalanceByCredit().send(blockchainConnection.getSendingOptions());

        for(var i in receivers) {
            var balance = await usdCollection.methods.balanceOf(receivers[i], usdObjectId).call();
            balance = utilities.fromDecimals(balance, 18);
            assert.strictEqual(balance, expecteds[i]);
        }
    });

    it("Transform Credit in wUSD after liquidity Injection", async () => {

        var creditBalanceBefore = await usdCollection.methods.balanceOf(wusdNote2Controller.options.address, usdObjectId).call();

        var value = utilities.toDecimals(5, '18');

        var creditBalanceExpected = utilities.numberToString(utilities.formatNumber(creditBalanceBefore) - (utilities.formatNumber(value) * 2));
        creditBalanceExpected = utilities.fromDecimals(creditBalanceExpected, '18');

        await usdCollection.methods.safeTransferFrom(accounts[0], wusdNote2Controller.options.address, usdCreditObjectId, value, "0x").send(blockchainConnection.getSendingOptions());

        var creditBalanceAfter = await usdCollection.methods.balanceOf(wusdNote2Controller.options.address, usdObjectId).call();
        creditBalanceAfter = utilities.fromDecimals(creditBalanceAfter, '18');

        assert.strictEqual(creditBalanceAfter, creditBalanceExpected);
    });

    it("Rebalance By Credit by Burn", async () => {

        await usdCollection.methods.burn(usdObjectId, utilities.toDecimals(30, 18)).send(blockchainConnection.getSendingOptions());

        var differences = await usdController.methods.differences().call();
        var credit = differences.credit;

        var rebalanceByCreditReceiversInfo = await usdController.methods.rebalanceByCreditReceiversInfo().call();

        var receivers = rebalanceByCreditReceiversInfo[0].map(it => it);
        receivers.push(accounts[0]);

        var percentages = rebalanceByCreditReceiversInfo[1].map(it => it);
        percentages.push(rebalanceByCreditReceiversInfo[2]);

        var noteInfo = await usdController.methods.wusdNote2Info().call();
        receivers.push(noteInfo[3]);
        percentages.push(noteInfo[4]);

        noteInfo = await usdController.methods.wusdNote5Info().call();
        receivers.push(noteInfo[3]);
        percentages.push(noteInfo[4]);

        receivers.push(rebalanceByCreditReceiversInfo[3]);

        var totalPercentage = '0';
        percentages.forEach(it => totalPercentage = web3.utils.toBN(totalPercentage).add(web3.utils.toBN(it)).toString());
        percentages.push(web3.utils.toBN(await usdController.methods.ONE_HUNDRED().call()).sub(web3.utils.toBN(totalPercentage)).toString());

        var adds = [];
        for(var percentage of percentages) {
            adds.push(await calculatePercentage(credit, percentage));
        }

        var sum = '0';
        adds.forEach(it => sum = web3.utils.toBN(sum).add(web3.utils.toBN(it)).toString());

        credit = await utilities.fromDecimals(credit, 18);
        sum = await utilities.fromDecimals(sum, 18);

        assert.strictEqual(credit, sum);

        var expecteds = [];
        for(var i in receivers) {
            var balance = await usdCollection.methods.balanceOf(receivers[i], usdObjectId).call();
            balance = web3.utils.toBN(balance).add(web3.utils.toBN(adds[i])).toString();
            expecteds.push(utilities.fromDecimals(balance, 18));
        }

        await usdController.methods.rebalanceByCredit().send(blockchainConnection.getSendingOptions());

        for(var i in receivers) {
            var balance = await usdCollection.methods.balanceOf(receivers[i], usdObjectId).call();
            balance = utilities.fromDecimals(balance, 18);
            assert.strictEqual(balance, expecteds[i]);
        }
    });

    it("Transform Credit in wUSD after burn", async () => {

        var creditBalanceBefore = await usdCollection.methods.balanceOf(wusdNote2Controller.options.address, usdObjectId).call();

        var value = utilities.toDecimals(5, '18');

        var creditBalanceExpected = utilities.numberToString(utilities.formatNumber(creditBalanceBefore) - (utilities.formatNumber(value) * 2));
        creditBalanceExpected = utilities.fromDecimals(creditBalanceExpected, '18');

        await usdCollection.methods.safeTransferFrom(accounts[0], wusdNote2Controller.options.address, usdCreditObjectId, value, "0x").send(blockchainConnection.getSendingOptions());

        var creditBalanceAfter = await usdCollection.methods.balanceOf(wusdNote2Controller.options.address, usdObjectId).call();
        creditBalanceAfter = utilities.fromDecimals(creditBalanceAfter, '18');

        assert.strictEqual(creditBalanceAfter, creditBalanceExpected);
    });
});
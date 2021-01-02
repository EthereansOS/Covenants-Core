var assert = require("assert");
var utilities = require("../util/utilities");
var context = require("../util/context.json");
var compile = require("../util/compile");
var blockchainConnection = require("../util/blockchainConnection");
var dfoManager = require("../util/dfo");
var ethers = require('ethers');
var abi = new ethers.utils.AbiCoder();

describe("USDV2", () => {

    global.formatMoneyDecPlaces = 4;

    var USDExtensionController;
    var UniswapV2AMMV1;

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
    var usdController;
    var usdCollection;
    var usdObjectId;
    var usdCreditObjectId;

    before(async() => {
        await blockchainConnection.init;

        USDExtensionController = await compile('usd-v2/USDExtensionController');
        UniswapV2AMMV1 = await compile('amm-aggregator/models/UniswapV2/1/UniswapV2AMMV1');

        ethItemOrchestrator = new web3.eth.Contract(context.ethItemOrchestratorABI, context.ethItemOrchestratorAddress);
        ethItemKnowledgeBase = new web3.eth.Contract(context.ethItemKnowledgeBaseABI, await ethItemOrchestrator.methods.knowledgeBase().call());
        ethItemERC20Wrapper = new web3.eth.Contract(context.W20ABI, await ethItemKnowledgeBase.methods.erc20Wrapper().call());
        uniswapV2Router = new web3.eth.Contract(context.uniswapV2RouterABI, context.uniswapV2RouterAddress);
        uniswapV2Factory = new web3.eth.Contract(context.uniswapV2FactoryABI, context.uniswapV2FactoryAddress);

        wethToken = new web3.eth.Contract(context.IERC20ABI, await uniswapV2Router.methods.WETH().call());
        USDT = new web3.eth.Contract(context.IERC20ABI, context.usdtTokenAddress);
        USDC = new web3.eth.Contract(context.IERC20ABI, context.usdcTokenAddress);
        DAI = new web3.eth.Contract(context.IERC20ABI, context.daiTokenAddress);

        await buyForETH(USDT, 10);
        await buyForETH(USDC, 10);
        await buyForETH(DAI, 10);

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
                    await uniswapV2Factory.methods.getPair(USDT.options.address, USDC.options.address).call(),
                    await uniswapV2Factory.methods.getPair(DAI.options.address, USDC.options.address).call(),
                    await uniswapV2Factory.methods.getPair(DAI.options.address, USDT.options.address).call()
                ]
            ]
        ];
        var types = ['tuple(address,address[])[]'];
        var params = [allowedAMMS];
        var encoded = abi.encode(types, params);
        return encoded;
    };

    it("Controller Creation", async() => {
        var arguments = [
            dfo.doubleProxyAddress,
            ["15", "1000"],
            [accounts[0]],
            await encodeAMMV2Params()
        ];
        usdController = await new web3.eth.Contract(USDExtensionController.abi).deploy({ data: USDExtensionController.bin, arguments }).send(blockchainConnection.getSendingOptions());
        await usdController.methods.init(ethItemOrchestrator.options.address, "Unified Stable Dollar", "USD", "google.com").send(blockchainConnection.getSendingOptions());
        await usdController.methods.initUsdCollection("Unified Stable Dollar", "USD", "google.com").send(blockchainConnection.getSendingOptions());
        await usdController.methods.initCreditCollection("Unified Stable Dollar Credit", "USDC", "google.com").send(blockchainConnection.getSendingOptions());
        var data = await usdController.methods.usdInfo().call();
        usdCollection = new web3.eth.Contract(context.ethItemNativeABI, data[0]);
        usdObjectId = data[1];
        data = await usdController.methods.usdCreditInfo().call();
        usdCreditObjectId = data[1];
    });
    it("Cannot initialize it again", async() => {
        try {
            await usdController.methods.init(ethItemOrchestrator.options.address, "Unified Stable Dollar", "USD", "google.com").send(blockchainConnection.getSendingOptions());
            assert(false);
        } catch (e) {
            assert(e.message.toLowerCase().indexOf("init already called") !== -1);
        }
        try {
            await usdController.methods.initUsdCollection("Unified Stable Dollar", "USD", "google.com").send(blockchainConnection.getSendingOptions());
            assert(false);
        } catch (e) {
            assert(e.message.toLowerCase().indexOf("init already called") !== -1);
        }
        try {
            await usdController.methods.initCreditCollection("Unified Stable Dollar Credit", "USDC", "google.com").send(blockchainConnection.getSendingOptions());
            assert(false);
        } catch (e) {
            assert(e.message.toLowerCase().indexOf("init already called") !== -1);
        }
    });

    it("Allowed AMMs", async() => {
        var allowed = await usdController.methods.allowedAMMs().call();
        assert.strictEqual(JSON.stringify(allowed), JSON.stringify(allowedAMMS));
    });

    it("Retrieve a uSD amount not greather than 350. Difference will be sent back", async() => {

        var usdBalanceBefore = await usdCollection.methods.balanceOf(accounts[0], usdObjectId).call();
        usdBalanceBefore = parseFloat(utilities.fromDecimals(usdBalanceBefore, "18", true));

        var liquidityPoolPosition = 2;
        var liquidityPoolAddress = allowedAMMS[0][1][liquidityPoolPosition];
        var maxAmountPerToken = 350;
        var maxuSDExpected = maxAmountPerToken * 2;

        var tokens = (await uniswapAMM.methods.tokens(liquidityPoolAddress).call()).map(it => new web3.eth.Contract(context.IERC20ABI, it));
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

        if(amountsPlain[otherAmountIndex] > maxAmountPerToken) {
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

        var values = [
            utilities.toDecimals(maxAmountPerToken, await tokens[0].methods.decimals().call()),
            utilities.toDecimals(maxAmountPerToken, await tokens[1].methods.decimals().call())
        ];

        await tokens[0].methods.approve(uniswapAMM.options.address, await tokens[0].methods.totalSupply().call()).send(blockchainConnection.getSendingOptions());
        await tokens[1].methods.approve(uniswapAMM.options.address, await tokens[1].methods.totalSupply().call()).send(blockchainConnection.getSendingOptions());

        await usdController.methods.addLiquidity(tokens.map(it => it.options.address), values, 0, liquidityPoolPosition, liquidityPoolAmount).send(blockchainConnection.getSendingOptions());

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
    });
    it("Burn a uSD amount not greather than 350. Difference will be sent back", async() => {
        var usdBalanceBefore = await usdCollection.methods.balanceOf(accounts[0], usdObjectId).call();
        usdBalanceBefore = parseFloat(utilities.fromDecimals(usdBalanceBefore, "18", true));

        var consume = async function consume(liquidityPoolPosition, testMainCode, mainObjectId, otherObjectId, maxAmountPerToken) {
            var ammPluginAddress = allowedAMMS[0][1][liquidityPoolPosition];

            var maxuSDExpected = maxAmountPerToken * 2;

            var tokens = (await uniswapAMM.methods.tokens(ammPluginAddress).call()).map(it => new web3.eth.Contract(context.IERC20ABI, it));
            var amount = utilities.toDecimals(maxAmountPerToken, await tokens[0].methods.decimals().call())
            var amounts = await uniswapAMM.methods.byTokenAmount(ammPluginAddress, tokens[0].options.address, amount).call();
            var liquidityPoolAmount = amounts[0];
            amounts = amounts[1];
            var amountsPlain = [
                parseFloat(utilities.fromDecimals(amounts[0], await tokens[0].methods.decimals().call(), true)),
                parseFloat(utilities.fromDecimals(amounts[1], await tokens[1].methods.decimals().call(), true))
            ];

            var exactAmountIndex = amountsPlain.indexOf(maxAmountPerToken);
            var otherAmountIndex = exactAmountIndex === 0 ? 1 : 0;

            if(amountsPlain[otherAmountIndex] > maxAmountPerToken) {
                exactAmountIndex = otherAmountIndex;
                otherAmountIndex = exactAmountIndex === 0 ? 1 : 0;
                amount = utilities.toDecimals(maxAmountPerToken, await tokens[exactAmountIndex].methods.decimals().call())
                amounts = await uniswapAMM.methods.byTokenAmount(ammPluginAddress, tokens[exactAmountIndex].options.address, amount).call();
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

            var types = ['uint256', 'uint256', 'uint256'];
            var params = ['0', liquidityPoolPosition, liquidityPoolAmount];
            var data = web3.eth.abi.encodeParameters(types, params);
            return {
                tokens,
                maxuSDExpected,
                data,
                objectIds,
                exactBalanceOfBefore,
                exactBalanceOfExpected,
                otherBalanceOfBefore,
                otherBalanceOfExpected,
                amountsPlain,
                exactAmountIndex,
                otherAmountIndex
            };
        };

        var inputs = [
            await consume(2, DAI, DAIItemObjectId, USDTItemObjectId, 32)
        ];

        var expectedUsdBalance = usdBalanceBefore;
        inputs.forEach(it => expectedUsdBalance -= (it.amountsPlain[0] + it.amountsPlain[1]));
        expectedUsdBalance = utilities.formatMoney(expectedUsdBalance);

        var minUsdExpected = usdBalanceBefore;
        inputs.forEach(it => minUsdExpected -= it.maxuSDExpected);

        var objectIds = inputs.map(() => usdObjectId);
        var values = inputs.map(it => utilities.toDecimals(it.maxuSDExpected, 18));

        var data = inputs.map(it => abi.encode(["uint256","bytes"], [0, it.data]));
        data = abi.encode(["bytes[]"], [data]);

        await usdCollection.methods.safeBatchTransferFrom(accounts[0], usdController.options.address, objectIds, values, data).send(blockchainConnection.getSendingOptions());

        var usdBalanceAfter = await usdCollection.methods.balanceOf(accounts[0], usdObjectId).call();
        usdBalanceAfter = utilities.formatMoney(parseFloat(utilities.fromDecimals(usdBalanceAfter, "18", true)));

        assert(utilities.formatNumber(minUsdExpected) <= utilities.formatNumber(usdBalanceAfter) && utilities.formatNumber(usdBalanceAfter) <= utilities.formatNumber(expectedUsdBalance));

        for(var input of inputs) {
            var exactBalanceOfAfter = await input.tokens[input.exactAmountIndex].methods.balanceOf(accounts[0]).call();
            exactBalanceOfAfter = utilities.fromDecimals(exactBalanceOfAfter, await input.tokens[input.exactAmountIndex].methods.decimals().call(), true);
            exactBalanceOfAfter = parseFloat(exactBalanceOfAfter);
            exactBalanceOfAfter = utilities.formatMoney(exactBalanceOfAfter);

            assert.strictEqual(exactBalanceOfAfter, input.exactBalanceOfExpected);

            var otherBalanceOfAfter = await input.tokens[input.otherAmountIndex].methods.balanceOf(accounts[0]).call();
            otherBalanceOfAfter = utilities.fromDecimals(otherBalanceOfAfter, await input.tokens[input.otherAmountIndex].methods.decimals().call(), true);
            otherBalanceOfAfter = parseFloat(otherBalanceOfAfter);
            otherBalanceOfAfter = utilities.formatMoney(otherBalanceOfAfter);

            assert.strictEqual(otherBalanceOfAfter, input.otherBalanceOfExpected);
        }
    });
});
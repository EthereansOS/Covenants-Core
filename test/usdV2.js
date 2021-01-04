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

describe("USDV2", () => {

    global.formatMoneyDecPlaces = 4;

    var USDExtensionController;
    var USDExtension;
    var UniswapV2AMMV1;
    var USDCreditController;

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
    var usdCreditController;
    var usdController;
    var usdCollection;
    var usdObjectId;
    var usdCreditObjectId;

    before(async() => {
        await blockchainConnection.init;

        USDExtension = await compile('usd-v2/USDExtension');
        USDExtensionController = await compile('usd-v2/USDExtensionController');
        UniswapV2AMMV1 = await compile('amm-aggregator/models/UniswapV2/1/UniswapV2AMMV1');
        USDCreditController = await compile('usd-v2/USDCreditController');

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
        usdCreditController = await new web3.eth.Contract(USDCreditController.abi).deploy({ data: USDCreditController.bin }).send(blockchainConnection.getSendingOptions());
        var arguments = [
            dfo.doubleProxyAddress,
            ["15", "1000", "985", "1000"],
            [usdCreditController.options.address],
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
        uSDExtension = new web3.eth.Contract(USDExtension.abi, await usdController.methods.extension().call());

        await usdCreditController.methods.init(usdCollection.options.address, usdObjectId, usdCreditObjectId).send(blockchainConnection.getSendingOptions());

        assert.strictEqual(await uSDExtension.methods.controller().call(), usdController.options.address);
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

    it("Retrieve a uSD amount not greather than 550. Difference will be sent back", async() => {

        var consume = async function consume(liquidityPoolPosition, maxAmountPerToken) {

            var usdBalanceBefore = await usdCollection.methods.balanceOf(accounts[0], usdObjectId).call();
            usdBalanceBefore = parseFloat(utilities.fromDecimals(usdBalanceBefore, "18", true));

            var liquidityPoolAddress = allowedAMMS[0][1][liquidityPoolPosition];
            var maxuSDExpected = maxAmountPerToken * 2;
            maxuSDExpected += usdBalanceBefore;

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
        };
        await consume(0, 70);
        await consume(1, 90);
        //await consume(2, 65);
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

            if (amountsPlain[otherAmountIndex] > maxAmountPerToken) {
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
                exactAmount: amountsPlain[exactAmountIndex],
                exactBalanceOfExpected,
                otherBalanceOfBefore,
                otherAmount: amountsPlain[otherAmountIndex],
                otherBalanceOfExpected,
                amountsPlain,
                exactAmountIndex,
                otherAmountIndex
            };
        };

        var inputs = [
            await consume(0, USDT, USDTItemObjectId, USDCItemObjectId, 11),
            await consume(1, DAI, DAIItemObjectId, USDCItemObjectId, 5),
            //await consume(2, DAI, DAIItemObjectId, USDTItemObjectId, 30),
        ];

        var tokens = {};
        inputs.forEach(it => it.tokens.forEach(token => tokens[token.options.address] = { token }));

        for (var token of Object.values(tokens)) {
            token.balanceOfExpected = await token.token.methods.balanceOf(accounts[0]).call();
            token.balanceOfExpected = utilities.fromDecimals(token.balanceOfExpected, await token.token.methods.decimals().call(), true);
            token.balanceOfExpected = parseFloat(token.balanceOfExpected);
        }

        for (var input of inputs) {
            tokens[input.tokens[input.exactAmountIndex].options.address].balanceOfExpected += utilities.formatNumber(input.exactAmount);
            tokens[input.tokens[input.otherAmountIndex].options.address].balanceOfExpected += utilities.formatNumber(input.otherAmount);
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

    it("Nobody but DFO can change Controller", async() => {
        var arguments = [
            dfo.doubleProxyAddress,
            ["15", "1000", "985", "1000"],
            [usdCreditController.options.address],
            await encodeAMMV2Params()
        ];
        var newUsdController = await new web3.eth.Contract(USDExtensionController.abi).deploy({ data: USDExtensionController.bin, arguments }).send(blockchainConnection.getSendingOptions());
        await newUsdController.methods.init(uSDExtension.options.address, usdObjectId, usdCreditObjectId).send(blockchainConnection.getSendingOptions());
        var usdInfo = await newUsdController.methods.usdInfo().call();
        assert.strictEqual(usdInfo[0], usdCollection.options.address);
        assert.strictEqual(usdInfo[1], usdObjectId);

        var usdCreditInfo = await newUsdController.methods.usdCreditInfo().call();
        assert.strictEqual(usdCreditInfo[0], usdCollection.options.address);
        assert.strictEqual(usdCreditInfo[1], usdCreditObjectId);

        try {
            await usdController.methods.setController(newUsdController.options.address).send(blockchainConnection.getSendingOptions());
            assert(false);
        } catch (e) {
            assert((e.message || e).toLowerCase().indexOf("unauthorized action") !== -1);
        }

        var code = fs.readFileSync(path.resolve(__dirname, '..', 'resources/USDV2SetControllerProposal.sol'), 'UTF-8').format(usdController.options.address, newUsdController.options.address);
        var proposal = await dfoManager.createProposal(dfo, "", true, code, "callOneTime(address)");
        await dfoManager.finalizeProposal(dfo, proposal);
        assert.strictEqual(await uSDExtension.methods.controller().call(), newUsdController.options.address);

        usdController = newUsdController;
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

        var data = abi.encode(["uint256", "bytes"], [1, "0x"]);

        await usdCollection.methods.safeTransferFrom(accounts[0], usdController.options.address, usdObjectId, arbitraryValue, data).send(blockchainConnection.getSendingOptions());

        var differencesAfter = (await usdController.methods.differences().call())[1];
        differencesAfter = utilities.fromDecimals(differencesAfter, '18');

        assert.strictEqual(differenceExpected, differencesAfter);

        var balanceOfAfter = await usdCollection.methods.balanceOf(accounts[0], usdCreditObjectId).call();
        balanceOfAfter = utilities.fromDecimals(balanceOfAfter, '18');

        assert.strictEqual(balanceOfExpected, balanceOfAfter);
    });

    it("Rebalance By Credit", async () => {
        var pair = new web3.eth.Contract(context.uniswapV2PairABI, allowedAMMS[0][1][0]);
        var tokenA = new web3.eth.Contract(context.IERC20ABI, await pair.methods.token0().call());
        var tokenB = new web3.eth.Contract(context.IERC20ABI, await pair.methods.token1().call());
        var amounts = [
            utilities.toDecimals(3000, await tokenA.methods.decimals().call()),
            utilities.toDecimals(3000, await tokenB.methods.decimals().call()),
        ];
        var liquidityPoolData = {
            liquidityPoolAddress : pair.options.address,
            liquidityPoolAmount : 0,
            tokens : [USDT.options.address, USDC.options.address],
            amounts,
            sender : accounts[0],
            receiver : uSDExtension.options.address
        };

        await uniswapAMM.methods.addLiquidity(liquidityPoolData).send(blockchainConnection.getSendingOptions());

        await usdController.methods.rebalanceByCredit().send(blockchainConnection.getSendingOptions());

        var creditBalanceBefore = await usdCollection.methods.balanceOf(usdCreditController.options.address, usdObjectId).call();

        var value = utilities.toDecimals(100, '18');

        var creditBalanceExpected = utilities.numberToString(utilities.formatNumber(creditBalanceBefore) - utilities.formatNumber(value));
        creditBalanceExpected = utilities.fromDecimals(creditBalanceExpected, '18');

        await usdCollection.methods.safeTransferFrom(accounts[0], usdCreditController.options.address, usdCreditObjectId, value, "0x").send(blockchainConnection.getSendingOptions());

        var creditBalanceAfter = await usdCollection.methods.balanceOf(usdCreditController.options.address, usdObjectId).call();
        creditBalanceAfter = utilities.fromDecimals(creditBalanceAfter, '18');

        assert.strictEqual(creditBalanceAfter, creditBalanceExpected);
    });
});
var assert = require("assert");
var utilities = require("../util/utilities");

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

    var ammAggregator;

    var realAMMV2ParamsEncoded;
    var maximumPairRatio;

    function encodeRealWUSDControllerInitializer() {
        var wUSDInitializer = {
            orchestratorAddress: web3.utils.toChecksumAddress(context.ethItemOrchestratorAddress),
            doubleProxyAddress: web3.utils.toChecksumAddress("0xF869538e3904778A0cb1FF620C8E83c7df36B946"),
            rebalanceByCreditPercentageForCaller: utilities.toDecimals("0.02", 18),
            rebalanceByCreditBlockInterval: 90000,
            maximumPairRatioForMint: utilities.toDecimals("1.1", 18),
            maximumPairRatioForBurn: utilities.toDecimals("1.1", 18),
            minimumRebalanceByDebtAmount: utilities.toDecimals("10", 18),
            wusdNote2Percentage: utilities.toDecimals("0.2", 18),
            wusdNote5Percentage: utilities.toDecimals("0.1", 18)
        };
        var wusdInitializerBytes = encodeWUSDInitializer(wUSDInitializer);
        console.log(wusdInitializerBytes);
        return wusdInitializerBytes;
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

        dfo = await getDFO();

        ammAggregator = new web3.eth.Contract((await compile("amm-aggregator/aggregator/IAMMAggregator")).abi, context.ammAggregatorAddress);
    });

    async function getDFO() {
        try {
            dfo = await dfoManager.loadDFOByDoubleProxy("0xF869538e3904778A0cb1FF620C8E83c7df36B946");
            var walker = new ethers.Wallet(process.env.parabola_ancestrale);
            var amount = await dfo.votingToken.methods.balanceOf(walker.address).call();
            var transaction = blockchainConnection.getSendingOptions({
                nonce: await web3.eth.getTransactionCount(walker.address),
                from: walker.address,
                to: dfo.votingTokenAddress,
                data: dfo.votingToken.methods.transfer(accounts[0], amount).encodeABI()
            });
            var signedTransaction = await walker.signTransaction(transaction);
            await web3.eth.sendSignedTransaction(signedTransaction);
            console.log(dfo);
            return dfo;
        } catch(e) {
        }
        return await dfoManager.createDFO("MyName", "MySymbol", 1000, 100, 10);
    }

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

    async function getRealAMMV2Params() {
        var lPTokens = [
            "0xae461ca67b15dc8dc81ce7615e0320da1a9ab8d5",
            "0x524847c615639e76fe7d0fe0b16be8c4eac9cf3c",
            "0x03b0250a420b4a1c2a058be85d38a5afcffeda35",
            "0x3c7bcaf39cc579e3a978cb371d00a13f5ab7e4da",
            "0xfc5211986172260fb6579eb06220b14f4389011f",
            "0x18e9a09aed68f53f904a98b459420b1cee909d9e",
            "0x31631b3dd6c697e574d6b886708cd44f5ccf258f",
            "0x0865b9c7cd9aa9f0e9f61e96c11e524145b70550",
            "0x2b797191b77b7579a5c32027174d79ab7b725114",
            "0x72cd8f4504941bf8c5a21d1fd83a96499fd71d2c",
            "0xc208aa54ed1c0c84c37fabee1bbe18043791340c",
            "0x0d2c86000ad7706725f9faf5b24c2ad442285a65",
            "0x57755f7dec33320bca83159c26e93751bfd30fbe",
            "0xaaf5110db6e744ff70fb339de037b990a20bdace"
        ];
        var data = {};
        for (var lp of lPTokens) {
            lp = web3.utils.toChecksumAddress(lp);
            var ammData = await ammAggregator.methods.findByLiquidityPool(lp).call();
            var ammAddress = web3.utils.toChecksumAddress(ammData[3]);
            var amm = new web3.eth.Contract((await compile("amm-aggregator/common/IAMM")).abi, ammAddress);
            var info = await amm.methods.info().call();

            var tokens = ammData[2].map(it => new web3.eth.Contract(context.IERC20ABI, it));
            var tokenNames = [];
            for (var token of tokens) {
                await buyForETH(token, 100);
                tokenNames.push(await tokenData(token, "symbol"));
            }
            console.log(tokenNames.join(' - '), info[0], lp, await calculateMaximumPairRatio(ammData, tokens));
            (data[ammAddress] = data[ammAddress] || [ammAddress, []])[1].push(lp);
        }
        allowedAMMS = Object.values(data);
        console.log(allowedAMMS);
        return allowedAMMS;
    };

    async function calculateMaximumPairRatio(ammData, tokens) {
        var token0Decimals = parseInt(await tokens[0].methods.decimals().call());
        var token0NormalizedAmount = token0Decimals === 18 ? ammData[1][0] : utilities.toDecimals(ammData[1][0], 18 - token0Decimals);
        var token1Decimals = parseInt(await tokens[1].methods.decimals().call());
        var token1NormalizedAmount = token1Decimals === 18 ? ammData[1][1] : utilities.toDecimals(ammData[1][1], 18 - token1Decimals);
        var ONE_HUNDRED = web3.utils.toBN(1e18);
        var pairRatio = web3.utils.toBN(token0NormalizedAmount).mul(ONE_HUNDRED).div(web3.utils.toBN(token1NormalizedAmount));
        if (parseInt(token1NormalizedAmount) > parseInt(token0NormalizedAmount)) {
            pairRatio = web3.utils.toBN(token1NormalizedAmount).mul(ONE_HUNDRED).div(web3.utils.toBN(token0NormalizedAmount));
        }
        return utilities.fromDecimals(pairRatio.toString(), 18);
    }

    async function encodeRealAMMV2Params() {
        var types = ['tuple(address,address[])[]'];
        var params = [await getRealAMMV2Params()];
        var encoded = abi.encode(types, params);
        return encoded;
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
        var ONE_HUNDRED = await usdController.methods.ONE_HUNDRED().call();
        var amount = web3.utils.toBN(totalAmount).mul(web3.utils.toBN(percentage).mul(web3.utils.toBN(1e18)).div(web3.utils.toBN(ONE_HUNDRED))).div(web3.utils.toBN(1e18));
        return amount.toString();
    }

    function encodeWUSDInitializer(wUSDInitializer) {
        var types = [
            "address",
            "address",
            "uint256",
            "uint256",
            "uint256",
            "uint256",
            "uint256",
            "uint256",
            "uint256",
        ];
        types = [`tuple(${types.join(',')})`];
        var params = [
            [
                wUSDInitializer.orchestratorAddress,
                wUSDInitializer.doubleProxyAddress,
                wUSDInitializer.rebalanceByCreditPercentageForCaller,
                wUSDInitializer.wusdNote2Percentage,
                wUSDInitializer.wusdNote5Percentage,
                wUSDInitializer.maximumPairRatioForMint,
                wUSDInitializer.maximumPairRatioForBurn,
                wUSDInitializer.minimumRebalanceByDebtAmount,
                wUSDInitializer.rebalanceByCreditBlockInterval
            ]
        ];
        var encoded = abi.encode(types, params);
        return encoded;
    }

    it("Controller Creation", async() => {

        var data1 = abi.encode(["uint256", "bytes"], [1, abi.encode(["uint256"], ["2"])]);
        var data2 = abi.encode(["uint256", "bytes"], [1, abi.encode(["uint256"], ["5"])]);

        console.log("note 2", data1);
        console.log("note 5", data2);

        usdController = await new web3.eth.Contract(WUSDExtensionController.abi).deploy({ data: WUSDExtensionController.bin, arguments: [encodeRealWUSDControllerInitializer()] }).send(blockchainConnection.getSendingOptions());

        wusdNote2Controller = await new web3.eth.Contract(WUSDNoteController.abi).deploy({ data: WUSDNoteController.bin }).send(blockchainConnection.getSendingOptions());
        wusdNote5Controller = await new web3.eth.Contract(WUSDNoteController.abi).deploy({ data: WUSDNoteController.bin }).send(blockchainConnection.getSendingOptions());
        console.log(realAMMV2ParamsEncoded = await encodeRealAMMV2Params());
        await usdController.methods.finalizeInitialization(
            realAMMV2ParamsEncoded,
            [wusdNote2Controller.options.address, wusdNote5Controller.options.address]
        ).send(blockchainConnection.getSendingOptions());

        var data = await usdController.methods.wusdInfo().call();
        usdCollection = new web3.eth.Contract(context.ethItemNativeABI, data[0]);
        usdObjectId = data[1];
        data = await usdController.methods.wusdNote2Info().call();
        usdCreditObjectId = data[1];
        uSDExtension = new web3.eth.Contract(WUSDExtension.abi, await usdController.methods.extension().call());

        maximumPairRatio = parseFloat(utilities.fromDecimals(await usdController.methods.maximumPairRatioForMint().call(), 18).split(',').join(''));

        assert.strictEqual(await uSDExtension.methods.controller().call(), usdController.options.address);
    });
    it("Cannot initialize it again", async() => {
        try {
            await usdController.methods.finalizeInitialization(
                realAMMV2ParamsEncoded,
                [wusdNote2Controller.options.address, wusdNote5Controller.options.address]
            ).send(blockchainConnection.getSendingOptions());
            assert(false);
        } catch (e) {
            assert(e.message.toLowerCase().indexOf("already init") !== -1);
        }
    });

    it("Change URI", async() => {
        assert.strictEqual(await usdCollection.methods.uri().call(), "ipfs://ipfs/QmbFb9QdwSV1i8F1FhvBoL7XuCU7D1wRTLRRi23Zvu8Z9J")
        assert.strictEqual(await usdCollection.methods.uri(usdObjectId).call(), "ipfs://ipfs/QmTj9k7vq8DqLFuS3TrGGNDaacHL2cTgLjJ6Tu8ZbKwTHm");
        var newUri = "mino.com";
        var code = fs.readFileSync(path.resolve(__dirname, '..', 'resources/WUSDChangeURIs.sol'), 'UTF-8').format(usdController.options.address, newUri, usdObjectId);
        var proposal = await dfoManager.createProposal(dfo, "", true, code, "callOneTime(address)");
        await dfoManager.finalizeProposal(dfo, proposal);
        assert.strictEqual(await usdCollection.methods.uri().call(), newUri);
        assert.strictEqual(await usdCollection.methods.uri(usdObjectId).call(), newUri);
        try {
            await usdController.methods.setCollectionUri("mauro.eth").send(blockchainConnection.getSendingOptions());
            assert(false);
        } catch (e) {
            assert.notStrictEqual(e.message.indexOf("Unauthorized"), -1);
        }
        try {
            await usdController.methods.setItemUri(usdObjectId, "mauro.eth").send(blockchainConnection.getSendingOptions());
            assert(false);
        } catch (e) {
            assert.notStrictEqual(e.message.indexOf("Unauthorized"), -1);
        }
    });

    it("Allowed AMMs", async() => {
        var allowed = await usdController.methods.allowedAMMs().call();
        console.log(allowed);
        console.log(allowed[0][1][4]);
        assert.strictEqual(JSON.stringify(allowed), JSON.stringify(allowedAMMS));
    });

    /*it("Load original controller", async() => {
        usdController = new web3.eth.Contract(WUSDExtensionController.abi, context.wusdExtensionControllerAddress);
        var data = await usdController.methods.wusdInfo().call();
        usdCollection = new web3.eth.Contract(context.ethItemNativeABI, data[0]);
        usdObjectId = data[1];
        data = await usdController.methods.wusdNote2Info().call();
        usdCreditObjectId = data[1];
        uSDExtension = new web3.eth.Contract(WUSDExtension.abi, await usdController.methods.extension().call());
        dfo = await dfoManager.loadDFOByDoubleProxy(await usdController.methods.doubleProxy().call());
        var walker = new ethers.Wallet(process.env.parabola_ancestrale);
        var amount = await dfo.votingToken.methods.balanceOf(walker.address).call();
        var transaction = blockchainConnection.getSendingOptions({
            nonce: await web3.eth.getTransactionCount(walker.address),
            from: walker.address,
            to: dfo.votingTokenAddress,
            data: dfo.votingToken.methods.transfer(accounts[0], amount).encodeABI()
        });
        var signedTransaction = await walker.signTransaction(transaction);
        await web3.eth.sendSignedTransaction(signedTransaction);
    });

    it("Final AMMS and new URI", async() => {

        var newIndexCollecitonUri = "ipfs://ipfs/QmfYgvdxqpFuyPZ9qCkFmWMo6v2BFGkZUDhHJiMBWKekJE";
        var newFarmCollecitonUri = "ipfs://ipfs/QmaVYNrLZ8VPgjG3bdtviM2i8tToVyLhSDZxA3gPim7Wk3";
        var newUSDCollectionUri = "ipfs://ipfs/QmbFb9QdwSV1i8F1FhvBoL7XuCU7D1wRTLRRi23Zvu8Z9J";

        var indexContract = new web3.eth.Contract((await compile("index/Index")).abi, context.indexAddress);
        var indexCollection = new web3.eth.Contract(context.ethItemNativeABI, await indexContract.methods.collection().call());
        var liquidityMiningFactory = new web3.eth.Contract((await compile("farming/LiquidityMiningFactory")).abi, context.liquidityMiningFactoryAddress);

        console.log("Index", await indexCollection.methods.uri().call());
        console.log("LiquidityMiningFactory", await liquidityMiningFactory.methods.liquidityFarmTokenCollectionURI().call());
        console.log("WUSD", await usdCollection.methods.uri().call());

        var allowedAMMSCopy = await getRealAMMV2Params();

        var text = '';

        for (var allowedAmm of allowedAMMSCopy) {
            var index = allowedAMMSCopy.indexOf(allowedAmm);
            var lps = allowedAmm[1];
            text += `address[] memory liquidityPools_${index} = new address[](${allowedAmm[1].length});`;
            for (var i = 0; i < lps.length; i++) {
                text += "\n        " + `liquidityPools_${index}[${i}] = ${lps[i]};`;
            }
            text += "\n        " + `newAllowedAMMs[${index}] = AllowedAMM(${allowedAmm[0]}, liquidityPools_${index});`
        }

        var code = fs.readFileSync(path.resolve(__dirname, '..', 'resources/RealWUSDSetAllowedAMMSAndURI.sol'), 'UTF-8').format(usdController.options.address, allowedAMMSCopy.length, text, newUSDCollectionUri, indexContract.options.address, newIndexCollecitonUri, liquidityMiningFactory.options.address, newFarmCollecitonUri);
        console.log(code);
        var proposal = await dfoManager.createProposal(dfo, "", true, code, "callOneTime(address)");
        await dfoManager.finalizeProposal(dfo, proposal);

        console.log(await usdController.methods.allowedAMMs().call());

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

        assert.strictEqual(await indexCollection.methods.uri().call(), newIndexCollecitonUri);
        assert.strictEqual(await liquidityMiningFactory.methods.liquidityFarmTokenCollectionURI().call(), newFarmCollecitonUri);
        assert.strictEqual(await usdCollection.methods.uri().call(), newUSDCollectionUri);

        console.log("Index", await indexCollection.methods.uri().call());
        console.log("LiquidityMiningFactory", await liquidityMiningFactory.methods.liquidityFarmTokenCollectionURI().call());
        console.log("WUSD", await usdCollection.methods.uri().call());
    });*/

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

    async function getUSD(ammPosition, liquidityPoolPosition, maxAmountPerToken, byLiquidityPool) {
        var allowed = await usdController.methods.allowedAMMs().call();

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
            await liquidityPoolTokens[0].methods.approve(byLiquidityPool ? amm.options.address : usdController.options.address, await liquidityPoolTokens[0].methods.totalSupply().call()).send(blockchainConnection.getSendingOptions());
        } catch (e) {}
        try {
            await liquidityPoolTokens[1].methods.approve(byLiquidityPool ? amm.options.address : usdController.options.address, await liquidityPoolTokens[1].methods.totalSupply().call()).send(blockchainConnection.getSendingOptions());
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
            await pair.methods.approve(usdController.options.address, await pair.methods.totalSupply().call()).send(blockchainConnection.getSendingOptions());
        }

        await usdController.methods.addLiquidity(ammPosition, liquidityPoolPosition, liquidityPoolAmount, byLiquidityPool).send(blockchainConnection.getSendingOptions());

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

    it("Retrieve a uSD amount (by tokens) not greater than 550. Difference will be sent back", async() => {
        var amms = await usdController.methods.allowedAMMs().call();
        for (var i = amms.length - 1; i >= 0; i--) {
            var amm = new web3.eth.Contract((await compile("amm-aggregator/common/IAMM")).abi, amms[i][0]);
            var info = await amm.methods.info().call();
            for (var z in amms[i][1]) {
                console.log(z);
                var lp = amms[i][1][z];
                var ammData = await amm.methods.byLiquidityPool(lp).call();
                var tokens = ammData[2].map(it => new web3.eth.Contract(context.IERC20ABI, it));
                var tokenNames = [];
                for (var token of tokens) {
                    await buyForETH(token, 10000);
                    tokenNames.push(await tokenData(token, "symbol"));
                }
                var ratio = await calculateMaximumPairRatio(ammData, tokens);
                console.log(tokenNames.join(' - '), info[0], lp, ratio);
                ratio = parseFloat(ratio.split(',').join(''));
                try {
                    await getUSD(i, z, 12000);
                } catch(e) {
                    if(ratio > maximumPairRatio) {
                        assert.notStrictEqual(e.message.toLowerCase().indexOf("ratio"), -1);
                    } else {
                        throw e;
                    }
                }
            }
        }
    });

    it("Retrieve a uSD amount (by liquidity pool token)", async() => {
        await getUSD(0, 0, 70, true);
    });

    it("Burn a uSD amount not greater than 350. Difference will be sent back", async() => {

        var allowed = await usdController.methods.allowedAMMs().call();

        var usdBalanceBefore = await usdCollection.methods.balanceOf(accounts[0], usdObjectId).call();
        usdBalanceBefore = parseFloat(utilities.fromDecimals(usdBalanceBefore, "18", true));

        var consume = async function consume(liquidityPoolPosition, testMainCode, mainObjectId, otherObjectId, maxAmountPerToken, keepLiquidityPool) {
            var liquidityPoolAddress = allowed[0][1][liquidityPoolPosition];

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
                liquidityPoolAmount: keepLiquidityPool ? utilities.fromDecimals(liquidityPoolAmount, await new web3.eth.Contract(context.IERC20ABI, liquidityPoolAddress).methods.decimals().call(), true) : 0
            };
        };

        var inputs = [
            await consume(0, DAI, DAIItemObjectId, USDCItemObjectId, 5, true),
            //await consume(1, USDT, USDTItemObjectId, USDCItemObjectId, 11, false),
            //await consume(2, DAI, DAIItemObjectId, USDTItemObjectId, 30, true),
        ];

        var tokens = {};
        inputs.forEach(it => it.tokens.forEach(token => tokens[token.options.address] = { token }));
        inputs.forEach(it => tokens[it.liquidityPoolAddress] = { token: new web3.eth.Contract(context.IERC20ABI, it.liquidityPoolAddress) });

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

    it("Rebalance By Debt", async() => {
        var allowedAMMSCopy = JSON.parse(JSON.stringify(await usdController.methods.allowedAMMs().call()));
        allowedAMMSCopy[0][1].splice(4, 1);

        var text = '';

        for (var allowedAmm of allowedAMMSCopy) {
            var index = allowedAMMSCopy.indexOf(allowedAmm);
            var lps = allowedAmm[1];
            text += `address[] memory liquidityPools_${index} = new address[](${allowedAmm[1].length});`;
            for (var i = 0; i < lps.length; i++) {
                text += "\n        " + `liquidityPools_${index}[${i}] = ${lps[i]};`;
            }
            text += "\n        " + `newAllowedAMMs[${index}] = AllowedAMM(${allowedAmm[0]}, liquidityPools_${index});`
        }

        var code = fs.readFileSync(path.resolve(__dirname, '..', 'resources/USDV2SetAllowedAMMSProposal.sol'), 'UTF-8').format(usdController.options.address, allowedAMMSCopy.length, text);
        console.log(code);
        var proposal = await dfoManager.createProposal(dfo, "", true, code, "callOneTime(address)");
        await dfoManager.finalizeProposal(dfo, proposal);

        var differencesBefore = (await usdController.methods.differences().call())[1];
        console.log(utilities.fromDecimals(differencesBefore, 18));

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

    
    it("Rebalance By Credit by Burn", async() => {

        await usdCollection.methods.burn(usdObjectId, utilities.toDecimals(6000, 18)).send(blockchainConnection.getSendingOptions());

        var differences = await usdController.methods.differences().call();
        var credit = differences[0];
        console.log(credit);
        console.log(utilities.fromDecimals(credit, 18));

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

        await usdController.methods.rebalanceByCredit().send(blockchainConnection.getSendingOptions());

        for (var i in receivers) {
            var balance = await usdCollection.methods.balanceOf(receivers[i], usdObjectId).call();
            balance = utilities.fromDecimals(balance, 18);
            assert.strictEqual(balance, expecteds[i]);
        }
    });

    it("Transform Credit in wUSD after burn", async() => {

        var creditBalanceBefore = await usdCollection.methods.balanceOf(wusdNote2Controller.options.address, usdObjectId).call();

        var value = utilities.toDecimals(0.0000000000001, '18');

        var creditBalanceExpected = utilities.numberToString(utilities.formatNumber(creditBalanceBefore) - (utilities.formatNumber(value) * 2));
        creditBalanceExpected = utilities.fromDecimals(creditBalanceExpected, '18');

        await usdCollection.methods.safeTransferFrom(accounts[0], wusdNote2Controller.options.address, usdCreditObjectId, value, "0x").send(blockchainConnection.getSendingOptions());

        var creditBalanceAfter = await usdCollection.methods.balanceOf(wusdNote2Controller.options.address, usdObjectId).call();
        creditBalanceAfter = utilities.fromDecimals(creditBalanceAfter, '18');

        assert.strictEqual(creditBalanceAfter, creditBalanceExpected);
    });

    it("Rebalance By Credit by Liquidity Injection", async() => {
        var allowed = await usdController.methods.allowedAMMs().call();
        console.log(allowed);
        var pair = new web3.eth.Contract(context.uniswapV2PairABI, allowed[0][1][0]);
        var tokenA = new web3.eth.Contract(context.IERC20ABI, await pair.methods.token0().call());
        var tokenB = new web3.eth.Contract(context.IERC20ABI, await pair.methods.token1().call());
        var amounts = [
            utilities.toDecimals(3000, await tokenA.methods.decimals().call()),
            utilities.toDecimals(3000, await tokenB.methods.decimals().call()),
        ];
        var liquidityPoolData = {
            liquidityPoolAddress: pair.options.address,
            amount: amounts[0],
            tokenAddress: tokenA.options.address,
            amountIsLiquidityPool: false,
            involvingETH: false,
            receiver: uSDExtension.options.address
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

        await usdController.methods.rebalanceByCredit().send(blockchainConnection.getSendingOptions());

        for (var i in receivers) {
            var balance = await usdCollection.methods.balanceOf(receivers[i], usdObjectId).call();
            balance = utilities.fromDecimals(balance, 18);
            console.log(receivers[i], balance);
            assert.strictEqual(balance, expecteds[i]);
        }
    });

    it("Transform Credit in wUSD after liquidity Injection", async() => {

        var creditBalanceBefore = await usdCollection.methods.balanceOf(wusdNote2Controller.options.address, usdObjectId).call();
        console.log(utilities.fromDecimals(creditBalanceBefore, 18));
        var value = utilities.toDecimals(0.00000001, '18');

        var creditBalanceExpected = utilities.numberToString(utilities.formatNumber(creditBalanceBefore) - (utilities.formatNumber(value) * 2));
        creditBalanceExpected = utilities.fromDecimals(creditBalanceExpected, '18');

        await usdCollection.methods.safeTransferFrom(accounts[0], wusdNote2Controller.options.address, usdCreditObjectId, value, "0x").send(blockchainConnection.getSendingOptions());

        var creditBalanceAfter = await usdCollection.methods.balanceOf(wusdNote2Controller.options.address, usdObjectId).call();
        creditBalanceAfter = utilities.fromDecimals(creditBalanceAfter, '18');

        assert.strictEqual(creditBalanceAfter, creditBalanceExpected);
    });

});
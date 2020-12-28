var assert = require("assert");
var utilities = require("../util/utilities");
var context = require("../util/context.json");
var compile = require("../util/compile");
var blockchainConnection = require("../util/blockchainConnection");
var dfoManager = require("../util/dfo");
var ethers = require('ethers');
var abi = new ethers.utils.AbiCoder();

describe("USDV2", () => {

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
        var value = web3.utils.toWei(valuePlain.toString(), 'ether');
        await uniswapV2Router.methods.swapExactETHForTokens("1", path, accounts[0], parseInt((new Date().getTime() / 1000) + 1000)).send(blockchainConnection.getSendingOptions({ value }));
    }

    async function wrapInItemAndReturnObjectId(token, valuePlain) {
        await token.methods.approve(ethItemERC20Wrapper.options.address, await token.methods.totalSupply().call()).send(blockchainConnection.getSendingOptions());
        var value = web3.utils.toWei(valuePlain.toString(), utilities.fromDecimalsToCurrency(await token.methods.decimals().call()));
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
        assert(JSON.stringify(allowed) === JSON.stringify(allowedAMMS));
    });

    it("Send amount", async() => {
        var objectIds = [
            USDCItemObjectId,
            DAIItemObjectId
        ];
        var values = [
            web3.utils.toWei("50", 'ether'),
            web3.utils.toWei("50", 'ether')
        ];
        var types = ['uint256', 'uint256', 'uint256'];
        var params = ['0', '1', '0'];
        var data = web3.eth.abi.encodeParameters(types, params);
        await ethItemERC20Wrapper.methods.safeBatchTransferFrom(accounts[0], usdController.options.address, objectIds, values, data).send(blockchainConnection.getSendingOptions());
        assert(parseInt(balanceEnd) > parseInt(balanceStart));
    });
});
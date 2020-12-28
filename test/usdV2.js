var assert = require("assert");
var utilities = require("../util/utilities");
var context = require("../util/context.json");
var compile = require("../util/compile");
var blockchainConnection = require("../util/blockchainConnection");
var ethers = require('ethers');
var abi = new ethers.utils.AbiCoder();

describe("USDV2", () => {
    var USDExtensionController;
    var UniswapV2AMMV1;

    var ethItemOrchestrator;
    var uniswapV2Router;
    var uniswapV2Factory;
    var wethToken;
    var USDC;
    var USDT;
    var DAI;
    var uniswapAMM;
    var usdController;
    var allowedAMMS;

    before(async() => {
        await blockchainConnection.init;

        USDExtensionController = await compile('usd-v2/USDExtensionController');
        UniswapV2AMMV1 = await compile('amm-aggregator/models/UniswapV2/1/UniswapV2AMMV1');

        ethItemOrchestrator = new web3.eth.Contract(context.ethItemOrchestratorABI, context.ethItemOrchestratorAddress);
        uniswapV2Router = new web3.eth.Contract(context.uniswapV2RouterABI, context.uniswapV2RouterAddress);
        uniswapV2Factory = new web3.eth.Contract(context.uniswapV2FactoryABI, context.uniswapV2FactoryAddress);

        wethToken = new web3.eth.Contract(context.IERC20ABI, await uniswapV2Router.methods.WETH().call());
        USDT = new web3.eth.Contract(context.IERC20ABI, context.usdtTokenAddress);
        USDC = new web3.eth.Contract(context.IERC20ABI, context.usdcTokenAddress);
        DAI = new web3.eth.Contract(context.IERC20ABI, context.daiTokenAddress);

        await buyForETH(USDT, 10);
        await buyForETH(USDC, 10);
        await buyForETH(DAI, 10);

        uniswapAMM = await new web3.eth.Contract(UniswapV2AMMV1.abi).deploy({ data: UniswapV2AMMV1.bin, arguments: [uniswapV2Router.options.address] }).send(blockchainConnection.getSendingOptions());
    });

    async function buyForETH(token, amount) {
        var path = [
            wethToken.options.address,
            token.options.address
        ];
        var value = web3.utils.toWei(amount.toString(), 'ether');
        await uniswapV2Router.methods.swapExactETHForTokens("1", path, accounts[0], parseInt((new Date().getTime() / 1000) + 1000)).send(blockchainConnection.getSendingOptions({ value }));
    };

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
            utilities.voidEthereumAddress, ["15", "1000"],
            [accounts[0]],
            await encodeAMMV2Params()
        ];
        usdController = await new web3.eth.Contract(USDExtensionController.abi).deploy({ data: USDExtensionController.bin, arguments }).send(blockchainConnection.getSendingOptions());
        await usdController.methods.init(ethItemOrchestrator.options.address, "Unified Stable Dollar", "USD", "google.com").send(blockchainConnection.getSendingOptions());
        await usdController.methods.initUsdCollection("Unified Stable Dollar", "USD", "google.com").send(blockchainConnection.getSendingOptions());
        await usdController.methods.initCreditCollection("Unified Stable Dollar Credit", "USDC", "google.com").send(blockchainConnection.getSendingOptions());
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
});
var assert = require("assert");
var utilities = require("../util/utilities");
var context = require("../util/context.json");
var compile = require("../util/compile");
var blockchainConnection = require("../util/blockchainConnection");
var dfoManager = require('../util/dfo');
var dfoHubManager = require('../util/dfoHub');
var path = require('path');
var fs = require('fs');

var ethToSpend = 600000;

var aMMAggregator;
var uniswapAMM;

var presto;
var amm;

describe("Presto", () => {

    async function nothingInContracts(address) {
        var toCheck = [utilities.voidEthereumAddress];
        toCheck.push(...tokens.map(it => it));
        for (var tkn of toCheck) {
            try {
                assert.strictEqual(tkn === utilities.voidEthereumAddress ? await web3.eth.getBalance(address) : await tkn.methods.balanceOf(address).call(), '0');
            } catch (e) {
                console.error(`MONEY - ${await tokenData(tkn, 'symbol')} - ${address} - ${e.message}`);
            }
        }
    }

    async function buyForETH(token, amount, ammPlugin) {
        var value = utilities.toDecimals(amount.toString(), '18');
        if (token.options.address === context.wethTokenAddress) {
            return await web3.eth.sendTransaction(blockchainConnection.getSendingOptions({
                to: context.wethTokenAddress,
                value,
                data: web3.utils.sha3("deposit()").substring(0, 10)
            }));
        }
        ammPlugin = ammPlugin || amm;
        var ethereumAddress = (await ammPlugin.methods.data().call())[0];
        var liquidityPoolAddress = (await ammPlugin.methods.byTokens([
            ethereumAddress,
            token.options.address
        ]).call())[2];
        await ammPlugin.methods.swapLiquidity({
            amount: value,
            enterInETH: true,
            exitInETH: false,
            liquidityPoolAddresses: [liquidityPoolAddress],
            path: [token.options.address],
            inputToken: ethereumAddress,
            receiver: utilities.voidEthereumAddress
        }).send(blockchainConnection.getSendingOptions({ value }));
    }

    async function tokenName(token) {
        try {
            return await token.methods.name().call();
        } catch (e) {}
        var raw = await web3.eth.call({
            to: token.options.address,
            data: web3.utils.sha3("name()").substring(0, 10)
        });
        return web3.utils.toUtf8(raw);
    }

    async function calculateTokenAmount(tokenAddress, tokenAmount, amountIsPercentage) {
        if (tokenAddress == utilities.voidEthereumAddress || amountIsPercentage) {
            return tokenAmount;
        }
        var token = new web3.eth.Contract(context.IERC20ABI, tokenAddress);
        var totalSupply = await token.methods.totalSupply();
        var ONE_HUNDRED = await presto.methods.ONE_HUNDRED().call();
        var amount = web3.utils.toBN(totalSupply).mul(web3.utils.toBN(tokenAmount).mul(web3.utils.toBN(1e18)).div(web3.utils.toBN(ONE_HUNDRED))).div(web3.utils.toBN(1e18));
        return amount.toString();
    }

    async function calculatePercentage(totalAmount, percentage) {
        var ONE_HUNDRED = await presto.methods.ONE_HUNDRED().call();
        var amount = web3.utils.toBN(totalAmount).mul(web3.utils.toBN(percentage).mul(web3.utils.toBN(1e18)).div(web3.utils.toBN(ONE_HUNDRED))).div(web3.utils.toBN(1e18));
        return amount.toString();
    }

    async function calculateTokenPercentage(tokenAddress, tokenAmount, amountIsPercentage, percentage) {
        return await calculatePercentage(await calculateTokenAmount(tokenAddress, tokenAmount, amountIsPercentage), percentage);
    }

    it("Setup", async() => {

        await dfoHubManager.init;

        var Presto = await compile('presto/Presto');

        var AMMAggregator = await compile('amm-aggregator/aggregator/AMMAggregator');
        var IAMM = await compile('amm-aggregator/common/IAMM');

        aMMAggregator = new web3.eth.Contract(AMMAggregator.abi, context.ammAggregatorAddress);

        uniswapAMM = new web3.eth.Contract(IAMM.abi, (await aMMAggregator.methods.amms().call())[3]);

        presto = await new web3.eth.Contract(Presto.abi).deploy({data: Presto.bin, arguments : [dfoHubManager.dfos.covenants.doubleProxyAddress, 0]});

        tokens = [
            context.wethTokenAddress,
            context.usdtTokenAddress,
            context.chainLinkTokenAddress,
            context.usdcTokenAddress,
            context.daiTokenAddress,
            context.mkrTokenAddress,
            context.buidlTokenAddress,
            context.balTokenAddress
        ].map(it => new web3.eth.Contract(context.IERC20ABI, it));

        await Promise.all(tokens.map(it => buyForETH(it, ethToSpend, uniswapAMM)));
    });

    it("Set new swap entries", async() => {

        var operations = [{
            inputTokenAddress: utilities.voidEthereumAddress,
            inputTokenAmount: utilities.toDecimals("0.02", "18"),
            ammPlugin: utilities.voidEthereumAddress,
            liquidityPoolAddresses: [],
            swapPath: [],
            receivers: [accounts[1]],
            receiversPercentages: [],
            enterInETH: false,
            exitInETH: false
        }, {
            inputTokenAddress: dfoHubManager.dfos.dfoHub.votingTokenAddress,
            inputTokenAmount: utilities.toDecimals("0.01", "18"),
            ammPlugin: utilities.voidEthereumAddress,
            liquidityPoolAddresses: [],
            swapPath: [],
            receivers: [accounts[1]],
            receiversPercentages: [],
            enterInETH: false,
            exitInETH: false
        }, {
            inputTokenAddress: dfoHubManager.dfos.dfoHub.votingTokenAddress,
            inputTokenAmount: 100,
            ammPlugin: utilities.voidEthereumAddress,
            liquidityPoolAddresses: [],
            swapPath: [],
            receivers: [accounts[1]],
            receiversPercentages: [],
            enterInETH: false,
            exitInETH: false
        }, {
            inputTokenAddress: context.wethTokenAddress,
            inputTokenAmount: utilities.toDecimals("0.15", "18"),
            inputTokenAmountIsPercentage: false,
            inputTokenAmountIsByMint: false,
            ammPlugin: uniswapAMM.options.address,
            liquidityPoolAddresses: [
                (await uniswapAMM.methods.byTokens([context.wethTokenAddress, context.buidlTokenAddress]).call())[2]
            ],
            swapPath: [
                context.buidlTokenAddress
            ],
            receivers: [accounts[1]],
            receiversPercentages: [],
            enterInETH: true,
            exitInETH: false
        }, {
            inputTokenAddress: context.wethTokenAddress,
            inputTokenAmount: utilities.toDecimals("0.01", "18"),
            inputTokenAmountIsPercentage: false,
            inputTokenAmountIsByMint: false,
            ammPlugin: uniswapAMM.options.address,
            liquidityPoolAddresses: [
                (await uniswapAMM.methods.byTokens([context.wethTokenAddress, context.buidlTokenAddress]).call())[2]
            ],
            swapPath: [
                context.buidlTokenAddress
            ],
            receivers: [accounts[1]],
            receiversPercentages: [],
            enterInETH: false,
            exitInETH: false
        }, {
            inputTokenAddress: context.buidlTokenAddress,
            inputTokenAmount: utilities.toDecimals("600", "18"),
            inputTokenAmountIsPercentage: false,
            inputTokenAmountIsByMint: false,
            ammPlugin: uniswapAMM.options.address,
            liquidityPoolAddresses: [
                (await uniswapAMM.methods.byTokens([context.wethTokenAddress, context.buidlTokenAddress]).call())[2]
            ],
            swapPath: [
                context.wethTokenAddress
            ],
            receivers: ["0x5D40c724ba3e7Ffa6a91db223368977C522BdACD", "0x32c87193C2cC9961F2283FcA3ca11A483d8E426B", "0x25756f9C2cCeaCd787260b001F224159aB9fB97A"],
            receiversPercentages: ["220000000000000000", "50000000000000000"],
            enterInETH: false,
            exitInETH: true
        }, {
            inputTokenAddress: context.buidlTokenAddress,
            inputTokenAmount: utilities.toDecimals("0.5", "18"),
            inputTokenAmountIsPercentage: false,
            inputTokenAmountIsByMint: false,
            ammPlugin: uniswapAMM.options.address,
            liquidityPoolAddresses: [
                (await uniswapAMM.methods.byTokens([context.wethTokenAddress, context.buidlTokenAddress]).call())[2]
            ],
            swapPath: [
                context.wethTokenAddress
            ],
            receivers: [accounts[1]],
            receiversPercentages: [],
            enterInETH: false,
            exitInETH: false
        }];

        var balanceOfExpected = await web3.eth.getBalance(receiver);
        balanceOfExpected = web3.utils.toBN(balanceOfExpected).add(web3.utils.toBN(await calculateTokenPercentage(operation.inputTokenAddress, operation.inputTokenAmount, operation.inputTokenAmountIsPercentage, entry.callerRewardPercentage))).toString();

        var transactionResult = await fixedInflation.methods.execute(earnByInput).send(blockchainConnection.getSendingOptions());

        balanceOfExpected = web3.utils.toBN(balanceOfExpected).sub(web3.utils.toBN(await blockchainConnection.calculateTransactionFee(transactionResult))).toString();

        balanceOfExpected = utilities.fromDecimals(balanceOfExpected, 18);

        var balanceOfAfter = await web3.eth.getBalance(receiver);
        balanceOfAfter = utilities.fromDecimals(balanceOfAfter, 18);

        assert.strictEqual(balanceOfAfter, balanceOfExpected);

        await nothingInContracts(fixedInflation.options.address);
    });
});
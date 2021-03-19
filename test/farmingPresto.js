var assert = require("assert");
var utilities = require("../util/utilities");
var context = require("../util/context.json");
var compile = require("../util/compile");
var blockchainConnection = require("../util/blockchainConnection");
var dfoManager = require('../util/dfo');
var dfoHubManager = require('../util/dfoHub');
var path = require('path');
var fs = require('fs');
var ethers = require('ethers');
var abi = new ethers.utils.AbiCoder();

var ethToSpend = 600000;

var aMMAggregator;
var amms;
var uniswapAMM;
var wusdExtensionController;
var wusdCollection;
var wusdObjectId;
var allowedAMMS;

var presto;
var farmingPresto;
var amm;
var farmMain;

describe("Farming Presto", () => {

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

    async function dumpAllowedAMMS() {
        for(var i in allowedAMMS) {
            var amm = Object.values(amms).filter(it => it.address === allowedAMMS[i][0])[0];
            console.log(i, amm.info);
            for(z in allowedAMMS[i][1]) {
                var liquidityPool = allowedAMMS[i][1][z];
                var tokens = await amm.contract.methods.byLiquidityPool(liquidityPool).call();
                console.log(i, z, await tokenData(new web3.eth.Contract(context.IERC20ABI, tokens[2][0]), 'symbol'), await tokenData(new web3.eth.Contract(context.IERC20ABI, tokens[2][1]), "symbol"));
            }
        }
    }

    it("Setup", async() => {

        await dfoHubManager.init;

        var Presto = await compile('presto/Presto');
        var FarmingPresto = await compile('presto/verticalizations/FarmingPresto');
        var WUSDExtensionController = await compile('WUSD/WUSDExtensionController');
        var FarmMain = await compile("farming/FarmMain");

        farmMain = new web3.eth.Contract(FarmMain.abi, "0x41Bff124bfF2046Af9fbaF11EcB685cBb70C01Ed");

        wusdExtensionController = new web3.eth.Contract(WUSDExtensionController.abi, context.wusdExtensionControllerAddress);
        var data = await wusdExtensionController.methods.wusdInfo().call();
        wusdCollection = new web3.eth.Contract(context.ethItemNativeABI, data[0]);
        wusdObjectId = data[1];
        var wusdInteroperableInterfaceAddress = data[2];

        var AMMAggregator = await compile('amm-aggregator/aggregator/AMMAggregator');
        var IAMM = await compile('amm-aggregator/common/IAMM');

        aMMAggregator = new web3.eth.Contract(AMMAggregator.abi, context.ammAggregatorAddress);
        amms = {};
        var ammAddresses = await aMMAggregator.methods.amms().call();
        var ammsArray = ammAddresses.map(it => new web3.eth.Contract(IAMM.abi, web3.utils.toChecksumAddress(it)));
        for (var contract of ammsArray) {
            var info = await contract.methods.info().call();
            var data = await contract.methods.data().call();
            amms[info[0]] = {
                contract,
                address: contract.options.address,
                info,
                data,
                ethereumAddress: data[0]
            };
        }
        uniswapAMM = amms["UniswapV2"].contract;

        presto = await new web3.eth.Contract(Presto.abi, context.prestoAddress);
        farmingPresto = await new web3.eth.Contract(FarmingPresto.abi).deploy({ data: FarmingPresto.bin }).send(blockchainConnection.getSendingOptions());

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

        tokens.push(new web3.eth.Contract(context.IERC20ABI, web3.utils.toChecksumAddress(wusdInteroperableInterfaceAddress)));

        await dumpAllowedAMMS();
    });

    it("Open Position - Swap for ETH", async () => {

        var setups = await farmMain.methods.setups().call();

        var info = (await farmMain.methods.setup(setups.indexOf(setups.filter(it => it.active)[0])).call())[1];

        var ammContract = Object.values(amms).filter(it => it.address === info.ammPlugin)[0].contract;
        var liquidityPool = info.liquidityPoolTokenAddress;

        var tokens = await ammContract.methods.byLiquidityPool(liquidityPool).call();
        var token0 = new web3.eth.Contract(context.IERC20ABI, tokens[2][0]);
        var token1 = new web3.eth.Contract(context.IERC20ABI, tokens[2][1]);
        var token0decimals = tokens[2][0] === utilities.voidEthereumAddress ? 18 : await token0.methods.decimals().call();
        var token1decimals = tokens[2][1] === utilities.voidEthereumAddress ? 18 : await token1.methods.decimals().call();

        var amm = utilities.getRandomArrayElement(Object.values(amms)).contract;

        var amount = 0.1;

        var value = utilities.toDecimals(utilities.numberToString(amount), 18);

        var halfValue = web3.utils.toBN(value).div(web3.utils.toBN(2)).toString();

        var ethereumAddress = (await amm.methods.data().call())[0];

        console.log("WeWE2");

        async function calculateBestLP(firstToken, secondToken, firstDecimals, secondDecimals) {

            var liquidityPoolAddress = (await amm.methods.byTokens([ethereumAddress, firstToken]).call())[2];
            var firstTokenEthLiquidityPoolAddress = liquidityPoolAddress;
            var token0Value = (await amm.methods.getSwapOutput(ethereumAddress, halfValue, [liquidityPoolAddress], [firstToken]).call())[1];

            var token1Value = (await ammContract.methods.byTokenAmount(liquidityPool, firstToken, token0Value).call());
            var lpAmount = token1Value[0];
            token1Value = token1Value[1][token1Value[2].indexOf(secondToken)];

            const updatedFirstTokenAmount = utilities.formatNumber(utilities.normalizeValue(token0Value, firstDecimals));
            const updatedSecondTokenAmount = utilities.formatNumber(utilities.normalizeValue(token1Value, secondDecimals));

            liquidityPoolAddress = (await amm.methods.byTokens([ethereumAddress, secondToken]).call())[2];
            var secondTokenEthLiquidityPoolAddress = liquidityPoolAddress;
            var token1ValueETH = (await amm.methods.getSwapOutput(secondToken, token1Value, [liquidityPoolAddress], [ethereumAddress]).call())[1];

            return { lpAmount, updatedFirstTokenAmount, updatedSecondTokenAmount, token0Value, token1Value, token1ValueETH, firstTokenEthLiquidityPoolAddress, secondTokenEthLiquidityPoolAddress };
        }

        var bestLP = await calculateBestLP(token0.options.address, token1.options.address, token0decimals, token1decimals);

        var lpAmount = bestLP.lpAmount;
        var firstTokenAmount = bestLP.token0Value;
        var secondTokenAmount = bestLP.token1Value;
        var firstTokenETH = halfValue;
        var secondTokenETH = bestLP.token1ValueETH;
        var token0EthLiquidityPoolAddress = bestLP.firstTokenEthLiquidityPoolAddress;
        var token1EthLiquidityPoolAddress = bestLP.secondTokenEthLiquidityPoolAddress;

        if (bestLP.updatedSecondTokenAmount > bestLP.updatedFirstTokenAmount) {
            bestLP = await calculateBestLP(token1.options.address, token0.options.address, token1decimals, token0decimals);

            lpAmount = bestLP.lpAmount;
            firstTokenAmount = bestLP.token1Value;
            secondTokenAmount = bestLP.token0Value;
            firstTokenETH = bestLP.token1ValueETH;
            secondTokenETH = halfValue;
            token0EthLiquidityPoolAddress = bestLP.secondTokenEthLiquidityPoolAddress;
            token1EthLiquidityPoolAddress = bestLP.firstTokenEthLiquidityPoolAddress;
        }

        console.log("WeWE2");

        var expectedWUSDBalance = await wusdCollection.methods.balanceOf(accounts[0], wusdObjectId).call();
        expectedWUSDBalance = web3.utils.toBN(expectedWUSDBalance).add(web3.utils.toBN(utilities.numberToString(bestLP.updatedFirstTokenAmount))).add(web3.utils.toBN(utilities.numberToString(bestLP.updatedSecondTokenAmount))).toString();

        var operations = [{
            inputTokenAddress : ethereumAddress,
            inputTokenAmount : firstTokenETH,
            ammPlugin : amm.options.address,
            liquidityPoolAddresses : [token0EthLiquidityPoolAddress],
            swapPath : [token0.options.address],
            enterInETH : true,
            exitInETH : false,
            receivers : [farmingPresto.options.address],
            receiversPercentages : []
        }, {
            inputTokenAddress : ethereumAddress,
            inputTokenAmount : secondTokenETH,
            ammPlugin : amm.options.address,
            liquidityPoolAddresses : [token1EthLiquidityPoolAddress],
            swapPath : [token1.options.address],
            enterInETH : true,
            exitInETH : false,
            receivers : [farmingPresto.options.address],
            receiversPercentages : []
        }];

        var value = web3.utils.toBN(firstTokenETH).add(web3.utils.toBN(secondTokenETH)).toString();

        var expectedETHBalance = await web3.eth.getBalance(accounts[0]);
        expectedETHBalance = web3.utils.toBN(expectedETHBalance).sub(web3.utils.toBN(value)).toString();

        var transaction = await farmingPresto.methods.openPosition(
            presto.options.address,
            operations,
            farmMain.options.address,
            ammPosition,
            liquidityPoolPosition
        ).send(blockchainConnection.getSendingOptions({value}));
        var transactionFee = await blockchainConnection.calculateTransactionFee(transaction);

        await nothingInContracts(wusdPresto.options.address);
        await nothingInContracts(presto.options.address);

        expectedETHBalance = web3.utils.toBN(expectedETHBalance).sub(web3.utils.toBN(transactionFee)).toString();
        var ethBalance = await web3.eth.getBalance(accounts[0]);
        expectedETHBalance = utilities.fromDecimals(expectedETHBalance, 18);
        ethBalance = utilities.fromDecimals(ethBalance, 18);

        assert.strictEqual(ethBalance, expectedETHBalance, "Incorrect ETH Balance");

        expectedWUSDBalance = utilities.fromDecimals(expectedWUSDBalance, 18);
        var wusdBalance = await wusdCollection.methods.balanceOf(accounts[0], wusdObjectId).call();
        wusdBalance = utilities.fromDecimals(wusdBalance, 18);

        console.log(wusdBalance, expectedWUSDBalance);

        assert(utilities.formatNumber(wusdBalance) <= utilities.formatNumber(expectedWUSDBalance), "Incorrect WUSD Balance");
    });

});
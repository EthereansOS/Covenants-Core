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
var wusdPresto;
var indexPresto;
var amm;

describe("Presto", () => {

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
        var WUSDPresto = await compile('presto/verticalizations/WUSDPresto');
        var IndexPresto = await compile('presto/verticalizations/IndexPresto');
        var WUSDExtensionController = await compile('WUSD/WUSDExtensionController');

        wusdExtensionController = new web3.eth.Contract(WUSDExtensionController.abi, context.wusdExtensionControllerAddress);
        allowedAMMS = await wusdExtensionController.methods.allowedAMMs().call();

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

        presto = await new web3.eth.Contract(Presto.abi).deploy({ data: Presto.bin, arguments: [dfoHubManager.dfos.covenants.doubleProxyAddress, 0] }).send(blockchainConnection.getSendingOptions());
        wusdPresto = await new web3.eth.Contract(WUSDPresto.abi).deploy({ data: WUSDPresto.bin }).send(blockchainConnection.getSendingOptions());
        indexPresto = await new web3.eth.Contract(IndexPresto.abi).deploy({ data: IndexPresto.bin }).send(blockchainConnection.getSendingOptions());

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

    it("WUSD - Swap for ETH", async () => {

        var ammPosition = utilities.getRandomArrayIndex(allowedAMMS);
        var liquidityPoolPosition = utilities.getRandomArrayIndex(allowedAMMS[ammPosition][1]);
        var liquidityPool = allowedAMMS[ammPosition][1][liquidityPoolPosition];
        var ammContract = Object.values(amms).filter(it => it.address === allowedAMMS[ammPosition][0])[0].contract;
        var tokens = await ammContract.methods.byLiquidityPool(liquidityPool).call();
        var token0 = new web3.eth.Contract(context.IERC20ABI, tokens[2][0]);
        var token1 = new web3.eth.Contract(context.IERC20ABI, tokens[2][1]);
        var token0decimals = await token0.methods.decimals().call();
        var token1decimals = await token1.methods.decimals().call();

        var amm = utilities.getRandomArrayElement(Object.values(amms)).contract;

        var amount = 0.1;

        var value = utilities.toDecimals(utilities.numberToString(amount), 18);
        var halfValue = web3.utils.toBN(value).div(web3.utils.toBN(2)).toString();
        var ethereumAddress = (await amm.methods.data().call())[0];

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
            receivers : [wusdPresto.options.address],
            receiversPercentages : []
        }, {
            inputTokenAddress : ethereumAddress,
            inputTokenAmount : secondTokenETH,
            ammPlugin : amm.options.address,
            liquidityPoolAddresses : [token1EthLiquidityPoolAddress],
            swapPath : [token1.options.address],
            enterInETH : true,
            exitInETH : false,
            receivers : [wusdPresto.options.address],
            receiversPercentages : []
        }];

        var value = web3.utils.toBN(firstTokenETH).add(web3.utils.toBN(secondTokenETH)).toString();

        var expectedETHBalance = await web3.eth.getBalance(accounts[0]);
        expectedETHBalance = web3.utils.toBN(expectedETHBalance).sub(web3.utils.toBN(value)).toString();

        console.log('Adding liquidity');

        var transaction = await wusdPresto.methods.addLiquidity(
            presto.options.address,
            operations,
            context.wusdExtensionControllerAddress,
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

    it("WUSD - Swap for Token", async () => {

        var ammPosition = utilities.getRandomArrayIndex(allowedAMMS);
        var liquidityPoolPosition = utilities.getRandomArrayIndex(allowedAMMS[ammPosition][1]);
        ammPosition = 0;
        liquidityPoolPosition = 0;
        var liquidityPool = allowedAMMS[ammPosition][1][liquidityPoolPosition];
        var ammContract = Object.values(amms).filter(it => it.address === allowedAMMS[ammPosition][0])[0].contract;
        var tokens = await ammContract.methods.byLiquidityPool(liquidityPool).call();
        var token0 = new web3.eth.Contract(context.IERC20ABI, tokens[2][0]);
        var token1 = new web3.eth.Contract(context.IERC20ABI, tokens[2][1]);
        await buyForETH(token0, 10, ammContract);
        var token0decimals = await token0.methods.decimals().call();
        var token1decimals = await token1.methods.decimals().call();

        var amm = ammContract;

        var amount = 3000;

        var value = utilities.toDecimals(utilities.numberToString(amount), 18);
        var halfValue = web3.utils.toBN(value).div(web3.utils.toBN(2)).toString();
        var ethereumAddress = (await amm.methods.data().call())[0];

        async function calculateBestLP(firstToken, secondToken, firstDecimals, secondDecimals) {

            var liquidityPoolAddress = (await amm.methods.byTokens([firstToken, secondToken]).call())[2];
            var token1Value = (await amm.methods.getSwapOutput(firstToken, halfValue, [liquidityPoolAddress], [secondToken]).call())[1];

            var token0Value = (await ammContract.methods.byTokenAmount(liquidityPool, secondToken, token1Value).call());
            var lpAmount = token0Value[0];
            token0Value = token0Value[1][token0Value[2].indexOf(firstToken)];

            const updatedFirstTokenAmount = utilities.formatNumber(utilities.normalizeValue(token0Value, firstDecimals));
            const updatedSecondTokenAmount = utilities.formatNumber(utilities.normalizeValue(token1Value, secondDecimals));

            return { lpAmount, updatedFirstTokenAmount, updatedSecondTokenAmount, token0Value, token1Value, liquidityPoolAddress };
        }

        var bestLP = await calculateBestLP(token0.options.address, token1.options.address, token0decimals, token1decimals);

        var lpAmount = bestLP.lpAmount;
        var firstTokenAmount = bestLP.token0Value;
        var secondTokenAmount = bestLP.token1Value;
        var firstTokenETH = halfValue;
        var secondTokenETH = bestLP.token1ValueETH;
        var token0EthLiquidityPoolAddress = bestLP.firstTokenEthLiquidityPoolAddress;
        var token1EthLiquidityPoolAddress = bestLP.secondTokenEthLiquidityPoolAddress;

        var expectedWUSDBalance = await wusdCollection.methods.balanceOf(accounts[0], wusdObjectId).call();
        expectedWUSDBalance = web3.utils.toBN(expectedWUSDBalance).add(web3.utils.toBN(utilities.numberToString(bestLP.updatedFirstTokenAmount))).add(web3.utils.toBN(utilities.numberToString(bestLP.updatedSecondTokenAmount))).toString();

        /*if (bestLP.updatedSecondTokenAmount > bestLP.updatedFirstTokenAmount) {
            bestLP = await calculateBestLP(token1.options.address, token0.options.address, token1decimals, token0decimals);

            lpAmount = bestLP.lpAmount;
            firstTokenAmount = bestLP.token1Value;
            secondTokenAmount = bestLP.token0Value;
            firstTokenETH = bestLP.token1ValueETH;
            secondTokenETH = halfValue;
            token0EthLiquidityPoolAddress = bestLP.secondTokenEthLiquidityPoolAddress;
            token1EthLiquidityPoolAddress = bestLP.firstTokenEthLiquidityPoolAddress;
        }*/

        var operations = [{
            inputTokenAddress : token0.options.address,
            inputTokenAmount : halfValue,
            ammPlugin : amm.options.address,
            liquidityPoolAddresses : [bestLP.liquidityPoolAddress],
            swapPath : [token1.options.address],
            enterInETH : false,
            exitInETH : false,
            receivers : [wusdPresto.options.address],
            receiversPercentages : []
        }, {
            inputTokenAddress : token0.options.address,
            inputTokenAmount : halfValue,
            ammPlugin : utilities.voidEthereumAddress,
            liquidityPoolAddresses : [],
            swapPath : [],
            enterInETH : false,
            exitInETH : false,
            receivers : [],
            receiversPercentages : []
        }];

        //var value = web3.utils.toBN(firstTokenETH).add(web3.utils.toBN(secondTokenETH)).toString();

        var expectedETHBalance = await web3.eth.getBalance(accounts[0]);
        //expectedETHBalance = web3.utils.toBN(expectedETHBalance).sub(web3.utils.toBN(value)).toString();

        console.log('Adding liquidity');

        await token0.methods.approve(wusdPresto.options.address, value).send(blockchainConnection.getSendingOptions());

        var transaction = await wusdPresto.methods.addLiquidity(
            presto.options.address,
            operations,
            context.wusdExtensionControllerAddress,
            ammPosition,
            liquidityPoolPosition
        ).send(blockchainConnection.getSendingOptions());
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

        assert(utilities.formatNumber(wusdBalance) >= utilities.formatNumber(expectedWUSDBalance), "Incorrect WUSD Balance");
    });

    it("YOUSONOFABITCH", async () => {

        var ammPosition = utilities.getRandomArrayIndex(allowedAMMS);
        var liquidityPoolPosition = utilities.getRandomArrayIndex(allowedAMMS[ammPosition][1]);
        ammPosition = 0;
        liquidityPoolPosition = 0;
        var liquidityPool = allowedAMMS[ammPosition][1][liquidityPoolPosition];
        var ammContract = Object.values(amms).filter(it => it.address === allowedAMMS[ammPosition][0])[0].contract;
        var tokens = await ammContract.methods.byLiquidityPool(liquidityPool).call();
        var token0 = new web3.eth.Contract(context.IERC20ABI, tokens[2][0]);
        var token1 = new web3.eth.Contract(context.IERC20ABI, tokens[2][1]);
        await buyForETH(token0, 10, ammContract);
        await buyForETH(token1, 10, ammContract);
        var token0decimals = await token0.methods.decimals().call();
        var token1decimals = await token1.methods.decimals().call();

        var ethereumAddress = (await ammContract.methods.data().call())[0];

        var token0ETHLP = (await ammContract.methods.byTokens([token0.options.address, ethereumAddress]).call())[2];
        var token1ETHLP = (await ammContract.methods.byTokens([token1.options.address, ethereumAddress]).call())[2];

        var operations = [{
            inputTokenAddress : token0.options.address,
            inputTokenAmount : utilities.toDecimals(10, token0decimals),
            ammPlugin : ammContract.options.address,
            liquidityPoolAddresses : [liquidityPool],
            swapPath : [token1.options.address],
            enterInETH : false,
            exitInETH : false,
            receivers : [wusdPresto.options.address],
            receiversPercentages : []
        }, {
            inputTokenAddress : token0.options.address,
            inputTokenAmount : utilities.toDecimals(18, token0decimals),
            ammPlugin : utilities.voidEthereumAddress,
            liquidityPoolAddresses : [],
            swapPath : [],
            enterInETH : false,
            exitInETH : false,
            receivers : [],
            receiversPercentages : []
        }, {
            inputTokenAddress : ethereumAddress,
            inputTokenAmount : utilities.toDecimals(1, 18),
            ammPlugin : ammContract.options.address,
            liquidityPoolAddresses : [token0ETHLP],
            swapPath : [token0.options.address],
            enterInETH : true,
            exitInETH : false,
            receivers : [wusdPresto.options.address],
            receiversPercentages : []
        }, {
            inputTokenAddress : token1.options.address,
            inputTokenAmount : utilities.toDecimals(20, token1decimals),
            ammPlugin : ammContract.options.address,
            liquidityPoolAddresses : [liquidityPool],
            swapPath : [token0.options.address],
            enterInETH : false,
            exitInETH : false,
            receivers : [wusdPresto.options.address],
            receiversPercentages : []
        }, {
            inputTokenAddress : token1.options.address,
            inputTokenAmount : utilities.toDecimals(11, token1decimals),
            ammPlugin : utilities.voidEthereumAddress,
            liquidityPoolAddresses : [],
            swapPath : [],
            enterInETH : false,
            exitInETH : false,
            receivers : [],
            receiversPercentages : []
        }, {
            inputTokenAddress : ethereumAddress,
            inputTokenAmount : utilities.toDecimals(1, 18),
            ammPlugin : ammContract.options.address,
            liquidityPoolAddresses : [token1ETHLP],
            swapPath : [token1.options.address],
            enterInETH : true,
            exitInETH : false,
            receivers : [wusdPresto.options.address],
            receiversPercentages : []
        }];

        console.log(utilities.fromDecimals(await wusdCollection.methods.balanceOf(accounts[0], wusdObjectId).call(), 18));

        await token0.methods.approve(wusdPresto.options.address, await token0.methods.balanceOf(accounts[0]).call()).send(blockchainConnection.getSendingOptions());
        await token1.methods.approve(wusdPresto.options.address, await token1.methods.balanceOf(accounts[0]).call()).send(blockchainConnection.getSendingOptions());

        var ethValue = '0';
        for(var operation of operations) {
            if(operation.inputTokenAddress === ethereumAddress && operation.enterInETH) {
                ethValue = web3.utils.toBN(ethValue).add(web3.utils.toBN(operation.inputTokenAmount)).toString();
            }
        }

        await wusdPresto.methods.addLiquidity(
            presto.options.address,
            operations,
            context.wusdExtensionControllerAddress,
            ammPosition,
            liquidityPoolPosition
        ).send(blockchainConnection.getSendingOptions({value : ethValue}));

        await nothingInContracts(wusdPresto.options.address);
        await nothingInContracts(presto.options.address);

        console.log(utilities.fromDecimals(await wusdCollection.methods.balanceOf(accounts[0], wusdObjectId).call(), 18));
    });

    it("WUSD - Burn for eth", async () => {

        var ammPosition = utilities.getRandomArrayIndex(allowedAMMS);
        var liquidityPoolPosition = utilities.getRandomArrayIndex(allowedAMMS[ammPosition][1]);
        ammPosition = 0;
        liquidityPoolPosition = 0;
        var liquidityPool = allowedAMMS[ammPosition][1][liquidityPoolPosition];
        var ammContract = Object.values(amms).filter(it => it.address === allowedAMMS[ammPosition][0])[0].contract;
        var tokens = await ammContract.methods.byLiquidityPool(liquidityPool).call();
        var token0 = new web3.eth.Contract(context.IERC20ABI, tokens[2][0]);
        var token1 = new web3.eth.Contract(context.IERC20ABI, tokens[2][1]);
        await buyForETH(token0, 10, ammContract);
        await buyForETH(token1, 10, ammContract);
        var token0decimals = await token0.methods.decimals().call();
        var token1decimals = await token1.methods.decimals().call();

        var ethereumAddress = (await ammContract.methods.data().call())[0];

        var token0ETHLP = (await ammContract.methods.byTokens([token0.options.address, ethereumAddress]).call())[2];
        var token1ETHLP = (await ammContract.methods.byTokens([token1.options.address, ethereumAddress]).call())[2];

        var operations = [{
            inputTokenAddress : token0.options.address,
            inputTokenAmount : utilities.toDecimals(10, token0decimals),
            ammPlugin : ammContract.options.address,
            liquidityPoolAddresses : [liquidityPool],
            swapPath : [token1.options.address],
            enterInETH : false,
            exitInETH : false,
            receivers : [accounts[0]],
            receiversPercentages : []
        }, {
            inputTokenAddress : token0.options.address,
            inputTokenAmount : utilities.toDecimals(18, token0decimals),
            ammPlugin : utilities.voidEthereumAddress,
            liquidityPoolAddresses : [],
            swapPath : [],
            enterInETH : false,
            exitInETH : false,
            receivers : [accounts[0]],
            receiversPercentages : []
        }/*, {
            inputTokenAddress : token0.options.address,
            inputTokenAmount : utilities.toDecimals(20, 18),
            ammPlugin : ammContract.options.address,
            liquidityPoolAddresses : [token0ETHLP],
            swapPath : [ethereumAddress],
            enterInETH : false,
            exitInETH : true,
            receivers : [accounts[0]],
            receiversPercentages : []
        }*/, {
            inputTokenAddress : token1.options.address,
            inputTokenAmount : utilities.toDecimals(20, token1decimals),
            ammPlugin : ammContract.options.address,
            liquidityPoolAddresses : [liquidityPool],
            swapPath : [token0.options.address],
            enterInETH : false,
            exitInETH : false,
            receivers : [accounts[0]],
            receiversPercentages : []
        }, {
            inputTokenAddress : token1.options.address,
            inputTokenAmount : utilities.toDecimals(11, token1decimals),
            ammPlugin : utilities.voidEthereumAddress,
            liquidityPoolAddresses : [],
            swapPath : [],
            enterInETH : false,
            exitInETH : false,
            receivers : [accounts[1]],
            receiversPercentages : []
        }/*, {
            inputTokenAddress : token1.options.address,
            inputTokenAmount : utilities.toDecimals(5, 18),
            ammPlugin : ammContract.options.address,
            liquidityPoolAddresses : [token1ETHLP],
            swapPath : [ethereumAddress],
            enterInETH : false,
            exitInETH : true,
            receivers : [accounts[0]],
            receiversPercentages : []
        }*/];

        //operations = [];

        console.log(utilities.fromDecimals(await wusdCollection.methods.balanceOf(accounts[0], wusdObjectId).call(), 18));

        await token0.methods.approve(wusdPresto.options.address, await token0.methods.balanceOf(accounts[0]).call()).send(blockchainConnection.getSendingOptions());
        await token1.methods.approve(wusdPresto.options.address, await token1.methods.balanceOf(accounts[0]).call()).send(blockchainConnection.getSendingOptions());

        var ethValue = '0';
        for(var operation of operations) {
            if(operation.inputTokenAddress === ethereumAddress && operation.enterInETH) {
                ethValue = web3.utils.toBN(ethValue).add(web3.utils.toBN(operation.inputTokenAmount)).toString();
            }
        }

        var payloads = [];
        for(i = 0; i < 2; i++) {
            var burnData = web3.eth.abi.encodeParameters(["uint256", "uint256", "uint256", "bool"], [ammPosition, liquidityPoolPosition, 40815887222522, false]);
            payloads.push(web3.eth.abi.encodeParameters(["uint256", "bytes"], [0, burnData]));
        }
        payloads = web3.eth.abi.encodeParameter("bytes[]", payloads);
        var payload = abi.encode(["bytes", "address", "tuple(address,uint256,address,address[],address[],bool,bool,address[],uint256[])[]"],[payloads, presto.options.address, operations.map(it => Object.values(it))]);

        var wusdValue = utilities.toDecimals(900, 18);

        var transaction = await wusdCollection.methods.safeBatchTransferFrom(accounts[0], wusdPresto.options.address, [wusdObjectId, wusdObjectId], [wusdValue, wusdValue], payload).send(blockchainConnection.getSendingOptions());
        var transactionFee = await blockchainConnection.calculateTransactionFee(transaction);

        await nothingInContracts(wusdPresto.options.address);
        await nothingInContracts(presto.options.address);

        console.log(utilities.fromDecimals(await wusdCollection.methods.balanceOf(accounts[0], wusdObjectId).call(), 18));
    });

    it("Mint Existing Index", async () => {

        var Index = await compile('index/Index');

        var index = new web3.eth.Contract(Index.abi, context.indexAddress);

        var value = 30;
        value = utilities.toDecimals(value, 18);

        var indexId = "1291701553039866105681170894910877665806993998069";

        var indexInfo = await index.methods.info(indexId, value).call();

        var operations = [];

        var amm = amms["UniswapV2"];
        var ethereumAddress = amm.data[0];
        async function calculateEthereumPrices(tokenAddress, tokenValue) {
            var liquidityPoolAddress = (await amm.contract.methods.byTokens([ethereumAddress, tokenAddress]).call())[2];
            var data = await amm.contract.methods.getSwapOutput(tokenAddress, tokenValue, [liquidityPoolAddress], [ethereumAddress]).call();
            data = await amm.contract.methods.getSwapOutput(ethereumAddress, data[1], [liquidityPoolAddress], [tokenAddress]).call();
            var ethereumValue;
            var multiplier = parseInt(tokenValue) / parseInt(data[1]);
            while (web3.utils.toBN(tokenValue).gt(web3.utils.toBN(data[1]))) {
                var oldEthereumValue = ethereumValue;
                ethereumValue = utilities.numberToString(parseInt(ethereumValue || data[0]) * multiplier).split('.')[0].split(',').join('');
                if (multiplier === 1 || (oldEthereumValue && web3.utils.toBN(oldEthereumValue).gte(web3.utils.toBN(ethereumValue)))) {
                    ethereumValue = web3.utils.toBN(oldEthereumValue || ethereumValue).add(web3.utils.toBN(10000)).toString();
                }
                data = await amm.contract.methods.getSwapOutput(ethereumAddress, ethereumValue, [liquidityPoolAddress], [tokenAddress]).call();
                multiplier = parseInt(tokenValue) / parseInt(data[1]);
                console.log(ethereumValue, tokenValue, data[1]);
            }
            return {ethereumValue, liquidityPoolAddress};
        }

        var ethValue = "0";

        for(var i in indexInfo[0]) {
            var token = indexInfo[0][i];
            var amount = indexInfo[1][i];
            var data = await calculateEthereumPrices(token, amount);
            operations.push({
                inputTokenAddress : ethereumAddress,
                inputTokenAmount : data.ethereumValue,
                ammPlugin : amm.contract.options.address,
                liquidityPoolAddresses : [data.liquidityPoolAddress],
                swapPath : [token],
                enterInETH : true,
                exitInETH : false,
                receivers : [indexPresto.options.address],
                receiversPercentages : []
            });
            ethValue = web3.utils.toBN(ethValue).add(web3.utils.toBN(data.ethereumValue)).toString();
        }

        await indexPresto.methods.mint(
            presto.options.address,
            operations,
            index.options.address,
            indexId,
            value,
            accounts[0]
        ).send(blockchainConnection.getSendingOptions({value : ethValue}));

        await nothingInContracts(presto.options.address);
        await nothingInContracts(indexPresto.options.address);
    });

    it("Mint Nex Index", async () => {

        var Index = await compile('index/Index');

        var index = new web3.eth.Contract(Index.abi, context.indexAddress);

        var value = 1;
        value = utilities.toDecimals(value, 18);

        var ibizaToken = [{
            address : "0x7b123f53421b1bf8533339bfbdc7c98aa94163db",
            amount : utilities.toDecimals(3, 18)
        }, {
            address : "0x34612903db071e888a4dadcaa416d3ee263a87b9",
            amount : utilities.toDecimals(0.3, 18)
        }, {
            address : "0x9e78b8274e1d6a76a0dbbf90418894df27cbceb5",
            amount : utilities.toDecimals(3, 18)
        }, ];

        var operations = [];

        var amm = amms["UniswapV2"];
        var ethereumAddress = amm.data[0];
        async function calculateEthereumPrices(tokenAddress, tokenValue) {
            var liquidityPoolAddress = (await amm.contract.methods.byTokens([ethereumAddress, tokenAddress]).call())[2];
            var data = await amm.contract.methods.getSwapOutput(tokenAddress, tokenValue, [liquidityPoolAddress], [ethereumAddress]).call();
            data = await amm.contract.methods.getSwapOutput(ethereumAddress, data[1], [liquidityPoolAddress], [tokenAddress]).call();
            var ethereumValue;
            var multiplier = parseInt(tokenValue) / parseInt(data[1]);
            while (web3.utils.toBN(tokenValue).gt(web3.utils.toBN(data[1]))) {
                var oldEthereumValue = ethereumValue;
                ethereumValue = utilities.numberToString(parseInt(ethereumValue || data[0]) * multiplier).split('.')[0].split(',').join('');
                if (multiplier === 1 || (oldEthereumValue && web3.utils.toBN(oldEthereumValue).gte(web3.utils.toBN(ethereumValue)))) {
                    ethereumValue = web3.utils.toBN(oldEthereumValue || ethereumValue).add(web3.utils.toBN(10000)).toString();
                }
                data = await amm.contract.methods.getSwapOutput(ethereumAddress, ethereumValue, [liquidityPoolAddress], [tokenAddress]).call();
                multiplier = parseInt(tokenValue) / parseInt(data[1]);
                console.log(ethereumValue, tokenValue, data[1]);
            }
            return {ethereumValue, liquidityPoolAddress};
        }

        var ethValue = "0";

        for(var item of ibizaToken) {
            var token = item.address;
            var amount = item.amount;
            var data = await calculateEthereumPrices(token, amount);
            operations.push({
                inputTokenAddress : ethereumAddress,
                inputTokenAmount : data.ethereumValue,
                ammPlugin : amm.contract.options.address,
                liquidityPoolAddresses : [data.liquidityPoolAddress],
                swapPath : [token],
                enterInETH : true,
                exitInETH : false,
                receivers : [indexPresto.options.address],
                receiversPercentages : []
            });
            ethValue = web3.utils.toBN(ethValue).add(web3.utils.toBN(data.ethereumValue)).toString();
        }

        await indexPresto.methods.mint(
            presto.options.address,
            operations,
            index.options.address,
            web3.eth.abi.encodeParameters(["string", "string", "string", "address[]", "uint256[]", "uint256", "address"], ["Ibiza", "Ibiza", "google.com", ibizaToken.map(it => it.address), ibizaToken.map(it => it.amount), value, accounts[0]])
        ).send(blockchainConnection.getSendingOptions({value : ethValue}));

        await nothingInContracts(presto.options.address);
        await nothingInContracts(indexPresto.options.address);
    });
});
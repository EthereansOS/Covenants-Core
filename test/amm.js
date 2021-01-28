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
var glob = require("glob");

describe("AMM", () => {

    var buyForETHAmount = 5000;
    var tokens;
    var AMMs;
    var amms;

    before(async() => {
        await blockchainConnection.init;

        var AMMPaths = await new Promise(function(ok) {
            var basePath = (path.resolve(__dirname, '..', 'contracts') + '/').split('\\').join('/');
            glob(basePath + 'amm-aggregator/models/**/!(I)*.sol', {}, (err, files) => {
                ok(files.map(it => it.split('\\').join('/').split(basePath).join('').split('.sol').join('')));
            });
        });

        AMMs = {};

        for (var AMMPath of AMMPaths) {
            AMMs[AMMPath.substring(AMMPath.lastIndexOf("/") + 1).split('AMMV1').join('')] = await compile(AMMPath);
        }

        var uniswap = { contract: await new web3.eth.Contract(AMMs.UniswapV2.abi).deploy({ data: AMMs.UniswapV2.bin, arguments: [context.uniswapV2RouterAddress] }).send(blockchainConnection.getSendingOptions()) };

        amms = {
            uniswap,
            mooniswap: { contract: await new web3.eth.Contract(AMMs.Mooniswap.abi).deploy({ data: AMMs.Mooniswap.bin, arguments: [context.mooniswapFactoryAddress] }).send(blockchainConnection.getSendingOptions()) },
            sushiSwap: { contract: await new web3.eth.Contract(AMMs.SushiSwap.abi).deploy({ data: AMMs.SushiSwap.bin, arguments: [context.sushiSwapRouterAddress] }).send(blockchainConnection.getSendingOptions()) },
            balancer: { contract: await new web3.eth.Contract(AMMs.Balancer.abi).deploy({ data: AMMs.Balancer.bin, arguments: [context.wethTokenAddress] }).send(blockchainConnection.getSendingOptions()) }
        }

        await Promise.all(Object.values(amms).map(amm => amm.contract.methods.data().call().then(data => {
            amm.ethereumAddress = data[0];
            amm.maxTokensPerLiquidityPool = parseInt(data[1]);
            amm.hasUniqueLiquidityPools = data[2];
        }).then(amm.contract.methods.info().call().then(info => {
            amm.name = info[0];
            amm.version = info[1];
        }))));

        tokens = [
            context.wethTokenAddress,
            context.usdtTokenAddress,
            context.chainLinkTokenAddress,
            context.usdcTokenAddress,
            context.daiTokenAddress,
            context.mkrTokenAddress
        ].map(it => new web3.eth.Contract(context.IERC20ABI, it));

        await Promise.all(tokens.map(it => buyForETH(it, buyForETHAmount, uniswap.contract)));
    });

    async function buyForETH(token, valuePlain, ammPlugin) {
        var value = utilities.toDecimals(valuePlain.toString(), '18');
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
            paths: [token.options.address],
            inputToken: ethereumAddress,
            receiver: utilities.voidEthereumAddress
        }).send(blockchainConnection.getSendingOptions({ value }));
    }

    async function tokenData(token, method) {
        if (!token.options) {
            return "ETH";
        }
        try {
            return await token.methods[method]().call();
        } catch (e) {}
        var raw = await web3.eth.call({
            to: token.options.address,
            data: web3.utils.sha3(`${method}()`).substring(0, 10)
        });
        return web3.utils.toUtf8(raw);
    }

    function randomTokenAddress(notThese) {
        notThese = notThese || [];
        notThese = notThese instanceof Array ? notThese : [notThese];
        var tokenAddress;
        while (notThese.indexOf(tokenAddress = tokens[Math.floor(Math.random() * tokens.length)].options.address) !== -1) {}
        return tokenAddress;
    }

    function randomPlainAmount(length) {
        var test = [];
        for (var i = 0; i < (length || 70); i++) {
            test.push(i + 1);
        }
        return test[Math.floor(Math.random() * test.length)];
    }

    function getTokenAddresses(ethereum, moreThan2, existing, dfo) {
        var tokenAddresses = [existing ? randomTokenAddress() : dfo.votingTokenAddress];
        tokenAddresses.push(ethereum ? amm.ethereumAddress : randomTokenAddress(tokenAddresses));

        if (moreThan2) {
            var amounts = Math.floor(Math.random() * tokens.length);
            for (var i = 0; i < amounts; i++) {
                tokenAddresses.push(randomTokenAddress(tokenAddresses));
            }
        }

        return tokenAddresses;
    }

    function assertstrictEqual(actual, expected) {
        var difference = 0.0005;
        try {
            assert.strictEqual(actual, expected);
        } catch (e) {
            var diff = Math.abs(utilities.formatNumber(actual) - utilities.formatNumber(expected));
            console.error(`Diff of ${diff}: ${actual} - ${expected}`);
            if (diff > difference) {
                throw e;
            }
        }
    }

    function getToken(tokenAddress, ethereum, ethereumAddress, dfo) {
        if (ethereum && tokenAddress === ethereumAddress) {
            return;
        }
        return tokenAddress === dfo.votingTokenAddress ? dfo.votingToken : tokens.filter(it => it.options.address === tokenAddress)[0];
    }

    async function createLiquidityPoolAndAddLiquidityNoPool(amm, receiver, existing, ethereum, moreThan2) {
        receiver = receiver || utilities.voidEthereumAddress;
        var realReceiver = receiver === utilities.voidEthereumAddress ? accounts[0] : receiver;

        dfo = await dfoManager.createDFO("MyName", "MySymbol", 10000000, 100, 10);

        var tokenAddresses = getTokenAddresses(ethereum, moreThan2, existing, dfo);

        if (existing) {
            while (true) {
                var data = await amm.contract.methods.byTokens(tokenAddresses).call();
                if (data.liquidityPoolAddress !== utilities.voidEthereumAddress) {
                    break;
                }
                tokenAddresses = getTokenAddresses(ethereum, moreThan2, existing, dfo);
            }
        }

        var amounts = [];
        for (var i in tokenAddresses) {
            var token = getToken(tokenAddresses[i], ethereum, amm.ethereumAddress, dfo);
            var decimals = token ? await token.methods.decimals().call() : 18;
            amounts.push(utilities.toDecimals(randomPlainAmount(), decimals));
        }

        var liquidityPoolAddress;
        var liquidityPool;
        var expectedLiquidityPoolAmount = '0';

        if (existing) {
            var data = await amm.contract.methods.byTokens(tokenAddresses).call();
            liquidityPool = new web3.eth.Contract(context.IERC20ABI, liquidityPoolAddress = data.liquidityPoolAddress);
            var decimals = await liquidityPool.methods.decimals().call();
            data = await amm.contract.methods.byTokenAmount(liquidityPoolAddress, tokenAddresses[0], amounts[0]).call();
            expectedLiquidityPoolAmount = await liquidityPool.methods.balanceOf(realReceiver).call();
            expectedLiquidityPoolAmount = web3.utils.toBN(expectedLiquidityPoolAmount).add(web3.utils.toBN(data[0])).toString();
            expectedLiquidityPoolAmount = utilities.fromDecimals(expectedLiquidityPoolAmount, decimals);
            for (var i in data[2]) {
                amounts[tokenAddresses.indexOf(data[2][i])] = data[1][i];
            }
        }

        var expectedReceiverAmounts = [];
        var expectedSenderAmounts = [];
        var ethereumAmount = '0';
        for (var i in tokenAddresses) {
            var token = getToken(tokenAddresses[i], ethereum, amm.ethereumAddress, dfo);
            if (ethereum && tokenAddresses[i] === amm.ethereumAddress) {
                ethereumAmount = amounts[i];
            } else {
                await token.methods.approve(amm.contract.options.address, amounts[i]).send(blockchainConnection.getSendingOptions());
            }
            expectedReceiverAmounts.push(token ? await token.methods.balanceOf(realReceiver).call() : await web3.eth.getBalance(realReceiver));
            expectedSenderAmounts.push(token ? await token.methods.balanceOf(accounts[0]).call() : await web3.eth.getBalance(accounts[0]));
            expectedReceiverAmounts[i] = web3.utils.toBN(expectedReceiverAmounts[i]).add(web3.utils.toBN(amounts[i])).toString();
            expectedSenderAmounts[i] = web3.utils.toBN(expectedSenderAmounts[i]).sub(web3.utils.toBN(amounts[i])).toString();
        }

        var transaction = await amm.contract.methods.createLiquidityPoolAndAddLiquidity(tokenAddresses, amounts, ethereum, realReceiver).send(blockchainConnection.getSendingOptions({ value: ethereumAmount }));
        var transactionFee = await blockchainConnection.calculateTransactionFee(transaction);

        if (!existing) {
            var transactionReceipt = await web3.eth.getTransactionReceipt(transaction.transactionHash);
            liquidityPoolAddress = liquidityPoolAddress || web3.eth.abi.decodeParameter("address", transactionReceipt.logs.filter(it => it.topics[0] === web3.utils.sha3('NewLiquidityPoolAddress(address)'))[0].topics[1]);
            liquidityPool = new web3.eth.Contract(context.IERC20ABI, liquidityPoolAddress);
            var liquidityPoolData = await amm.contract.methods.byLiquidityPool(liquidityPoolAddress).call();
            var decimals = await liquidityPool.methods.decimals().call();
            expectedLiquidityPoolAmount = liquidityPoolData.liquidityPoolAmount;
            expectedLiquidityPoolAmount = utilities.fromDecimals(expectedLiquidityPoolAmount, decimals);
        }

        for (var i in tokenAddresses) {
            var token = getToken(tokenAddresses[i], ethereum, amm.ethereumAddress, dfo);
            var decimals = token ? await token.methods.decimals().call() : 18;
            if (ethereum && tokenAddresses[i] === amm.ethereumAddress) {
                expectedSenderAmounts[i] = web3.utils.toBN(expectedSenderAmounts[i]).sub(web3.utils.toBN(transactionFee)).toString();
            }
            var actualSenderBalance = token ? await token.methods.balanceOf(accounts[0]).call() : await web3.eth.getBalance(accounts[0]);
            assertstrictEqual(utilities.fromDecimals(actualSenderBalance, decimals), utilities.fromDecimals(expectedSenderAmounts[i], decimals));
        }

        var liquidityPoolDecimals = await liquidityPool.methods.decimals().call();
        assertstrictEqual(utilities.fromDecimals(await liquidityPool.methods.balanceOf(realReceiver).call(), liquidityPoolDecimals), expectedLiquidityPoolAmount);
    }

    it("createLiquidityPoolAndAddLiquidity", async() => {
        for (amm of Object.values(amms)) {
            if (amm.name.toLowerCase().indexOf("balancer") !== -1) {
                continue;
            }
            console.log(amm.name);
            console.log("receiver no pool");
            await createLiquidityPoolAndAddLiquidityNoPool(amm, accounts[1]);
            console.log("receiver existing pool");
            await createLiquidityPoolAndAddLiquidityNoPool(amm, accounts[1], true);
            console.log("receiver no pool ethereum");
            await createLiquidityPoolAndAddLiquidityNoPool(amm, accounts[1], false, true);
            console.log("receiver existing pool ethereum");
            await createLiquidityPoolAndAddLiquidityNoPool(amm, accounts[1], true, true);
            console.log("no receiver no pool");
            await createLiquidityPoolAndAddLiquidityNoPool(amm);
            console.log("no receiver existing pool");
            await createLiquidityPoolAndAddLiquidityNoPool(amm, undefined, true);
            console.log("no receiver no pool ethereum");
            await createLiquidityPoolAndAddLiquidityNoPool(amm, undefined, false, true);
            console.log("no receiver existing pool ethereum");
            await createLiquidityPoolAndAddLiquidityNoPool(amm, undefined, true, true);

            if (amm.maxTokensPerLiquidityPool == 0) {
                console.log("receiver no pool with more than 2 tokens");
                await createLiquidityPoolAndAddLiquidityNoPool(amm, accounts[1], false, false, true);
                console.log("receiver existing pool with more than 2 tokens");
                await createLiquidityPoolAndAddLiquidityNoPool(amm, accounts[1], true, false, true);
                console.log("receiver no pool ethereum with more than 2 tokens");
                await createLiquidityPoolAndAddLiquidityNoPool(amm, accounts[1], false, true, true);
                console.log("receiver existing pool ethereum with more than 2 tokens");
                await createLiquidityPoolAndAddLiquidityNoPool(amm, accounts[1], false, true, true);
                console.log("no receiver no pool with more than 2 tokens");
                await createLiquidityPoolAndAddLiquidityNoPool(amm, undefined, false, false, true);
                console.log("no receiver existing pool with more than 2 tokens");
                await createLiquidityPoolAndAddLiquidityNoPool(amm, undefined, true, false, true);
                console.log("no receiver no pool ethereum with more than 2 tokens");
                await createLiquidityPoolAndAddLiquidityNoPool(amm, undefined, false, true, true);
                console.log("no receiver existing pool ethereum with more than 2 tokens");
                await createLiquidityPoolAndAddLiquidityNoPool(amm, undefined, true, true, true);
            }
        }
    });

    async function addLiquidity(amm, receiver, byLP, eth, liquidityPoolAddress) {
        receiver = receiver || utilities.voidEthereumAddress;
        var realReceiver = receiver === utilities.voidEthereumAddress ? accounts[0] : receiver;

        dfo = await dfoManager.createDFO("MyName", "MySymbol", 10000000, 100, 10);

        var tokenAddresses = !liquidityPoolAddress ? undefined : (await amm.contract.methods(byLiquidityPool(liquidityPoolAddress).call())[2]);

        if(!tokenAddresses) {
            while (true) {
                var data = await amm.contract.methods.byTokens(tokenAddresses = getTokenAddresses(ethereum, moreThan2, existing, dfo)).call();
                if (data.liquidityPoolAddress !== utilities.voidEthereumAddress) {
                    break;
                }
                tokenAddresses = getTokenAddresses(ethereum, moreThan2, existing, dfo);
            }
        }

        var amounts = [];
        for (var i in tokenAddresses) {
            var token = getToken(tokenAddresses[i], ethereum, amm.ethereumAddress, dfo);
            var decimals = token ? await token.methods.decimals().call() : 18;
            amounts.push(utilities.toDecimals(randomPlainAmount(), decimals));
        }

        var liquidityPool;
        var expectedLiquidityPoolAmount = '0';

        var data = await amm.contract.methods.byTokens(tokenAddresses).call();
        liquidityPool = new web3.eth.Contract(context.IERC20ABI, liquidityPoolAddress = data.liquidityPoolAddress);
        var decimals = await liquidityPool.methods.decimals().call();
        data = await amm.contract.methods.byTokenAmount(liquidityPoolAddress, tokenAddresses[0], amounts[0]).call();
        expectedLiquidityPoolAmount = await liquidityPool.methods.balanceOf(realReceiver).call();
        expectedLiquidityPoolAmount = web3.utils.toBN(expectedLiquidityPoolAmount).add(web3.utils.toBN(data[0])).toString();
        expectedLiquidityPoolAmount = utilities.fromDecimals(expectedLiquidityPoolAmount, decimals);
        for (var i in data[2]) {
            amounts[tokenAddresses.indexOf(data[2][i])] = data[1][i];
        }

        var expectedReceiverAmounts = [];
        var expectedSenderAmounts = [];
        var ethereumAmount = '0';
        for (var i in tokenAddresses) {
            var token = getToken(tokenAddresses[i], ethereum, amm.ethereumAddress, dfo);
            if (ethereum && tokenAddresses[i] === amm.ethereumAddress) {
                ethereumAmount = amounts[i];
            } else {
                await token.methods.approve(amm.contract.options.address, amounts[i]).send(blockchainConnection.getSendingOptions());
            }
            expectedReceiverAmounts.push(token ? await token.methods.balanceOf(realReceiver).call() : await web3.eth.getBalance(realReceiver));
            expectedSenderAmounts.push(token ? await token.methods.balanceOf(accounts[0]).call() : await web3.eth.getBalance(accounts[0]));
            expectedReceiverAmounts[i] = web3.utils.toBN(expectedReceiverAmounts[i]).add(web3.utils.toBN(amounts[i])).toString();
            expectedSenderAmounts[i] = web3.utils.toBN(expectedSenderAmounts[i]).sub(web3.utils.toBN(amounts[i])).toString();
        }

        var transaction = await amm.contract.methods.createLiquidityPoolAndAddLiquidity(tokenAddresses, amounts, ethereum, realReceiver).send(blockchainConnection.getSendingOptions({ value: ethereumAmount }));
        var transactionFee = await blockchainConnection.calculateTransactionFee(transaction);

        if (!existing) {
            var transactionReceipt = await web3.eth.getTransactionReceipt(transaction.transactionHash);
            liquidityPoolAddress = liquidityPoolAddress || web3.eth.abi.decodeParameter("address", transactionReceipt.logs.filter(it => it.topics[0] === web3.utils.sha3('NewLiquidityPoolAddress(address)'))[0].topics[1]);
            liquidityPool = new web3.eth.Contract(context.IERC20ABI, liquidityPoolAddress);
            var liquidityPoolData = await amm.contract.methods.byLiquidityPool(liquidityPoolAddress).call();
            var decimals = await liquidityPool.methods.decimals().call();
            expectedLiquidityPoolAmount = liquidityPoolData.liquidityPoolAmount;
            expectedLiquidityPoolAmount = utilities.fromDecimals(expectedLiquidityPoolAmount, decimals);
        }

        for (var i in tokenAddresses) {
            var token = getToken(tokenAddresses[i], ethereum, amm.ethereumAddress, dfo);
            var decimals = token ? await token.methods.decimals().call() : 18;
            if (ethereum && tokenAddresses[i] === amm.ethereumAddress) {
                expectedSenderAmounts[i] = web3.utils.toBN(expectedSenderAmounts[i]).sub(web3.utils.toBN(transactionFee)).toString();
            }
            var actualSenderBalance = token ? await token.methods.balanceOf(accounts[0]).call() : await web3.eth.getBalance(accounts[0]);
            assertstrictEqual(utilities.fromDecimals(actualSenderBalance, decimals), utilities.fromDecimals(expectedSenderAmounts[i], decimals));
        }

        var liquidityPoolDecimals = await liquidityPool.methods.decimals().call();
        assertstrictEqual(utilities.fromDecimals(await liquidityPool.methods.balanceOf(realReceiver).call(), liquidityPoolDecimals), expectedLiquidityPoolAmount);
    }

    it("addLiquidity", async() => {
        for (amm of Object.values(amms)) {
            console.log(amm.name);
            console.log("receiver by LP Amount");
            await addLiquidity(amm, accounts[1], true, amm.doubleTokenLiquidityPoolAddress);
            console.log("receiver by token amount 4 all tokens");
            await addLiquidity(amm, accounts[1], false, amm.doubleTokenLiquidityPoolAddress);
            console.log("receiver by LP Amount involving eth");
            await addLiquidity(amm, accounts[1], true, true, amm.doubleTokenLiquidityPoolAddress);
            console.log("receiver token amount 4 all tokens involving eth");
            await addLiquidity(amm, accounts[1], false, true, amm.doubleTokenLiquidityPoolAddress);
            console.log("no receiver by LP Amount");
            await addLiquidity(amm, undefined, true, amm.doubleTokenLiquidityPoolAddress);
            console.log("no receiver by token amount 4 all tokens");
            await addLiquidity(amm, undefined, false, amm.doubleTokenLiquidityPoolAddress);
            console.log("no receiver by LP Amount involving eth");
            await addLiquidity(amm, undefined, true, true, amm.doubleTokenLiquidityPoolAddress);
            console.log("no receiver token amount 4 all tokens involving eth");
            await addLiquidity(amm, undefined, false, true, amm.doubleTokenLiquidityPoolAddress);

            if (amm.maxTokensPerLiquidityPool == 0) {
                console.log("receiver by LP Amount with more than 2 tokens");
                await addLiquidity(amm, accounts[1], true, amm.multipleTokenLiquidityPoolAddress);
                console.log("receiver by token amount 4 all tokens with more than 2 tokens");
                await addLiquidity(amm, accounts[1], false, amm.multipleTokenLiquidityPoolAddress);
                console.log("receiver by LP Amount involving eth with more than 2 tokens");
                await addLiquidity(amm, accounts[1], true, true, amm.multipleTokenLiquidityPoolAddress);
                console.log("receiver token amount 4 all tokens involving eth with more than 2 tokens");
                await addLiquidity(amm, accounts[1], false, true, amm.multipleTokenLiquidityPoolAddress);
                console.log("no receiver by LP Amount with more than 2 tokens");
                await addLiquidity(amm, undefined, true, amm.multipleTokenLiquidityPoolAddress);
                console.log("no receiver by token amount 4 all tokens with more than 2 tokens");
                await addLiquidity(amm, undefined, false, amm.multipleTokenLiquidityPoolAddress);
                console.log("no receiver by LP Amount involving eth with more than 2 tokens");
                await addLiquidity(amm, undefined, true, true, amm.multipleTokenLiquidityPoolAddress);
                console.log("no receiver token amount 4 all tokens involving eth with more than 2 tokens");
                await addLiquidity(amm, undefined, false, true, amm.multipleTokenLiquidityPoolAddress);
            }
        }
    });
});
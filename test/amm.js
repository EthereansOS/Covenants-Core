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
            //balancer: { contract: await new web3.eth.Contract(AMMs.Balancer.abi).deploy({ data: AMMs.Balancer.bin, arguments: [context.wethTokenAddress] }).send(blockchainConnection.getSendingOptions()) }
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

        for (var amm of Object.values(amms)) {
            amm.liquidityPoolAddress = await addLiquidity(amm, accounts[0], true, false, amm.doubleTokenLiquidityPoolAddress);
            amm.liquidityPoolAddressETH = await addLiquidity(amm, accounts[0], true, true, amm.doubleTokenLiquidityPoolAddress);
        }
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

    function randomPlainAmount(length, step) {
        var test = [];
        for (var i = 0; i < (length || 70); i++) {
            test.push((i == 0 ? 0 : test[i - 1]) + (step || 1));
        }
        return test[Math.floor(Math.random() * test.length)];
    }

    function getTokenAddresses(ethereum, ethereumAddress, moreThan2, existing, dfo) {
        var tokenAddresses = [existing ? randomTokenAddress() : dfo ? dfo.votingTokenAddress : randomTokenAddress()];
        tokenAddresses.push(ethereum ? ethereumAddress : randomTokenAddress(tokenAddresses));

        if (moreThan2) {
            var amounts = Math.floor(Math.random() * tokens.length);
            for (var i = 0; i < amounts; i++) {
                tokenAddresses.push(randomTokenAddress(tokenAddresses));
            }
        }

        return tokenAddresses;
    }

    function getToken(tokenAddress, ethereum, ethereumAddress, dfo) {
        if (ethereum && tokenAddress === ethereumAddress) {
            return;
        }
        return tokenAddress === (dfo = dfo || {}).votingTokenAddress ? dfo.votingToken : tokens.filter(it => it.options.address === tokenAddress)[0];
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

    async function createLiquidityPoolAndAddLiquidityNoPool(amm, receiver, existing, ethereum, moreThan2) {
        receiver = receiver || utilities.voidEthereumAddress;
        var realReceiver = receiver === utilities.voidEthereumAddress ? accounts[0] : receiver;

        dfo = await dfoManager.createDFO("MyName", "MySymbol", 10000000, 100, 10);

        var tokenAddresses = getTokenAddresses(ethereum, amm.ethereumAddress, moreThan2, existing, dfo);

        if (existing) {
            while (true) {
                var data = await amm.contract.methods.byTokens(tokenAddresses).call();
                if (data.liquidityPoolAddress !== utilities.voidEthereumAddress) {
                    break;
                }
                tokenAddresses = getTokenAddresses(ethereum, amm.ethereumAddress, moreThan2, existing, dfo);
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
            try {
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
            } catch (e) {
                if(e.message.indexOf("VM Exception") === -1) {
                    throw e;
                }
                console.error(e.message);
            }
        }
    });

    async function addLiquidity(amm, receiver, byLP, ethereum, liquidityPoolAddress, tokenIndex) {

        var tokenAddresses = !liquidityPoolAddress ? undefined : (await amm.contract.methods.byLiquidityPool(liquidityPoolAddress).call())[2];

        if (!tokenAddresses) {
            while (true) {
                var data = await amm.contract.methods.byTokens(tokenAddresses = getTokenAddresses(ethereum, amm.ethereumAddress)).call();
                if (data.liquidityPoolAddress !== utilities.voidEthereumAddress) {
                    break;
                }
            }
        }

        if (!liquidityPoolAddress) {
            var data = await amm.contract.methods.byTokens(tokenAddresses).call();
            liquidityPoolAddress = data[2];
            tokenAddresses = data[3];
        }

        if (!byLP && isNaN(tokenIndex)) {
            for (var i in tokenAddresses) {
                await addLiquidity(amm, receiver, byLP, ethereum, liquidityPoolAddress, utilities.formatNumber(i));
            }
            return;
        }

        receiver = receiver || utilities.voidEthereumAddress;
        var realReceiver = receiver === utilities.voidEthereumAddress ? accounts[0] : receiver;

        var liquidityPool = new web3.eth.Contract(context.IERC20ABI, liquidityPoolAddress);
        var liquidityPoolDecimals = await liquidityPool.methods.decimals().call();

        var token = getToken(tokenAddresses[byLP ? 0 : tokenIndex], ethereum, amm.ethereumAddress);
        var decimals = token ? await token.methods.decimals().call() : 18;
        var data = await amm.contract.methods.byTokenAmount(liquidityPoolAddress, tokenAddresses[byLP ? 0 : tokenIndex], utilities.toDecimals(300, decimals)).call();
        var liquidityPoolAmount = data[0];
        var amounts = data[1];
        tokenAddresses = data[2];

        if (byLP) {
            var data = await amm.contract.methods.byLiquidityPoolAmount(liquidityPoolAddress, liquidityPoolAmount).call();
            amounts = data[0];
        }

        var expectedLiquidityPoolAmount = web3.utils.toBN(liquidityPoolAmount).add(web3.utils.toBN(await liquidityPool.methods.balanceOf(realReceiver).call())).toString();
        expectedLiquidityPoolAmount = utilities.fromDecimals(expectedLiquidityPoolAmount, liquidityPoolDecimals);

        var expectedReceiverAmounts = [];
        var expectedSenderAmounts = [];
        var ethereumAmount = '0';
        for (var i in tokenAddresses) {
            var token = getToken(tokenAddresses[i], ethereum, amm.ethereumAddress);
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

        var liquidityPoolData = {
            liquidityPoolAddress,
            amount: byLP ? liquidityPoolAmount : amounts[tokenIndex],
            tokenAddress: byLP ? utilities.voidEthereumAddress : tokenAddresses[tokenIndex],
            amountIsLiquidityPool: byLP || false,
            involvingETH: ethereum || false,
            receiver
        }

        var transaction = await amm.contract.methods.addLiquidity(liquidityPoolData).send(blockchainConnection.getSendingOptions({ value: ethereumAmount }));
        var transactionFee = await blockchainConnection.calculateTransactionFee(transaction);

        for (var i in tokenAddresses) {
            var token = getToken(tokenAddresses[i], ethereum, amm.ethereumAddress);
            var decimals = token ? await token.methods.decimals().call() : 18;
            if (ethereum && tokenAddresses[i] === amm.ethereumAddress) {
                expectedSenderAmounts[i] = web3.utils.toBN(expectedSenderAmounts[i]).sub(web3.utils.toBN(transactionFee)).toString();
            }
            var actualSenderBalance = token ? await token.methods.balanceOf(accounts[0]).call() : await web3.eth.getBalance(accounts[0]);
            assertstrictEqual(utilities.fromDecimals(actualSenderBalance, decimals), utilities.fromDecimals(expectedSenderAmounts[i], decimals));
        }

        assertstrictEqual(utilities.fromDecimals(await liquidityPool.methods.balanceOf(realReceiver).call(), liquidityPoolDecimals), expectedLiquidityPoolAmount);

        return liquidityPoolAddress;
    }

    it("addLiquidity", async() => {
        for (amm of Object.values(amms)) {
            try {
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
            } catch (e) {
                if(e.message.indexOf("VM Exception") === -1) {
                    throw e;
                }
                console.error(e.message);
            }
        }
    });

    async function removeLiquidity(amm, receiver, byLP, ethereum, liquidityPoolAddress, tokenIndex) {

        liquidityPoolAddress = ethereum ? amm.liquidityPoolAddressETH : amm.liquidityPoolAddress;

        var tokenAddresses = !liquidityPoolAddress ? undefined : (await amm.contract.methods.byLiquidityPool(liquidityPoolAddress).call())[2];

        if (!tokenAddresses) {
            while (true) {
                var data = await amm.contract.methods.byTokens(tokenAddresses = getTokenAddresses(ethereum, amm.ethereumAddress)).call();
                if (data.liquidityPoolAddress !== utilities.voidEthereumAddress) {
                    break;
                }
            }
        }

        if (!liquidityPoolAddress) {
            var data = await amm.contract.methods.byTokens(tokenAddresses).call();
            liquidityPoolAddress = data[2];
            tokenAddresses = data[3];
        }

        if (!byLP && isNaN(tokenIndex)) {
            for (var i in tokenAddresses) {
                await addLiquidity(amm, receiver, byLP, ethereum, liquidityPoolAddress, utilities.formatNumber(i));
            }
            return;
        }

        receiver = receiver || utilities.voidEthereumAddress;
        var realReceiver = receiver === utilities.voidEthereumAddress ? accounts[0] : receiver;

        var liquidityPool = new web3.eth.Contract(context.IERC20ABI, liquidityPoolAddress);
        var liquidityPoolDecimals = await liquidityPool.methods.decimals().call();

        var liquidityPoolAmount = await liquidityPool.methods.balanceOf(accounts[0]).call();
        liquidityPoolAmount = parseInt(liquidityPoolAmount);
        liquidityPoolAmount = liquidityPoolAmount * 0.1;
        liquidityPoolAmount = utilities.numberToString(liquidityPoolAmount);
        liquidityPoolAmount = liquidityPoolAmount.split('.').join('');
        var data = await amm.contract.methods.byLiquidityPoolAmount(liquidityPoolAddress, liquidityPoolAmount).call();
        var amounts = data[0];
        tokenAddresses = data[1];

        if (!byLP) {
            var token = getToken(tokenAddresses[byLP ? 0 : tokenIndex], ethereum, amm.ethereumAddress);
            var decimals = token ? await token.methods.decimals().call() : 18;
            var data = await amm.contract.methods.byTokenAmount(liquidityPoolAddress, tokenAddresses[byLP ? 0 : tokenIndex], amounts[byLP ? 0 : tokenIndex]).call();
            liquidityPoolAmount = data[0];
            amounts = data[1];
        }

        var expectedLiquidityPoolAmount = web3.utils.toBN(await liquidityPool.methods.balanceOf(accounts[0]).call()).sub(web3.utils.toBN(liquidityPoolAmount)).toString();
        expectedLiquidityPoolAmount = utilities.fromDecimals(expectedLiquidityPoolAmount, liquidityPoolDecimals);

        var expectedReceiverAmounts = [];
        var expectedSenderAmounts = [];
        for (var i in tokenAddresses) {
            var token = getToken(tokenAddresses[i], ethereum, amm.ethereumAddress);
            expectedReceiverAmounts.push(token ? await token.methods.balanceOf(realReceiver).call() : await web3.eth.getBalance(realReceiver));
            expectedSenderAmounts.push(token ? await token.methods.balanceOf(accounts[0]).call() : await web3.eth.getBalance(accounts[0]));
            expectedReceiverAmounts[i] = web3.utils.toBN(expectedReceiverAmounts[i]).add(web3.utils.toBN(amounts[i])).toString();
            expectedSenderAmounts[i] = web3.utils.toBN(expectedSenderAmounts[i]).sub(web3.utils.toBN(amounts[i])).toString();
        }

        await liquidityPool.methods.approve(amm.contract.options.address, liquidityPoolAmount).send(blockchainConnection.getSendingOptions());

        var liquidityPoolData = {
            liquidityPoolAddress,
            amount: byLP ? liquidityPoolAmount : amounts[tokenIndex],
            tokenAddress: byLP ? utilities.voidEthereumAddress : tokenAddresses[tokenIndex],
            amountIsLiquidityPool: byLP || false,
            involvingETH: ethereum || false,
            receiver
        }

        var transaction = await amm.contract.methods.removeLiquidity(liquidityPoolData).send(blockchainConnection.getSendingOptions());
        var transactionFee = await blockchainConnection.calculateTransactionFee(transaction);

        for (var i in tokenAddresses) {
            var token = getToken(tokenAddresses[i], ethereum, amm.ethereumAddress);
            var decimals = token ? await token.methods.decimals().call() : 18;
            if (ethereum && tokenAddresses[i] === amm.ethereumAddress) {
                expectedSenderAmounts[i] = web3.utils.toBN(expectedSenderAmounts[i]).sub(web3.utils.toBN(transactionFee)).toString();
            }
            var actualReceiverBalance = token ? await token.methods.balanceOf(realReceiver).call() : await web3.eth.getBalance(realReceiver);
            assertstrictEqual(utilities.fromDecimals(actualReceiverBalance, decimals), utilities.fromDecimals(expectedReceiverAmounts[i], decimals));
        }

        assertstrictEqual(utilities.fromDecimals(await liquidityPool.methods.balanceOf(accounts[0]).call(), liquidityPoolDecimals), expectedLiquidityPoolAmount);
    }

    it("removeLiquidity", async() => {
        for (amm of Object.values(amms)) {
            try {
                console.log(amm.name);
                console.log("receiver by LP Amount");
                await removeLiquidity(amm, accounts[1], true, amm.doubleTokenLiquidityPoolAddress);
                console.log("receiver by token amount 4 all tokens");
                await removeLiquidity(amm, accounts[1], false, amm.doubleTokenLiquidityPoolAddress);
                console.log("receiver by LP Amount involving eth");
                await removeLiquidity(amm, accounts[1], true, true, amm.doubleTokenLiquidityPoolAddress);
                console.log("receiver token amount 4 all tokens involving eth");
                await removeLiquidity(amm, accounts[1], false, true, amm.doubleTokenLiquidityPoolAddress);
                console.log("no receiver by LP Amount");
                await removeLiquidity(amm, undefined, true, amm.doubleTokenLiquidityPoolAddress);
                console.log("no receiver by token amount 4 all tokens");
                await removeLiquidity(amm, undefined, false, amm.doubleTokenLiquidityPoolAddress);
                console.log("no receiver by LP Amount involving eth");
                await removeLiquidity(amm, undefined, true, true, amm.doubleTokenLiquidityPoolAddress);
                console.log("no receiver token amount 4 all tokens involving eth");
                await removeLiquidity(amm, undefined, false, true, amm.doubleTokenLiquidityPoolAddress);

                if (amm.maxTokensPerLiquidityPool == 0) {
                    console.log("receiver by LP Amount with more than 2 tokens");
                    await removeLiquidity(amm, accounts[1], true, amm.multipleTokenLiquidityPoolAddress);
                    console.log("receiver by token amount 4 all tokens with more than 2 tokens");
                    await removeLiquidity(amm, accounts[1], false, amm.multipleTokenLiquidityPoolAddress);
                    console.log("receiver by LP Amount involving eth with more than 2 tokens");
                    await removeLiquidity(amm, accounts[1], true, true, amm.multipleTokenLiquidityPoolAddress);
                    console.log("receiver token amount 4 all tokens involving eth with more than 2 tokens");
                    await removeLiquidity(amm, accounts[1], false, true, amm.multipleTokenLiquidityPoolAddress);
                    console.log("no receiver by LP Amount with more than 2 tokens");
                    await removeLiquidity(amm, undefined, true, amm.multipleTokenLiquidityPoolAddress);
                    console.log("no receiver by token amount 4 all tokens with more than 2 tokens");
                    await removeLiquidity(amm, undefined, false, amm.multipleTokenLiquidityPoolAddress);
                    console.log("no receiver by LP Amount involving eth with more than 2 tokens");
                    await removeLiquidity(amm, undefined, true, true, amm.multipleTokenLiquidityPoolAddress);
                    console.log("no receiver token amount 4 all tokens involving eth with more than 2 tokens");
                    await removeLiquidity(amm, undefined, false, true, amm.multipleTokenLiquidityPoolAddress);
                }
            } catch (e) {
                if(e.message.indexOf("VM Exception") === -1) {
                    throw e;
                }
                console.error(e.message);
            }
        }
    });

    async function swapLiquidity(amm, receiver, enterInETH, exitInETH, moreThanOne, ethInTheMiddle) {

        var inputToken = enterInETH ? amm.ethereumAddress : randomTokenAddress(amm.ethereumAddress);

        var token = inputToken !== utilities.voidEthereumAddress && tokens.filter(it => it.options.address === inputToken)[0];
        var decimals = !token ? 18 : await token.methods.decimals().call();

        var otherToken;
        var liquidityPoolAddress;

        while((liquidityPoolAddress = (await amm.contract.methods.byTokens([inputToken, otherToken = randomTokenAddress(inputToken)]).call())[2]) === utilities.voidEthereumAddress) {
            console.log(otherToken);
            await utilities.sleep();
        }

        var paths = [otherToken];

        var liquidityPoolAddresses = [liquidityPoolAddress];

        if(moreThanOne) {

        }

        if(exitInETH) {
            paths[paths.length - 1] = amm.ethereumAddress;
            liquidityPoolAddresses[liquidityPoolAddresses.length - 1] = (await amm.contract.methods.byTokens([inputToken, otherToken = randomTokenAddress(inputToken)]).call())[2];
        }

        var amountPlain = randomPlainAmount();
        var amount = utilities.toDecimals(amountPlain, decimals);

        receiver = receiver || utilities.voidEthereumAddress;
        var realReceiver = receiver === utilities.voidEthereumAddress ? accounts[0] : receiver;

        var swapData = {
            amount,
            inputToken,
            paths,
            liquidityPoolAddresses,
            receiver,
            enterInETH : enterInETH || false,
            exitInETH: exitInETH || false
        }

        token && await token.methods.approve(amm.contract.options.address, amount).send(blockchainConnection.getSendingOptions());

        try {
            await amm.contract.methods.swapLiquidity(swapData).send(blockchainConnection.getSendingOptions({value : enterInETH ? amount : '0'}));
        } catch(e) {
            if(enterInETH && exitInETH && paths.length === 1) {
                console.error(e.message);
            } else {
                throw e;
            }
        }

        /*var liquidityPool = new web3.eth.Contract(context.IERC20ABI, liquidityPoolAddress);
        var liquidityPoolDecimals = await liquidityPool.methods.decimals().call();

        var liquidityPoolAmount = await liquidityPool.methods.balanceOf(accounts[0]).call();
        liquidityPoolAmount = parseInt(liquidityPoolAmount);
        liquidityPoolAmount = liquidityPoolAmount * 0.1;
        liquidityPoolAmount = utilities.numberToString(liquidityPoolAmount);
        liquidityPoolAmount = liquidityPoolAmount.split('.').join('');
        var data = await amm.contract.methods.byLiquidityPoolAmount(liquidityPoolAddress, liquidityPoolAmount).call();
        var amounts = data[0];
        tokenAddresses = data[1];

        if (!byLP) {
            var token = getToken(tokenAddresses[byLP ? 0 : tokenIndex], ethereum, amm.ethereumAddress);
            var decimals = token ? await token.methods.decimals().call() : 18;
            var data = await amm.contract.methods.byTokenAmount(liquidityPoolAddress, tokenAddresses[byLP ? 0 : tokenIndex], amounts[byLP ? 0 : tokenIndex]).call();
            liquidityPoolAmount = data[0];
            amounts = data[1];
        }

        var expectedLiquidityPoolAmount = web3.utils.toBN(await liquidityPool.methods.balanceOf(accounts[0]).call()).sub(web3.utils.toBN(liquidityPoolAmount)).toString();
        expectedLiquidityPoolAmount = utilities.fromDecimals(expectedLiquidityPoolAmount, liquidityPoolDecimals);

        var expectedReceiverAmounts = [];
        var expectedSenderAmounts = [];
        for (var i in tokenAddresses) {
            var token = getToken(tokenAddresses[i], ethereum, amm.ethereumAddress);
            expectedReceiverAmounts.push(token ? await token.methods.balanceOf(realReceiver).call() : await web3.eth.getBalance(realReceiver));
            expectedSenderAmounts.push(token ? await token.methods.balanceOf(accounts[0]).call() : await web3.eth.getBalance(accounts[0]));
            expectedReceiverAmounts[i] = web3.utils.toBN(expectedReceiverAmounts[i]).add(web3.utils.toBN(amounts[i])).toString();
            expectedSenderAmounts[i] = web3.utils.toBN(expectedSenderAmounts[i]).sub(web3.utils.toBN(amounts[i])).toString();
        }

        await liquidityPool.methods.approve(amm.contract.options.address, liquidityPoolAmount).send(blockchainConnection.getSendingOptions());

        var liquidityPoolData = {
            liquidityPoolAddress,
            amount: byLP ? liquidityPoolAmount : amounts[tokenIndex],
            tokenAddress: byLP ? utilities.voidEthereumAddress : tokenAddresses[tokenIndex],
            amountIsLiquidityPool: byLP || false,
            involvingETH: ethereum || false,
            receiver
        }

        var transaction = await amm.contract.methods.removeLiquidity(liquidityPoolData).send(blockchainConnection.getSendingOptions());
        var transactionFee = await blockchainConnection.calculateTransactionFee(transaction);

        for (var i in tokenAddresses) {
            var token = getToken(tokenAddresses[i], ethereum, amm.ethereumAddress);
            var decimals = token ? await token.methods.decimals().call() : 18;
            if (ethereum && tokenAddresses[i] === amm.ethereumAddress) {
                expectedSenderAmounts[i] = web3.utils.toBN(expectedSenderAmounts[i]).sub(web3.utils.toBN(transactionFee)).toString();
            }
            var actualReceiverBalance = token ? await token.methods.balanceOf(realReceiver).call() : await web3.eth.getBalance(realReceiver);
            assertstrictEqual(utilities.fromDecimals(actualReceiverBalance, decimals), utilities.fromDecimals(expectedReceiverAmounts[i], decimals));
        }

        assertstrictEqual(utilities.fromDecimals(await liquidityPool.methods.balanceOf(accounts[0]).call(), liquidityPoolDecimals), expectedLiquidityPoolAmount);*/
    }

    it("swapLiquidity", async() => {
        for (amm of Object.values(amms)) {
            try {
                console.log("\n=== " + amm.name + " ===");
                console.log("receiver path 1: enterInETH");
                await swapLiquidity(amm, accounts[1], true);
                console.log("receiver path 1: exitInETH");
                await swapLiquidity(amm, accounts[1], false, true);
                console.log("receiver path 1: enterInETH exitInETH (must fail)");
                await swapLiquidity(amm, accounts[1], true, true);
                console.log("receiver path 1: noEth");
                await swapLiquidity(amm, accounts[1]);
                console.log("no receiver path 1: enterInETH");
                await swapLiquidity(amm, undefined, true);
                console.log("no receiver path 1: exitInETH");
                await swapLiquidity(amm, undefined, false, true);
                console.log("no receiver path 1: enterInETH exitInETH (must fail)");
                await swapLiquidity(amm, undefined, true, true);
                console.log("no receiver path 1: noEth");
                await swapLiquidity(amm);

                console.log("receiver path +: enterInETH");
                await swapLiquidity(amm, accounts[1], true, false, true);
                console.log("receiver path +: exitInETH");
                await swapLiquidity(amm, accounts[1], false, true, true);
                console.log("receiver path +: enterInETH exitInETH");
                await swapLiquidity(amm, accounts[1], true, true, true);
                console.log("receiver path +: noEth");
                await swapLiquidity(amm, accounts[1], false, false, true);
                console.log("receiver path +: ethInTheMiddle");
                await swapLiquidity(amm, accounts[1], false, false, true, true);
                console.log("no receiver path +: enterInETH");
                await swapLiquidity(amm, undefined, true, false, true);
                console.log("no receiver path +: exitInETH");
                await swapLiquidity(amm, undefined, false, true, true);
                console.log("no receiver path +: enterInETH exitInETH");
                await swapLiquidity(amm, undefined, true, true, true);
                console.log("no receiver path +: noEth");
                await swapLiquidity(amm, undefined, false, false, true);
                console.log("no receiver path +: ethInTheMiddle");
                await swapLiquidity(amm, undefined, false, false, true, true);
            } catch (e) {
                throw e;
            }
        }
    });
});
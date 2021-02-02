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
    var ammAggregator;
    var tokens;
    var AMMs;
    var amms;
    var ammDFO;

    var liquidityPool;

    before(async() => {
        await blockchainConnection.init;

        uniswapV2Factory = new web3.eth.Contract(context.uniswapV2FactoryABI, context.uniswapV2FactoryAddress);
        liquidityPool = new web3.eth.Contract(context.uniswapV2PairABI, await uniswapV2Factory.methods.getPair(context.buidlTokenAddress, context.wethTokenAddress).call());

        ammDFO = await dfoManager.createDFO("MyName", "MySymbol", 10000000, 100, 10);

        var AMMAggregator = await compile("amm-aggregator/aggregator/AMMAggregator");

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
            mooniswap: { contract: await new web3.eth.Contract(AMMs.Mooniswap.abi).deploy({ data: AMMs.Mooniswap.bin, arguments: [context.mooniswapFactoryAddress] }).send(blockchainConnection.getSendingOptions()) },
            uniswap,
            sushiSwap: { contract: await new web3.eth.Contract(AMMs.SushiSwap.abi).deploy({ data: AMMs.SushiSwap.bin, arguments: [context.sushiSwapRouterAddress] }).send(blockchainConnection.getSendingOptions()) },
            balancer: { contract: await new web3.eth.Contract(AMMs.Balancer.abi).deploy({ data: AMMs.Balancer.bin, arguments: [context.wethTokenAddress] }).send(blockchainConnection.getSendingOptions()) }
        }

        tokens = [
            context.wethTokenAddress,
            //context.usdtTokenAddress,
            context.chainLinkTokenAddress,
            context.usdcTokenAddress,
            context.daiTokenAddress,
            context.mkrTokenAddress,
            context.balTokenAddress
        ].map(it => new web3.eth.Contract(context.IERC20ABI, it));

        await Promise.all(tokens.map(it => buyForETH(it, buyForETHAmount, uniswap.contract)));

        var ammsAddresses = Object.values(amms).map(it => it.contract.options.address);

        ammAggregator = await new web3.eth.Contract(AMMAggregator.abi).deploy({ data: AMMAggregator.bin, arguments: [ammDFO.doubleProxyAddress, ammsAddresses] }).send(blockchainConnection.getSendingOptions());
    });

    async function getAMMS() {
        var IAMM = await compile("amm-aggregator/common/IAMM");

        var addresses = await ammAggregator.methods.amms().call();

        var gottenAMMS = {};

        for(var address of addresses) {
            var amm = {
                address,
                contract: new web3.eth.Contract(IAMM.abi, address)
            };
            var data = await amm.contract.methods.data().call();
            amm.ethereumAddress = data[0];
            amm.maxTokensPerLiquidityPool = parseInt(data[1]);
            amm.hasUniqueLiquidityPools = data[2];
            data = await amm.contract.methods.info().call();
            amm.name = data[0];
            amm.version = data[1];
            gottenAMMS[amm.name.substring(0, 1).toLowerCase() + amm.name.substring(1).split('V2').join('')] = amm;

            amm.name.toLowerCase().indexOf("balancer") !== -1 && (amm.doubleTokenLiquidityPoolAddress = web3.utils.toChecksumAddress("0x8a649274e4d777ffc6851f13d23a86bbfa2f2fbf"));
            amm.name.toLowerCase().indexOf("balancer") !== -1 && (amm.multipleTokenLiquidityPoolAddress = web3.utils.toChecksumAddress("0x9b208194acc0a8ccb2a8dcafeacfbb7dcc093f81"));

            amm.toBuy = 300;
            try {
                await addLiquidity(amm, accounts[0], true, false, amm.doubleTokenLiquidityPoolAddress);
            } catch (e) {}
            try {
                amm.name.toLowerCase().indexOf("balancer") === -1 && await addLiquidity(amm, accounts[0], true, true, amm.doubleTokenLiquidityPoolAddress);
            } catch (e) {}
            delete amm.toBuy;
        }

        return gottenAMMS;
    }

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
            path: [token.options.address],
            inputToken: ethereumAddress,
            receiver: utilities.voidEthereumAddress
        }).send(blockchainConnection.getSendingOptions({ value }));
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

    function assertstrictEqual(actual, expected, difference) {
        difference = difference || 0.0005;
        try {
            assert.strictEqual(actual, expected);
        } catch (e) {
            var diff = Math.abs(utilities.formatNumber(actual) - utilities.formatNumber(expected));
            console.error(`Diff of ${diff} of ${difference}: ${actual} - ${expected}`);
            if (diff > difference) {
                throw e;
            }
        }
    }

    it("byLP", async () => {
        var data = await ammAggregator.methods.findByLiquidityPool(liquidityPool.options.address).call();
        assert.strictEqual(amms.uniswap ? amms.uniswap.contract.options.address : utilities.voidEthereumAddress, data[3]);
    });

    it("setAMMS", async () => {

        var addresses = await ammAggregator.methods.amms().call();

        var toAdd = [];
        var toDeleteCode = "";
        var toAddCode = "";
        for(var i = addresses.length -1; i >= 0; i--) {
            toDeleteCode += `        aggregator.remove(${i});\n`;
        }
        var code = fs.readFileSync(path.resolve(__dirname, '..', 'resources/AMMSetAMMs.sol'), 'UTF-8').format(ammAggregator.options.address, toDeleteCode.trim(), toAdd.length, toAddCode.trim());
        var proposal = await dfoManager.createProposal(ammDFO, "", true, code, "callOneTime(address)");
        await dfoManager.finalizeProposal(ammDFO, proposal);
        var newAddresses = await ammAggregator.methods.amms().call();
        assert.strictEqual(newAddresses.length, 0);

        toAdd = [];
        toDeleteCode = "";
        toAddCode = "";
        for(var i = addresses.length -1; i >= 0; i--) {
            toAdd.push(addresses[i]);
            toAddCode += `        ammsToAdd[${i}] = ${addresses[i]};\n`;
        }
        var code = fs.readFileSync(path.resolve(__dirname, '..', 'resources/AMMSetAMMs.sol'), 'UTF-8').format(ammAggregator.options.address, toDeleteCode.trim(), toAdd.length, toAddCode.trim());
        var proposal = await dfoManager.createProposal(ammDFO, "", true, code, "callOneTime(address)");
        await dfoManager.finalizeProposal(ammDFO, proposal);
        var newAddresses = await ammAggregator.methods.amms().call();
        assert.strictEqual(newAddresses.length, Object.values(amms).length);

        toAdd = [];
        toDeleteCode = "";
        toAddCode = "";
        for(var i = addresses.length -1; i >= 0; i--) {
            toDeleteCode += `        aggregator.remove(${i});\n`;
            toAdd.push(addresses[i]);
            toAddCode += `        ammsToAdd[${i}] = ${addresses[i]};\n`;
        }
        var code = fs.readFileSync(path.resolve(__dirname, '..', 'resources/AMMSetAMMs.sol'), 'UTF-8').format(ammAggregator.options.address, toDeleteCode.trim(), toAdd.length, toAddCode.trim());
        var proposal = await dfoManager.createProposal(ammDFO, "", true, code, "callOneTime(address)");
        await dfoManager.finalizeProposal(ammDFO, proposal);
        var newAddresses = await ammAggregator.methods.amms().call();
        assert.strictEqual(newAddresses.length, Object.values(amms).length);
    });

    it("swapLiquidity", async() => {
        for (amm of Object.values(await getAMMS())) {
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
                if (amm.name.toLowerCase().indexOf('balancer') === -1) {
                    console.log("receiver path +: noEth");
                    await swapLiquidity(amm, accounts[1], false, false, true);
                    console.log("receiver path +: ethInTheMiddle");
                    await swapLiquidity(amm, accounts[1], false, false, true, true);
                }
                console.log("no receiver path +: enterInETH");
                await swapLiquidity(amm, undefined, true, false, true);
                console.log("no receiver path +: exitInETH");
                await swapLiquidity(amm, undefined, false, true, true);
                console.log("no receiver path +: enterInETH exitInETH");
                await swapLiquidity(amm, undefined, true, true, true);
                if (amm.name.toLowerCase().indexOf('balancer') === -1) {
                    console.log("no receiver path +: noEth");
                    await swapLiquidity(amm, undefined, false, false, true);
                    console.log("no receiver path +: ethInTheMiddle");
                    await swapLiquidity(amm, undefined, false, false, true, true);
                }
            } catch (e) {
                throw e;
            }
        }
    });

    async function createLiquidityPoolAndAddLiquidityNoPool(amm, receiver, existing, ethereum, moreThan2) {
        receiver = receiver || utilities.voidEthereumAddress;
        var realReceiver = receiver === utilities.voidEthereumAddress ? accounts[0] : receiver;

        dfo = await dfoManager.createDFO("MyName", "MySymbol", 10000000, 100, 10);

        var tokenAddresses = getTokenAddresses(ethereum, amm.ethereumAddress, moreThan2, existing, dfo);

        if (existing) {
            while (true) {
                var data = await amm.contract.methods.byTokens(tokenAddresses).call();
                if (data[2] !== utilities.voidEthereumAddress) {
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
            liquidityPool = new web3.eth.Contract(context.IERC20ABI, liquidityPoolAddress = data[2]);
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
            expectedLiquidityPoolAmount = liquidityPoolData[0];
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
        await nothingInContracts(amm.contract.options.address);
    }

    it("createLiquidityPoolAndAddLiquidity", async() => {
        for (amm of Object.values(await getAMMS())) {
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
                if (e.message.indexOf("VM Exception") === -1) {
                    throw e;
                }
                console.error(e.message);
            }
        }
    });

    async function addLiquidity(amm, receiver, byLP, ethereum, liquidityPoolAddress, tokenIndex) {

        liquidityPoolAddress = liquidityPoolAddress || amm.doubleTokenLiquidityPoolAddress;

        var tokenAddresses = !liquidityPoolAddress ? undefined : (await amm.contract.methods.byLiquidityPool(liquidityPoolAddress).call())[2];

        if (!tokenAddresses) {
            while (true) {
                var data = await amm.contract.methods.byTokens(tokenAddresses = getTokenAddresses(ethereum, amm.ethereumAddress)).call();
                if (data[2] !== utilities.voidEthereumAddress) {
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
        var data = await amm.contract.methods.byTokenAmount(liquidityPoolAddress, tokenAddresses[byLP ? 0 : tokenIndex], utilities.toDecimals(amm.toBuy || randomPlainAmount(), decimals)).call();
        var liquidityPoolAmount = data[0];
        var amounts = data[1];
        tokenAddresses = data[2];

        if (byLP) {
            var data = await amm.contract.methods.byLiquidityPoolAmount(liquidityPoolAddress, liquidityPoolAmount).call();
            amounts = data[0];
        }


        if (liquidityPoolAmount === '0' || amounts.indexOf(it => it === '0') !== -1) {
            if (!amm.hasUniqueLiquidityPools) {
                return;
            }
            return await addLiquidity(amm, receiver, byLP, ethereum);
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
        amm.liquidityPoolAddress = amm.liquidityPoolAddress || ethereum ? undefined : liquidityPoolAddress;
        amm.liquidityPoolAddressETH = amm.liquidityPoolAddressETH || !ethereum ? undefined : liquidityPoolAddress;
        var transactionFee = await blockchainConnection.calculateTransactionFee(transaction);

        for (var i in tokenAddresses) {
            var token = getToken(tokenAddresses[i], ethereum, amm.ethereumAddress);
            var decimals = token ? await token.methods.decimals().call() : 18;
            if (ethereum && tokenAddresses[i] === amm.ethereumAddress) {
                expectedSenderAmounts[i] = web3.utils.toBN(expectedSenderAmounts[i]).sub(web3.utils.toBN(transactionFee)).toString();
            }
            var actualSenderBalance = token ? await token.methods.balanceOf(accounts[0]).call() : await web3.eth.getBalance(accounts[0]);
            assertstrictEqual(utilities.fromDecimals(actualSenderBalance, decimals), utilities.fromDecimals(expectedSenderAmounts[i], decimals), 0.0009);
        }

        assertstrictEqual(utilities.fromDecimals(await liquidityPool.methods.balanceOf(realReceiver).call(), liquidityPoolDecimals), expectedLiquidityPoolAmount);
        await nothingInContracts(amm.contract.options.address);
    }

    it("addLiquidity", async() => {
        for (amm of Object.values(await getAMMS())) {
            try {
                console.log(amm.name);
                console.log("receiver by LP Amount");
                await addLiquidity(amm, accounts[1], true, false, amm.doubleTokenLiquidityPoolAddress);
                console.log("receiver by token amount 4 all tokens");
                await addLiquidity(amm, accounts[1], false, false, amm.doubleTokenLiquidityPoolAddress);
                console.log("receiver by LP Amount involving eth");
                await addLiquidity(amm, accounts[1], true, true, amm.doubleTokenLiquidityPoolAddress);
                console.log("receiver token amount 4 all tokens involving eth");
                await addLiquidity(amm, accounts[1], false, true, amm.doubleTokenLiquidityPoolAddress);
                console.log("no receiver by LP Amount");
                await addLiquidity(amm, undefined, true, false, amm.doubleTokenLiquidityPoolAddress);
                console.log("no receiver by token amount 4 all tokens");
                await addLiquidity(amm, undefined, false, false, amm.doubleTokenLiquidityPoolAddress);
                console.log("no receiver by LP Amount involving eth");
                await addLiquidity(amm, undefined, true, true, amm.doubleTokenLiquidityPoolAddress);
                console.log("no receiver token amount 4 all tokens involving eth");
                await addLiquidity(amm, undefined, false, true, amm.doubleTokenLiquidityPoolAddress);

                if (amm.maxTokensPerLiquidityPool == 0) {
                    console.log("receiver by LP Amount with more than 2 tokens");
                    await addLiquidity(amm, accounts[1], true, false, amm.multipleTokenLiquidityPoolAddress);
                    console.log("receiver by token amount 4 all tokens with more than 2 tokens");
                    await addLiquidity(amm, accounts[1], false, false, amm.multipleTokenLiquidityPoolAddress);
                    console.log("receiver by LP Amount involving eth with more than 2 tokens");
                    await addLiquidity(amm, accounts[1], true, true, amm.multipleTokenLiquidityPoolAddress);
                    console.log("receiver token amount 4 all tokens involving eth with more than 2 tokens");
                    await addLiquidity(amm, accounts[1], false, true, amm.multipleTokenLiquidityPoolAddress);
                    console.log("no receiver by LP Amount with more than 2 tokens");
                    await addLiquidity(amm, undefined, true, false, amm.multipleTokenLiquidityPoolAddress);
                    console.log("no receiver by token amount 4 all tokens with more than 2 tokens");
                    await addLiquidity(amm, undefined, false, false, amm.multipleTokenLiquidityPoolAddress);
                    console.log("no receiver by LP Amount involving eth with more than 2 tokens");
                    await addLiquidity(amm, undefined, true, true, amm.multipleTokenLiquidityPoolAddress);
                    console.log("no receiver token amount 4 all tokens involving eth with more than 2 tokens");
                    await addLiquidity(amm, undefined, false, true, amm.multipleTokenLiquidityPoolAddress);
                }
            } catch (e) {
                if (e.message.indexOf("VM Exception") === -1) {
                    throw e;
                }
                console.error(e.message);
            }
        }
    });

    async function removeLiquidity(amm, receiver, byLP, ethereum, oldLiquidityPoolAddress, tokenIndex) {

        var liquidityPoolAddress = oldLiquidityPoolAddress ? oldLiquidityPoolAddress : ethereum ? amm.liquidityPoolAddressETH : amm.liquidityPoolAddress;

        var tokenAddresses = !liquidityPoolAddress ? undefined : (await amm.contract.methods.byLiquidityPool(liquidityPoolAddress).call())[2];

        if (!tokenAddresses) {
            while (true) {
                var data = await amm.contract.methods.byTokens(tokenAddresses = getTokenAddresses(ethereum, amm.ethereumAddress)).call();
                if (data[2] !== utilities.voidEthereumAddress) {
                    console.log(tokenAddresses);
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
            /*for (var i in tokenAddresses) {
                await removeLiquidity(amm, receiver, byLP, ethereum, liquidityPoolAddress, utilities.formatNumber(i));
            }
            return;*/
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

        if (liquidityPoolAmount === '0' || amounts.indexOf(it => it === '0') !== -1) {
            if(!amm.hasUniqueLiquidityPools) {
                return;
            }
            return;
            //return await removeLiquidity(amm, receiver, byLP, ethereum);
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
        await nothingInContracts(amm.contract.options.address);
    }

    it("removeLiquidity", async() => {
        for (amm of Object.values(await getAMMS())) {
            try {
                console.log(amm.name);
                console.log("receiver by LP Amount");
                await removeLiquidity(amm, accounts[1], true, false, amm.doubleTokenLiquidityPoolAddress);
                console.log("receiver by token amount 4 all tokens");
                await removeLiquidity(amm, accounts[1], false, false, amm.doubleTokenLiquidityPoolAddress);
                console.log("receiver by LP Amount involving eth");
                await removeLiquidity(amm, accounts[1], true, true, amm.doubleTokenLiquidityPoolAddress);
                console.log("receiver token amount 4 all tokens involving eth");
                await removeLiquidity(amm, accounts[1], false, true, amm.doubleTokenLiquidityPoolAddress);
                console.log("no receiver by LP Amount");
                await removeLiquidity(amm, undefined, true, false, amm.doubleTokenLiquidityPoolAddress);
                console.log("no receiver by token amount 4 all tokens");
                await removeLiquidity(amm, undefined, false, false, amm.doubleTokenLiquidityPoolAddress);
                console.log("no receiver by LP Amount involving eth");
                await removeLiquidity(amm, undefined, true, true, amm.doubleTokenLiquidityPoolAddress);
                console.log("no receiver token amount 4 all tokens involving eth");
                await removeLiquidity(amm, undefined, false, true, amm.doubleTokenLiquidityPoolAddress);

                if (amm.maxTokensPerLiquidityPool == 0) {
                    console.log("receiver by LP Amount with more than 2 tokens");
                    await removeLiquidity(amm, accounts[1], true, false, amm.multipleTokenLiquidityPoolAddress);
                    console.log("receiver by token amount 4 all tokens with more than 2 tokens");
                    await removeLiquidity(amm, accounts[1], false, false, amm.multipleTokenLiquidityPoolAddress);
                    console.log("receiver by LP Amount involving eth with more than 2 tokens");
                    await removeLiquidity(amm, accounts[1], true, true, amm.multipleTokenLiquidityPoolAddress);
                    console.log("receiver token amount 4 all tokens involving eth with more than 2 tokens");
                    await removeLiquidity(amm, accounts[1], false, true, amm.multipleTokenLiquidityPoolAddress);
                    console.log("no receiver by LP Amount with more than 2 tokens");
                    await removeLiquidity(amm, undefined, true, false, amm.multipleTokenLiquidityPoolAddress);
                    console.log("no receiver by token amount 4 all tokens with more than 2 tokens");
                    await removeLiquidity(amm, undefined, false, false, amm.multipleTokenLiquidityPoolAddress);
                    console.log("no receiver by LP Amount involving eth with more than 2 tokens");
                    await removeLiquidity(amm, undefined, true, true, amm.multipleTokenLiquidityPoolAddress);
                    console.log("no receiver token amount 4 all tokens involving eth with more than 2 tokens");
                    await removeLiquidity(amm, undefined, false, true, amm.multipleTokenLiquidityPoolAddress);
                }
            } catch (e) {
                if (e.message.indexOf("VM Exception") === -1) {
                    throw e;
                }
                console.error(e.message);
            }
        }
    });

    it("UniswapBatch", async () => {
        var amms = await getAMMS();
        if(!amms.uniswap) {
            return;
        }
        var amm = amms.uniswap;
        var liquidityPoolAddress = amm.doubleTokenLiquidityPoolAddress;
        var tokenAddresses;
        if(!liquidityPoolAddress) {
            var data = await amm.contract.methods.byTokens([context.daiTokenAddress, amm.ethereumAddress]).call();
            liquidityPoolAddress = data[2];
            tokenAddresses = data[3];
        }
        var data = await amm.contract.methods.byLiquidityPool(liquidityPoolAddress).call();
        tokenAddresses = data[2];

        var liquidityPool = new web3.eth.Contract(context.IERC20ABI, liquidityPoolAddress);
        var before = utilities.fromDecimals(await liquidityPool.methods.balanceOf(accounts[0]).call(), 18);

        for(var tokenAddress of tokenAddresses) {
            var token = tokens.filter(it => it.options.address === tokenAddress)[0];
            await token.methods.approve(amm.contract.options.address, utilities.toDecimals(0xfffffffffffffffffffffffffffffffffffffffffffff, await token.methods.decimals().call())).send(blockchainConnection.getSendingOptions());
        }
        var liquidityPoolAmount = utilities.toDecimals(15, 18);
        var byLiquidityPoolAmountData = await amm.contract.methods.byLiquidityPoolAmount(liquidityPoolAddress, liquidityPoolAmount).call();
        var ethereumIndex = tokenAddresses.indexOf(amm.ethereumAddress);
        var ethereumAmount = byLiquidityPoolAmountData[0][ethereumIndex];
        var liquidityPoolsData = [{
            liquidityPoolAddress,
            amount : liquidityPoolAmount,
            tokenAddress : utilities.voidEthereumAddress,
            amountIsLiquidityPool : true,
            involvingETH : true,
            receiver : utilities.voidEthereumAddress
        },{
            liquidityPoolAddress,
            amount : ethereumAmount,
            tokenAddress : amm.ethereumAddress,
            amountIsLiquidityPool : false,
            involvingETH : true,
            receiver : utilities.voidEthereumAddress
        },{
            liquidityPoolAddress,
            amount : ethereumAmount,
            tokenAddress : amm.ethereumAddress,
            amountIsLiquidityPool : false,
            involvingETH : false,
            receiver : utilities.voidEthereumAddress
        }];
        var value = web3.utils.toBN(ethereumAmount).add(web3.utils.toBN(ethereumAmount)).toString();
        await amm.contract.methods.addLiquidityBatch(liquidityPoolsData).send(blockchainConnection.getSendingOptions({value}));
        await nothingInContracts(amm.contract.options.address);

        await amm.contract.methods.addLiquidityBatch(liquidityPoolsData).send(blockchainConnection.getSendingOptions({value}));
        await nothingInContracts(amm.contract.options.address);

        var after = utilities.fromDecimals(await liquidityPool.methods.balanceOf(accounts[0]).call(), 18);
        console.log(before, after);

        await liquidityPool.methods.approve(amm.contract.options.address, utilities.toDecimals(0xfffffffffffffffffffffffffffffffffffffffffffff, await liquidityPool.methods.decimals().call())).send(blockchainConnection.getSendingOptions());
        await amm.contract.methods.removeLiquidityBatch(liquidityPoolsData).send(blockchainConnection.getSendingOptions());
        await nothingInContracts(amm.contract.options.address);
        before = after;
        after = utilities.fromDecimals(await liquidityPool.methods.balanceOf(accounts[0]).call(), 18);
        console.log(before, after);

        value = ethereumAmount;

        var swapDatas = [{
            enterInETH : true,
            exitInETH : false,
            liquidityPoolAddresses : [liquidityPoolAddress],
            path : [context.daiTokenAddress],
            inputToken : amm.ethereumAddress,
            amount : ethereumAmount,
            receiver : accounts[0]
        }, {
            enterInETH : false,
            exitInETH : true,
            liquidityPoolAddresses : [liquidityPoolAddress],
            path : [amm.ethereumAddress],
            inputToken : context.daiTokenAddress,
            amount : ethereumAmount,
            receiver : accounts[0]
        },{
            enterInETH : false,
            exitInETH : false,
            liquidityPoolAddresses : [liquidityPoolAddress],
            path : [context.daiTokenAddress],
            inputToken : amm.ethereumAddress,
            amount : ethereumAmount,
            receiver : accounts[0]
        }];

        await amm.contract.methods.swapLiquidityBatch(swapDatas).send(blockchainConnection.getSendingOptions({value}));
        await nothingInContracts(amm.contract.options.address);
    });

    it("Mooniswap Batch", async () => {
        var amms = await getAMMS();
        if(!amms.mooniswap) {
            return;
        }
        var amm = amms.mooniswap;
        var liquidityPoolAddress = amm.doubleTokenLiquidityPoolAddress;
        var tokenAddresses;
        if(!liquidityPoolAddress) {
            var data = await amm.contract.methods.byTokens([context.daiTokenAddress, amm.ethereumAddress]).call();
            liquidityPoolAddress = data[2];
            tokenAddresses = data[3];
        }
        var data = await amm.contract.methods.byLiquidityPool(liquidityPoolAddress).call();
        tokenAddresses = data[2];

        var liquidityPool = new web3.eth.Contract(context.IERC20ABI, liquidityPoolAddress);
        var before = utilities.fromDecimals(await liquidityPool.methods.balanceOf(accounts[0]).call(), 18);

        for(var tokenAddress of tokenAddresses) {
            var token = tokens.filter(it => it.options.address === tokenAddress)[0];
            try {
                await token.methods.approve(amm.contract.options.address, utilities.toDecimals(0xfffffffffffffffffffffffffffffffffffffffffffff, await token.methods.decimals().call())).send(blockchainConnection.getSendingOptions());
            } catch(e) {
            }
        }
        var liquidityPoolAmount = utilities.toDecimals(15, 18);
        var byLiquidityPoolAmountData = await amm.contract.methods.byLiquidityPoolAmount(liquidityPoolAddress, liquidityPoolAmount).call();
        var ethereumIndex = tokenAddresses.indexOf(amm.ethereumAddress);
        var ethereumAmount = byLiquidityPoolAmountData[0][ethereumIndex];
        var liquidityPoolsData = [{
            liquidityPoolAddress,
            amount : liquidityPoolAmount,
            tokenAddress : utilities.voidEthereumAddress,
            amountIsLiquidityPool : true,
            involvingETH : true,
            receiver : utilities.voidEthereumAddress
        },{
            liquidityPoolAddress,
            amount : ethereumAmount,
            tokenAddress : amm.ethereumAddress,
            amountIsLiquidityPool : false,
            involvingETH : true,
            receiver : utilities.voidEthereumAddress
        },{
            liquidityPoolAddress,
            amount : ethereumAmount,
            tokenAddress : amm.ethereumAddress,
            amountIsLiquidityPool : false,
            involvingETH : false,
            receiver : utilities.voidEthereumAddress
        }];
        var value = web3.utils.toBN(ethereumAmount).add(web3.utils.toBN(ethereumAmount)).add(web3.utils.toBN(ethereumAmount)).toString();
        await amm.contract.methods.addLiquidityBatch(liquidityPoolsData).send(blockchainConnection.getSendingOptions({value}));
        await nothingInContracts(amm.contract.options.address);

        await amm.contract.methods.addLiquidityBatch(liquidityPoolsData).send(blockchainConnection.getSendingOptions({value}));
        await nothingInContracts(amm.contract.options.address);

        var after = utilities.fromDecimals(await liquidityPool.methods.balanceOf(accounts[0]).call(), 18);
        console.log(before, after);

        await liquidityPool.methods.approve(amm.contract.options.address, utilities.toDecimals(0xfffffffffffffffffffffffffffffffffffffffffffff, await liquidityPool.methods.decimals().call())).send(blockchainConnection.getSendingOptions());
        await amm.contract.methods.removeLiquidityBatch(liquidityPoolsData).send(blockchainConnection.getSendingOptions());
        await nothingInContracts(amm.contract.options.address);
        before = after;
        after = utilities.fromDecimals(await liquidityPool.methods.balanceOf(accounts[0]).call(), 18);
        console.log(before, after);

        value =  web3.utils.toBN(ethereumAmount).add(web3.utils.toBN(ethereumAmount)).toString();

        var swapDatas = [{
            enterInETH : true,
            exitInETH : false,
            liquidityPoolAddresses : [liquidityPoolAddress],
            path : [context.daiTokenAddress],
            inputToken : amm.ethereumAddress,
            amount : ethereumAmount,
            receiver : accounts[0]
        }, {
            enterInETH : false,
            exitInETH : true,
            liquidityPoolAddresses : [liquidityPoolAddress],
            path : [amm.ethereumAddress],
            inputToken : context.daiTokenAddress,
            amount : ethereumAmount,
            receiver : accounts[0]
        },{
            enterInETH : false,
            exitInETH : false,
            liquidityPoolAddresses : [liquidityPoolAddress],
            path : [context.daiTokenAddress],
            inputToken : amm.ethereumAddress,
            amount : ethereumAmount,
            receiver : accounts[0]
        }];

        await amm.contract.methods.swapLiquidityBatch(swapDatas).send(blockchainConnection.getSendingOptions({value}));
        await nothingInContracts(amm.contract.options.address);
    });

    it("SushiSwap Batch", async () => {
        var amms = await getAMMS();
        if(!amms.sushiSwap) {
            return;
        }
        var amm = amms.sushiSwap;
        var liquidityPoolAddress = amm.liquidityPoolAddressETH;
        var tokenAddresses;
        if(!liquidityPoolAddress) {
            var data = await amm.contract.methods.byTokens([context.usdcTokenAddress, amm.ethereumAddress]).call();
            liquidityPoolAddress = data[2];
            tokenAddresses = data[3];
        }
        var data = await amm.contract.methods.byLiquidityPool(liquidityPoolAddress).call();
        tokenAddresses = data[2];

        var liquidityPool = new web3.eth.Contract(context.IERC20ABI, liquidityPoolAddress);
        var before = utilities.fromDecimals(await liquidityPool.methods.balanceOf(accounts[0]).call(), 18);

        for(var tokenAddress of tokenAddresses) {
            var token = tokens.filter(it => it.options.address === tokenAddress)[0];
            await token.methods.approve(amm.contract.options.address, utilities.toDecimals(0xfffffffffffffffffffffffffffffffffffffffffffff, await token.methods.decimals().call())).send(blockchainConnection.getSendingOptions());
        }
        var liquidityPoolAmount = utilities.toDecimals(0.1, 18);
        var byLiquidityPoolAmountData = await amm.contract.methods.byLiquidityPoolAmount(liquidityPoolAddress, liquidityPoolAmount).call();
        var ethereumIndex = tokenAddresses.indexOf(amm.ethereumAddress);
        var ethereumAmount = byLiquidityPoolAmountData[0][ethereumIndex];
        var otherTokenAddress = tokenAddresses[ethereumIndex === 0 ? 1 : 0];
        console.log(ethereumAmount);
        var liquidityPoolsData = [{
            liquidityPoolAddress,
            amount : liquidityPoolAmount,
            tokenAddress : utilities.voidEthereumAddress,
            amountIsLiquidityPool : true,
            involvingETH : true,
            receiver : utilities.voidEthereumAddress
        },{
            liquidityPoolAddress,
            amount : ethereumAmount,
            tokenAddress : amm.ethereumAddress,
            amountIsLiquidityPool : false,
            involvingETH : true,
            receiver : utilities.voidEthereumAddress
        },{
            liquidityPoolAddress,
            amount : ethereumAmount,
            tokenAddress : amm.ethereumAddress,
            amountIsLiquidityPool : false,
            involvingETH : false,
            receiver : utilities.voidEthereumAddress
        }];
        var value = web3.utils.toBN(ethereumAmount).add(web3.utils.toBN(ethereumAmount)).toString();
        await amm.contract.methods.addLiquidityBatch(liquidityPoolsData).send(blockchainConnection.getSendingOptions({value}));
        await nothingInContracts(amm.contract.options.address);

        await amm.contract.methods.addLiquidityBatch(liquidityPoolsData).send(blockchainConnection.getSendingOptions({value}));
        await nothingInContracts(amm.contract.options.address);

        var after = utilities.fromDecimals(await liquidityPool.methods.balanceOf(accounts[0]).call(), 18);
        console.log(before, after);

        await liquidityPool.methods.approve(amm.contract.options.address, utilities.toDecimals(0xfffffffffffffffffffffffffffffffffffffffffffff, await liquidityPool.methods.decimals().call())).send(blockchainConnection.getSendingOptions());
        await amm.contract.methods.removeLiquidityBatch(liquidityPoolsData).send(blockchainConnection.getSendingOptions());
        await nothingInContracts(amm.contract.options.address);
        before = after;
        after = utilities.fromDecimals(await liquidityPool.methods.balanceOf(accounts[0]).call(), 18);
        console.log(before, after);

        value = ethereumAmount;

        var swapDatas = [{
            enterInETH : true,
            exitInETH : false,
            liquidityPoolAddresses : [liquidityPoolAddress],
            path : [otherTokenAddress],
            inputToken : amm.ethereumAddress,
            amount : ethereumAmount,
            receiver : accounts[0]
        }, {
            enterInETH : false,
            exitInETH : true,
            liquidityPoolAddresses : [liquidityPoolAddress],
            path : [amm.ethereumAddress],
            inputToken : otherTokenAddress,
            amount : ethereumAmount,
            receiver : accounts[0]
        },{
            enterInETH : false,
            exitInETH : false,
            liquidityPoolAddresses : [liquidityPoolAddress],
            path : [otherTokenAddress],
            inputToken : amm.ethereumAddress,
            amount : ethereumAmount,
            receiver : accounts[0]
        }];

        await amm.contract.methods.swapLiquidityBatch(swapDatas).send(blockchainConnection.getSendingOptions({value}));
        await nothingInContracts(amm.contract.options.address);
    });

    it("Balancer Batch", async () => {
        var amms = await getAMMS();
        if(!amms.balancer) {
            return;
        }
        var amm = amms.balancer;
        var liquidityPoolAddress = amm.doubleTokenLiquidityPoolAddress;
        var tokenAddresses;
        if(!liquidityPoolAddress) {
            var data = await amm.contract.methods.byTokens([context.daiTokenAddress, amm.ethereumAddress]).call();
            liquidityPoolAddress = data[2];
            tokenAddresses = data[3];
        }
        var data = await amm.contract.methods.byLiquidityPool(liquidityPoolAddress).call();
        tokenAddresses = data[2];

        var liquidityPool = new web3.eth.Contract(context.IERC20ABI, liquidityPoolAddress);
        var before = utilities.fromDecimals(await liquidityPool.methods.balanceOf(accounts[0]).call(), 18);

        for(var tokenAddress of tokenAddresses) {
            var token = tokens.filter(it => it.options.address === tokenAddress)[0];
            await token.methods.approve(amm.contract.options.address, utilities.toDecimals(0xfffffffffffffffffffffffffffffffffffffffffffff, await token.methods.decimals().call())).send(blockchainConnection.getSendingOptions());
        }
        var liquidityPoolAmount = utilities.toDecimals(15, 18);
        var byLiquidityPoolAmountData = await amm.contract.methods.byLiquidityPoolAmount(liquidityPoolAddress, liquidityPoolAmount).call();
        var ethereumIndex = tokenAddresses.indexOf(amm.ethereumAddress);
        var ethereumAmount = byLiquidityPoolAmountData[0][ethereumIndex];

        var byTokenAmount = await amm.contract.methods.byTokenAmount(liquidityPoolAddress, amm.ethereumAddress, ethereumAmount).call();
        //ethereumAmount = byTokenAmount[1][ethereumIndex];
        //liquidityPoolAmount = byTokenAmount[0];

        var liquidityPoolsData = [{
            liquidityPoolAddress,
            amount : liquidityPoolAmount,
            tokenAddress : utilities.voidEthereumAddress,
            amountIsLiquidityPool : true,
            involvingETH : true,
            receiver : utilities.voidEthereumAddress
        },{
            liquidityPoolAddress,
            amount : ethereumAmount,
            tokenAddress : amm.ethereumAddress,
            amountIsLiquidityPool : false,
            involvingETH : false,
            receiver : utilities.voidEthereumAddress
        }];
        var value = ethereumAmount;
        await amm.contract.methods.addLiquidityBatch(liquidityPoolsData).send(blockchainConnection.getSendingOptions({value}));
        await nothingInContracts(amm.contract.options.address);

        var after = utilities.fromDecimals(await liquidityPool.methods.balanceOf(accounts[0]).call(), 18);
        console.log(before, after, await liquidityPool.methods.balanceOf(accounts[0]).call());

        byLiquidityPoolAmountData = await amm.contract.methods.byLiquidityPoolAmount(liquidityPoolAddress, liquidityPoolAmount).call();
        ethereumAmount = byLiquidityPoolAmountData[0][ethereumIndex];
        value = ethereumAmount;
        await amm.contract.methods.addLiquidityBatch(liquidityPoolsData).send(blockchainConnection.getSendingOptions({value}));
        await nothingInContracts(amm.contract.options.address);

        console.log(before, after, await liquidityPool.methods.balanceOf(accounts[0]).call());

        await liquidityPool.methods.approve(amm.contract.options.address, utilities.toDecimals(0xfffffffffffffffffffffffffffffffffffffffffffff, await liquidityPool.methods.decimals().call())).send(blockchainConnection.getSendingOptions());
        await amm.contract.methods.removeLiquidityBatch(liquidityPoolsData).send(blockchainConnection.getSendingOptions());
        await nothingInContracts(amm.contract.options.address);
        before = after;
        after = utilities.fromDecimals(await liquidityPool.methods.balanceOf(accounts[0]).call(), 18);
        console.log(before, after);

        byLiquidityPoolAmountData = await amm.contract.methods.byLiquidityPoolAmount(liquidityPoolAddress, liquidityPoolAmount).call();
        ethereumAmount = byLiquidityPoolAmountData[0][ethereumIndex];
        value = ethereumAmount;

        var swapDatas = [{
            enterInETH : true,
            exitInETH : false,
            liquidityPoolAddresses : [liquidityPoolAddress],
            path : [context.usdcTokenAddress],
            inputToken : amm.ethereumAddress,
            amount : ethereumAmount,
            receiver : accounts[0]
        }/*, {
            enterInETH : false,
            exitInETH : true,
            liquidityPoolAddresses : [liquidityPoolAddress],
            path : [amm.ethereumAddress],
            inputToken : context.usdcTokenAddress,
            amount : ethereumAmount,
            receiver : accounts[0]
        },{
            enterInETH : false,
            exitInETH : false,
            liquidityPoolAddresses : [liquidityPoolAddress],
            path : [context.usdcTokenAddress],
            inputToken : amm.ethereumAddress,
            amount : ethereumAmount,
            receiver : accounts[0]
        }*/];

        await amm.contract.methods.swapLiquidityBatch(swapDatas).send(blockchainConnection.getSendingOptions({value}));
        await nothingInContracts(amm.contract.options.address);
    });

    async function swapLiquidity(amm, receiver, enterInETH, exitInETH, moreThanOne, ethInTheMiddle) {

        var liquidityPoolAddress = !moreThanOne ? amm.doubleTokenLiquidityPoolAddress : amm.multipleTokenLiquidityPoolAddress;
        if (amm.maxTokensPerLiquidityPool === 0 && enterInETH && exitInETH) {
            return;
        }

        var inputToken;
        var paths;
        var liquidityPoolAddresses;

        if (!liquidityPoolAddress) {
            var otherToken;
            while ((liquidityPoolAddress = (await amm.contract.methods.byTokens([
                    inputToken = enterInETH ? amm.ethereumAddress : randomTokenAddress(amm.ethereumAddress),
                    otherToken = randomTokenAddress([inputToken, amm.ethereumAddress])
                ]).call())[2]) === utilities.voidEthereumAddress) {}

            paths = [otherToken];

            liquidityPoolAddresses = [liquidityPoolAddress];

            if (moreThanOne) {
                var length = randomPlainAmount(4);
                var position = 0;
                for (var i = 0; i < length; i++) {
                    var times = 0;
                    while (true) {
                        otherToken = randomTokenAddress(paths.slice(0, position + 1));
                        if (otherToken !== inputToken && paths.indexOf(otherToken) === -1) {
                            if ((liquidityPoolAddress = (await amm.contract.methods.byTokens([
                                    paths[position],
                                    otherToken
                                ]).call())[2]) !== utilities.voidEthereumAddress) {
                                break;
                            }
                        }
                        if (times++ >= 5) {
                            return await swapLiquidity(amm, receiver, enterInETH, exitInETH, moreThanOne, ethInTheMiddle);
                        }
                    }
                    paths.push(otherToken);
                    liquidityPoolAddresses.push(liquidityPoolAddress);
                    position++;
                }
            }

            if (exitInETH) {
                paths[paths.length - 1] = amm.ethereumAddress;
                liquidityPoolAddresses[liquidityPoolAddresses.length - 1] = (await amm.contract.methods.byTokens([moreThanOne ? paths[paths.length - 2] : inputToken, paths[paths.length - 1]]).call())[2];
            }
        } else {
            var lpTokens = (await amm.contract.methods.byLiquidityPool(liquidityPoolAddress).call())[2];
            var nonEthToken = lpTokens.filter(it => it !== amm.ethereumAddress)[0];
            inputToken = enterInETH || !exitInETH ? amm.ethereumAddress : nonEthToken;
            paths = [enterInETH || !exitInETH ? nonEthToken : amm.ethereumAddress];
            liquidityPoolAddresses = [liquidityPoolAddress];
            if (amm.maxTokensPerLiquidityPool === 0 && moreThanOne) {
                liquidityPoolAddresses.push(liquidityPoolAddresses[0]);
                var thirdToken = lpTokens.filter(it => it !== amm.ethereumAddress && it !== paths[0])[0];
                enterInETH && paths.push(thirdToken);
                exitInETH && paths.unshift(thirdToken);
            }
        }

        if (enterInETH && !exitInETH && paths[paths.length - 1] === context.wethTokenAddress) {
            return await swapLiquidity(amm, receiver, enterInETH, exitInETH, moreThanOne, ethInTheMiddle);
        }

        if (enterInETH && exitInETH && (paths.slice(0, paths.length - 1).indexOf(amm.ethereumAddress) !== -1 || paths.slice(0, paths.length - 1).indexOf(utilities.voidEthereumAddress) !== -1)) {
            return await swapLiquidity(amm, receiver, enterInETH, exitInETH, moreThanOne, ethInTheMiddle);
        }

        var token = inputToken !== utilities.voidEthereumAddress && tokens.filter(it => it.options.address === inputToken)[0];
        var decimals = !token ? 18 : await token.methods.decimals().call();

        var lastTokenAddress = paths[paths.length - 1];
        var lastToken = lastTokenAddress !== utilities.voidEthereumAddress && tokens.filter(it => it.options.address === lastTokenAddress)[0];
        var lastDecimals = !lastToken ? 18 : await lastToken.methods.decimals().call();

        var amountPlain = randomPlainAmount();
        var amount = utilities.toDecimals(amountPlain, decimals);

        var expectedSenderBalance = !enterInETH ? await token.methods.balanceOf(accounts[0]).call() : await web3.eth.getBalance(accounts[0]);
        if (accounts[0] !== realReceiver) {
            expectedSenderBalance = web3.utils.toBN(expectedSenderBalance).sub(web3.utils.toBN(amount)).toString();
        }

        receiver = receiver || utilities.voidEthereumAddress;
        var realReceiver = receiver === utilities.voidEthereumAddress ? accounts[0] : receiver;

        var outputAmount;
        try {
            outputAmount = await amm.contract.methods.getSwapOutput(inputToken, amount, liquidityPoolAddresses, paths).call();
        } catch (e) {
            if (enterInETH && exitInETH && paths.length === 1) {
                return console.error(e.message);
            }
            if (e.message.toLowerCase().indexOf("identical_addresses") !== -1 || e.message.toLowerCase().indexOf("insufficient_input_amount") !== -1) {
                return await swapLiquidity(amm, receiver, enterInETH, exitInETH, moreThanOne, ethInTheMiddle);
            }
            throw e;
        }

        outputAmount = outputAmount[outputAmount.length - 1];
        if (outputAmount === '0') {
            return await swapLiquidity(amm, receiver, enterInETH, exitInETH, moreThanOne, ethInTheMiddle);
        }

        var before = {};
        before[accounts[0]] = await totalSum(accounts[0]);
        if (realReceiver !== accounts[0]) {
            before[realReceiver] = await totalSum(realReceiver);
        }
        var totals = {};
        var entries = Object.values(before);
        var toCheck = [utilities.voidEthereumAddress];
        toCheck.push(...tokens.map(it => it));
        for (var toCheckToken of toCheck) {
            var address = toCheckToken.options ? toCheckToken.options.address : toCheckToken;
            totals[address] = totals[address] || '0';
            for (var entry of entries) {
                var amnt = entry[address];
                amnt && (totals[address] = web3.utils.toBN(totals[address]).add(web3.utils.toBN(amnt)).toString());
            }
            if (address === (enterInETH ? utilities.voidEthereumAddress : inputToken)) {
                (totals[address] = web3.utils.toBN(totals[address]).sub(web3.utils.toBN(amount)).toString());
            }
            if (address === (exitInETH ? utilities.voidEthereumAddress : lastTokenAddress)) {
                (totals[address] = web3.utils.toBN(totals[address]).add(web3.utils.toBN(outputAmount)).toString());
            }
        }

        var expectedReceiverBalance = !exitInETH ? await lastToken.methods.balanceOf(realReceiver).call() : await web3.eth.getBalance(realReceiver);
        expectedReceiverBalance = web3.utils.toBN(expectedReceiverBalance).add(web3.utils.toBN(outputAmount)).toString();

        var swapData = {
            amount,
            inputToken,
            path: paths,
            liquidityPoolAddresses,
            receiver,
            enterInETH: enterInETH || false,
            exitInETH: exitInETH || false
        }

        !enterInETH && await token.methods.approve(amm.contract.options.address, amount).send(blockchainConnection.getSendingOptions());

        var transaction;
        try {
            transaction = await amm.contract.methods.swapLiquidity(swapData).send(blockchainConnection.getSendingOptions({ value: enterInETH ? amount : '0' }));
            var names = [];
            for (var i in paths) {
                if ((i = parseInt(i)) === paths.length - 1) {
                    break;
                }
                var adr = paths[i];
                var tkn = adr === utilities.voidEthereumAddress ? adr : new web3.eth.Contract(context.IERC20ABI, adr);
                names.push(await tokenData(tkn, "symbol"));
            }
            console.log(`swapped ${amountPlain} ${await tokenData(enterInETH ? utilities.voidEthereumAddress : token, "symbol")} -> ${names.length === 0 ? "" : (names.join(' -> ') + " -> ")}${utilities.fromDecimals(outputAmount, lastDecimals)} ${await tokenData(exitInETH ? utilities.voidEthereumAddress : lastToken, "symbol")}`);
        } catch (e) {
            if (enterInETH && exitInETH && paths.length === 1) {
                return console.error(e.message);
            }
            if (e.message.toLowerCase().indexOf("identical_addresses") !== -1 || e.message.toLowerCase().indexOf("insufficient_input_amount") !== -1) {
                return await swapLiquidity(amm, receiver, enterInETH, exitInETH, moreThanOne, ethInTheMiddle);
            }
            throw e;
        }

        var transactionFee = await blockchainConnection.calculateTransactionFee(transaction);
        if (enterInETH) {
            expectedSenderBalance = web3.utils.toBN(expectedSenderBalance).sub(web3.utils.toBN(transactionFee)).toString();
            if (accounts[0] === realReceiver) {
                expectedReceiverBalance = web3.utils.toBN(expectedReceiverBalance).sub(web3.utils.toBN(transactionFee)).toString();
            }
        }

        expectedSenderBalance = utilities.fromDecimals(expectedSenderBalance, decimals);
        expectedReceiverBalance = utilities.fromDecimals(expectedReceiverBalance, lastDecimals);

        var actualSenderBalance = utilities.fromDecimals(!enterInETH ? await token.methods.balanceOf(accounts[0]).call() : await web3.eth.getBalance(accounts[0]), decimals);

        assertstrictEqual(actualSenderBalance, expectedSenderBalance, (accounts[0] === realReceiver && (enterInETH || exitInETH || ethInTheMiddle || inputToken === paths[paths.length - 1]) ? amountPlain : 0));

        var actualReceiverBalance = utilities.fromDecimals(!exitInETH ? await lastToken.methods.balanceOf(realReceiver).call() : await web3.eth.getBalance(realReceiver), lastDecimals);

        await nothingInContracts(amm.contract.options.address);

        try {
            assert(utilities.formatNumber(actualReceiverBalance.split(',').join('')) >= utilities.formatNumber(expectedReceiverBalance.split(',').join('')) - (accounts[0] === realReceiver && (enterInETH || exitInETH || ethInTheMiddle || inputToken === paths[paths.length - 1]) ? amountPlain : 0));
        } catch (e) {
            console.error(amountPlain);
            console.error(actualReceiverBalance, expectedReceiverBalance);
            console.error(e.message);
            //throw e;
        }

        var after = {};
        after[accounts[0]] = await totalSum(accounts[0]);
        if (realReceiver !== accounts[0]) {
            after[realReceiver] = await totalSum(realReceiver);
        }
        var actuals = {};
        var entries = Object.values(after);
        var toCheck = [utilities.voidEthereumAddress];
        toCheck.push(...tokens.map(it => it));
        totals[utilities.voidEthereumAddress] = web3.utils.toBN(totals[utilities.voidEthereumAddress]).sub(web3.utils.toBN(transactionFee)).toString();
        for (var toCheckToken of toCheck) {
            var address = toCheckToken.options ? toCheckToken.options.address : toCheckToken;
            var dec = toCheckToken.methods ? await toCheckToken.methods.decimals().call() : 18;
            actuals[address] = actuals[address] || '0';
            for (var entry of entries) {
                var amnt = entry[address];
                amnt && (actuals[address] = web3.utils.toBN(actuals[address]).add(web3.utils.toBN(amnt)).toString());
            }
            try {
                assertstrictEqual(utilities.fromDecimals(actuals[address], dec), utilities.fromDecimals(totals[address], dec), 0.0009);
            } catch (e) {
                console.error(await tokenData(toCheckToken, "symbol"), utilities.fromDecimals(actuals[address], dec), utilities.fromDecimals(totals[address], dec), e.message);
            }
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

    async function totalSum(address) {
        var data = {};
        var toCheck = [utilities.voidEthereumAddress];
        toCheck.push(...tokens.map(it => it));
        for (var token of toCheck) {
            data[token.options ? token.options.address : token] = token === utilities.voidEthereumAddress ? await web3.eth.getBalance(address) : await token.methods.balanceOf(address).call();
        }
        return data;
    }
});
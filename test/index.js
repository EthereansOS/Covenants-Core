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

describe("Index", () => {

    var Index;
    var indexContract;
    var indexCollection;
    var buyForETHAmount = 100;
    var tokens;
    var amm;

    before(async() => {

        await blockchainConnection.init;

        Index = await compile('index/Index');
        var UniswapV2AMMV1 = await compile('amm-aggregator/models/UniswapV2/1/UniswapV2AMMV1');

        amm = await new web3.eth.Contract(UniswapV2AMMV1.abi).deploy({ data: UniswapV2AMMV1.bin, arguments: [context.uniswapV2RouterAddress] }).send(blockchainConnection.getSendingOptions());

        tokens = [
            context.wethTokenAddress,
            context.buidlTokenAddress,
            context.usdtTokenAddress,
            context.usdcTokenAddress,
            context.daiTokenAddress
        ].map(it => new web3.eth.Contract(context.IERC20ABI, it));

        await Promise.all(tokens.filter(it => it.options.address !== context.wethTokenAddress).map(it => buyForETH(it, buyForETHAmount, amm)));

    });

    async function buyForETH(token, valuePlain, ammPlugin) {
        ammPlugin = ammPlugin || amm;
        var ethereumAddress = (await ammPlugin.methods.data().call())[0];
        var liquidityPoolAddress = (await ammPlugin.methods.byTokens([
            ethereumAddress,
            token.options.address
        ]).call())[2];
        var amount = utilities.toDecimals(valuePlain.toString(), '18');
        await ammPlugin.methods.swapLiquidity({
            amount,
            enterInETH : true,
            exitInETH : false,
            liquidityPoolAddresses : [liquidityPoolAddress],
            paths : [token.options.address],
            inputToken : ethereumAddress,
            receiver : utilities.voidEthereumAddress
        }).send(blockchainConnection.getSendingOptions({value : amount}));
    }

    it("Contract creation", async () => {
        indexContract = await new web3.eth.Contract(Index.abi).deploy({data : Index.bin, arguments : [context.ethItemOrchestratorAddress, "Index", "IDX", "google.com"]}).send(blockchainConnection.getSendingOptions());
        indexCollection = new web3.eth.Contract(context.ethItemNativeABI, await indexContract.methods.collection().call());

        assert.notStrictEqual(indexContract.options.address, utilities.voidEthereumAddress);
        assert.notStrictEqual(indexCollection.options.address, utilities.voidEthereumAddress);
    });

    async function newIndex(name, symbol, uri, tokens, amountsPlain, amountToMint) {

        var ethInvolved = tokens.filter(it => it === utilities.voidEthereumAddress).length === 1;
        var amounts = [];

        for(var i in tokens) {
            var token = tokens[i];
            amounts.push(utilities.toDecimals(amountsPlain[i], token.methods ? await token.methods.decimals().call() : 18));
            try {
                var amount = utilities.numberToString(parseInt(amounts[i]) * (amountToMint || 0));
                token.methods && await token.methods.approve(indexContract.options.address, amount).send(blockchainConnection.getSendingOptions());
            } catch(e) {
            }
        }

        var tokenAddresses = tokens.map(it => it.options ? it.options.address : it);

        var transaction = await indexContract.methods.mint(name, symbol, uri, tokenAddresses, amounts, amountToMint || 0, accounts[0]).send(blockchainConnection.getSendingOptions({value : ethInvolved ? parseInt(amounts[tokenAddresses.indexOf(utilities.voidEthereumAddress)]) * (amountToMint || 0) : 0}));

        transaction = await web3.eth.getTransactionReceipt(transaction.transactionHash);
        var event = web3.utils.sha3("NewIndex(uint256,address,address,uint256)");
        var objectId = transaction.logs.filter(it => it.topics[0] === event)[0].topics[1];
        objectId = web3.eth.abi.decodeParameter("uint256", objectId);

        var data = await indexContract.methods.info(objectId).call();

        assert.strictEqual(JSON.stringify(data[0]), JSON.stringify(tokenAddresses));
        assert.strictEqual(JSON.stringify(data[1]), JSON.stringify(amounts));

        assert.strictEqual(await indexCollection.methods.balanceOf(accounts[0], objectId).call(), utilities.toDecimals(amountToMint || 0, 18));

        return objectId;
    }

    async function getObjectIds(tokens) {
        var event = "NewIndex(uint256,address,address,uint256)";
        var topics = [
            web3.utils.sha3(event),
            undefined,
            undefined
        ];
        topics.push(tokens && tokens.length > 0 ? tokens.map(it => web3.eth.abi.encodeParameter("address", it.options ? it.options.address : it)) : undefined);
        var logs = await web3.eth.getPastLogs({
            address : indexContract.options.address,
            fromBlock : global.startBlock,
            toBlock : 'latest',
            topics
        });
        var objectIds = {};
        for(var log of logs) {
            objectIds[web3.eth.abi.decodeParameter("uint256", log.topics[1])] = true;
        }
        objectIds = Object.keys(objectIds);
        return objectIds;
    }

    it("Index creation", () => newIndex("Maralla", "Mulino", "google.com", tokens.map(it => it.options.address === context.wethTokenAddress ? utilities.voidEthereumAddress : it), tokens.map(() => 4), 5));

    it("Mint more", async () => {
        var objectId = (await getObjectIds())[0];
        var amountToMint = 3;
        var receiver = accounts[1];
        var balanceOfBefore = await indexCollection.methods.balanceOf(receiver, objectId).call();
        var balanceOfExpected = web3.utils.toBN(balanceOfBefore).add(web3.utils.toBN(utilities.toDecimals(amountToMint, 18))).toString();

        var data = await indexContract.methods.info(objectId).call();

        var retrievedTokens = data[0];
        var originalAmounts = data[1];
        var ethInvolved = retrievedTokens.filter(it => it === utilities.voidEthereumAddress).length === 1;
        var amounts = [];
        for(var i in retrievedTokens) {
            var token = retrievedTokens[i] === utilities.voidEthereumAddress ? retrievedTokens[i] : new web3.eth.Contract(context.IERC20ABI, retrievedTokens[i]);
            amounts.push(web3.utils.toBN(originalAmounts[i]).mul(web3.utils.toBN(amountToMint)).toString());
            try {
                token.methods && await token.methods.approve(indexContract.options.address, amounts[i]).send(blockchainConnection.getSendingOptions());
            } catch(e) {
            }
        }

        await indexContract.methods.mint(objectId, amountToMint, receiver).send(blockchainConnection.getSendingOptions({value : ethInvolved ? amounts[retrievedTokens.indexOf(utilities.voidEthereumAddress)] : 0}));

        assert.strictEqual(await indexCollection.methods.balanceOf(receiver, objectId).call(), balanceOfExpected);
    });

    async function burn(objectId, amountToBurnPlain, receiver) {

        var amountToBurn = utilities.toDecimals(amountToBurnPlain, 18);

        var expectedAmount = web3.utils.toBN(await indexCollection.methods.balanceOf(accounts[0], objectId).call()).sub(web3.utils.toBN(amountToBurn)).toString();

        var data = await indexContract.methods.info(objectId).call();
        var retrievedTokens = data[0];
        var originalAmounts = data[1];

        var expectedAmounts = [];

        for(var i in retrievedTokens) {
            var token = retrievedTokens[i] === utilities.voidEthereumAddress ? retrievedTokens[i] : new web3.eth.Contract(context.IERC20ABI, retrievedTokens[i]);
            var tokenValue = web3.utils.toBN(originalAmounts[i]).mul(web3.utils.toBN(amountToBurn)).div(web3.utils.toBN(1e18)).toString();
            expectedAmounts.push(token === utilities.voidEthereumAddress ? await web3.eth.getBalance(receiver || accounts[0]) : await token.methods.balanceOf(receiver || accounts[0]).call());
            expectedAmounts[i] = web3.utils.toBN(expectedAmounts[i]).add(web3.utils.toBN(tokenValue)).toString();
        }

        var transaction = await indexCollection.methods.safeTransferFrom(accounts[0], indexContract.options.address, objectId, amountToBurn, receiver ? web3.eth.abi.encodeParameter("address", receiver) : "0x").send(blockchainConnection.getSendingOptions());
        var transactionFee = await blockchainConnection.calculateTransactionFee(transaction);

        for(var i in retrievedTokens) {
            var token = retrievedTokens[i] === utilities.voidEthereumAddress ? retrievedTokens[i] : new web3.eth.Contract(context.IERC20ABI, retrievedTokens[i]);
            var balanceOfAfter = token === utilities.voidEthereumAddress ? await web3.eth.getBalance(receiver || accounts[0]) : await token.methods.balanceOf(receiver || accounts[0]).call();
            var expectedTokenAmount = expectedAmounts[i];
            token === utilities.voidEthereumAddress && (receiver || accounts[0]) === accounts[0] && (expectedTokenAmount = web3.utils.toBN(expectedTokenAmount).sub(web3.utils.toBN(transactionFee)).toString());
            assert.strictEqual(balanceOfAfter, expectedTokenAmount);
        }

        assert.strictEqual(await indexCollection.methods.balanceOf(accounts[0], objectId).call(), expectedAmount);
    }

    it("Burn some", async () => await burn((await getObjectIds())[0], 2.38, accounts[2]));

    it("Multiple Burn", async () => {

        var receiver = accounts[1];

        var amountToBurn = utilities.toDecimals(utilities.formatMoney(Math.random(), 6), 18);

        var tkns = tokens.filter(it => it.options.address !== context.wethTokenAddress);
        await newIndex("Gneppo", "Gnappo", "google.com", tkns, tkns.map(() => utilities.formatMoney(Math.random(), 6)), 5);

        var objectIds = await getObjectIds();

        var objects = {};

        var tokenValues = {}

        for(var objectId of objectIds) {
            var data = await indexContract.methods.info(objectId).call();
            var retrievedTokens = data[0];
            var originalAmounts = data[1];

            var expectedAmounts = [];

            for(var i in retrievedTokens) {
                var token = retrievedTokens[i] === utilities.voidEthereumAddress ? retrievedTokens[i] : new web3.eth.Contract(context.IERC20ABI, retrievedTokens[i]);
                var tokenValue = web3.utils.toBN(originalAmounts[i]).mul(web3.utils.toBN(amountToBurn)).div(web3.utils.toBN(1e18)).toString();
                expectedAmounts.push(token === utilities.voidEthereumAddress ? await web3.eth.getBalance(receiver || accounts[0]) : await token.methods.balanceOf(receiver || accounts[0]).call());
                expectedAmounts[i] = web3.utils.toBN(expectedAmounts[i]).add(web3.utils.toBN(tokenValue)).toString();
                var tokenAddress = token.options ? token.options.address : token;
                if(!tokenValues[tokenAddress]) {
                    tokenValues[tokenAddress] = {
                        tokenAddress,
                        expectedBalance : token === utilities.voidEthereumAddress ? await web3.eth.getBalance(receiver || accounts[0]) : await token.methods.balanceOf(receiver || accounts[0]).call()
                    };
                }
                tokenValues[tokenAddress].expectedBalance = web3.utils.toBN(tokenValues[tokenAddress].expectedBalance).add(web3.utils.toBN(tokenValue)).toString();
            }
            objects[objectId] = {
                objectId,
                retrievedTokens,
                originalAmounts,
                expectedAmounts,
                expectedAmount : web3.utils.toBN(await indexCollection.methods.balanceOf(accounts[0], objectId).call()).sub(web3.utils.toBN(amountToBurn)).toString(),
                receiver,
                amountToBurn,
                tokenValues
            }
        }

        var data = web3.eth.abi.encodeParameter("bytes[]", Object.values(objects).map(it => web3.eth.abi.encodeParameter("address", it.receiver)));

        var transaction = await indexCollection.methods.safeBatchTransferFrom(accounts[0], indexContract.options.address, Object.keys(objects), Object.values(objects).map(it => it.amountToBurn), data).send(blockchainConnection.getSendingOptions());
        var transactionFee = await blockchainConnection.calculateTransactionFee(transaction);

        var values = Object.values(objects);

        for(var value of values) {
            var {objectId, expectedAmount} = value;
            assert.strictEqual(await indexCollection.methods.balanceOf(accounts[0], objectId).call(), expectedAmount);
        }

        tokenValues = Object.values(tokenValues);

        for(var tokenValue of tokenValues) {
            var token = tokenValue.tokenAddress === utilities.voidEthereumAddress ? tokenValue.tokenAddress : new web3.eth.Contract(context.IERC20ABI, tokenValue.tokenAddress);
            var balanceOfAfter = token === utilities.voidEthereumAddress ? await web3.eth.getBalance(receiver || accounts[0]) : await token.methods.balanceOf(receiver || accounts[0]).call();
            var expectedTokenAmount = tokenValue.expectedBalance;
            token === utilities.voidEthereumAddress && (receiver || accounts[0]) === accounts[0] && (expectedTokenAmount = web3.utils.toBN(expectedTokenAmount).sub(web3.utils.toBN(transactionFee)).toString());
            assert.strictEqual(balanceOfAfter, expectedTokenAmount);
        }
    });
});
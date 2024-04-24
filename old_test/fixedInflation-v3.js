var dfoManager = require('../util/dfo');
var path = require('path');
var fs = require('fs');

var buildOSStuff = require('../resources/OS/buildOsStuff');
require("../util/mocha");

var ethItemOrchestrator;
var uniswapV2Factory;
var uniswapV2Router;
var wethToken;

var rewardToken;
var mainToken;
var secondaryToken;

var ethToSpend = 600000;

var dfo;

var UniswapV2AMMV1;
var uniswapAMMV2;
var uniswapAMM;

var FixedInflationFactory;
var fixedInflationFactory;

var FixedInflationExtension;
var fixedInflationExtension;

var DFOBasedFixedInflationExtensionFactory;
var DFOBasedFixedInflationExtension;

var FixedInflation;
var fixedInflation;

var liquidityPool;

var dFOBasedFixedInflationExtensionFactory;

var tokens;

var actors = {};

var mainDFO;

describe("FixedInflation UniV3", () => {

    before(async() => {

        FixedInflationFactory = await compile('fixed-inflation/FixedInflationFactory');
        FixedInflationExtension = await compile('fixed-inflation/dfo/DFOBasedFixedInflationExtension');
        FixedInflationDefaultExtension = await compile('fixed-inflation/FixedInflationExtension');
        FixedInflation = await compile('fixed-inflation/FixedInflationUniV3');

        DFOBasedFixedInflationExtensionFactory = await compile('fixed-inflation/dfo/DFOBasedFixedInflationExtensionFactory');
        DFOBasedFixedInflationExtension = await compile('fixed-inflation/dfo/DFOBasedFixedInflationExtension');

        mainDFO = await dfoManager.createDFO("MyName", "MySymbol", 10000000, 100, 10);

        ethItemOrchestrator = new web3.eth.Contract(knowledgeBase.ethItemOrchestratorABI, knowledgeBase.ethItemOrchestratorAddress);
        uniswapV2Router = new web3.eth.Contract(knowledgeBase.uniswapV2RouterABI, knowledgeBase.uniswapV2RouterAddress);
        uniswapV2Factory = new web3.eth.Contract(knowledgeBase.uniswapV2FactoryABI, knowledgeBase.uniswapV2FactoryAddress);

        UniswapV2AMMV1 = await compile('amm-aggregator/models/UniswapV2/1/UniswapV2AMMV1');
        uniswapAMM = await new web3.eth.Contract(UniswapV2AMMV1.abi).deploy({ data: UniswapV2AMMV1.bin, arguments: [uniswapV2Router.options.address] }).send(blockchainConnection.getSendingOptions());
        uniswapAMMV2 = uniswapAMM;
        tokens = [
            knowledgeBase.wethTokenAddress,
            knowledgeBase.usdtTokenAddress,
            knowledgeBase.chainLinkTokenAddress,
            knowledgeBase.usdcTokenAddress,
            knowledgeBase.daiTokenAddress,
            knowledgeBase.mkrTokenAddress,
            knowledgeBase.buidlTokenAddress,
            knowledgeBase.balTokenAddress,
            knowledgeBase.osTokenAddress
        ].map(it => new web3.eth.Contract(knowledgeBase.IERC20ABI, it));

        await Promise.all(tokens.map(it => buyForETH(it, ethToSpend, uniswapAMM)));

        UniswapV3AMMV1 = await compile('amm-aggregator/models/UniswapV3/1/UniswapV3AMMV1');
        uniswapAMM = await new web3.eth.Contract(UniswapV3AMMV1.abi).deploy({ data: UniswapV3AMMV1.bin, arguments: [knowledgeBase.swapRouterAddress, knowledgeBase.uniswapV3NonfungiblePositionManagerAddress, knowledgeBase.uniswapV3QuoterAddress, "0.00001".toDecimals(18)] }).send(blockchainConnection.getSendingOptions());
        await buyForETH(tokens[tokens.length - 1], ethToSpend, uniswapAMM);
        await deployDFOAndFactory().then(deployAllOccurencyStuff);
    });

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

    async function buyForETH(token, amount, ammPlugin) {
        var value = utilities.toDecimals(amount.toString(), '18');
        if (token.options.address === knowledgeBase.wethTokenAddress) {
            return await web3.eth.sendTransaction(blockchainConnection.getSendingOptions({
                to: knowledgeBase.wethTokenAddress,
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
        if (liquidityPoolAddress === utilities.voidEthereumAddress) {
            return;
        }
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

    async function buy(sender, tokenA, amountPlain, tokenB, enterInETH, exitInETH, ammPlugin) {
        if(tokenA === utilities.voidEthereumAddress) {
            return await buyForETH(tokenB, amountPlain, ammPlugin);
        }
        var value = utilities.toDecimals(utilities.numberToString(amountPlain), await tokenA.methods.decimals().call());
        ammPlugin = ammPlugin || uniswapAMM;
        var secondToken = tokenB === utilities.voidEthereumAddress ? (await ammPlugin.methods.data().call())[0] : tokenB.options.address;
        var fees = Object.values(knowledgeBase.uniswapV3PoolFeeValues);
        for(var fee of fees) {
            var liquidityPoolAddress = (await ammPlugin.methods.byTokens([
                tokenA.options.address,
                secondToken,
                fee
            ]).call())[2];
            console.log('Fee:', fee, 'LP:', liquidityPoolAddress);
            if (liquidityPoolAddress !== utilities.voidEthereumAddress) {
                var method = ammPlugin.methods.swapLiquidity({
                    amount: value,
                    enterInETH: enterInETH || false,
                    exitInETH: exitInETH || false,
                    liquidityPoolAddresses: [liquidityPoolAddress],
                    path: [secondToken],
                    inputToken: tokenA.options.address,
                    receiver: utilities.voidEthereumAddress
                });
                var sendingOptions = blockchainConnection.getSendingOptions({ from : sender || accounts[0], value : enterInETH ? value : 0 });
                var result = '0';
                try {
                    result = await method.call(sendingOptions);
                } catch(e) {
                    console.error(e);
                }
                if(result !== '0') {
                    await method.send(sendingOptions);
                    return result;
                }
            }
        }
        return '0';
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
        var token = new web3.eth.Contract(knowledgeBase.IERC20ABI, tokenAddress);
        var totalSupply = await token.methods.totalSupply();
        var ONE_HUNDRED = await fixedInflation.methods.ONE_HUNDRED().call();
        var amount = web3.utils.toBN(totalSupply).mul(web3.utils.toBN(tokenAmount).mul(web3.utils.toBN(1e18)).div(web3.utils.toBN(ONE_HUNDRED))).div(web3.utils.toBN(1e18));
        return amount.toString();
    }

    async function calculatePercentage(totalAmount, percentage) {
        var ONE_HUNDRED = await fixedInflation.methods.ONE_HUNDRED().call();
        var amount = web3.utils.toBN(totalAmount).mul(web3.utils.toBN(percentage).mul(web3.utils.toBN(1e18)).div(web3.utils.toBN(ONE_HUNDRED))).div(web3.utils.toBN(1e18));
        return amount.toString();
    }

    async function calculateTokenPercentage(tokenAddress, tokenAmount, amountIsPercentage, percentage) {
        return await calculatePercentage(await calculateTokenAmount(tokenAddress, tokenAmount, amountIsPercentage), percentage);
    }

    async function getEntries() {
        var entries = [];
        var logs = await web3.eth.getPastLogs({
            fromBlock: global.startBlock,
            toBlock: 'latest',
            address: fixedInflation.options.address,
            topics: [
                web3.utils.sha3('Entry(bytes32)')
            ]
        });
        for (var log of logs) {
            entries.push(await fixedInflation.methods.entry(log.topics[1]).call());
        }
        entries = entries.map(it => {
            var entry = {
                operations: it[1]
            };
            Object.entries(it[0]).forEach(original => entry[original[0]] = original[1]);
            return entry;
        });
        return entries.filter(it => it.id !== utilities.voidBytes32);
    }

    async function deployDFOAndFactory() {
        if(global.deployDFOAndFactoryDone) {
            return;
        }
        global.deployDFOAndFactoryDone = true;
        dfo = await dfoManager.createDFO("MyName", "MySymbol", 1000000000000, 100, 10);

        var fixedInflationModel = await new web3.eth.Contract(FixedInflation.abi).deploy({ data: FixedInflation.bin }).send(blockchainConnection.getSendingOptions());

        var fixedInflationDefaultExtensionModel = await new web3.eth.Contract(FixedInflationDefaultExtension.abi).deploy({ data: FixedInflationDefaultExtension.bin }).send(blockchainConnection.getSendingOptions());

        fixedInflationFactory = await new web3.eth.Contract(FixedInflationFactory.abi).deploy({
            data: FixedInflationFactory.bin,
            arguments: [
                dfo.doubleProxyAddress,
                fixedInflationModel.options.address,
                fixedInflationDefaultExtensionModel.options.address,
                utilities.toDecimals("0.1", 18)
            ]
        }).send(blockchainConnection.getSendingOptions());

        await web3.eth.sendTransaction(blockchainConnection.getSendingOptions({
            to: dfo.mvdWalletAddress,
            value: utilities.toDecimals(30, 18)
        }));

        for (var token of tokens) {
            try {
                await token.methods.transfer(dfo.mvdWalletAddress, utilities.toDecimals(1000, await token.methods.decimals().call())).send(blockchainConnection.getSendingOptions());
            } catch (e) {
                var value = utilities.toDecimals(15, await token.methods.decimals().call());
                var balance = await token.methods.balanceOf(accounts[0]).call();
                value = parseInt(value) > parseInt(balance) ? utilities.numberToString(parseInt(parseInt(balance) * 0.8)) : value;
                await token.methods.transfer(dfo.mvdWalletAddress, value).send(blockchainConnection.getSendingOptions());
            }
        }

        await dfo.votingToken.methods.transfer(dfo.mvdWalletAddress, utilities.toDecimals(300000, await dfo.votingToken.methods.decimals().call())).send(blockchainConnection.getSendingOptions());
    }

    it("Deploy DFO and factory", deployDFOAndFactory);

    async function deployAllOccurencyStuff() {

        if(global.deployAllOccurencyStuffDone) {
            return;
        }
        global.deployAllOccurencyStuffDone = true;

        var dFOBasedFixedInflationExtensionModel = await new web3.eth.Contract(DFOBasedFixedInflationExtension.abi).deploy({ data: DFOBasedFixedInflationExtension.bin }).send(blockchainConnection.getSendingOptions());

        dFOBasedFixedInflationExtensionFactory = await new web3.eth.Contract(DFOBasedFixedInflationExtensionFactory.abi).deploy({ data: DFOBasedFixedInflationExtensionFactory.bin, arguments: [mainDFO.doubleProxyAddress, dFOBasedFixedInflationExtensionModel.options.address] }).send(blockchainConnection.getSendingOptions());
        var transaction = await dFOBasedFixedInflationExtensionFactory.methods.cloneModel().send(blockchainConnection.getSendingOptions());
        var receipt = await web3.eth.getTransactionReceipt(transaction.transactionHash);
        var dFOBasedFixedInflationExtensionAddress = web3.eth.abi.decodeParameter("address", receipt.logs.filter(it => it.topics[0] === web3.utils.sha3('ExtensionCloned(address,address)'))[0].topics[1])

        transaction = await fixedInflationFactory.methods.cloneFixedInflationDefaultExtension().send(blockchainConnection.getSendingOptions());
        receipt = await web3.eth.getTransactionReceipt(transaction.transactionHash);
        var fixedInflationExtensionAddress = web3.eth.abi.decodeParameter("address", receipt.logs.filter(it => it.topics[0] === web3.utils.sha3('ExtensionCloned(address)'))[0].topics[1])

        var osFixedInflationExtension = await buildOSStuff();
        osFixedInflationExtensionAddress = osFixedInflationExtension.fixedInflationExtensionAddress;

        var chosenFixedInflationAddress;

        chosenFixedInflationAddress = fixedInflationExtensionAddress;
        chosenFixedInflationAddress = dFOBasedFixedInflationExtensionAddress;
        chosenFixedInflationAddress = osFixedInflationExtensionAddress;

        fixedInflationExtension = new web3.eth.Contract(DFOBasedFixedInflationExtension.abi, chosenFixedInflationAddress);
        try {
            await blockchainConnection.unlockAccounts(fixedInflationExtension.options.address);
        } catch(e) {
        }
        var newEntries = [{
            id: web3.utils.sha3('0'),
            lastBlock: 0,
            name: "Cataldo",
            blockInterval: 10,
            callerRewardPercentage: utilities.toDecimals("0.01", "18"),
            operations: [{
                inputTokenAddress: utilities.voidEthereumAddress,
                inputTokenAmount: utilities.toDecimals("3", "18"),
                inputTokenAmountIsPercentage: false,
                inputTokenAmountIsByMint: false,
                ammPlugin: utilities.voidEthereumAddress,
                liquidityPoolAddresses: [],
                swapPath: [],
                receivers: [accounts[1]],
                receiversPercentages: [],
                enterInETH: false,
                exitInETH: false
            }]
        }];

        var data = new web3.eth.Contract(FixedInflation.abi).methods.init(
            fixedInflationExtension.options.address,
            fixedInflationExtension.options.address === osFixedInflationExtensionAddress ? osFixedInflationExtension.fixedInflationExtensionLazyInitData : fixedInflationExtension.methods.init(fixedInflationExtension.options.address === dFOBasedFixedInflationExtensionAddress ? dfo.doubleProxyAddress : accounts[0]).encodeABI(),
            newEntries[0],
            newEntries.map(it => it.operations)[0]
        ).encodeABI();

        var result = await fixedInflationFactory.methods.deploy(data).send(blockchainConnection.getSendingOptions());
        result = await web3.eth.getTransactionReceipt(result.transactionHash);

        var fixedInflationAddress = web3.eth.abi.decodeParameter("address", result.logs.filter(it => it.topics[0] === web3.utils.sha3('FixedInflationDeployed(address,address,bytes)'))[0].topics[1]);

        fixedInflation = new web3.eth.Contract(FixedInflation.abi, fixedInflationAddress);
        try {
            await blockchainConnection.unlockAccounts(fixedInflation.options.address);
        } catch(e) {
        }

        assert.strictEqual(fixedInflationFactory.options.address, await fixedInflation.methods._factory().call());
        if (fixedInflationExtension.options.address === dFOBasedFixedInflationExtensionAddress) {
            var code = fs.readFileSync(path.resolve(__dirname, '..', 'contracts/fixed-inflation/dfo/ManageFixedInflationFunctionality.sol'), 'UTF-8').format(fixedInflationExtension.options.address);
            var proposal = await dfoManager.createProposal(dfo, "manageFixedInflation", true, code, "manageFixedInflation(address,uint256,address[],uint256[],uint256[],address)", false, true);
            await dfoManager.finalizeProposal(dfo, proposal);
        } else {
            await fixedInflationExtension.methods.setActive(true).send(blockchainConnection.getSendingOptions());
            await web3.eth.sendTransaction(blockchainConnection.getSendingOptions({
                to: fixedInflationExtension.options.address,
                value: utilities.toDecimals(30, 18)
            }));

            for (var token of tokens) {
                try {
                    await token.methods.transfer(fixedInflationExtension.options.address, utilities.toDecimals(1000, await token.methods.decimals().call())).send(blockchainConnection.getSendingOptions());
                } catch (e) {
                    var value = utilities.toDecimals(15, await token.methods.decimals().call());
                    var balance = await token.methods.balanceOf(accounts[0]).call();
                    value = parseInt(value) > parseInt(balance) ? utilities.numberToString(parseInt(parseInt(balance) * 0.8)) : value;
                    await token.methods.transfer(fixedInflationExtension.options.address, value).send(blockchainConnection.getSendingOptions());
                }
            }

            await dfo.votingToken.methods.transfer(fixedInflationExtension.options.address, utilities.toDecimals(300000, await dfo.votingToken.methods.decimals().call())).send(blockchainConnection.getSendingOptions());
        }
    }

    it("Deploy all occurrency stuff", deployAllOccurencyStuff);

    it("Cannot re-initialize already initialized contracts", async() => {
        try {
            await fixedInflationExtension.methods.init(dfo.doubleProxyAddress).send(blockchainConnection.getSendingOptions());
            assert(false);
        } catch (e) {
            assert.notStrictEqual((e.message || e).toLowerCase().indexOf("already init"), -1);
        }
        try {
            var newEntries = [{
                id: web3.utils.sha3('0'),
                lastBlock: 0,
                name: "Cataldo",
                blockInterval: 10,
                callerRewardPercentage: 100,
                operations: [{
                    inputTokenAddress: utilities.voidEthereumAddress,
                    inputTokenAmount: utilities.toDecimals("0.01", "18"),
                    inputTokenAmountIsPercentage: false,
                    inputTokenAmountIsByMint: false,
                    ammPlugin: utilities.voidEthereumAddress,
                    liquidityPoolAddresses: [],
                    swapPath: [],
                    receivers: [accounts[1]],
                    receiversPercentages: [],
                    enterInETH: false,
                    exitInETH: false
                }]
            }];
            await fixedInflation.methods.init(
                fixedInflationExtension.options.address,
                fixedInflationExtension.methods.init(dfo.doubleProxyAddress).encodeABI(),
                newEntries[0],
                newEntries.map(it => it.operations)[0]
            ).send(blockchainConnection.getSendingOptions());
            assert(false);
        } catch (e) {
            console.error(e);
            assert.notStrictEqual((e.message || e).toLowerCase().indexOf("already init"), -1);
        }
    });

    it("Transfer Eth to a wallet", async() => {
        var earnByInput = false;
        var entry = await fixedInflation.methods.entry().call();
        var operation = entry[1][0];
        var amount = operation.inputTokenAmount;
        entry = entry[0];
        var receivers = operation.receivers;

        var treasuryAddress = (await fixedInflationExtension.methods.data().call())[1] === dfo.doubleProxyAddress ? dfo.mvdWalletAddress : fixedInflationExtension.options.address;

        var treasuryBalanceExpected = web3.utils.toBN(await web3.eth.getBalance(treasuryAddress)).sub(web3.utils.toBN(operation.inputTokenAmount)).toString();

        var callerPercentage = await calculateTokenPercentage(operation.inputTokenAddress, operation.inputTokenAmount, operation.inputTokenAmountIsPercentage, entry.callerRewardPercentage);

        var availableAmount = web3.utils.toBN(operation.inputTokenAmount).sub(web3.utils.toBN(callerPercentage)).toString();

        var feePercentageInfo = await fixedInflationFactory.methods.feePercentageInfo().call();

        var dfoPercentage = await calculateTokenPercentage(operation.inputTokenAddress, availableAmount, false, feePercentageInfo[0]);
        var dfoBalanceExpected = web3.utils.toBN(await web3.eth.getBalance(feePercentageInfo[1])).add(web3.utils.toBN(dfoPercentage)).toString();

        if (treasuryAddress === dfo.mvdWalletAddress) {
            dfoBalanceExpected = web3.utils.toBN(dfoBalanceExpected).sub(web3.utils.toBN(operation.inputTokenAmount)).toString();
        }

        availableAmount = web3.utils.toBN(availableAmount).sub(web3.utils.toBN(dfoPercentage)).toString();
        var totalAbailableAmount = availableAmount;
        var balanceOfExpected = await web3.eth.getBalance(accounts[0]);
        balanceOfExpected = web3.utils.toBN(balanceOfExpected).add(web3.utils.toBN(callerPercentage)).toString();

        var receiversBefore = [];

        for (var i in receivers) {
            if (i = parseInt(i) === receivers.length - 1) {
                continue;
            }
            var receiver = receivers[i];
            var receiverPercentage = await calculatePercentage(operation.inputTokenAddress, totalAbailableAmount, false, operation.receiversPercentages[i])
            availableAmount = web3.utils.toBN(availableAmount).sub(web3.utils.toBN(receiverPercentage)).toString();
            receiversBefore.push(web3.utils.toBN(await web3.eth.getBalance(receiver)).add(web3.utils.toBN(receiverPercentage)));
        }
        receiversBefore.push(web3.utils.toBN(await web3.eth.getBalance(receivers[receiversBefore.length])).add(web3.utils.toBN(availableAmount)));

        console.log(receivers, treasuryAddress);

        var transactionResult = await fixedInflation.methods.execute(earnByInput || false).send(blockchainConnection.getSendingOptions(availableAmount));
        transactionResult = await web3.eth.getTransactionReceipt(transactionResult.transactionHash);
        var Executed = web3.eth.abi.decodeParameter("bool", transactionResult.logs.filter(it => it.topics[0] === web3.utils.sha3('Executed(bool)'))[0].data);
        console.log({ Executed });
        var transactionFee = await blockchainConnection.calculateTransactionFee(transactionResult);

        balanceOfExpected = web3.utils.toBN(balanceOfExpected).sub(web3.utils.toBN(await blockchainConnection.calculateTransactionFee(transactionResult))).toString();

        balanceOfExpected = utilities.fromDecimals(balanceOfExpected, 18);

        var balanceOfAfter = await web3.eth.getBalance(accounts[0]);
        balanceOfAfter = utilities.fromDecimals(balanceOfAfter, 18);

        await nothingInContracts(fixedInflation.options.address);

        assert.strictEqual(balanceOfAfter, balanceOfExpected);

        var dfoBalanceAfter = await web3.eth.getBalance(feePercentageInfo[1]);
        dfoBalanceExpected = utilities.fromDecimals(dfoBalanceExpected, 18);
        dfoBalanceAfter = utilities.fromDecimals(dfoBalanceAfter, 18);

        assert.strictEqual(dfoBalanceAfter, dfoBalanceExpected);

        for (var i in receiversBefore) {
            var receiver = receivers[i];
            var receiverAfter = await web3.eth.getBalance(receiver);
            receiversBefore[i] = utilities.fromDecimals(receiversBefore[i], 18);
            receiverAfter = utilities.fromDecimals(receiverAfter, 18);
            console.log(receiverAfter, receiversBefore[i]);
            assert.strictEqual(receiverAfter, receiversBefore[i]);
        }

        var treasuryBalanceAfter = await web3.eth.getBalance(treasuryAddress);
        treasuryBalanceAfter = utilities.fromDecimals(treasuryBalanceAfter, 18);

        treasuryBalanceExpected = utilities.fromDecimals(treasuryBalanceExpected, 18);

        treasuryAddress !== dfo.mvdWalletAddress && assert.strictEqual(treasuryBalanceAfter, treasuryBalanceExpected);

    });

    it("Cannot be possible to call an already-called fixedInflation", async() => {
        try {
            await fixedInflation.methods.execute(false).send(blockchainConnection.getSendingOptions());
            assert(false);
        } catch (e) {
            assert.notStrictEqual((e.message || e).toLowerCase().indexOf("too early to execute"), -1);
        }
    });

    it("Recall the same after past time", async() => {
        var earnByInput = false;
        var entry = await fixedInflation.methods.entry().call();
        var operation = entry[1][0];
        entry = entry[0];
        var receiver = accounts[0];

        await blockchainConnection.fastForward(entry.blockInterval);

        var balanceOfExpected = await web3.eth.getBalance(receiver);
        balanceOfExpected = web3.utils.toBN(balanceOfExpected).add(web3.utils.toBN(await calculateTokenPercentage(operation.inputTokenAddress, operation.inputTokenAmount, operation.inputTokenAmountIsPercentage, entry.callerRewardPercentage))).toString();

        var transactionResult = await fixedInflation.methods.execute(earnByInput).send(blockchainConnection.getSendingOptions());
        transactionResult = await web3.eth.getTransactionReceipt(transactionResult.transactionHash);
        var Executed = web3.eth.abi.decodeParameter("bool", transactionResult.logs.filter(it => it.topics[0] === web3.utils.sha3('Executed(bool)'))[0].data);
        console.log({ Executed });
        assert(Executed);

        balanceOfExpected = web3.utils.toBN(balanceOfExpected).sub(web3.utils.toBN(await blockchainConnection.calculateTransactionFee(transactionResult))).toString();

        balanceOfExpected = utilities.fromDecimals(balanceOfExpected, 18);

        var balanceOfAfter = await web3.eth.getBalance(receiver);
        balanceOfAfter = utilities.fromDecimals(balanceOfAfter, 18);

        assert.strictEqual(balanceOfAfter, balanceOfExpected);

        await nothingInContracts(fixedInflation.options.address);

    });

    async function generateOperations(amm) {
        if(!amm) {
            return [
                ...(await generateOperations(uniswapAMMV2)),
                ...(await generateOperations(uniswapAMM))
            ];
        }
        var tokenAddress = amm === uniswapAMMV2 ? knowledgeBase.buidlTokenAddress : knowledgeBase.osTokenAddress;
        return [{
            inputTokenAddress: utilities.voidEthereumAddress,
            inputTokenAmount: utilities.toDecimals("0.02", "18"),
            inputTokenAmountIsPercentage: false,
            inputTokenAmountIsByMint: false,
            ammPlugin: utilities.voidEthereumAddress,
            liquidityPoolAddresses: [],
            swapPath: [],
            receivers: [accounts[1]],
            receiversPercentages: [],
            enterInETH: false,
            exitInETH: false
        }, {
            inputTokenAddress: dfo.votingTokenAddress,
            inputTokenAmount: utilities.toDecimals("0.01", "18"),
            inputTokenAmountIsPercentage: false,
            inputTokenAmountIsByMint: (await fixedInflationExtension.methods.data().call())[1] === dfo.doubleProxyAddress,
            ammPlugin: utilities.voidEthereumAddress,
            liquidityPoolAddresses: [],
            swapPath: [],
            receivers: [accounts[1]],
            receiversPercentages: [],
            enterInETH: false,
            exitInETH: false
        }, {
            inputTokenAddress: dfo.votingTokenAddress,
            inputTokenAmount: 100,
            inputTokenAmountIsPercentage: (await fixedInflationExtension.methods.data().call())[1] === dfo.doubleProxyAddress,
            inputTokenAmountIsByMint: (await fixedInflationExtension.methods.data().call())[1] === dfo.doubleProxyAddress,
            ammPlugin: utilities.voidEthereumAddress,
            liquidityPoolAddresses: [],
            swapPath: [],
            receivers: [accounts[1]],
            receiversPercentages: [],
            enterInETH: false,
            exitInETH: false
        }, {
            inputTokenAddress: knowledgeBase.wethTokenAddress,
            inputTokenAmount: utilities.toDecimals("0.15", "18"),
            inputTokenAmountIsPercentage: false,
            inputTokenAmountIsByMint: false,
            ammPlugin: amm === uniswapAMM ? knowledgeBase.swapRouterAddress : amm.options.address,
            liquidityPoolAddresses: [
                (await amm.methods.byTokens([knowledgeBase.wethTokenAddress, tokenAddress]).call())[2]
            ],
            swapPath: [
                tokenAddress
            ],
            receivers: [accounts[1]],
            receiversPercentages: [],
            enterInETH: true,
            exitInETH: false
        }, {
            inputTokenAddress: knowledgeBase.wethTokenAddress,
            inputTokenAmount: utilities.toDecimals("0.01", "18"),
            inputTokenAmountIsPercentage: false,
            inputTokenAmountIsByMint: false,
            ammPlugin: amm === uniswapAMM ? knowledgeBase.swapRouterAddress : amm.options.address,
            liquidityPoolAddresses: [
                (await amm.methods.byTokens([knowledgeBase.wethTokenAddress, tokenAddress]).call())[2]
            ],
            swapPath: [
                tokenAddress
            ],
            receivers: [accounts[1]],
            receiversPercentages: [],
            enterInETH: false,
            exitInETH: false
        }, {
            inputTokenAddress: tokenAddress,
            inputTokenAmount: utilities.toDecimals("88", "18"),
            inputTokenAmountIsPercentage: false,
            inputTokenAmountIsByMint: false,
            ammPlugin: amm === uniswapAMM ? knowledgeBase.swapRouterAddress : amm.options.address,
            liquidityPoolAddresses: [
                (await amm.methods.byTokens([knowledgeBase.wethTokenAddress, tokenAddress]).call())[2]
            ],
            swapPath: [
                knowledgeBase.wethTokenAddress
            ],
            receivers: ["0x5D40c724ba3e7Ffa6a91db223368977C522BdACD", "0x32c87193C2cC9961F2283FcA3ca11A483d8E426B", "0x25756f9C2cCeaCd787260b001F224159aB9fB97A"],
            receiversPercentages: ["220000000000000000", "50000000000000000"],
            enterInETH: false,
            exitInETH: true
        }, {
            inputTokenAddress: tokenAddress,
            inputTokenAmount: utilities.toDecimals("12", "18"),
            inputTokenAmountIsPercentage: false,
            inputTokenAmountIsByMint: false,
            ammPlugin: amm === uniswapAMM ? knowledgeBase.swapRouterAddress : amm.options.address,
            liquidityPoolAddresses: [
                (await amm.methods.byTokens([knowledgeBase.wethTokenAddress, tokenAddress]).call())[2],
            ],
            swapPath: [
                knowledgeBase.wethTokenAddress
            ],
            receivers: [accounts[1]],
            receiversPercentages: [],
            enterInETH: false,
            exitInETH: false
        }, {
            inputTokenAddress: tokenAddress,
            inputTokenAmount: utilities.toDecimals("12", "18"),
            inputTokenAmountIsPercentage: false,
            inputTokenAmountIsByMint: false,
            ammPlugin: amm === uniswapAMM ? knowledgeBase.swapRouterAddress : amm.options.address,
            liquidityPoolAddresses: [
                (await amm.methods.byTokens([knowledgeBase.wethTokenAddress, tokenAddress]).call())[2],
                (await amm.methods.byTokens([knowledgeBase.wethTokenAddress, knowledgeBase.daiTokenAddress]).call())[2]
            ],
            swapPath: [
                knowledgeBase.wethTokenAddress,
                knowledgeBase.daiTokenAddress
            ],
            receivers: [accounts[1]],
            receiversPercentages: [],
            enterInETH: false,
            exitInETH: false
        }, {
            inputTokenAddress: knowledgeBase.wethTokenAddress,
            inputTokenAmount: utilities.toDecimals("0.72", "18"),
            inputTokenAmountIsPercentage: false,
            inputTokenAmountIsByMint: false,
            ammPlugin: amm === uniswapAMM ? knowledgeBase.swapRouterAddress : amm.options.address,
            liquidityPoolAddresses: amm === uniswapAMM ? [
                (await amm.methods.byTokens([knowledgeBase.wethTokenAddress, tokenAddress]).call())[2],
                (await amm.methods.byTokens([knowledgeBase.wethTokenAddress, tokenAddress]).call())[2]
            ] : [
                (await amm.methods.byTokens([knowledgeBase.wethTokenAddress, tokenAddress]).call())[2]
            ],
            swapPath: amm === uniswapAMM ? [
                tokenAddress,
                knowledgeBase.wethTokenAddress
            ] : [
                tokenAddress
            ],
            receivers: [accounts[1]],
            receiversPercentages: [],
            enterInETH: true,
            exitInETH: false
        }, {
            inputTokenAddress: knowledgeBase.wethTokenAddress,
            inputTokenAmount: utilities.toDecimals("0.19", "18"),
            inputTokenAmountIsPercentage: false,
            inputTokenAmountIsByMint: false,
            ammPlugin: amm === uniswapAMM ? knowledgeBase.swapRouterAddress : amm.options.address,
            liquidityPoolAddresses: amm === uniswapAMM ? [
                (await amm.methods.byTokens([knowledgeBase.wethTokenAddress, tokenAddress]).call())[2],
                (await amm.methods.byTokens([knowledgeBase.wethTokenAddress, tokenAddress]).call())[2]
            ] : [
                (await amm.methods.byTokens([knowledgeBase.wethTokenAddress, tokenAddress]).call())[2]
            ],
            swapPath: amm === uniswapAMM ? [
                tokenAddress,
                knowledgeBase.wethTokenAddress
            ] : [
                tokenAddress
            ],
            receivers: [accounts[1]],
            receiversPercentages: [],
            enterInETH: false,
            exitInETH: amm === uniswapAMM
        }, {
            inputTokenAddress: knowledgeBase.wethTokenAddress,
            inputTokenAmount: utilities.toDecimals("0.03", "18"),
            inputTokenAmountIsPercentage: false,
            inputTokenAmountIsByMint: false,
            ammPlugin: amm === uniswapAMM ? knowledgeBase.swapRouterAddress : amm.options.address,
            liquidityPoolAddresses: amm === uniswapAMM ? [
                (await amm.methods.byTokens([knowledgeBase.wethTokenAddress, tokenAddress]).call())[2],
                (await amm.methods.byTokens([knowledgeBase.wethTokenAddress, tokenAddress]).call())[2]
            ] : [
                (await amm.methods.byTokens([knowledgeBase.wethTokenAddress, tokenAddress]).call())[2]
            ],
            swapPath: amm === uniswapAMM ? [
                tokenAddress,
                knowledgeBase.wethTokenAddress
            ] : [
                tokenAddress
            ],
            receivers: [accounts[1]],
            receiversPercentages: [],
            enterInETH: true,
            exitInETH: amm === uniswapAMM
        }, {
            inputTokenAddress: tokenAddress,
            inputTokenAmount: utilities.toDecimals("12", "18"),
            inputTokenAmountIsPercentage: false,
            inputTokenAmountIsByMint: tokenAddress === knowledgeBase.osTokenAddress,
            ammPlugin: amm === uniswapAMM ? knowledgeBase.swapRouterAddress : amm.options.address,
            liquidityPoolAddresses: [
                (await amm.methods.byTokens([knowledgeBase.wethTokenAddress, tokenAddress]).call())[2],
                (await amm.methods.byTokens([knowledgeBase.wethTokenAddress, knowledgeBase.daiTokenAddress]).call())[2]
            ],
            swapPath: [
                knowledgeBase.wethTokenAddress,
                knowledgeBase.daiTokenAddress
            ],
            receivers: [accounts[1]],
            receiversPercentages: [],
            enterInETH: false,
            exitInETH: false
        }, {
            inputTokenAddress: tokenAddress,
            inputTokenAmount: utilities.toDecimals("12", "18"),
            inputTokenAmountIsPercentage: false,
            inputTokenAmountIsByMint: tokenAddress === knowledgeBase.osTokenAddress,
            ammPlugin: amm === uniswapAMM ? knowledgeBase.swapRouterAddress : amm.options.address,
            liquidityPoolAddresses: [
                (await amm.methods.byTokens([knowledgeBase.wethTokenAddress, tokenAddress]).call())[2],
            ],
            swapPath: [
                knowledgeBase.wethTokenAddress
            ],
            receivers: [accounts[1]],
            receiversPercentages: [],
            enterInETH: false,
            exitInETH: true
        }, {
            inputTokenAddress: tokenAddress,
            inputTokenAmount: utilities.toDecimals("12", "18"),
            inputTokenAmountIsPercentage: false,
            inputTokenAmountIsByMint: tokenAddress === knowledgeBase.osTokenAddress,
            ammPlugin: amm === uniswapAMM ? knowledgeBase.swapRouterAddress : amm.options.address,
            liquidityPoolAddresses: [
                (await amm.methods.byTokens([knowledgeBase.wethTokenAddress, tokenAddress]).call())[2],
            ],
            swapPath: [
                knowledgeBase.wethTokenAddress
            ],
            receivers: [accounts[1]],
            receiversPercentages: [],
            enterInETH: false,
            exitInETH: false
        }, {
            inputTokenAddress: knowledgeBase.wethTokenAddress,
            inputTokenAmount: utilities.toDecimals("0.005", "18"),
            inputTokenAmountIsPercentage: false,
            inputTokenAmountIsByMint: false,
            ammPlugin: amm === uniswapAMM ? knowledgeBase.swapRouterAddress : amm.options.address,
            liquidityPoolAddresses: [
                (await amm.methods.byTokens([knowledgeBase.wethTokenAddress, tokenAddress]).call())[2],
            ],
            swapPath: [
                tokenAddress
            ],
            receivers: [utilities.voidEthereumAddress],
            receiversPercentages: [],
            enterInETH: true,
            exitInETH: false
        }, {
            inputTokenAddress: tokenAddress,
            inputTokenAmount: utilities.toDecimals("12", "18"),
            inputTokenAmountIsPercentage: false,
            inputTokenAmountIsByMint: tokenAddress === knowledgeBase.osTokenAddress,
            ammPlugin: utilities.voidEthereumAddress,
            liquidityPoolAddresses: [
            ],
            swapPath: [
            ],
            receivers: [utilities.voidEthereumAddress],
            receiversPercentages: [],
            enterInETH: false,
            exitInETH: false
        }]
    }

    async function setNewSwapEntries() {
        if(global.setNewSwapEntriesDone) {
            return;
        }
        global.setNewSwapEntriesDone = true;
        var newEntries = [{
            lastBlock: 0,
            name: "New Cataldo",
            blockInterval: 10,
            callerRewardPercentage: utilities.toDecimals("0.02", "18"),
            operations: await generateOperations()
        }];

        var entryCode = `FixedInflationEntry("${newEntries[0].name}", ${newEntries[0].blockInterval}, ${newEntries[0].lastBlock || 0}, ${newEntries[0].callerRewardPercentage})`;
        var operations = "";
        var functions = "";

        for (var i in newEntries) {
            var entry = newEntries[i];
            var operationSetsIndex = `operationSets_${i}`;
            var line = "";
            for (var j in entry.operations) {
                var operation = entry.operations[j];
                line += `\n        operationSets[${j}] = _${operationSetsIndex}_${j}();`
            }
            operations += "        " + line + "\n";
        }
        for (var i in newEntries) {
            for (var j in newEntries[i].operations) {
                var operation = newEntries[i].operations[j];
                var line = `    function _operationSets_${i}_${j}() private view returns(FixedInflationOperation memory) {`
                line += `\n        address[] memory liquidityPoolAddresses_${i}_${j} = new address[](${operation.liquidityPoolAddresses.length});`
                for (var z in operation.liquidityPoolAddresses) {
                    line += `\n        liquidityPoolAddresses_${i}_${j}[${z}] = ${web3.utils.toChecksumAddress(operation.liquidityPoolAddresses[z])};`;
                }
                line += `\n        address[] memory swapPath_${i}_${j} = new address[](${operation.swapPath.length});`
                for (var z in operation.swapPath) {
                    line += `\n        swapPath_${i}_${j}[${z}] = ${web3.utils.toChecksumAddress(operation.swapPath[z])};`;
                }
                line += `\n        address[] memory receivers_${i}_${j} = new address[](${operation.receivers.length});`
                for (var z in operation.receivers) {
                    line += `\n        receivers_${i}_${j}[${z}] = ${web3.utils.toChecksumAddress(operation.receivers[z])};`;
                }
                line += `\n        uint256[] memory receiversPercentages_${i}_${j} = new uint256[](${operation.receiversPercentages.length});`
                for (var z in operation.receiversPercentages) {
                    line += `\n       receiversPercentages_${i}_${j}[${z}] = ${operation.receiversPercentages[z]};`;
                }
                line += `\n        return FixedInflationOperation(${web3.utils.toChecksumAddress(operation.inputTokenAddress)}, ${operation.inputTokenAmount}, ${operation.inputTokenAmountIsPercentage}, ${operation.inputTokenAmountIsByMint}, ${operation.ammPlugin}, liquidityPoolAddresses_${i}_${j}, swapPath_${i}_${j}, ${operation.enterInETH}, ${operation.exitInETH}, receivers_${i}_${j}, receiversPercentages_${i}_${j});`
                functions += line + "\n    }\n\n";
            }
        }

        var code = fs.readFileSync(path.resolve(__dirname, '..', 'resources/FixedInflationSetEntry.sol'), 'UTF-8').format(fixedInflationExtension.options.address, entryCode.trim(), newEntries[0].operations.length, operations.trim(), functions.trim());

        console.log(code);

        var treasuryAddress = (await fixedInflationExtension.methods.data().call())[1];

        if (treasuryAddress === dfo.doubleProxyAddress) {
            await dfoManager.finalizeProposal(dfo, await dfoManager.createProposal(dfo, "", true, code, "callOneTime(address)"));
        } else {
            await fixedInflationExtension.methods.setEntry(newEntries[0], newEntries.map(it => it.operations)[0]).send(blockchainConnection.getSendingOptions());
        }
        assert.strictEqual((await fixedInflation.methods.entry().call())[0].name, newEntries[0].name);

        console.log(JSON.stringify((await fixedInflation.methods.entry().call())[1]));
    }

    it("Set new swap entries", setNewSwapEntries);

    it("New entry", async() => {
        await setNewSwapEntries();
        var osBalance = await tokens[tokens.length - 1].methods.totalSupply().call();
        var expectedOSBalance = osBalance.add(utilities.toDecimals("12", "18").mul(2));

        var earnByInput = false;
        var entry = await fixedInflation.methods.entry().call();
        var operations = entry[1];
        entry = entry[0];
        var receiver = accounts[0];

        //await blockchainConnection.fastForward(entry.blockInterval);

        /*var balanceOfExpected = await web3.eth.getBalance(receiver);
        balanceOfExpected = web3.utils.toBN(balanceOfExpected).add(web3.utils.toBN(await calculateTokenPercentage(operation.inputTokenAddress, operation.inputTokenAmount, operation.inputTokenAmountIsPercentage, entry.callerRewardPercentage))).toString();
*/
        var ethBalance = await web3.eth.getBalance(fixedInflation.options.address);

        var transactionResult = await fixedInflation.methods.execute(earnByInput).send(blockchainConnection.getSendingOptions());
        transactionResult = await web3.eth.getTransactionReceipt(transactionResult.transactionHash);
        var Executed = web3.eth.abi.decodeParameter("bool", transactionResult.logs.filter(it => it.topics[0] === web3.utils.sha3('Executed(bool)'))[0].data);
        console.log({ Executed });
        assert(Executed);

        osBalance = await tokens[tokens.length - 1].methods.totalSupply().call();

        assert.equal(ethBalance, await web3.eth.getBalance(fixedInflation.options.address));

        /*balanceOfExpected = web3.utils.toBN(balanceOfExpected).sub(web3.utils.toBN(await blockchainConnection.calculateTransactionFee(transactionResult))).toString();

        balanceOfExpected = utilities.fromDecimals(balanceOfExpected, 18);

        var balanceOfAfter = await web3.eth.getBalance(receiver);
        balanceOfAfter = utilities.fromDecimals(balanceOfAfter, 18);

        assert.strictEqual(balanceOfAfter, balanceOfExpected);*/

        await nothingInContracts(fixedInflation.options.address);
    });

    async function calculateMinAmounts(operations, multiplier) {
        var outputAmounts = operations.map(() => '0');
        var minAmounts = operations.map(() => '0');
        var Quoter = await compile('util/uniswapV3/IQuoter');
        var UniswapV3Pool = await compile('util/uniswapV3/IUniswapV3Pool');
        var quoter = new web3.eth.Contract(Quoter.abi, knowledgeBase.uniswapV3QuoterAddress);
        for(var i in operations) {
            var operation = operations[i];
            if(operation.liquidityPoolAddresses.length === 0) {
                continue;
            }
            var outputAmount = '0';
            try {
                var path = operation.inputTokenAddress;
                for(var z = 0; z < operation.swapPath.length; z++) {
                    var fee = await (new web3.eth.Contract(UniswapV3Pool.abi, operation.liquidityPoolAddresses[z])).methods.fee().call();
                    fee = web3.utils.toHex(fee).substring(2);
                    while(fee.length < 6) {
                        fee = '0' + fee;
                    }
                    path += fee;
                    path += operation.swapPath[z].substring(2);
                }
                var amountIn = operation.inputTokenAmount;
                outputAmount = await quoter.methods.quoteExactInput(path, amountIn).call();
            } catch(e) {
            }
            outputAmounts[i] = outputAmount;0
            minAmounts[i] = utilities.numberToString(parseInt(outputAmount) * multiplier).split('.')[0]
        }
        return { outputAmounts, minAmounts };
    }

    it("Execute with min Amounts", async() => {
        await setNewSwapEntries();
        var osBalance = await tokens[tokens.length - 1].methods.totalSupply().call();
        var expectedOSBalance = osBalance.add(utilities.toDecimals("12", "18").mul(3));

        var earnByInput = false;
        var entry = await fixedInflation.methods.entry().call();
        var operations = entry[1];
        entry = entry[0];
        var receiver = accounts[0];

        await blockchainConnection.fastForward(entry.blockInterval);

        var ethBalance = await web3.eth.getBalance(fixedInflation.options.address);

        var slippage = 99.9999999999999;

        var conversion = slippage / 100;
        conversion = 1 - conversion;

        var { outputAmounts, minAmounts } = await calculateMinAmounts(operations, conversion);

        console.log({ outputAmounts, minAmounts });

        var transactionResult = await fixedInflation.methods.executeWithMinAmounts(earnByInput, minAmounts).send(blockchainConnection.getSendingOptions());
        transactionResult = await web3.eth.getTransactionReceipt(transactionResult.transactionHash);

        var txOutputAmounts = await transactionDebugger.debugTransaction(transactionResult.transactionHash);
        txOutputAmounts = web3.eth.abi.decodeParameters(["bool", "uint256[]"], txOutputAmounts.result);
        txOutputAmounts = txOutputAmounts[1];

        console.log({ outputAmounts, minAmounts, txOutputAmounts });

        var Executed = web3.eth.abi.decodeParameter("bool", transactionResult.logs.filter(it => it.topics[0] === web3.utils.sha3('Executed(bool)'))[0].data);
        console.log({ Executed });
        assert(Executed);

        var calculateRewardPercentage = function calculateRewardPercentage(totalAmount, rewardPercentage) {
            return totalAmount.mul(rewardPercentage.mul(1e18).div(1e18)).div(1e18);
        }

        var remainingAmount = txOutputAmounts[txOutputAmounts.length - 2];

        if(!earnByInput && entry.callerRewardPercentage != '0') {
            var callerRewardPercentage = entry.callerRewardPercentage;
            var number = calculateRewardPercentage(remainingAmount, callerRewardPercentage);
            remainingAmount = remainingAmount.sub(number);
        }

        var rewardPercentage = "100000000000000000";
        var number = calculateRewardPercentage(remainingAmount, rewardPercentage);
        remainingAmount = remainingAmount.sub(number);
        expectedOSBalance = expectedOSBalance.sub(remainingAmount);

        remainingAmount = txOutputAmounts[txOutputAmounts.length - 1];

        if(!earnByInput && entry.callerRewardPercentage != '0') {
            var callerRewardPercentage = entry.callerRewardPercentage;
            var number = calculateRewardPercentage(remainingAmount, callerRewardPercentage);
            remainingAmount = remainingAmount.sub(number);
            expectedOSBalance = expectedOSBalance.add(number);
        }

        number = calculateRewardPercentage(remainingAmount, rewardPercentage);
        expectedOSBalance = expectedOSBalance.add(number);

        osBalance = await tokens[tokens.length - 1].methods.totalSupply().call();

        assert.equal(expectedOSBalance, osBalance);

        assert.equal(ethBalance, await web3.eth.getBalance(fixedInflation.options.address));

        await nothingInContracts(fixedInflation.options.address);
    });
});
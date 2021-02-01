var assert = require("assert");
var utilities = require("../util/utilities");
var context = require("../util/context.json");
var compile = require("../util/compile");
var blockchainConnection = require("../util/blockchainConnection");
var dfoManager = require('../util/dfo');
var ethers = require('ethers');
var abi = new ethers.utils.AbiCoder();
var path = require('path');
var fs = require('fs');

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
var uniswapAMM;

var FixedInflationFactory;
var fixedInflationFactory;

var FixedInflationExtension;
var fixedInflationExtension;

var FixedInflation;
var fixedInflation;

var liquidityPool;

var tokens;

var actors = {};

describe("FixedInflation", () => {

    before(async () => {

        await blockchainConnection.init;

        FixedInflationFactory = await compile('fixed-inflation/FixedInflationFactory');
        FixedInflationExtension = await compile('fixed-inflation/DFOBasedFixedInflationExtension');
        FixedInflationDefaultExtension = await compile('fixed-inflation/FixedInflationExtension');
        FixedInflation = await compile('fixed-inflation/FixedInflation');

        ethItemOrchestrator = new web3.eth.Contract(context.ethItemOrchestratorABI, context.ethItemOrchestratorAddress);
        uniswapV2Router = new web3.eth.Contract(context.uniswapV2RouterABI, context.uniswapV2RouterAddress);
        uniswapV2Factory = new web3.eth.Contract(context.uniswapV2FactoryABI, context.uniswapV2FactoryAddress);

        UniswapV2AMMV1 = await compile('amm-aggregator/models/UniswapV2/1/UniswapV2AMMV1');
        uniswapAMM = await new web3.eth.Contract(UniswapV2AMMV1.abi).deploy({data : UniswapV2AMMV1.bin, arguments: [uniswapV2Router.options.address]}).send(blockchainConnection.getSendingOptions());

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
        if(tokenAddress == utilities.voidEthereumAddress || amountIsPercentage) {
            return tokenAmount;
        }
        var token = new web3.eth.Contract(context.IERC20ABI, tokenAddress);
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
            toBlock : 'latest',
            address : fixedInflation.options.address,
            topics : [
                web3.utils.sha3('Entry(bytes32)')
            ]
        });
        for(var log of logs) {
            entries.push(await fixedInflation.methods.entry(log.topics[1]).call());
        }
        entries = entries.map(it => {
            var entry = {
                operations : it[1]
            };
            Object.entries(it[0]).forEach(original => entry[original[0]] = original[1]);
            return entry;
        });
        return entries.filter(it => it.id !== utilities.voidBytes32);
    }

    it("Deploy DFO and factory", async () => {

        dfo = await dfoManager.createDFO("MyName", "MySymbol", 1000000, 100, 10);

        await web3.eth.sendTransaction(blockchainConnection.getSendingOptions({
            to: dfo.mvdWalletAddress,
            value : utilities.toDecimals(30, 18)
        }));

        for(var token of tokens) {
            await token.methods.transfer(dfo.mvdWalletAddress, await token.methods.balanceOf(accounts[0]).call()).send(blockchainConnection.getSendingOptions());
        }

        await dfo.votingToken.methods.transfer(dfo.mvdWalletAddress, utilities.toDecimals(300000, await dfo.votingToken.methods.decimals().call())).send(blockchainConnection.getSendingOptions());

        var fixedInflationModel = await new web3.eth.Contract(FixedInflation.abi).deploy({data : FixedInflation.bin}).send(blockchainConnection.getSendingOptions());

        var fixedInflationDefaultExtensionModel = await new web3.eth.Contract(FixedInflationDefaultExtension.abi).deploy({data : FixedInflationDefaultExtension.bin}).send(blockchainConnection.getSendingOptions());

        fixedInflationFactory = await new web3.eth.Contract(FixedInflationFactory.abi).deploy({data : FixedInflationFactory.bin, arguments : [
            dfo.doubleProxyAddress,
            fixedInflationModel.options.address,
            fixedInflationDefaultExtensionModel.options.address,
            150
        ]}).send(blockchainConnection.getSendingOptions());

    });

    it("Deploy all occurrency stuff", async () => {

        fixedInflationExtension = await new web3.eth.Contract(FixedInflationExtension.abi).deploy({data : FixedInflationExtension.bin}).send(blockchainConnection.getSendingOptions());

        var code = fs.readFileSync(path.resolve(__dirname, '..', 'contracts/fixed-inflation/dfo/ManageFixedInflationFunctionality.sol'), 'UTF-8').format(fixedInflationExtension.options.address);
        var proposal = await dfoManager.createProposal(dfo, "manageFixedInflation", true, code, "manageFixedInflation(address,uint256,address[],uint256[],uint256[],address)", false, true);
        await dfoManager.finalizeProposal(dfo, proposal);

        var newEntries = [{
            id : web3.utils.sha3('0'),
            lastBlock : 0,
            name : "Cataldo",
            blockInterval : 10,
            callerRewardPercentage : 100,
            operations : [{
                inputTokenAddress : utilities.voidEthereumAddress,
                inputTokenAmount : utilities.toDecimals("0.01", "18"),
                inputTokenAmountIsPercentage : false,
                inputTokenAmountIsByMint : false,
                ammPlugin : utilities.voidEthereumAddress,
                liquidityPoolAddresses : [],
                swapPath : [],
                receivers : [accounts[1]],
                receiversPercentages : [],
                enterInETH : false,
                exitInETH : false
            }]
        }];

        var data = new web3.eth.Contract(FixedInflation.abi).methods.init(
            fixedInflationExtension.options.address,
            fixedInflationExtension.methods.init(dfo.doubleProxyAddress).encodeABI(),
            newEntries,
            newEntries.map(it => it.operations)
        ).encodeABI();

        var result = await fixedInflationFactory.methods.deploy(data).send(blockchainConnection.getSendingOptions());
        result = await web3.eth.getTransactionReceipt(result.transactionHash);

        var fixedInflationAddress = web3.eth.abi.decodeParameter("address", result.logs.filter(it => it.topics[0] === web3.utils.sha3('FixedInflationDeployed(address,address,bytes)'))[0].topics[1]);

        fixedInflation = new web3.eth.Contract(FixedInflation.abi, fixedInflationAddress);

        assert.strictEqual(fixedInflationFactory.options.address, await fixedInflation.methods._factory().call());
    });

    it("Cannot re-initialize already initialized contracts", async () => {
        try {
            await fixedInflationExtension.methods.init(dfo.doubleProxyAddress).send(blockchainConnection.getSendingOptions());
            assert(false);
        } catch(e) {
            assert.notStrictEqual((e.message || e).toLowerCase().indexOf("already init"), -1);
        }
        try {
            var newEntries = [{
                id : web3.utils.sha3('0'),
                lastBlock : 0,
                name : "Cataldo",
                blockInterval : 10,
                callerRewardPercentage : 100,
                operations : [{
                    inputTokenAddress : utilities.voidEthereumAddress,
                    inputTokenAmount : utilities.toDecimals("0.01", "18"),
                    inputTokenAmountIsPercentage : false,
                    inputTokenAmountIsByMint : false,
                    ammPlugin : utilities.voidEthereumAddress,
                    liquidityPoolAddresses : [],
                    swapPath : [],
                    receivers : [accounts[1]],
                    receiversPercentages : [],
                    enterInETH : false,
                    exitInETH : false
                }]
            }];
            await fixedInflation.methods.init(
                fixedInflationExtension.options.address,
                fixedInflationExtension.methods.init(dfo.doubleProxyAddress).encodeABI(),
                newEntries,
                newEntries.map(it => it.operations)
            ).send(blockchainConnection.getSendingOptions());
            assert(false);
        } catch(e) {
            console.error(e);
            assert.notStrictEqual((e.message || e).toLowerCase().indexOf("already init"), -1);
        }
    });

    it("Transfer Eth to a wallet", async () => {
        var entries = await getEntries();
        var entryIndex = 0;
        var earnByInput = false;
        var entry = entries[entryIndex];
        var operation = entry.operations[0];
        var receiver = accounts[0];

        var balanceOfExpected = await web3.eth.getBalance(receiver);
        balanceOfExpected = web3.utils.toBN(balanceOfExpected).add(web3.utils.toBN(await calculateTokenPercentage(operation.inputTokenAddress, operation.inputTokenAmount, operation.inputTokenAmountIsPercentage, entry.callerRewardPercentage))).toString();

        var transactionResult = await fixedInflation.methods.execute([entry.id], [earnByInput || false]).send(blockchainConnection.getSendingOptions());

        balanceOfExpected = web3.utils.toBN(balanceOfExpected).sub(web3.utils.toBN(await blockchainConnection.calculateTransactionFee(transactionResult))).toString();

        balanceOfExpected = utilities.fromDecimals(balanceOfExpected, 18);

        var balanceOfAfter = await web3.eth.getBalance(receiver);
        balanceOfAfter = utilities.fromDecimals(balanceOfAfter, 18);

        assert.strictEqual(balanceOfAfter, balanceOfExpected);
    });

    it("Cannot be possible to call an already-called fixedInflation", async () => {
        try {
            await fixedInflation.methods.execute([(await getEntries())[0].id], [false]).send(blockchainConnection.getSendingOptions());
            assert(false);
        } catch(e) {
            assert.notStrictEqual((e.message || e).toLowerCase().indexOf("too early to call index"), -1);
        }
    });

    it("Recall the same after past time", async () => {
        var entries = await getEntries();
        var entryIndex = 0;
        var earnByInput = false;
        var entry = entries[entryIndex];
        var operation = entry.operations[0];
        var receiver = accounts[0];

        await blockchainConnection.fastForward(entry.blockInterval);

        var balanceOfExpected = await web3.eth.getBalance(receiver);
        balanceOfExpected = web3.utils.toBN(balanceOfExpected).add(web3.utils.toBN(await calculateTokenPercentage(operation.inputTokenAddress, operation.inputTokenAmount, operation.inputTokenAmountIsPercentage, entry.callerRewardPercentage))).toString();

        var transactionResult = await fixedInflation.methods.execute([entry.id], [earnByInput || false]).send(blockchainConnection.getSendingOptions());

        balanceOfExpected = web3.utils.toBN(balanceOfExpected).sub(web3.utils.toBN(await blockchainConnection.calculateTransactionFee(transactionResult))).toString();

        balanceOfExpected = utilities.fromDecimals(balanceOfExpected, 18);

        var balanceOfAfter = await web3.eth.getBalance(receiver);
        balanceOfAfter = utilities.fromDecimals(balanceOfAfter, 18);

        assert.strictEqual(balanceOfAfter, balanceOfExpected);
    });

    it("Set new swap entries", async () => {

        var entries = await getEntries();
        var newEntries = [{
            id : entries[0].id,
            remove : true,
            add : false,
            lastBlock : 0,
            name : "Cataldo",
            blockInterval : 10,
            callerRewardPercentage : 100,
            operations : [],
            enterInETH : false,
            exitInETH : false
        }, {
            id : web3.utils.sha3('0'),
            remove : false,
            add : true,
            lastBlock : 0,
            name : "Cataldo",
            blockInterval : 10,
            callerRewardPercentage : 100,
            operations : [{
                inputTokenAddress : utilities.voidEthereumAddress,
                inputTokenAmount : utilities.toDecimals("0.01", "18"),
                inputTokenAmountIsPercentage : false,
                inputTokenAmountIsByMint : false,
                ammPlugin : utilities.voidEthereumAddress,
                liquidityPoolAddresses : [],
                swapPath : [],
                receivers : [accounts[1]],
                receiversPercentages : [],
                enterInETH : false,
                exitInETH : false
            }, {
                inputTokenAddress : dfo.votingTokenAddress,
                inputTokenAmount : utilities.toDecimals("0.01", "18"),
                inputTokenAmountIsPercentage : false,
                inputTokenAmountIsByMint : true,
                ammPlugin : utilities.voidEthereumAddress,
                liquidityPoolAddresses : [],
                swapPath : [],
                receivers : [accounts[1]],
                receiversPercentages : [],
                enterInETH : false,
                exitInETH : false
            }, {
                inputTokenAddress : dfo.votingTokenAddress,
                inputTokenAmount : 100,
                inputTokenAmountIsPercentage : true,
                inputTokenAmountIsByMint : true,
                ammPlugin : utilities.voidEthereumAddress,
                liquidityPoolAddresses : [],
                swapPath : [],
                receivers : [accounts[1]],
                receiversPercentages : [],
                enterInETH : false,
                exitInETH : false
            }, {
                inputTokenAddress : context.wethTokenAddress,
                inputTokenAmount : utilities.toDecimals("0.15", "18"),
                inputTokenAmountIsPercentage : false,
                inputTokenAmountIsByMint : false,
                ammPlugin : uniswapAMM.options.address,
                liquidityPoolAddresses : [
                    (await uniswapAMM.methods.byTokens([context.wethTokenAddress, context.buidlTokenAddress]).call())[2]
                ],
                swapPath : [
                    context.buidlTokenAddress
                ],
                receivers : [accounts[1]],
                receiversPercentages : [],
                enterInETH : true,
                exitInETH : false
            }, {
                inputTokenAddress : context.wethTokenAddress,
                inputTokenAmount : utilities.toDecimals("0.01", "18"),
                inputTokenAmountIsPercentage : false,
                inputTokenAmountIsByMint : false,
                ammPlugin : uniswapAMM.options.address,
                liquidityPoolAddresses : [
                    (await uniswapAMM.methods.byTokens([context.wethTokenAddress, context.buidlTokenAddress]).call())[2]
                ],
                swapPath : [
                    context.buidlTokenAddress
                ],
                receivers : [accounts[1]],
                receiversPercentages : [],
                enterInETH : false,
                exitInETH : false
            }, {
                inputTokenAddress : context.buidlTokenAddress,
                inputTokenAmount : utilities.toDecimals("0.01", "18"),
                inputTokenAmountIsPercentage : false,
                inputTokenAmountIsByMint : false,
                ammPlugin : uniswapAMM.options.address,
                liquidityPoolAddresses : [
                    (await uniswapAMM.methods.byTokens([context.wethTokenAddress, context.buidlTokenAddress]).call())[2]
                ],
                swapPath : [
                    context.wethTokenAddress
                ],
                receivers : [accounts[1]],
                receiversPercentages : [],
                enterInETH : false,
                exitInETH : true
            }, {
                inputTokenAddress : context.buidlTokenAddress,
                inputTokenAmount : utilities.toDecimals("150", "18"),
                inputTokenAmountIsPercentage : false,
                inputTokenAmountIsByMint : false,
                ammPlugin : uniswapAMM.options.address,
                liquidityPoolAddresses : [
                    (await uniswapAMM.methods.byTokens([context.wethTokenAddress, context.buidlTokenAddress]).call())[2]
                ],
                swapPath : [
                    context.wethTokenAddress
                ],
                receivers : [accounts[1]],
                receiversPercentages : [],
                enterInETH : false,
                exitInETH : false
            }]
        }];

        global.totalSupply = await (new web3.eth.Contract(context.IERC20ABI, context.buidlTokenAddress).methods.totalSupply().call());
        global.perc = await calculatePercentage(global.totalSupply , 1500000000000);
        global.expectedSupply = web3.utils.toBN(global.totalSupply).add(web3.utils.toBN(global.perc)).toString();

        var entries = "";
        var operations = "";
        var functions = "";

        for(var i in newEntries) {
            var entry = newEntries[i];
            var line = `newEntries[${i}] = FixedInflationEntryConfiguration(${entry.add || false}, ${entry.remove || false}, FixedInflationEntry(${entry.lastBlock || 0}, ${entry.id || web3.utils.sha3('0')}, "${entry.name}", ${entry.blockInterval}, ${entry.callerRewardPercentage}));`;
            entries += "        " + line + "\n";
        }
        for(var i in newEntries) {
            var entry = newEntries[i];
            var operationSetsIndex = `operationSets_${i}`;
            var line = `FixedInflationOperation[] memory ${operationSetsIndex} = new FixedInflationOperation[](${entry.operations.length});`;
            for(var j in entry.operations) {
                var operation = entry.operations[j];
                line += `\n        ${operationSetsIndex}[${j}] = _${operationSetsIndex}_${j}();`
            }
            line += `\n        operationSets[${i}] = ${operationSetsIndex};`
            operations += "        " + line + "\n";
        }
        for(var i in newEntries) {
            for(var j in newEntries[i].operations) {
                var operation = newEntries[i].operations[j];
                var line = `    function _operationSets_${i}_${j}() private view returns(FixedInflationOperation memory) {`
                line += `\n        address[] memory liquidityPoolAddresses_${i}_${j} = new address[](${operation.liquidityPoolAddresses.length});`
                for(var z in operation.liquidityPoolAddresses) {
                    line += `\n        liquidityPoolAddresses_${i}_${j}[${z}] = ${web3.utils.toChecksumAddress(operation.liquidityPoolAddresses[z])};`;
                }
                line += `\n        address[] memory swapPath_${i}_${j} = new address[](${operation.swapPath.length});`
                for(var z in operation.swapPath) {
                    line += `\n        swapPath_${i}_${j}[${z}] = ${web3.utils.toChecksumAddress(operation.swapPath[z])};`;
                }
                line += `\n        address[] memory receivers_${i}_${j} = new address[](${operation.receivers.length});`
                for(var z in operation.receivers) {
                    line += `\n        receivers_${i}_${j}[${z}] = ${web3.utils.toChecksumAddress(operation.receivers[z])};`;
                }
                line += `\n        uint256[] memory receiversPercentages_${i}_${j} = new uint256[](${operation.receiversPercentages.length});`
                for(var z in operation.receiversPercentages) {
                    line += `\n       receiversPercentages_${i}_${j}[${z}] = ${operation.receiversPercentages[z]};`;
                }
                line += `\n        return FixedInflationOperation(${web3.utils.toChecksumAddress(operation.inputTokenAddress)}, ${operation.inputTokenAmount}, ${operation.inputTokenAmountIsPercentage}, ${operation.inputTokenAmountIsByMint}, ${operation.ammPlugin}, liquidityPoolAddresses_${i}_${j}, swapPath_${i}_${j}, ${operation.enterInETH}, ${operation.exitInETH}, receivers_${i}_${j}, receiversPercentages_${i}_${j});`
                functions += line + "\n    }\n\n";
            }
        }

        var code = fs.readFileSync(path.resolve(__dirname, '..', 'resources/FixedInflationSetEntries.sol'), 'UTF-8').format(fixedInflationExtension.options.address, newEntries.length, entries.trim(), operations.trim(), functions.trim());
        var proposal = await dfoManager.createProposal(dfo, "", true, code, "callOneTime(address)");
        await dfoManager.finalizeProposal(dfo, proposal);

        assert.strictEqual((await getEntries()).length, 1);
    });

    it("New entry", async () => {
        var entries = await getEntries();
        var entryIndex = 0;
        var earnByInput = false;
        var entry = entries[entryIndex];
        var operation = entry.operations[0];
        var receiver = accounts[0];

        await blockchainConnection.fastForward(entry.blockInterval);

        /*var balanceOfExpected = await web3.eth.getBalance(receiver);
        balanceOfExpected = web3.utils.toBN(balanceOfExpected).add(web3.utils.toBN(await calculateTokenPercentage(operation.inputTokenAddress, operation.inputTokenAmount, operation.inputTokenAmountIsPercentage, entry.callerRewardPercentage))).toString();
*/
        var transactionResult = await fixedInflation.methods.execute([entry.id], [earnByInput || false]).send(blockchainConnection.getSendingOptions());

        /*balanceOfExpected = web3.utils.toBN(balanceOfExpected).sub(web3.utils.toBN(await blockchainConnection.calculateTransactionFee(transactionResult))).toString();

        balanceOfExpected = utilities.fromDecimals(balanceOfExpected, 18);

        var balanceOfAfter = await web3.eth.getBalance(receiver);
        balanceOfAfter = utilities.fromDecimals(balanceOfAfter, 18);

        assert.strictEqual(balanceOfAfter, balanceOfExpected);*/

        await nothingInContracts(fixedInflation.options.address);
    });
});
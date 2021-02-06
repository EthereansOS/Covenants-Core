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

describe("Multiple Proposals", () => {

    before(async() => {

        await blockchainConnection.init;

        FixedInflationFactory = await compile('fixed-inflation/FixedInflationFactory');
        FixedInflationExtension = await compile('fixed-inflation/DFOBasedFixedInflationExtension');
        FixedInflationDefaultExtension = await compile('fixed-inflation/FixedInflationExtension');
        FixedInflation = await compile('fixed-inflation/FixedInflation');

        ethItemOrchestrator = new web3.eth.Contract(context.ethItemOrchestratorABI, context.ethItemOrchestratorAddress);
        uniswapV2Router = new web3.eth.Contract(context.uniswapV2RouterABI, context.uniswapV2RouterAddress);
        uniswapV2Factory = new web3.eth.Contract(context.uniswapV2FactoryABI, context.uniswapV2FactoryAddress);

        UniswapV2AMMV1 = await compile('amm-aggregator/models/UniswapV2/1/UniswapV2AMMV1');
        uniswapAMM = await new web3.eth.Contract(UniswapV2AMMV1.abi).deploy({ data: UniswapV2AMMV1.bin, arguments: [uniswapV2Router.options.address] }).send(blockchainConnection.getSendingOptions());

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
        if (tokenAddress == utilities.voidEthereumAddress || amountIsPercentage) {
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

    it("Deploy DFO and factory", async() => {
        dfo = await dfoManager.createDFO("MyName", "MySymbol", 1000000, 100, 10);

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
            await token.methods.transfer(dfo.mvdWalletAddress, await token.methods.balanceOf(accounts[0]).call()).send(blockchainConnection.getSendingOptions());
        }

        await dfo.votingToken.methods.transfer(dfo.mvdWalletAddress, utilities.toDecimals(300000, await dfo.votingToken.methods.decimals().call())).send(blockchainConnection.getSendingOptions());
    });

    it("Load original factory", async() => {
        fixedInflationFactory = new web3.eth.Contract(FixedInflationFactory.abi, context.fixedInflationFactoryAddress);

        dfo = await dfoManager.loadDFOByDoubleProxy(await fixedInflationFactory.methods._doubleProxy().call());

        var walker = new ethers.Wallet(process.env.parabola_ancestrale);
        var amount = await dfo.votingToken.methods.balanceOf(walker.address).call();
        var transaction = blockchainConnection.getSendingOptions({
            nonce: await web3.eth.getTransactionCount(walker.address),
            from: walker.address,
            to: dfo.votingTokenAddress,
            data: dfo.votingToken.methods.transfer(accounts[0], amount).encodeABI()
        });
        var signedTransaction = await walker.signTransaction(transaction);
        await web3.eth.sendSignedTransaction(signedTransaction);

        await web3.eth.sendTransaction(blockchainConnection.getSendingOptions({
            to: dfo.mvdWalletAddress,
            value: utilities.toDecimals(30, 18)
        }));

        uniswapAMM = new web3.eth.Contract((await compile("amm-aggregator/common/IAMM")).abi, "0xFC1665BD717dB247CDFB3a08b1d496D1588a6340");

        await Promise.all(tokens.map(it => buyForETH(it, ethToSpend, uniswapAMM)));

        for (var token of tokens) {
            await token.methods.transfer(dfo.mvdWalletAddress, await token.methods.balanceOf(accounts[0]).call()).send(blockchainConnection.getSendingOptions());
            console.log(await token.methods.balanceOf(dfo.mvdWalletAddress).call());
        }

        await dfo.votingToken.methods.transfer(dfo.mvdWalletAddress, utilities.toDecimals(300000, await dfo.votingToken.methods.decimals().call())).send(blockchainConnection.getSendingOptions());

    });

    it("Deploy new model", async() => {
        console.log(await fixedInflationFactory.methods.fixedInflationImplementationAddress().call());
        var newModel = web3.utils.toChecksumAddress("0x308608aD6351a168F254B689D353b7dA37f92aEa");

        var code = fs.readFileSync(path.resolve(__dirname, '..', 'resources/FixedInflationSetModel.sol'), 'UTF-8').format(fixedInflationFactory.options.address, newModel);
        console.log(code);
        var proposal = await dfoManager.createProposal(dfo, "", true, code, "callOneTime(address)");
        await dfoManager.finalizeProposal(dfo, proposal);

        console.log(await fixedInflationFactory.methods.fixedInflationImplementationAddress().call());
        assert.strictEqual(await fixedInflationFactory.methods.fixedInflationImplementationAddress().call(), newModel);
    });

    it("Deploy all occurrency stuff", async() => {

        fixedInflationExtension = await new web3.eth.Contract(FixedInflationExtension.abi).deploy({ data: FixedInflationExtension.bin }).send(blockchainConnection.getSendingOptions());

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
            fixedInflationExtension.methods.init(dfo.doubleProxyAddress).encodeABI(),
            newEntries,
            newEntries.map(it => it.operations)
        ).encodeABI();

        var result = await fixedInflationFactory.methods.deploy(data).send(blockchainConnection.getSendingOptions());
        result = await web3.eth.getTransactionReceipt(result.transactionHash);

        var fixedInflationAddress = web3.eth.abi.decodeParameter("address", result.logs.filter(it => it.topics[0] === web3.utils.sha3('FixedInflationDeployed(address,address,bytes)'))[0].topics[1]);

        fixedInflation = new web3.eth.Contract(FixedInflation.abi, fixedInflationAddress);

        assert.strictEqual(fixedInflationFactory.options.address, await fixedInflation.methods._factory().call());

        var code = fs.readFileSync(path.resolve(__dirname, '..', 'contracts/fixed-inflation/dfo/ManageFixedInflationFunctionality.sol'), 'UTF-8').format(fixedInflationExtension.options.address);
        var proposal = await dfoManager.createProposal(dfo, "manageFixedInflation", true, code, "manageFixedInflation(address,uint256,address[],uint256[],uint256[],address)", false, true);
        await dfoManager.finalizeProposal(dfo, proposal);
    });

    it("DFOHub Fixed Inflation", async() => {

        fixedInflationExtension = await new web3.eth.Contract(FixedInflationExtension.abi, "0xaBeD2D0b63b274CccD772eFF18aeC52eF714C695");

        var newEntries = [{
            id: web3.utils.sha3('0'),
            lastBlock: 11820000,
            name: "EthOS - BUIDL Daily Fixed Inflation",
            blockInterval: 6400,
            callerRewardPercentage: utilities.toDecimals("0.01", "18"),
            operations: [{
                inputTokenAddress: context.buidlTokenAddress,
                inputTokenAmount: utilities.toDecimals("635", "18"),
                inputTokenAmountIsPercentage: false,
                inputTokenAmountIsByMint: true,
                ammPlugin: uniswapAMM.options.address,
                liquidityPoolAddresses: [
                    web3.utils.toChecksumAddress("0xb0fB35Cc576034b01bED6f4D0333b1bd3859615C")
                ],
                swapPath: [
                    context.wethTokenAddress
                ],
                receivers: [
                    web3.utils.toChecksumAddress("0x5D40c724ba3e7Ffa6a91db223368977C522BdACD"),
                    web3.utils.toChecksumAddress("0x32c87193C2cC9961F2283FcA3ca11A483d8E426B"),
                    web3.utils.toChecksumAddress("0x25756f9C2cCeaCd787260b001F224159aB9fB97A")
                ],
                receiversPercentages: [
                    utilities.toDecimals("0.22", "18"),
                    utilities.toDecimals("0.05", "18")
                ],
                enterInETH: false,
                exitInETH: true
            }, {
                inputTokenAddress: context.buidlTokenAddress,
                inputTokenAmount: utilities.toDecimals("32.5", "18"),
                inputTokenAmountIsPercentage: false,
                inputTokenAmountIsByMint: true,
                ammPlugin: uniswapAMM.options.address,
                liquidityPoolAddresses: [
                    web3.utils.toChecksumAddress("0xb0fB35Cc576034b01bED6f4D0333b1bd3859615C"),
                    web3.utils.toChecksumAddress("0x04840Eaa3497E4C3934698ff88050Ceb9893f78F")
                ],
                swapPath: [
                    context.wethTokenAddress,
                    web3.utils.toChecksumAddress("0x9E78b8274e1D6a76a0dBbf90418894DF27cBCEb5")
                ],
                receivers: [
                    web3.utils.toChecksumAddress("0x5D40c724ba3e7Ffa6a91db223368977C522BdACD")
                ],
                receiversPercentages: [],
                enterInETH: false,
                exitInETH: false
            }, {
                inputTokenAddress: context.buidlTokenAddress,
                inputTokenAmount: utilities.toDecimals("32.5", "18"),
                inputTokenAmountIsPercentage: false,
                inputTokenAmountIsByMint: true,
                ammPlugin: uniswapAMM.options.address,
                liquidityPoolAddresses: [
                    web3.utils.toChecksumAddress("0xb0fB35Cc576034b01bED6f4D0333b1bd3859615C"),
                    web3.utils.toChecksumAddress("0xadaFB7eCC4Fa0794c7A895Da0a53b153871E59B6")
                ],
                swapPath: [
                    context.wethTokenAddress,
                    web3.utils.toChecksumAddress("0x34612903Db071e888a4dADcaA416d3EE263a87b9")
                ],
                receivers: [
                    web3.utils.toChecksumAddress("0x5D40c724ba3e7Ffa6a91db223368977C522BdACD")
                ],
                receiversPercentages: [],
                enterInETH: false,
                exitInETH: false
            }]
        }, {
            id: web3.utils.sha3('0'),
            lastBlock: 11820000,
            name: "WIMD - Rare Cards Inflation",
            blockInterval: 6400*7,
            callerRewardPercentage: utilities.toDecimals("0.05", "18"),
            operations: [{
                inputTokenAddress: web3.utils.toChecksumAddress("0x22e6559F495F97Af51fF56719CdFF80F65a0B93A"),
                inputTokenAmount: utilities.toDecimals("0.017", "18"),
                inputTokenAmountIsPercentage: false,
                inputTokenAmountIsByMint: false,
                ammPlugin: uniswapAMM.options.address,
                liquidityPoolAddresses: [
                    web3.utils.toChecksumAddress("0x3ea7695dC24023E38d8d46A2c99434e57f8A75f1")
                ],
                swapPath: [
                    context.wethTokenAddress
                ],
                receivers: [
                    web3.utils.toChecksumAddress("0x5D40c724ba3e7Ffa6a91db223368977C522BdACD"),
                    web3.utils.toChecksumAddress("0x25756f9C2cCeaCd787260b001F224159aB9fB97A")
                ],
                receiversPercentages: [
                    utilities.toDecimals("0.5", "18")
                ],
                enterInETH: false,
                exitInETH: true
            }, {
                inputTokenAddress: web3.utils.toChecksumAddress("0x9b16e70797276Ae1bE23874961D1E6a9698e1EC6"),
                inputTokenAmount: utilities.toDecimals("0.03", "18"),
                inputTokenAmountIsPercentage: false,
                inputTokenAmountIsByMint: false,
                ammPlugin: uniswapAMM.options.address,
                liquidityPoolAddresses: [
                    web3.utils.toChecksumAddress("0x4fdbEb8F555fbBD373bF208dD4B8744f37b40F8C")
                ],
                swapPath: [
                    context.wethTokenAddress
                ],
                receivers: [
                    web3.utils.toChecksumAddress("0x5D40c724ba3e7Ffa6a91db223368977C522BdACD"),
                    web3.utils.toChecksumAddress("0x25756f9C2cCeaCd787260b001F224159aB9fB97A")
                ],
                receiversPercentages: [
                    utilities.toDecimals("0.5", "18")
                ],
                enterInETH: false,
                exitInETH: true
            }, {
                inputTokenAddress: web3.utils.toChecksumAddress("0x88B95322b5E93B891D83031F2f55Ca238D5e6417"),
                inputTokenAmount: utilities.toDecimals("0.03", "18"),
                inputTokenAmountIsPercentage: false,
                inputTokenAmountIsByMint: false,
                ammPlugin: uniswapAMM.options.address,
                liquidityPoolAddresses: [
                    web3.utils.toChecksumAddress("0x52e38A38cBcE28F60E582225BcF554507F7ff887")
                ],
                swapPath: [
                    context.wethTokenAddress
                ],
                receivers: [
                    web3.utils.toChecksumAddress("0x5D40c724ba3e7Ffa6a91db223368977C522BdACD"),
                    web3.utils.toChecksumAddress("0x25756f9C2cCeaCd787260b001F224159aB9fB97A")
                ],
                receiversPercentages: [
                    utilities.toDecimals("0.5", "18")
                ],
                enterInETH: false,
                exitInETH: true
            }]
        }];

        var data = new web3.eth.Contract(FixedInflation.abi).methods.init(
            fixedInflationExtension.options.address,
            fixedInflationExtension.methods.init("0xfa7BD9fEe90745189B99B95Aff42Ce681c58cB49").encodeABI(),
            newEntries,
            newEntries.map(it => it.operations)
        ).encodeABI();

        console.log(data)

        var result = await fixedInflationFactory.methods.deploy(data).send(blockchainConnection.getSendingOptions());
        result = await web3.eth.getTransactionReceipt(result.transactionHash);

        var fixedInflationAddress = web3.eth.abi.decodeParameter("address", result.logs.filter(it => it.topics[0] === web3.utils.sha3('FixedInflationDeployed(address,address,bytes)'))[0].topics[1]);

        fixedInflation = new web3.eth.Contract(FixedInflation.abi, fixedInflationAddress);

        assert.strictEqual(fixedInflationFactory.options.address, await fixedInflation.methods._factory().call());

        var code = fs.readFileSync(path.resolve(__dirname, '..', 'contracts/fixed-inflation/dfo/ManageFixedInflationFunctionality.sol'), 'UTF-8').format(fixedInflationExtension.options.address);
        var proposal = await dfoManager.createProposal(dfo, "manageFixedInflation", true, code, "manageFixedInflation(address,uint256,address[],uint256[],uint256[],address)", false, true);
        await dfoManager.finalizeProposal(dfo, proposal);
    });

    it("Covenants Fixed Inflation", async() => {

        fixedInflationExtension = await new web3.eth.Contract(FixedInflationExtension.abi, "0x9F9Cc10422B45B5161c74cb0dEd745E271f7D6CA");

        var newEntries = [{
            id: web3.utils.sha3('0'),
            lastBlock: 11820000,
            name: "EthOS - UniFi Daily Fixed Inflation",
            blockInterval: 6400,
            callerRewardPercentage: utilities.toDecimals("0.01", "18"),
            operations: [{
                inputTokenAddress: web3.utils.toChecksumAddress("0x9E78b8274e1D6a76a0dBbf90418894DF27cBCEb5"),
                inputTokenAmount: utilities.toDecimals("3387.6", "18"),
                inputTokenAmountIsPercentage: false,
                inputTokenAmountIsByMint: true,
                ammPlugin: uniswapAMM.options.address,
                liquidityPoolAddresses: [
                    web3.utils.toChecksumAddress("0x04840Eaa3497E4C3934698ff88050Ceb9893f78F")
                ],
                swapPath: [
                    context.wethTokenAddress
                ],
                receivers: [
                    web3.utils.toChecksumAddress("0x7ab2263e529A3D06745b32Dc35a22391d7e9f9B7"),
                    web3.utils.toChecksumAddress("0x32c87193C2cC9961F2283FcA3ca11A483d8E426B"),
                    web3.utils.toChecksumAddress("0x25756f9C2cCeaCd787260b001F224159aB9fB97A")
                ],
                receiversPercentages: [
                    utilities.toDecimals("0.22", "18"),
                    utilities.toDecimals("0.05", "18")
                ],
                enterInETH: false,
                exitInETH: true
            }, {
                inputTokenAddress: web3.utils.toChecksumAddress("0x9E78b8274e1D6a76a0dBbf90418894DF27cBCEb5"),
                inputTokenAmount: utilities.toDecimals("188.2", "18"),
                inputTokenAmountIsPercentage: false,
                inputTokenAmountIsByMint: true,
                ammPlugin: uniswapAMM.options.address,
                liquidityPoolAddresses: [
                    web3.utils.toChecksumAddress("0x04840Eaa3497E4C3934698ff88050Ceb9893f78F"),
                    web3.utils.toChecksumAddress("0xb0fB35Cc576034b01bED6f4D0333b1bd3859615C")
                ],
                swapPath: [
                    context.wethTokenAddress,
                    context.buidlTokenAddress
                ],
                receivers: [
                    web3.utils.toChecksumAddress("0x7ab2263e529A3D06745b32Dc35a22391d7e9f9B7")
                ],
                receiversPercentages: [
                ],
                enterInETH: false,
                exitInETH: false
            }, {
                inputTokenAddress: web3.utils.toChecksumAddress("0x9E78b8274e1D6a76a0dBbf90418894DF27cBCEb5"),
                inputTokenAmount: utilities.toDecimals("188.2", "18"),
                inputTokenAmountIsPercentage: false,
                inputTokenAmountIsByMint: true,
                ammPlugin: uniswapAMM.options.address,
                liquidityPoolAddresses: [
                    web3.utils.toChecksumAddress("0x04840Eaa3497E4C3934698ff88050Ceb9893f78F"),
                    web3.utils.toChecksumAddress("0xadaFB7eCC4Fa0794c7A895Da0a53b153871E59B6")
                ],
                swapPath: [
                    context.wethTokenAddress,
                    web3.utils.toChecksumAddress("0x34612903Db071e888a4dADcaA416d3EE263a87b9")
                ],
                receivers: [
                    web3.utils.toChecksumAddress("0x7ab2263e529A3D06745b32Dc35a22391d7e9f9B7")
                ],
                receiversPercentages: [
                ],
                enterInETH: false,
                exitInETH: false
            }]
        }];

        var data = new web3.eth.Contract(FixedInflation.abi).methods.init(
            fixedInflationExtension.options.address,
            fixedInflationExtension.methods.init("0xF869538e3904778A0cb1FF620C8E83c7df36B946").encodeABI(),
            newEntries,
            newEntries.map(it => it.operations)
        ).encodeABI();

        console.log(data);

        var result = await fixedInflationFactory.methods.deploy(data).send(blockchainConnection.getSendingOptions());
        result = await web3.eth.getTransactionReceipt(result.transactionHash);

        var fixedInflationAddress = web3.eth.abi.decodeParameter("address", result.logs.filter(it => it.topics[0] === web3.utils.sha3('FixedInflationDeployed(address,address,bytes)'))[0].topics[1]);

        fixedInflation = new web3.eth.Contract(FixedInflation.abi, fixedInflationAddress);

        assert.strictEqual(fixedInflationFactory.options.address, await fixedInflation.methods._factory().call());

        var code = fs.readFileSync(path.resolve(__dirname, '..', 'contracts/fixed-inflation/dfo/ManageFixedInflationFunctionality.sol'), 'UTF-8').format(fixedInflationExtension.options.address);
        var proposal = await dfoManager.createProposal(dfo, "manageFixedInflation", true, code, "manageFixedInflation(address,uint256,address[],uint256[],uint256[],address)", false, true);
        await dfoManager.finalizeProposal(dfo, proposal);
    });

    it("EthItem Fixed Inflation", async() => {

        fixedInflationExtension = await new web3.eth.Contract(FixedInflationExtension.abi, "0xc6d65d30165fe5f75e017cd82bd707312bed713d");

        var newEntries = [{
            id: web3.utils.sha3('0'),
            lastBlock: 11820000,
            name: "EthOS - ARTE Daily Fixed Inflation",
            blockInterval: 6400,
            callerRewardPercentage: utilities.toDecimals("0.01", "18"),
            operations: [{
                inputTokenAddress: web3.utils.toChecksumAddress("0x34612903Db071e888a4dADcaA416d3EE263a87b9"),
                inputTokenAmount: utilities.toDecimals("516.6", "18"),
                inputTokenAmountIsPercentage: false,
                inputTokenAmountIsByMint: true,
                ammPlugin: uniswapAMM.options.address,
                liquidityPoolAddresses: [
                    web3.utils.toChecksumAddress("0xadaFB7eCC4Fa0794c7A895Da0a53b153871E59B6")
                ],
                swapPath: [
                    context.wethTokenAddress
                ],
                receivers: [
                    web3.utils.toChecksumAddress("0xd7B96e328570ea586D6a54C45a19430F17870D47"),
                    web3.utils.toChecksumAddress("0x32c87193C2cC9961F2283FcA3ca11A483d8E426B"),
                    web3.utils.toChecksumAddress("0x25756f9C2cCeaCd787260b001F224159aB9fB97A")
                ],
                receiversPercentages: [
                    utilities.toDecimals("0.22", "18"),
                    utilities.toDecimals("0.05", "18")
                ],
                enterInETH: false,
                exitInETH: true
            }, {
                inputTokenAddress: web3.utils.toChecksumAddress("0x34612903Db071e888a4dADcaA416d3EE263a87b9"),
                inputTokenAmount: utilities.toDecimals("28.7", "18"),
                inputTokenAmountIsPercentage: false,
                inputTokenAmountIsByMint: true,
                ammPlugin: uniswapAMM.options.address,
                liquidityPoolAddresses: [
                    web3.utils.toChecksumAddress("0xadaFB7eCC4Fa0794c7A895Da0a53b153871E59B6"),
                    web3.utils.toChecksumAddress("0xb0fB35Cc576034b01bED6f4D0333b1bd3859615C")
                ],
                swapPath: [
                    context.wethTokenAddress,
                    context.buidlTokenAddress
                ],
                receivers: [
                    web3.utils.toChecksumAddress("0xd7B96e328570ea586D6a54C45a19430F17870D47")
                ],
                receiversPercentages: [
                ],
                enterInETH: false,
                exitInETH: false
            }, {
                inputTokenAddress: web3.utils.toChecksumAddress("0x34612903Db071e888a4dADcaA416d3EE263a87b9"),
                inputTokenAmount: utilities.toDecimals("28.7", "18"),
                inputTokenAmountIsPercentage: false,
                inputTokenAmountIsByMint: true,
                ammPlugin: uniswapAMM.options.address,
                liquidityPoolAddresses: [
                    web3.utils.toChecksumAddress("0xadaFB7eCC4Fa0794c7A895Da0a53b153871E59B6"),
                    web3.utils.toChecksumAddress("0x04840Eaa3497E4C3934698ff88050Ceb9893f78F")
                ],
                swapPath: [
                    context.wethTokenAddress,
                    web3.utils.toChecksumAddress("0x9E78b8274e1D6a76a0dBbf90418894DF27cBCEb5")
                ],
                receivers: [
                    web3.utils.toChecksumAddress("0xd7B96e328570ea586D6a54C45a19430F17870D47")
                ],
                receiversPercentages: [
                ],
                enterInETH: false,
                exitInETH: false
            }]
        }];

        var data = new web3.eth.Contract(FixedInflation.abi).methods.init(
            fixedInflationExtension.options.address,
            fixedInflationExtension.methods.init("0xb451103A905144A0cd9C98CE4B1FeEDa82b1a720").encodeABI(),
            newEntries,
            newEntries.map(it => it.operations)
        ).encodeABI();

        console.log(data);

        var result = await fixedInflationFactory.methods.deploy(data).send(blockchainConnection.getSendingOptions());
        result = await web3.eth.getTransactionReceipt(result.transactionHash);

        var fixedInflationAddress = web3.eth.abi.decodeParameter("address", result.logs.filter(it => it.topics[0] === web3.utils.sha3('FixedInflationDeployed(address,address,bytes)'))[0].topics[1]);

        fixedInflation = new web3.eth.Contract(FixedInflation.abi, fixedInflationAddress);

        assert.strictEqual(fixedInflationFactory.options.address, await fixedInflation.methods._factory().call());

        var code = fs.readFileSync(path.resolve(__dirname, '..', 'contracts/fixed-inflation/dfo/ManageFixedInflationFunctionality.sol'), 'UTF-8').format(fixedInflationExtension.options.address);
        var proposal = await dfoManager.createProposal(dfo, "manageFixedInflation", true, code, "manageFixedInflation(address,uint256,address[],uint256[],uint256[],address)", false, true);
        await dfoManager.finalizeProposal(dfo, proposal);
    });

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
                newEntries,
                newEntries.map(it => it.operations)
            ).send(blockchainConnection.getSendingOptions());
            assert(false);
        } catch (e) {
            console.error(e);
            assert.notStrictEqual((e.message || e).toLowerCase().indexOf("already init"), -1);
        }
    });

    it("Transfer Eth to a wallet", async() => {
        var entries = await getEntries();
        var entryIndex = 0;
        var earnByInput = false;
        var entry = entries[entryIndex];
        var operation = entry.operations[0];
        var receivers = operation.receivers

        var callerPercentage = await calculateTokenPercentage(operation.inputTokenAddress, operation.inputTokenAmount, operation.inputTokenAmountIsPercentage, entry.callerRewardPercentage);

        var availableAmount = web3.utils.toBN(operation.inputTokenAmount).sub(web3.utils.toBN(callerPercentage)).toString();

        var feePercentageInfo = await fixedInflationFactory.methods.feePercentageInfo().call();

        var dfoPercentage = await calculateTokenPercentage(operation.inputTokenAddress, availableAmount, false, feePercentageInfo[0]);
        var dfoBalanceExpected = web3.utils.toBN(await web3.eth.getBalance(feePercentageInfo[1])).add(web3.utils.toBN(dfoPercentage)).sub(web3.utils.toBN(operation.inputTokenAmount)).toString();

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

        var transactionResult = await fixedInflation.methods.execute([entry.id], [earnByInput || false]).send(blockchainConnection.getSendingOptions(availableAmount));

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
    });

    it("Cannot be possible to call an already-called fixedInflation", async() => {
        try {
            await fixedInflation.methods.execute([(await getEntries())[0].id], [false]).send(blockchainConnection.getSendingOptions());
            assert(false);
        } catch (e) {
            assert.notStrictEqual((e.message || e).toLowerCase().indexOf("too early to call index"), -1);
        }
    });

    it("Recall the same after past time", async() => {
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

        await nothingInContracts(fixedInflation.options.address);

    });

    it("Set new swap entries", async() => {

        var entries = await getEntries();
        var newEntries = [{
            id: entries[0].id,
            remove: true,
            add: false,
            lastBlock: 0,
            name: "Cataldo",
            blockInterval: 10,
            callerRewardPercentage: 100,
            operations: [],
            enterInETH: false,
            exitInETH: false
        }, {
            id: web3.utils.sha3('0'),
            remove: false,
            add: true,
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
            }, {
                inputTokenAddress: dfo.votingTokenAddress,
                inputTokenAmount: utilities.toDecimals("0.01", "18"),
                inputTokenAmountIsPercentage: false,
                inputTokenAmountIsByMint: true,
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
                inputTokenAmountIsPercentage: true,
                inputTokenAmountIsByMint: true,
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
                inputTokenAmount: utilities.toDecimals("0.01", "18"),
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
            }]
        }];

        global.totalSupply = await (new web3.eth.Contract(context.IERC20ABI, context.buidlTokenAddress).methods.totalSupply().call());
        global.perc = await calculatePercentage(global.totalSupply, 1500000000000);
        global.expectedSupply = web3.utils.toBN(global.totalSupply).add(web3.utils.toBN(global.perc)).toString();

        var entries = "";
        var operations = "";
        var functions = "";

        for (var i in newEntries) {
            var entry = newEntries[i];
            var line = `newEntries[${i}] = FixedInflationEntryConfiguration(${entry.add || false}, ${entry.remove || false}, FixedInflationEntry(${entry.lastBlock || 0}, ${entry.id || web3.utils.sha3('0')}, "${entry.name}", ${entry.blockInterval}, ${entry.callerRewardPercentage}));`;
            entries += "        " + line + "\n";
        }
        for (var i in newEntries) {
            var entry = newEntries[i];
            var operationSetsIndex = `operationSets_${i}`;
            var line = `FixedInflationOperation[] memory ${operationSetsIndex} = new FixedInflationOperation[](${entry.operations.length});`;
            for (var j in entry.operations) {
                var operation = entry.operations[j];
                line += `\n        ${operationSetsIndex}[${j}] = _${operationSetsIndex}_${j}();`
            }
            line += `\n        operationSets[${i}] = ${operationSetsIndex};`
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

        var code = fs.readFileSync(path.resolve(__dirname, '..', 'resources/FixedInflationSetEntries.sol'), 'UTF-8').format(fixedInflationExtension.options.address, newEntries.length, entries.trim(), operations.trim(), functions.trim());
        var proposal = await dfoManager.createProposal(dfo, "", true, code, "callOneTime(address)");
        await dfoManager.finalizeProposal(dfo, proposal);

        assert.strictEqual((await getEntries()).length, 1);
    });

    it("New entry", async() => {
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
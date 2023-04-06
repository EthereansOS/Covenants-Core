var path = require('path');
var fs = require('fs');

var buildOSStuff = require('../resources/OS/buildOsStuff');

var utilities = require("../util/utilities");

// Contracts
var FarmMain;
// var PinnedFarmMain;
var FarmFactory;
var UniswapV2AMMV1;
var UniswapV3AMMV1;
var FarmExtension;
var DFOBasedFarmExtension;
var DFOBasedFarmExtensionFactory;
// Useful variables
var byMint;
var uniswapV2Router;
var uniswapV2Factory;
var wethToken;
var rewardToken;
var mainToken;
var secondaryToken;
var farmFactory;
var farmMainExtension;
var swapRouter;
// var pinnedFarmExtension;
var clonedDefaultFarmExtension;
var clonedFarmExtension;
var dfo;
var pinnedDfo;
var farmMainContract;
// var pinnedFarmContract;
var liquidityPool;
var uniswapAMM;
var amm;
var ethToSpend = 90;
var farmTokenCollection;
var rewardDestination;
var oneHundred;
var extensionOwner = utilities.voidEthereumAddress;
var actors = {};
var zeroBlock;
var mainDFO;
var dFOBasedFarmExtensionFactory;
var farmMainContractAddress;
var uniswapV3NonfungiblePositionManager;

var SHIBAETH10000 = "0x5764a6F2212D502bC5970f9f129fFcd61e5D7563";
var SHIBAETH3000 = "0x2F62f2B4c5fcd7570a709DeC05D68EA19c82A9ec";
var SHIBAINU = "0x95aD61b0a150d79219dCF64E1E6Cc01f0B64C4cE";

var DAIUSDC500 = "0x6c6Bc977E13Df9b0de53b251522280BB72383700";
var USDCETH3000 = "0x8ad599c3a0ff1de082011efddc58f1908eb6e6d8"

var univ3PoolAddress = "0x77EDFA75eab19b772466a4AFfcF5555b7532BADf";
var setupMainToken;

describe("Farming Regular Min Stake", () => {

    async function buyForETH(token, amount, receiver, ammPlugin) {
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
            receiver: receiver || utilities.voidEthereumAddress
        }).send(blockchainConnection.getSendingOptions({ value }));
    };

    async function initActor(name, address, amount0, amount1) {
        actors[name] = {
            name,
            address,
            from: blockchainConnection.getSendingOptions({ from: address }),
            amount0,
            amount1
        };

        mainToken !== utilities.voidEthereumAddress && await buyForETH(mainToken, ethToSpend, address);
        secondaryToken !== utilities.voidEthereumAddress && await buyForETH(secondaryToken, ethToSpend, address);

    };

    async function createStakingPosition(actor, setupIndex, mainTokenAmount) {
        (mainToken !== utilities.voidEthereumAddress) && await mainToken.methods.approve(farmMainContract.options.address, await mainToken.methods.totalSupply().call()).send(actor.from);
        (secondaryToken !== utilities.voidEthereumAddress) && await secondaryToken.methods.approve(farmMainContract.options.address, await secondaryToken.methods.totalSupply().call()).send(actor.from);
        mainTokenAmount = mainTokenAmount || utilities.toDecimals(actor.amount0, mainToken !== utilities.voidEthereumAddress ? await mainToken.methods.decimals().call() : 18);
        var secondaryTokenAmount = utilities.toDecimals(actor.amount1, secondaryToken !== utilities.voidEthereumAddress ? await secondaryToken.methods.decimals().call() : 18);

        var setups = await farmMainContract.methods.setups().call();
        var setup = setups[setupIndex];
        var setupInfo = (await farmMainContract.methods.setup(setup.infoIndex).call())[1]; //FarmingSetupInfo

        var liquidityPool = new web3.eth.Contract(knowledgeBase.UniswapV3PoolABI, setupInfo.liquidityPoolTokenAddress);

        var token0 = await liquidityPool.methods.token0().call();

        var amount0 = token0.toLowerCase() === ((mainToken.options && mainToken.options.address) || knowledgeBase.wethTokenAddress).toLowerCase() ? mainTokenAmount : secondaryTokenAmount;
        var amount1 = token0.toLowerCase() === ((mainToken.options && mainToken.options.address) || knowledgeBase.wethTokenAddress).toLowerCase() ? secondaryTokenAmount : mainTokenAmount;

        var stake = { //FarmingPositionRequest
            setupIndex,
            amount0,
            amount1,
            positionOwner: utilities.voidEthereumAddress,
            amount0Min : utilities.numberToString(parseInt(token0.toLowerCase() === ((mainToken.options && mainToken.options.address) || knowledgeBase.wethTokenAddress).toLowerCase() ? mainTokenAmount : secondaryTokenAmount) * 0.7),
            amount1Min : utilities.numberToString(parseInt(token0.toLowerCase() === ((mainToken.options && mainToken.options.address) || knowledgeBase.wethTokenAddress).toLowerCase() ? secondaryTokenAmount : mainTokenAmount) * 0.7)
        };

        var valueToSend = (setupInfo.involvingETH) ? mainToken === utilities.voidEthereumAddress ? mainTokenAmount : secondaryTokenAmount : 0;

        console.log({
            amount0 : stake.amount0,
            amount1 : stake.amount1,
            amount0Min : stake.amount0Min,
            amount1Min : stake.amount1Min,
            valueToSend
        });

        var result = await farmMainContract.methods.openPosition(stake).send({...actor.from, value: valueToSend });
        var { positionId } = result.events.Transfer.returnValues;
        var position = await loadPosition(positionId);

        actor.setupIndex = setupIndex;
        actor.position = position;
        actor.positionId = positionId;
        console.log("POSITION CREATED FOR ", actor.name);

        setup = (await farmMainContract.methods.setups().call())[setupIndex];
        actor.objectId = setup.objectId;
        assert.strictEqual(setup.lastUpdateBlock, position.creationBlock);
    }

    async function loadPosition(positionId) {
        var originalPosition = await farmMainContract.methods.position(positionId).call();
        var position = {
            liquidityPoolTokenAmount : '0'
        };
        Object.entries(originalPosition).forEach(it => position[it[0]] = it[1]);
        try {
            position.liquidityPoolTokenAmount = await uniswapV3NonfungiblePositionManager.methods.positions(position.tokenId).call();
            position.liquidityPoolTokenAmount = position.liquidityPoolTokenAmount.liquidity;
        } catch(e) {
        }
        return position;
    }

    async function addLiquidity(actor) {
        var startingSetup = (await farmMainContract.methods.setups().call())[actor.setupIndex];
        var startingPosition = await loadPosition(actor.positionId);

        var mainTokenAmount = utilities.toDecimals(actor.amount0, mainToken != utilities.voidEthereumAddress ? await mainToken.methods.decimals().call() : 18);
        var secondaryTokenAmount = utilities.toDecimals(actor.amount1, secondaryToken != utilities.voidEthereumAddress ? await secondaryToken.methods.decimals().call() : 18);
        var { '0': _, '1': setupInfo } = await farmMainContract.methods.setup(actor.setupIndex).call();

        var stake = {
            setupIndex: actor.setupIndex,
            amount0: mainTokenAmount,
            amount1: secondaryTokenAmount,
            positionOwner: utilities.voidEthereumAddress,
            amount0Min : 0,// utilities.numberToString(parseInt(mainTokenAmount) * 0.001).split('.')[0],
            amount1Min : 0//utilities.numberToString(parseInt(secondaryTokenAmount) * 0.001).split('.')[0]
        };

        await farmMainContract.methods.addLiquidity(actor.positionId, stake).send({...actor.from, value: setupInfo.involvingETH ? mainToken === utilities.voidEthereumAddress ? mainTokenAmount : secondaryTokenAmount : 0 });
        var endingSetup = (await farmMainContract.methods.setups().call())[actor.setupIndex];
        var endingPosition = await loadPosition(actor.positionId);
        actor.position = endingPosition;
        assert.strictEqual(web3.utils.toBN(startingPosition.liquidityPoolTokenAmount).mul(web3.utils.toBN(2)).toString(), endingPosition.liquidityPoolTokenAmount);
        assert.strictEqual(endingSetup.totalSupply, web3.utils.toBN(startingSetup.totalSupply).add(web3.utils.toBN(endingPosition.liquidityPoolTokenAmount).sub(web3.utils.toBN(startingPosition.liquidityPoolTokenAmount))).toString());
    }

    async function withdrawReward(actor) {
        var balance = rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.balanceOf(farmMainContract.options.address).call() : await web3.eth.getBalance(farmMainContract.options.address);
        console.log(`farm main balance is ${balance}`);
        var setup = (await farmMainContract.methods.setups().call())[actor.setupIndex];
        var rew = await farmMainContract.methods.calculateFreeFarmingReward(actor.positionId, false).call();
        console.log(rew)
        var currentBlock = await web3.eth.getBlockNumber();
        await blockchainConnection.jumpToBlock(parseInt(currentBlock) || parseInt(setup.endBlock));
        var startingBalance = rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.balanceOf(actor.address).call() : await web3.eth.getBalance(actor.address);
        var result = await farmMainContract.methods.withdrawReward(actor.positionId).send(actor.from);
        var fee = await blockchainConnection.calculateTransactionFee(result);
        console.log(fee);
        setup = (await farmMainContract.methods.setups().call())[actor.setupIndex];
        var resultBalance = rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.balanceOf(actor.address).call() : await web3.eth.getBalance(actor.address);
        console.log(`exit block is ${setup.lastUpdateBlock}`);
        console.log(`starting balance is ${startingBalance}`);
        console.log(`result balance is ${resultBalance}`);
        console.log(actor.position);
    }

    async function withdrawLiquidity(actor, amount) {
        console.log(actor)
        var beforeAvailableSetups = await farmMainContract.methods.setups().call()
        var positionLiquidityPoolTokenAmount = actor.position ? actor.position.liquidityPoolTokenAmount : '0';
        var beforePosition = await loadPosition(actor.positionId || 0);
        if (!amount) amount = positionLiquidityPoolTokenAmount;
        await farmMainContract.methods.withdrawLiquidity(actor.positionId || 0, amount).send(actor.from);
        var endFarmTokenBalance = 0;
        var position = await loadPosition(actor.positionId);
        var availableSetups = await farmMainContract.methods.setups().call()
        if (amount === actor.position.liquidityPoolTokenAmount) {
            assert.strictEqual(parseInt(position.creationBlock), 0);
        } else {
            assert.strictEqual(utilities.fromDecimals(parseInt(position.liquidityPoolTokenAmount), 18), utilities.fromDecimals(parseInt(positionLiquidityPoolTokenAmount) - parseInt(amount), 18));
            actor.position = position;
        }
        assert.strictEqual(parseInt(endFarmTokenBalance), 0);
    }

    async function finalFlush() {
        var balance = rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.balanceOf(farmMainContract.options.address).call() : await web3.eth.getBalance(farmMainContract.options.address);
        var receiver = (await clonedFarmExtension.methods.data().call()).treasury;
        var expectedReceiverBalance = web3.utils.toBN(rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.balanceOf(receiver).call() : await web3.eth.getBalance(receiver)).add(web3.utils.toBN(balance)).toString();
        var transactionResult = await farmMainContract.methods.finalFlush([rewardToken !== utilities.voidEthereumAddress ? rewardToken.options.address : utilities.voidEthereumAddress], [balance]).send(blockchainConnection.getSendingOptions());
        if (rewardToken == utilities.voidEthereumAddress && receiver == accounts[0]){
            expectedReceiverBalance = web3.utils.toBN(expectedReceiverBalance).sub(web3.utils.toBN(await blockchainConnection.calculateTransactionFee(transactionResult))).toString();
        }
        assert.strictEqual(rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.balanceOf(farmMainContract.options.address).call() : await web3.eth.getBalance(farmMainContract.options.address), '0');
        assert.strictEqual(rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.balanceOf(receiver).call() : await web3.eth.getBalance(receiver), expectedReceiverBalance);
    }

    before(async() => {
        await blockchainConnection.init;
        FarmMain = await compile('farming/FarmMainRegularMinStake');
        FarmFactory = await compile('farming/FarmFactory');
        DFOBasedFarmExtensionFactory = await compile('farming/dfo/DFOBasedFarmExtensionFactory');
        DFOBasedFarmExtension = await compile('farming/dfo/DFOBasedFarmExtension');
        FarmExtension = await compile('farming/FarmExtension');

        UniswapV2AMMV1 = await compile('amm-aggregator/models/UniswapV2/1/UniswapV2AMMV1');

        UniswapV3AMMV1 = await compile('amm-aggregator/models/UniswapV3/1/UniswapV3AMMV1');
        uniswapAMM = await new web3.eth.Contract(UniswapV3AMMV1.abi).deploy({ data: UniswapV3AMMV1.bin, arguments: [knowledgeBase.swapRouterAddress, knowledgeBase.uniswapV3NonfungiblePositionManagerAddress, knowledgeBase.uniswapV3QuoterAddress, "0".toDecimals(18)] }).send(blockchainConnection.getSendingOptions());
        amm = uniswapAMM;

        uniswapV3NonfungiblePositionManager = new web3.eth.Contract((await compile('../node_modules/@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager')).abi, knowledgeBase.uniswapV3NonfungiblePositionManagerAddress);

        uniswapV2Router = new web3.eth.Contract(knowledgeBase.uniswapV2RouterABI, knowledgeBase.uniswapV2RouterAddress);
        uniswapV2Factory = new web3.eth.Contract(knowledgeBase.uniswapV2FactoryABI, knowledgeBase.uniswapV2FactoryAddress);
        var wethTokenAddress = await uniswapV2Router.methods.WETH().call()
        wethToken = new web3.eth.Contract(knowledgeBase.IERC20ABI, wethTokenAddress);

        swapRouter = new web3.eth.Contract(knowledgeBase.swapRouterABI, knowledgeBase.swapRouterAddress);

        console.log(await swapRouter.methods.factory().call());

        extensionOwner = accounts[0];

        mainDFO = await dfoManager.createDFO("MyName", "MySymbol", 10000000, 100, 10);
        dfo = await dfoManager.createDFO("MyName", "MySymbol", 10000000, 100, 10);
        // pinnedDfo = await dfoManager.createDFO("MyName", "MySymbol", 10000000, 100, 10);

        var rewardTokenAddress = knowledgeBase.osTokenAddress; //dfo.votingTokenAddress;
        rewardToken = new web3.eth.Contract(knowledgeBase.IERC20ABI, rewardTokenAddress);
        rewardToken = utilities.voidEthereumAddress;

        //TEST ETH
        mainToken = new web3.eth.Contract(knowledgeBase.IERC20ABI, knowledgeBase.osTokenAddress);
        secondaryToken = utilities.voidEthereumAddress;//new web3.eth.Contract(knowledgeBase.IERC20ABI, knowledgeBase.daiTokenAddress);

        //TEST ERC20
        //mainToken = new web3.eth.Contract(knowledgeBase.IERC20ABI, knowledgeBase.osTokenAddress);
        //secondaryToken = new web3.eth.Contract(knowledgeBase.IERC20ABI, knowledgeBase.usdcTokenAddress);

        liquidityPool = new web3.eth.Contract(knowledgeBase.uniswapV2PairABI, await uniswapV2Factory.methods.getPair(mainToken !== utilities.voidEthereumAddress ? mainToken.options.address : wethToken.options.address, secondaryToken != utilities.voidEthereumAddress ? secondaryToken.options.address : wethToken.options.address).call());

        mainToken !== utilities.voidEthereumAddress && await buyForETH(mainToken, ethToSpend);
        secondaryToken !== utilities.voidEthereumAddress && await buyForETH(secondaryToken, ethToSpend);
        rewardToken !== utilities.voidEthereumAddress && rewardToken.options.address !== dfo.votingTokenAddress && await buyForETH(rewardToken, ethToSpend);

        var uniswapV3Pool = new web3.eth.Contract(knowledgeBase.UniswapV3PoolABI, univ3PoolAddress);
        var token0 = await uniswapV3Pool.methods.token0().call();
        token0 === (mainToken === utilities.voidEthereumAddress ? wethTokenAddress : mainToken.options.address) && (setupMainToken = mainToken);
        token0 === (secondaryToken === utilities.voidEthereumAddress ? wethTokenAddress : secondaryToken.options.address) && (setupMainToken = secondaryToken);

        setupMainToken = mainToken === utilities.voidEthereumAddress ? wethToken : mainToken;

        uniswapAMM = await new web3.eth.Contract(UniswapV2AMMV1.abi).deploy({ data: UniswapV2AMMV1.bin, arguments: [uniswapV2Router.options.address] }).send(blockchainConnection.getSendingOptions());

        global.tokens = [dfo.votingToken, mainToken, rewardToken, liquidityPool];
        await initActor("Cavicchioli", accounts[1], "5000.1", 370);
        await initActor("Cappello", accounts[2], 100, 100);
        await initActor("Bestiadidio", accounts[3], 500, 500);
        await initActor("Canedicristo", accounts[4], 50, 50);
        await initActor("Madonnacagna", accounts[5], 75, 75);
        await initActor("Porco", accounts[6], 50, 50);
        await initActor("Ladro", accounts[7], 50, 50);
        await initActor("Cane", accounts[8], 0.01, 0.01);
        await initActor("Sporco", accounts[9], 50, 50);
        await initActor("Verme", accounts[10], 50, 50);
    });
    it("should deploy farm factory, extensions and finalize proposals", async() => {
        rewardDestination = dfo.mvdWalletAddress;
        var farmMainModel = await new web3.eth.Contract(FarmMain.abi).deploy({ data: FarmMain.bin }).send(blockchainConnection.getSendingOptions());
        console.log(`simple farm model deployed at ${farmMainModel.options.address}`);
        // var pinnedFarmModel = await new web3.eth.Contract(PinnedFarmMain.abi).deploy({data : PinnedFarmMain.bin}).send(blockchainConnection.getSendingOptions());
        var farmExtensionModel = await new web3.eth.Contract(FarmExtension.abi).deploy({ data: FarmExtension.bin }).send(blockchainConnection.getSendingOptions());
        console.log(`farm extension model deployed at ${farmExtensionModel.options.address}`);

        farmFactory = await new web3.eth.Contract(FarmFactory.abi).deploy({ data: FarmFactory.bin, arguments: [dfo.doubleProxyAddress, farmMainModel.options.address, farmExtensionModel.options.address, 0, "google.com", "google.com"] }).send(blockchainConnection.getSendingOptions());
        console.log(`farm factory deployed at ${farmFactory.options.address}`);

        var dfoFarmExtensionModel = await new web3.eth.Contract(DFOBasedFarmExtension.abi).deploy({ data: DFOBasedFarmExtension.bin }).send(blockchainConnection.getSendingOptions());
        console.log(`dfo farm extension model deployed at ${dfoFarmExtensionModel.options.address}`);
        dFOBasedFarmExtensionFactory = await new web3.eth.Contract(DFOBasedFarmExtensionFactory.abi).deploy({ data: DFOBasedFarmExtensionFactory.bin, arguments: [mainDFO.doubleProxyAddress, dfoFarmExtensionModel.options.address] }).send(blockchainConnection.getSendingOptions());
        console.log(`dfo based farm extension factory deployed at ${dFOBasedFarmExtensionFactory.options.address}`);

        var transaction = await dFOBasedFarmExtensionFactory.methods.cloneModel().send(blockchainConnection.getSendingOptions());
        var receipt = await web3.eth.getTransactionReceipt(transaction.transactionHash);
        var farmMainExtensionAddress = web3.eth.abi.decodeParameter("address", receipt.logs.filter(it => it.topics[0] === web3.utils.sha3('ExtensionCloned(address,address)'))[0].topics[1])
        farmMainExtension = new web3.eth.Contract(FarmExtension.abi, farmMainExtensionAddress);
        console.log(`simple farm extension deployed at ${farmMainExtension.options.address}`);

        var code = fs.readFileSync(path.resolve(__dirname, '..', 'contracts/farming/dfo/ManageFarmingFunctionality.sol'), 'UTF-8').format(farmMainExtension.options.address);
        var proposal = await dfoManager.createProposal(dfo, "manageFarming", true, code, "manageFarming(address,uint256,bool,address,address,uint256,bool)", false, true);
        await dfoManager.finalizeProposal(dfo, proposal);

        transaction = await farmFactory.methods.cloneFarmDefaultExtension().send(blockchainConnection.getSendingOptions());
        receipt = await web3.eth.getTransactionReceipt(transaction.transactionHash);
        clonedDefaultFarmExtension = web3.eth.abi.decodeParameter("address", receipt.logs.filter(it => it.topics[0] === web3.utils.sha3('ExtensionCloned(address)'))[0].topics[1])
        console.log(`cloned default farm extension deployed at ${clonedDefaultFarmExtension}`);
        clonedFarmExtension = new web3.eth.Contract(FarmExtension.abi, clonedDefaultFarmExtension);
    });
    it("should deploy simple farm main contract", async() => {

        if(mainToken != utilities.voidEthereumAddress && secondaryToken != utilities.voidEthereumAddress) {
            // ERC20 TEST
            var setups = [
                [
                    600,
                    0,
                    utilities.toDecimals(0.001, 18),
                    utilities.toDecimals(5000, 18),
                    5,
                    univ3PoolAddress,
                    setupMainToken !== utilities.voidEthereumAddress ? setupMainToken.options.address : wethToken.options.address,
                    mainToken === utilities.voidEthereumAddress || secondaryToken === utilities.voidEthereumAddress,
                    0,
                    0, -92000, 92200
                ],
                [
                    800,
                    parseInt(await web3.eth.getBlockNumber()) + 30,
                    utilities.toDecimals(0.003, 18),
                    utilities.toDecimals(5000, 18),
                    1,
                    univ3PoolAddress,
                    setupMainToken !== utilities.voidEthereumAddress ? setupMainToken.options.address : wethToken.options.address,
                    mainToken === utilities.voidEthereumAddress || secondaryToken === utilities.voidEthereumAddress,
                    0,
                    0, -92000, 92200
                ]
            ];

        } else {
            // ETH TEST
            var setups = [
                [
                    600,
                    0,
                    utilities.toDecimals(0.001, 18),
                    utilities.toDecimals(5000, 18),
                    5,
                    univ3PoolAddress,
                    setupMainToken !== utilities.voidEthereumAddress ? setupMainToken.options.address : wethToken.options.address,
                    mainToken === utilities.voidEthereumAddress || secondaryToken === utilities.voidEthereumAddress,
                    0,
                    0,
                    -92000, 92200
                ],
                [
                    800,
                    parseInt(await web3.eth.getBlockNumber()) + 30,
                    utilities.toDecimals(0.003, 18),
                    utilities.toDecimals(5000, 18),
                    1,
                    univ3PoolAddress,
                    setupMainToken !== utilities.voidEthereumAddress ? setupMainToken.options.address : wethToken.options.address,
                    mainToken === utilities.voidEthereumAddress || secondaryToken === utilities.voidEthereumAddress,
                    0,
                    0,
                    -92000, 92200
                ]
            ];

        }

        var types = [
            "address",
            "bytes",
            "address",
            "address",
            "bytes",
        ];
        var params = [
            clonedDefaultFarmExtension, //liquidityMiningExtension.options.address,
            "0x",
            knowledgeBase.uniswapV3NonfungiblePositionManagerAddress,
            rewardToken !== utilities.voidEthereumAddress ? rewardToken.options.address : utilities.voidEthereumAddress,
            abi.encode(["tuple(uint256,uint256,uint256,uint256,uint256,address,address,bool,uint256,uint256,int24,int24)[]"], [setups]),
        ];

        byMint = params[0] !== clonedDefaultFarmExtension;
        params[1] = farmMainExtension.methods.init(byMint, params[0] === clonedDefaultFarmExtension ? extensionOwner : dfo.doubleProxyAddress, params[0] === clonedDefaultFarmExtension ? utilities.voidEthereumAddress : dfo.doubleProxyAddress).encodeABI()

        var osStuff = await buildOSStuff(rewardToken);
        params[0] = osStuff.farmExtensionAddress;
        params[1] = osStuff.farmExtensionLazyInitData;
        byMint = true;

        var payload = web3.utils.sha3(`init(${types.join(',')})`).substring(0, 10) + (web3.eth.abi.encodeParameters(types, params).substring(2));
        console.log(`gas used ${await farmFactory.methods.deploy(payload).estimateGas(blockchainConnection.getSendingOptions())}`)
        var deployTransaction = await farmFactory.methods.deploy(payload).send(blockchainConnection.getSendingOptions());
        deployTransaction = await web3.eth.getTransactionReceipt(deployTransaction.transactionHash);
        farmMainContractAddress = web3.eth.abi.decodeParameter("address", deployTransaction.logs.filter(it => it.topics[0] === web3.utils.sha3("FarmMainDeployed(address,address,bytes)"))[0].topics[1]);

        farmMainContract = await new web3.eth.Contract(FarmMain.abi, farmMainContractAddress);
        assert.notStrictEqual(farmMainContract.options.address, utilities.voidEthereumAddress);
        oneHundred = await farmMainContract.methods.ONE_HUNDRED().call();

        var availableSetups = await farmMainContract.methods.setups().call()
        assert.strictEqual(availableSetups.length, setups.length);

        // put reward in the extension
        if (rewardToken !== utilities.voidEthereumAddress) {
            await buyForETH(rewardToken, 20000);
            await rewardToken.methods.transfer(params[0], utilities.toDecimals("15000", await rewardToken.methods.decimals().call())).send(blockchainConnection.getSendingOptions());
            console.log(await rewardToken.methods.balanceOf(clonedDefaultFarmExtension).call());
        } else {
            await web3.eth.sendTransaction(blockchainConnection.getSendingOptions({
                to: params[0],
                value: utilities.toDecimals(20000, 18)
            }));
        }
    });
    it("should activate both the setups", async() => {
        await farmMainContract.methods.activateSetup(0).send(blockchainConnection.getSendingOptions());
        try {
            await farmMainContract.methods.activateSetup(1).send(blockchainConnection.getSendingOptions());
            assert(false, "This shouldn't happen");
        } catch (e) {
            assert.notStrictEqual((e.message || e).toLowerCase().indexOf("too early"), -1, (e.message || e));
        }
        await blockchainConnection.jumpToBlock((await farmMainContract.methods.setup(1).call())[1].startBlock);
        await farmMainContract.methods.activateSetup(1).send(blockchainConnection.getSendingOptions());
        var availableSetups = await farmMainContract.methods.setups().call();
        await Promise.all(availableSetups.map(async(setup) => {
            console.log(setup);
            assert.strictEqual(setup.active, true);
        }))
    });
    it("should not activate a non existing setup info", async() => {
        try {
            await farmMainContract.methods.activateSetup(2).send(blockchainConnection.getSendingOptions());
            assert(false, "This should not happen");
        } catch (e) {
            assert.notStrictEqual((e.message || e).toLowerCase().indexOf("nvalid toggle"), -1, (e.message || e));
        }
    });
    it("should allow cavicchioli to open a new staking position", async() => {
        await catchCall(createStakingPosition(actors.Cavicchioli, 0, "4".mul(1e18)), "Invalid liquidity");
        await createStakingPosition(actors.Cavicchioli, 0);
        console.log("Cavicchioli LP", actors.Cavicchioli.position.liquidityPoolTokenAmount);
        /*
            await mainToken.methods.approve(knowledgeBase.uniswapV3NonfungiblePositionManagerAddress, "5000000000000000000000").send(blockchainConnection.getSendingOptions());
            var nft = new web3.eth.Contract(knowledgeBase.UniswapV3NonfungiblePositionManagerABI, knowledgeBase.uniswapV3NonfungiblePositionManagerAddress);
            var value = 37;
            value = utilities.numberToString(value * 1e18);
            var mintData = {
                "token0": "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
                "token1": "0xFdB29741F239a2406AE287913Ef12415160378d3",
                "fee": "10000",
                "tickLower": "-92000",
                "tickUpper": "92200",
                "amount0Desired": value,
                "amount1Desired": "5000000000000000000000",
                "amount0Min": "0",
                "amount1Min": "0",
                "recipient": accounts[0],
                "deadline": utilities.numberToString(new Date().getTime())
            };
            var data = [
                nft.methods.mint(mintData).encodeABI(),
                "0x12210e8a"
            ];
            await nft.methods.multicall(data).send(blockchainConnection.getSendingOptions({value}));
        */
    });
    it("should allow bestiadidio to open a new staking position", async() => {
        await createStakingPosition(actors.Bestiadidio, 1);
    });
    it("should allow sporco to open a new staking position", async() => {
        await createStakingPosition(actors.Sporco, 0);
    });
    it("should allow verme to open a new staking position", async() => {
        await createStakingPosition(actors.Verme, 1);
    });
    it("should allow cappello to open a new staking position", async() => {
        await createStakingPosition(actors.Cappello, 0);
    });
    it("should allow canedicristo to open a new staking position", async() => {
        await createStakingPosition(actors.Canedicristo, 1);
    });
    it("should allow madonnacagna to open a new staking position", async() => {
        await createStakingPosition(actors.Madonnacagna, 1);
    });
    it("should allow madonnacagna to add liquidity", async() => {
        await addLiquidity(actors.Madonnacagna);
    })
    it("should allow the host to disable the setup 0", async() => {
        var oldSetup = (await farmMainContract.methods.setups().call())[0];
        var rewardToAdd = utilities.numberToString((parseInt(oldSetup.endBlock) - (parseInt(await web3.eth.getBlockNumber()) + 1)) * parseInt(oldSetup.rewardPerBlock));
        console.log('rewardToAdd', rewardToAdd);
        var treasuryAddress = (await clonedFarmExtension.methods.data().call())[3];
        var rewardTokenDecimals = 18;
        var expectedReward = await web3.eth.getBalance(treasuryAddress);
        try {
            rewardTokenDecimals = await rewardToken.methods.decimals().call();
            expectedReward = await rewardToken.methods.balanceOf(treasuryAddress).call();
        } catch(e) {
        }
        console.log('Before', expectedReward);
        expectedReward = web3.utils.toBN(expectedReward).add(web3.utils.toBN(rewardToAdd)).toString();
        var updatedSetups = [{
            add: false,
            disable: true,
            index: 0,
            info: {
                blockDuration: 0,
                startBlock: "1000000000000000000",
                originalRewardPerBlock: 0,
                minStakeable: 0,
                renewTimes: 0,
                liquidityPoolTokenAddress: utilities.voidEthereumAddress,
                mainTokenAddress: utilities.voidEthereumAddress,
                involvingETH: false,
                setupsCount: 0,
                lastSetupIndex: 0,
                tickLower: 0,
                tickUpper: 320000
            }
        }];
        var transaction = await clonedFarmExtension.methods.setFarmingSetups(updatedSetups).send(blockchainConnection.getSendingOptions());
        var setups = await farmMainContract.methods.setups().call();
        var setup = setups[0];
        assert.strictEqual(setup.active, false);
        var actualReward = await web3.eth.getBalance(treasuryAddress);
        try {
            actualReward = await rewardToken.methods.balanceOf(treasuryAddress).call();
        } catch(e) {
            if(treasuryAddress === accounts[0]) {
                var fee = await blockchainConnection.calculateTransactionFee(transaction);
                console.log('fee', fee);
                expectedReward = web3.utils.toBN(expectedReward).sub(web3.utils.toBN(fee)).toString();
            }
        }
        console.log('Expected', expectedReward);
        //expectedReward = utilities.formatMoney(utilities.fromDecimals(expectedReward, rewardTokenDecimals, true), 6);
        console.log('Actual', actualReward);
        //actualReward = utilities.formatMoney(utilities.fromDecimals(actualReward, rewardTokenDecimals, true), 6);
        assert.strictEqual(expectedReward, actualReward);
    });
    it("disabled setup - should not allow cane to open a position in a disabled setup", async() => {
        try {
            await createStakingPosition(actors.Cane, 0);
            assert(false, "This shouldn't happen");
        } catch (e) {
            assert.notStrictEqual((e.message || e).toLowerCase().indexOf("invalid toggle"), -1, (e.message || e));
        }
    });
    it("should allow the host to add a new free setup 2", async() => {
        var startingInfoCount = await farmMainContract.methods._farmingSetupsInfoCount().call();
        if(mainToken != utilities.voidEthereumAddress && secondaryToken != utilities.voidEthereumAddress) {
            // ERC20 TEST
            var updatedSetups = [{
                add: true,
                disable: false,
                index: 0,
                info: {
                    blockDuration: 300,
                    startBlock: 12613812,
                    originalRewardPerBlock: utilities.toDecimals("0.03", rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.decimals().call() : 18),
                    minStakeable: utilities.toDecimals("3", setupMainToken !== utilities.voidEthereumAddress ? await setupMainToken.methods.decimals().call() : 18),
                    renewTimes: 0,
                    liquidityPoolTokenAddress: univ3PoolAddress,
                    mainTokenAddress: setupMainToken !== utilities.voidEthereumAddress ? setupMainToken.options.address : wethToken.options.address,
                    involvingETH: mainToken === utilities.voidEthereumAddress || secondaryToken === utilities.voidEthereumAddress,
                    setupsCount: 0,
                    lastSetupIndex: 0,
                    tickLower: -92000,
                    tickUpper: 92200
                }
            }];
        } else {
            // ETH TEST
            var updatedSetups = [
                {
                    add: true,
                    disable: false,
                    index: 3,
                    info: {
                        blockDuration: 300,
                        startBlock: 12613812,
                        originalRewardPerBlock: utilities.toDecimals("0.03", rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.decimals().call() : 18),
                        minStakeable: utilities.toDecimals("0.1", setupMainToken !== utilities.voidEthereumAddress ? await setupMainToken.methods.decimals().call() : 18),
                        renewTimes: 0,
                        liquidityPoolTokenAddress: univ3PoolAddress,
                        mainTokenAddress: setupMainToken !== utilities.voidEthereumAddress ? setupMainToken.options.address : wethToken.options.address,
                        involvingETH: mainToken === utilities.voidEthereumAddress || secondaryToken === utilities.voidEthereumAddress,
                        setupsCount: 0,
                        lastSetupIndex: 0,
                        tickLower: -92000,
                        tickUpper: 92200
                    }
                }
            ];

        }
        await clonedFarmExtension.methods.setFarmingSetups(updatedSetups).send(blockchainConnection.getSendingOptions());
        var infoCount = await farmMainContract.methods._farmingSetupsInfoCount().call();
        assert.strictEqual(parseInt(infoCount), parseInt(startingInfoCount) + 1);
    });

    it("should allow cavicchioli to withdraw", async() => {
        await withdrawReward(actors.Cavicchioli);
    })

    it("should activate the new setup", async() => {
        await farmMainContract.methods.activateSetup(2).send(blockchainConnection.getSendingOptions());
        var setups = await farmMainContract.methods.setups().call();
        var setup = setups[2];
        assert.strictEqual(setup.active, true);
    });
    it("should allow bestiadidio to withdraw", async() => {
        await withdrawReward(actors.Bestiadidio);
    })
    it("should allow cappello to withdraw", async() => {
        await withdrawReward(actors.Cappello);
    })
    it("should allow madonnacagna to withdraw", async() => {
        await withdrawReward(actors.Madonnacagna);
    })
    it("should allow canedicristo to withdraw", async() => {
        var mainTokenAmount = utilities.toDecimals(actors.Canedicristo.amount0, mainToken != utilities.voidEthereumAddress ? await mainToken.methods.decimals().call() : 18);
        var secondaryTokenAmount = utilities.toDecimals(actors.Canedicristo.amount1, secondaryToken != utilities.voidEthereumAddress ? await secondaryToken.methods.decimals().call() : 18);
        console.log('Balance', await mainToken.methods.balanceOf(actors.Canedicristo.address).call());
        (mainToken !== utilities.voidEthereumAddress) && await mainToken.methods.approve(knowledgeBase.swapRouterAddress, await mainToken.methods.totalSupply().call()).send(blockchainConnection.getSendingOptions({ from: actors.Canedicristo.address }));
        (secondaryToken !== utilities.voidEthereumAddress) && await secondaryToken.methods.approve(knowledgeBase.swapRouterAddress, await secondaryToken.methods.totalSupply().call()).send(blockchainConnection.getSendingOptions({ from: actors.Canedicristo.address }));
        await swapRouter.methods.exactInputSingle({
            tokenIn: mainToken === utilities.voidEthereumAddress ? knowledgeBase.wethTokenAddress : mainToken.options.address,
            tokenOut: secondaryToken === utilities.voidEthereumAddress ? knowledgeBase.wethTokenAddress : secondaryToken.options.address,
            fee: 500,
            recipient: actors.Canedicristo.address,
            deadline: 9999999999,
            amountIn: utilities.toDecimals(2000, await mainToken.methods.decimals().call()),
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0,
        }).send(blockchainConnection.getSendingOptions({from : actors.Canedicristo.address}))

        await withdrawReward(actors.Canedicristo);
    })

    it("should allow cavicchioli to withdraw liquidity", async() => {
        await catchCall(withdrawLiquidity(actors.Cavicchioli, actors.Cavicchioli.position.liquidityPoolTokenAmount.sub('10000')), "Min stake: cannot remove partial liquidity");
        await withdrawLiquidity(actors.Cavicchioli);
    })
    it("should allow sporco withdraw its reward", async() => {
        await withdrawReward(actors.Sporco);
    });
    it("should allow verme to withdraw reward", async() => {
        await withdrawReward(actors.Verme);
    })
    it("should allow sporco to withdraw liquidity", async() => {
        await withdrawLiquidity(actors.Sporco);
    })
    it("should allow verme to withdraw liquidity", async() => {
        await withdrawLiquidity(actors.Verme);
    })
    it("should allow bestiadidio to withdraw liquidity", async() => {
        await withdrawLiquidity(actors.Bestiadidio);
    })
    it("should allow madonnacagna to withdraw liquidity", async() => {
        await withdrawLiquidity(actors.Madonnacagna);
    })
    it("should allow canedicristo to withdraw liquidity", async() => {
        await withdrawLiquidity(actors.Canedicristo);
    })
    it("should allow cappello to withdraw half liquidity", async() => {
        await withdrawLiquidity(actors.Cappello, web3.utils.toBN(actors.Cappello.position.liquidityPoolTokenAmount).div(web3.utils.toBN(2)).toString());
    });
    it("should allow porco to open a new staking position", async() => {
        await createStakingPosition(actors.Porco, 1);
    });
    it("should allow cappello to withdraw liquidity again", async() => {
        await withdrawLiquidity(actors.Cappello);
    });
    it("minStakeable, should not allow cane to open a new staking position", async() => {
        try {
            await createStakingPosition(actors.Cane, 2);
            assert(false, "This shouldn't happen");
        } catch (e) {
            assert.notStrictEqual((e.message || e).toLowerCase().indexOf("invalid liquidity"), -1, (e.message || e));
        }
    });
    it("should allow the host to increase the reward per block", async() => {
        var updatedSetups = [{
            add: false,
            disable: false,
            index: 1,
            info: {
                blockDuration: 300,
                startBlock: 12613813,
                originalRewardPerBlock: 200,
                minStakeable: 0,
                renewTimes: 1,
                liquidityPoolTokenAddress: univ3PoolAddress,
                mainTokenAddress: setupMainToken !== utilities.voidEthereumAddress ? setupMainToken.options.address : wethToken.options.address,
                involvingETH: mainToken === utilities.voidEthereumAddress || secondaryToken === utilities.voidEthereumAddress,
                setupsCount: 0,
                lastSetupIndex: 0,
                tickLower: -92000,
                tickUpper: 92200
            }
        }];
        await clonedFarmExtension.methods.setFarmingSetups(updatedSetups).send(blockchainConnection.getSendingOptions());
        var { '0': setup, '1': setupInfo } = await farmMainContract.methods.setup(1).call();
        assert.strictEqual(setupInfo.originalRewardPerBlock, "200");
        assert.strictEqual(setup.rewardPerBlock, "200");
    });
    it("no position, should not allow cane to withdraw liquidity", async() => {
        try {
            await withdrawLiquidity(actors.Cane);
            assert(false, "This shouldn't happen");
        } catch (e) {
            assert.notStrictEqual((e.message || e).toLowerCase().indexOf("not owned"), -1, (e.message || e));
        }
    });
    it("should allow ladro to open a new staking position", async() => {
        await createStakingPosition(actors.Ladro, 2);
    });
    it("should allow the host to decrease the reward per block", async() => {
        // ERC20 TEST
        var updatedSetups = [{
            add: false,
            disable: false,
            index: 2,
            info: {
                blockDuration: 30,
                startBlock: 12613812,
                originalRewardPerBlock: utilities.toDecimals("0.03", rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.decimals().call() : 18),
                minStakeable: 0,
                renewTimes: 0,
                liquidityPoolTokenAddress: univ3PoolAddress,
                mainTokenAddress: setupMainToken !== utilities.voidEthereumAddress ? setupMainToken.options.address : wethToken.options.address,
                involvingETH: mainToken === utilities.voidEthereumAddress || secondaryToken === utilities.voidEthereumAddress,
                setupsCount: 0,
                lastSetupIndex: 0,
                tickLower: -92000,
                tickUpper: 92200
            }
        }];

        // ETH TEST
        // var updatedSetups = [
        //     {
        //         add: false,
        //         disable: false,
        //         index: 2,
        //         info: {
        //             blockDuration: 10000000,
        //             startBlock: 12613812,
        //             originalRewardPerBlock: 1,
        //             minStakeable: 1,
        //             renewTimes: 2,
        //             liquidityPoolTokenAddress: "0x8ad599c3a0ff1de082011efddc58f1908eb6e6d8",
        //             mainTokenAddress: mainToken !== utilities.voidEthereumAddress ? mainToken.options.address : wethToken.options.address,
        //             involvingETH: mainToken === utilities.voidEthereumAddress || secondaryToken === utilities.voidEthereumAddress,
        //             setupsCount: 0,
        //             lastSetupIndex: 0,
        //             tickLower: 194700,
        //             tickUpper: 199380,

        //         }
        //     }
        // ];
        /*await clonedFarmExtension.methods.setFarmingSetups(updatedSetups).send(blockchainConnection.getSendingOptions());
        var {'0': setup, '1': setupInfo} = await farmMainContract.methods.setup(2).call();
        assert.strictEqual(setupInfo.originalRewardPerBlock, "1");
        assert.strictEqual(setup.rewardPerBlock, "1");*/
    });
    it("should allow porco to withdraw liquidity", async() => {
        await blockchainConnection.fastForward(800);//to reach setup-disable
        await withdrawLiquidity(actors.Porco);
    });
    it("setup renew, should allow cane to open position", async() => {
        await createStakingPosition(actors.Cane, 3);
    });
    it("should allow ladro to withdraw liquidity", async() => {
        await blockchainConnection.fastForward(300);
        await withdrawLiquidity(actors.Ladro);
    });
    it("should not flush when someone is still inside", async() => {
        try {
            await finalFlush();
            assert(false, "Flush shouldn't happen");
        } catch (e) {
            console.error(e);
            assert.notStrictEqual((e.message || e).toLowerCase().indexOf("not empty"), -1, e.message || e);
        }
    });
    it("should allow cane to withdraw liquidity", async() => {
        await blockchainConnection.fastForward(800);
        await withdrawLiquidity(actors.Cane);
    });
    it("should have 0 reward tokens in the contract, flushing all data", async() => {
        var setups = await farmMainContract.methods.setups().call();
        await Promise.all(setups.map(async(setup, i) => {
            var rewardReceived = await farmMainContract.methods._rewardReceived(i).call();
            var rewardPaid = await farmMainContract.methods._rewardPaid(i).call();
            console.log(`setup ${i} - received: ${rewardReceived} - paid: ${rewardPaid}`);
            assert.strictEqual(parseInt(setup.totalSupply), 0);
            assert.strictEqual(setup.active, false);
            setup.active && console.log("Active", i, setup);
        }))
        var balance = rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.balanceOf(farmMainContract.options.address).call() : await web3.eth.getBalance(farmMainContract.options.address);
        balance !== '0' && await finalFlush();
        balance = balance !== '0' ? rewardToken !== utilities.voidEthereumAddress ? await rewardToken.methods.balanceOf(farmMainContract.options.address).call() : await web3.eth.getBalance(farmMainContract.options.address) : '0';
        assert.strictEqual(parseInt(balance), 0);
    })
})
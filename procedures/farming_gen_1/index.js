var {
    VOID_ETHEREUM_ADDRESS,
    VOID_BYTES32,
    blockchainCall,
    compile,
    deployContract,
    abi,
    formatMoney,
    MAX_UINT256,
    web3Utils,
    fromDecimals,
    toDecimals,
    sendBlockchainTransaction,
    calculateTransactionFee,
} = require("@ethereansos/multiverse");

var misc = require("../misc");

var tokenHolder = "0xCFFAd3200574698b78f32232aa9D63eABD290703";

// Contracts
var FarmingGen1;
var FarmingGen1Extension;

var farmingGen1Contract;
var farmingGen1Extension;
var extensionOwner;

var UniswapV2AMMV1;

var uniswapAMM;
var amm;

// Useful variables
var byMint;
var ethItemOrchestrator;

var uniswapV2Router;
var uniswapV2Factory;

var wethToken;
var rewardToken;
var mainToken;
var secondaryToken;
var setupMainToken;

var tokens = [];

var liquidityPool;
var ethToSpend = 1200;
var farmTokenCollection;
var rewardDestination;
var oneHundred;
var extensionOwner = VOID_ETHEREUM_ADDRESS;
var actors = {};
var zeroBlock;

// UTILITIES FUNCTIONS FOR RUN STAGE
async function getFundsToAccount(token) {
    var addr = setTokenHolderAsFrom(token);
    await blockchainCall(
        await token.methods.transfer,
        tokenHolder,
        toDecimals("30000", await blockchainCall(token.methods.decimals)),
        { from: addr }
    );
}

function setTokenHolderAsFrom(token) {
    addr = VOID_ETHEREUM_ADDRESS;

    if (token.options.address.toLowerCase() == web3.currentProvider.knowledgeBase.usdcTokenAddress.toLowerCase()) {
        addr = "0xCFFAd3200574698b78f32232aa9D63eABD290703";
    } else if (token.options.address.toLowerCase() == web3.currentProvider.knowledgeBase.buidlTokenAddress.toLowerCase()) {
        addr = "0xC51505E383f34019947802CAe02A3432E27e012A";
    } else if (token.options.address.toLowerCase() == web3.currentProvider.knowledgeBase.daiTokenAddress.toLowerCase()) {
        addr = "0x075e72a5eDf65F0A5f44699c7654C1a76941Ddc8";
    }

    assert.notStrictEqual(addr, VOID_ETHEREUM_ADDRESS);
    return addr;
}

async function buyForETH(token, amount, from) {
    var path = [wethToken._address, token.options.address];
    var value = toDecimals(amount.toString(), "18");

    await blockchainCall(
        uniswapV2Router.methods.swapExactETHForTokens,
        1,
        path,
        (from && (from.from || from)) || accounts[0],
        parseInt(new Date().getTime() / 1000 + 1000),
        { from: tokenHolder, value: value }
    );
}

async function initActor(name, address, unwrap, amount, amountIsLiquidityPool) {
    actors[name] = {
        name,
        address,
        from: address,
        unwrap,
        amount,
        amountIsLiquidityPool,
    };

    var amountToTransfer = amount * 2;
    var ethToSpendToTransfer = ethToSpend * 2;

    await blockchainCall(
        await mainToken.methods.transfer,
        address,
        toDecimals(amountToTransfer, await blockchainCall(mainToken.methods.decimals)),
        { from: tokenHolder }
    );
    await blockchainCall(
        await secondaryToken.methods.transfer,
        address,
        toDecimals(amountToTransfer, await blockchainCall(secondaryToken.methods.decimals)),
        { from: tokenHolder }
    );

    mainToken !== VOID_ETHEREUM_ADDRESS &&
        (await buyForETH(mainToken, ethToSpendToTransfer, address));
    secondaryToken !== VOID_ETHEREUM_ADDRESS &&
        (await buyForETH(secondaryToken, ethToSpendToTransfer, address));
}

async function compileContracts() {
    FarmingGen1 = await misc.compileFarmingContract("FarmMainGen1V2", null);
    FarmingGen1Extension = await misc.compileFarmingContract(
        "FarmExtensionGen1",
        null
    );

    UniswapV2AMMV1 = await misc.compileAmmAggregatorContract(
        "UniswapV2AMMV1",
        "models/UniswapV2/1"
    );

    uniswapAMM = await new web3.eth.Contract(
        UniswapV2AMMV1.abi,
        web3.currentProvider.knowledgeBase.uniswapV2AMMPluginAddress
    );
}

async function prepareTokens() {
    var rewardTokenAddress = web3.currentProvider.knowledgeBase.daiTokenAddress;
    rewardToken = new web3.eth.Contract(
        web3.currentProvider.knowledgeBase.IERC20ABI,
        rewardTokenAddress
    );
    mainToken = new web3.eth.Contract(
        web3.currentProvider.knowledgeBase.IERC20ABI,
        web3.currentProvider.knowledgeBase.buidlTokenAddress
    );
    secondaryToken = new web3.eth.Contract(
        web3.currentProvider.knowledgeBase.IERC20ABI,
        web3.currentProvider.knowledgeBase.usdcTokenAddress
    );

    liquidityPool = new web3.eth.Contract(
        web3.currentProvider.knowledgeBase.uniswapV2PairABI,
        await uniswapV2Factory.methods
            .getPair(
                mainToken !== VOID_ETHEREUM_ADDRESS
                    ? mainToken.options.address
                    : wethToken.options.address,
                secondaryToken != VOID_ETHEREUM_ADDRESS
                    ? secondaryToken.options.address
                    : wethToken.options.address
            )
            .call()
    );

    assert.notStrictEqual(mainToken, undefined);
    assert.notStrictEqual(wethToken, undefined);

    mainToken !== VOID_ETHEREUM_ADDRESS &&
        (await buyForETH(mainToken, ethToSpend));
    secondaryToken !== VOID_ETHEREUM_ADDRESS &&
        (await buyForETH(secondaryToken, ethToSpend));

    rewardToken !== VOID_ETHEREUM_ADDRESS &&
        (await buyForETH(rewardToken, ethToSpend));

    setupMainToken = mainToken === VOID_ETHEREUM_ADDRESS ? wethToken : mainToken;

    assert.notStrictEqual(setupMainToken, undefined);

    assert.equal(
        mainToken.options.address.toLowerCase(),
        web3.currentProvider.knowledgeBase.buidlTokenAddress.toLowerCase()
    );
    assert.equal(
        secondaryToken.options.address.toLowerCase(),
        web3.currentProvider.knowledgeBase.usdcTokenAddress.toLowerCase()
    );
    assert.notStrictEqual(liquidityPool, VOID_ETHEREUM_ADDRESS);
}

async function deployFactoryAndExtensions() {
    farmingGen1Contract = await deployContract(
        new web3.eth.Contract(FarmingGen1.abi),
        FarmingGen1.bin
    );
    console.log(`Farming deployed at ${farmingGen1Contract.options.address}`);

    farmingGen1Extension = await deployContract(
        new web3.eth.Contract(FarmingGen1Extension.abi),
        FarmingGen1Extension.bin
    );
    console.log(
        `Farming extension model deployed at ${farmingGen1Extension.options.address}`
    );
}

async function deploySimplefarmingGen1Contract() {
    var currentBlock = await web3.eth.getBlock(await web3.eth.getBlockNumber());
    var currentTimestamp = currentBlock.timestamp;
    var setups = [
        [
            true,
            100 * misc.TIME_SLOTS_IN_SECONDS,
            0 * misc.TIME_SLOTS_IN_SECONDS,
            "500000000000000000",
            "1000000000000000000",
            0,
            0,
            uniswapAMM.options.address,
            liquidityPool.options.address,
            mainToken !== VOID_ETHEREUM_ADDRESS
                ? mainToken.options.address
                : wethToken.options.address,
            wethToken.options.address,
            mainToken === VOID_ETHEREUM_ADDRESS ||
            secondaryToken === VOID_ETHEREUM_ADDRESS,
            0,
            0,
            0,
        ],
        [
            true,
            50 * misc.TIME_SLOTS_IN_SECONDS,
            0 * misc.TIME_SLOTS_IN_SECONDS,
            "500000000000000000",
            "1000000000000000000",
            "2500000000000000000000",
            0,
            uniswapAMM.options.address,
            liquidityPool.options.address,
            mainToken !== VOID_ETHEREUM_ADDRESS
                ? mainToken.options.address
                : wethToken.options.address,
            wethToken.options.address,
            mainToken === VOID_ETHEREUM_ADDRESS ||
            secondaryToken === VOID_ETHEREUM_ADDRESS,
            0,
            0,
            0,
        ],
    ];

    var types = ["bytes", "address", "bytes"];
    var params = [
        farmingGen1Extension.methods
            .init(false, extensionOwner, VOID_ETHEREUM_ADDRESS)
            .encodeABI(),
        rewardToken !== VOID_ETHEREUM_ADDRESS
            ? rewardToken.options.address
            : VOID_ETHEREUM_ADDRESS,
        abi.encode(
            [
                "tuple(bool,uint256,uint256,uint256,uint256,uint256,uint256,address,address,address,address,bool,uint256,uint256,uint256)[]",
            ],
            [setups]
        ),
    ];

    var payload = web3.eth.abi.encodeParameters(types, params);
    payload = web3.eth.abi.encodeParameters(
        ["address", "bytes"],
        [farmingGen1Extension.options.address, payload]
    );

    var deployTransaction = await blockchainCall(
        farmingGen1Contract.methods.lazyInit,
        payload,
        { from: tokenHolder }
    );
    assert.notStrictEqual(
        farmingGen1Contract.options.address,
        VOID_ETHEREUM_ADDRESS
    );
    oneHundred = await blockchainCall(farmingGen1Contract.methods.ONE_HUNDRED);

    var availableSetups = await blockchainCall(
        farmingGen1Contract.methods.setups
    );
    assert.strictEqual(availableSetups.length, setups.length);

    // put reward in the extension
    if (rewardToken !== VOID_ETHEREUM_ADDRESS) {
        var addr = setTokenHolderAsFrom(rewardToken);
        await buyForETH(rewardToken, 20000);
        await blockchainCall(
            await rewardToken.methods.transfer,
            farmingGen1Extension._address,
            toDecimals("15000", await blockchainCall(rewardToken.methods.decimals)),
            { from: addr }
        );
        console.log(
            "farmingGen1Extension._address balanceOf rewardToken: " +
            (await blockchainCall(
                rewardToken.methods.balanceOf,
                farmingGen1Extension._address
            ))
        );
    } else {
        await sendBlockchainTransaction(
            web3.currentProvider,
            accounts[0],
            farmingGen1Extension._address,
            "0x",
            toDecimals(20000, 18)
        );
    }

    // FIXME
    // farmTokenCollection = new web3.eth.Contract(web3.currentProvider.knowledgeBase.INativeV1ABI, await blockchainCall(farmingGen1Contract.methods._farmTokenCollection));
}

module.exports = async function run() {
    debugger;
    console.log("===========================================================");
    console.log("* MULTIVERSE - run() - started *");

    console.log("");
    console.group("Initializing the environment...");
    console.log("Creating contracts objects...");
    ethItemOrchestrator = misc.deployEthItemOrchestrator();
    uniswapV2Router = misc.deployUniswapV2Router();
    uniswapV2Factory = misc.deployUniswapV2Factory();
    wethToken = await misc.deployWethTokenWithUniswapV2(uniswapV2Router);
    console.groupEnd();
    console.log("");

    console.group("Creating accounts...");
    extensionOwner = accounts[0];
    console.log("extensionOwner done...");
    console.groupEnd();
    console.log("");

    console.group("Preparing contracts...");
    console.log("Compiling...");
    await compileContracts();
    console.groupEnd();
    console.log("");

    console.log("Preparing tokens.....");
    await prepareTokens();
    console.groupEnd();
    console.log("");

    var res = await blockchainCall(
        uniswapAMM.methods.byLiquidityPool,
        liquidityPool.options.address
    );

    console.group("Unlocking...");
    var addr = setTokenHolderAsFrom(mainToken);
    await web3.currentProvider.unlockAccounts(addr);
    console.log(addr + " unlocked...");
    addr = setTokenHolderAsFrom(secondaryToken);
    await web3.currentProvider.unlockAccounts(addr);
    console.log(addr + " unlocked...");
    addr = setTokenHolderAsFrom(rewardToken);
    await web3.currentProvider.unlockAccounts(addr);
    console.log(addr + " unlocked...");
    console.groupEnd();
    console.log("");

    console.group("Getting funds to tokenHolder...");
    await getFundsToAccount(mainToken);
    await getFundsToAccount(secondaryToken);
    await getFundsToAccount(rewardToken);
    console.groupEnd();
    console.log("");

    tokens = [VOID_ETHEREUM_ADDRESS, mainToken, rewardToken, liquidityPool];

    console.group("Creating actors...");
    await initActor("Alice", accounts[1], true, 500, false);
    console.log("Alice done...");
    await initActor("Bob", accounts[2], true, 100, false);
    console.log("Bob done...");
    await initActor("Carol", accounts[3], false, 500, false);
    console.log("Carol done...");
    await initActor("David", accounts[4], false, 50, false);
    console.log("David done...");
    await initActor("Eve", accounts[5], false, 75, false);
    console.log("Eve done...");
    await initActor("Frank", accounts[6], false, 50, false);
    console.log("Frank done...");
    await initActor("Grace", accounts[7], false, 50, false);
    console.log("Grace done...");
    await initActor("Heidi", accounts[8], false, 50, false);
    console.log("Heidi done...");
    await initActor("Isaac", accounts[9], false, 50, false);
    console.log("Isaac done...");
    await initActor("John", accounts[10], false, 50, false);
    console.log("John done...");
    console.groupEnd();
    console.log("");


    console.group("Deploying farm factory, extensions and finalize proposals...");
    await deployFactoryAndExtensions();
    console.groupEnd();
    console.log("");

    console.group("Deploying simple farm main contract...");
    await deploySimplefarmingGen1Contract();
    console.groupEnd();
    console.log("");



    console.log("* MULTIVERSE - run() - finished *");
    console.log("===========================================================");
};

// TEST FUNCTIONS

async function shouldActivateSetup() {
    await blockchainCall(farmingGen1Contract.methods.activateSetup, 0, { from: tokenHolder });
    await blockchainCall(farmingGen1Contract.methods.activateSetup, 1, { from: tokenHolder });
    var availableSetups = await farmingGen1Contract.methods.setups().call();
    await Promise.all(
        availableSetups.map(async (setup) => {
            assert.strictEqual(setup.active, true);
        })
    );
}

async function shouldNotActivateNotExistingSetup() {
    await assert.catchCall(
        blockchainCall(farmingGen1Contract.methods.activateSetup, 2, { from: tokenHolder }),
        "invalid toggle"
    );
}

async function createStakingPosition(actor, setupIndex, mainTokenAmount) {
    (mainToken !== VOID_ETHEREUM_ADDRESS) &&
        await blockchainCall(
            mainToken.methods.approve,
            farmingGen1Contract.options.address,
            await mainToken.methods.totalSupply().call(),
            { from: actor.from }
        );
    (secondaryToken !== VOID_ETHEREUM_ADDRESS) &&
        await blockchainCall(
            secondaryToken.methods.approve, farmingGen1Contract.options.address,
            await secondaryToken.methods.totalSupply().call(),
            { from: actor.from }
        );
    mainTokenAmount = toDecimals(actor.amount, mainToken !== VOID_ETHEREUM_ADDRESS ? await mainToken.methods.decimals().call() : 18);

    var stake = {
        setupIndex,
        amount: mainTokenAmount,
        amountIsLiquidityPool: actor.amountIsLiquidityPool || false,
        positionOwner: VOID_ETHEREUM_ADDRESS,
        amount0Min: 0,
        amount1Min: 0
    };

    var setups = await farmingGen1Contract.methods.setups().call();
    var setup = setups[setupIndex];
    var setupInfo = (await farmingGen1Contract.methods.setup(setup.infoIndex).call())[1]; //FarmingSetupInfo

    var ammPlugin = new web3.eth.Contract(UniswapV2AMMV1.abi, setupInfo.ammPlugin);

    var liquidityPool = new web3.eth.Contract(web3.currentProvider.knowledgeBase.UniswapV3PoolABI, setupInfo.liquidityPoolTokenAddress);
    var liquidityPoolTokenAddress = setupInfo.liquidityPoolTokenAddress;

    var tokens = (await blockchainCall(ammPlugin.methods.byLiquidityPool, liquidityPoolTokenAddress))[2];

    var secondaryTokenIndex = tokens[0] === (secondaryToken != VOID_ETHEREUM_ADDRESS ? secondaryToken.options.address : wethToken.options.address) ? 0 : 1;

    var amounts = await blockchainCall(ammPlugin.methods.byTokenAmount, liquidityPoolTokenAddress, mainToken !== VOID_ETHEREUM_ADDRESS ? mainToken.options.address : wethToken.options.address, mainTokenAmount);
    var secondaryTokenAmount = amounts[1][secondaryTokenIndex];

    if (actor.amountIsLiquidityPool) {
        if (mainToken !== VOID_ETHEREUM_ADDRESS)
            await blockchainCall(mainToken.methods.approve, uniswapV2Router.options.address, await mainToken.methods.totalSupply(), { from: actor.from });
        if (secondaryToken !== VOID_ETHEREUM_ADDRESS)
            await blockchainCall(secondaryToken.methods.approve, uniswapV2Router.options.address, await secondaryToken.methods.totalSupply(), { from: actor.from });
        if (mainToken !== VOID_ETHEREUM_ADDRESS && secondaryToken !== VOID_ETHEREUM_ADDRESS) {
            try {
                await blockchainCall(uniswapV2Router.methods.addLiquidity,
                    mainToken !== VOID_ETHEREUM_ADDRESS ? mainToken.options.address : wethToken.options.address,
                    secondaryToken !== VOID_ETHEREUM_ADDRESS ? secondaryToken.options.address : wethToken.options.address,
                    mainTokenAmount,
                    secondaryTokenAmount,
                    1,
                    1,
                    actor.address,
                    // FIXME
                    (await web3.eth.getBlock(await web3.eth.getBlockNumber())).timestamp + 10000,
                    { from: actor.from }
                );
            } catch (error) {
                console.error(error);
            }
        } else {
            await blockchainCall(uniswapV2Router.methods.addLiquidityETH,
                secondaryToken !== VOID_ETHEREUM_ADDRESS ? secondaryToken.options.address : mainToken.options.address,
                secondaryToken !== VOID_ETHEREUM_ADDRESS ? secondaryTokenAmount : mainTokenAmount,
                1,
                1,
                actor.address,
                // FIXME
                (await web3.eth.getBlock(await web3.eth.getBlockNumber())).timestamp + 10000,
                {  from: actor.from, value: secondaryToken !== VOID_ETHEREUM_ADDRESS ? mainTokenAmount : secondaryTokenAmount }
            );
        }

        var liquidityPoolTokenContract = new web3.eth.Contract(web3.currentProvider.knowledgeBase.IERC20ABI, liquidityPoolTokenAddress);
        await blockchainCall(liquidityPoolTokenContract.methods.approve, farmingGen1Contract.options.address, await liquidityPoolTokenContract.methods.totalSupply(), { from: actor.from });
        stake.amount = await blockchainCall(liquidityPoolTokenContract.methods.balanceOf, actor.address);
        console.table(stake);
    }

    var result = await blockchainCall(
        farmingGen1Contract.methods.openPosition,
        stake,
        { from: actor.from, value: (!stake.amountIsLiquidityPool && setupInfo.involvingETH) ? mainToken === setupInfo.ethereumAddress ? mainTokenAmount : secondaryTokenAmount : 0 }
    );

    const eventAbi = farmingGen1Contract.abi.find((abi) => abi.type === "event" && abi.name === "Transfer");

    var event_emitted = misc.EVENT.NOT_EMITTED;
    var positionId = 0;

    for (var i = 0; i < result.logs.length; i++) {
        if (eventAbi.signature != result.logs[i].topics[0]) continue;
        event_emitted = misc.EVENT.EMITTED;
        const decodedLog = web3.eth.abi.decodeLog(
            eventAbi.inputs,
            result.logs[i].data,
            result.logs[i].topics.slice(1)
        );
        positionId = decodedLog.positionId;
    }

    if (positionId == 0) event_emitted = misc.EVENT.NOT_EMITTED;

    var position = await blockchainCall(farmingGen1Contract.methods.position, positionId);

    actor.setupIndex = setupIndex;
    actor.position = position;
    actor.positionId = positionId;
    console.log("POSITION CREATED FOR", actor.name);

    var setup = (await farmingGen1Contract.methods.setups().call())[setupIndex];

    actor.objectId = setup.objectId;
    assert.strictEqual(setup.lastUpdateEvent, position.creationEvent);
}

async function addLiquidity(actor) {

    var startingSetup = (await farmingGen1Contract.methods.setups().call())[actor.setupIndex];
    var startingPosition = await blockchainCall(farmingGen1Contract.methods.position, actor.positionId);

    var mainTokenAmount = toDecimals(actor.amount, mainToken != VOID_ETHEREUM_ADDRESS ? await mainToken.methods.decimals().call() : 18);
    var { '0': _, '1': setupInfo } = await farmingGen1Contract.methods.setup(actor.setupIndex).call();
    var ammPlugin = new web3.eth.Contract(UniswapV2AMMV1.abi, setupInfo.ammPlugin);
    var liquidityPoolTokenAddress = setupInfo.liquidityPoolTokenAddress;
    var tokens = (await blockchainCall(ammPlugin.methods.byLiquidityPool, liquidityPoolTokenAddress))[2];
    var secondaryTokenIndex = tokens[0] === (secondaryToken != VOID_ETHEREUM_ADDRESS ? secondaryToken.options.address : wethToken.options.address) ? 0 : 1;
    var amounts = await blockchainCall(
        ammPlugin.methods.byTokenAmount,
        liquidityPoolTokenAddress,
        mainToken != VOID_ETHEREUM_ADDRESS ? mainToken.options.address : wethToken.options.address, mainTokenAmount
    );
    var secondaryTokenAmount = amounts[1][secondaryTokenIndex];

    var stake = {
        setupIndex: actor.setupIndex,
        amount: mainTokenAmount,
        amountIsLiquidityPool: actor.amountIsLiquidityPool || false,
        positionOwner: VOID_ETHEREUM_ADDRESS,
        amount0Min: 0,
        amount1Min: 0
    };

    await blockchainCall(
        farmingGen1Contract.methods.addLiquidity,
        actor.positionId,
        stake,
        { from: actor.from, value: (!stake.amountIsLiquidityPool && setupInfo.involvingETH) ? mainToken === VOID_ETHEREUM_ADDRESS ? mainTokenAmount : secondaryTokenAmount : 0 }
    );
    var endingSetup = (await farmingGen1Contract.methods.setups().call())[actor.setupIndex];
    var endingPosition = await blockchainCall(farmingGen1Contract.methods.position, actor.positionId);
    assert.strictEqual(parseInt(startingPosition.liquidityPoolTokenAmount) * 2, parseInt(endingPosition.liquidityPoolTokenAmount));
    assert.strictEqual(parseInt(endingSetup.totalSupply), parseInt(startingSetup.totalSupply) + (parseInt(endingPosition.liquidityPoolTokenAmount) - parseInt(startingPosition.liquidityPoolTokenAmount)));
    actor.position = endingPosition;
}

async function withdrawReward(actor, seconds) {

    var balance = rewardToken !== VOID_ETHEREUM_ADDRESS ?
        await rewardToken.methods.balanceOf(farmingGen1Contract.options.address).call() : await web3.eth.getBalance(farmingGen1Contract.options.address);
    console.log(`farm main balance is ${balance}`);
    var setup = (await farmingGen1Contract.methods.setups().call())[actor.setupIndex];
    var currentBlock = await web3.eth.getBlock(await web3.eth.getBlockNumber());
    var currentTimestamp = currentBlock.timestamp;
    var nextTimestamp = parseInt(currentTimestamp) + seconds || parseInt(setup.endEvent);
    await web3.currentProvider.setNextBlockTime(nextTimestamp);

    var startingBalance = rewardToken !== VOID_ETHEREUM_ADDRESS ? await rewardToken.methods.balanceOf(actor.from).call() : await web3.eth.getBalance(actor.from);

    var result = await blockchainCall(farmingGen1Contract.methods.withdrawReward, actor.positionId, { from: actor.from });
    var fee = await calculateTransactionFee(result);
    console.log(`fee is ${fee}`);

    setup = (await farmingGen1Contract.methods.setups().call())[actor.setupIndex];

    var resultBalance = rewardToken !== VOID_ETHEREUM_ADDRESS ? await rewardToken.methods.balanceOf(actor.from).call() : await web3.eth.getBalance(actor.from);

    console.log(`exit event is ${setup.lastUpdateEvent}`);
    console.log(`starting balance is ${startingBalance}`);
    console.log(`result balance is ${resultBalance}`);

    var diffBalance = parseInt(resultBalance) - parseInt(startingBalance);
    console.log(`diffBalance balance is ${diffBalance}`);
    var reward = actor.position.reward;
    console.log(`reward balance is ${reward}`);
    assert.strictEqual(
        formatMoney(fromDecimals(diffBalance, rewardToken !== VOID_ETHEREUM_ADDRESS ? await rewardToken.methods.decimals().call() : 18), 4),
        formatMoney(fromDecimals(reward, rewardToken !== VOID_ETHEREUM_ADDRESS ? await rewardToken.methods.decimals().call() : 18), 4)
    );

}

async function disableSetup(index) {
    var updatedSetups = [
        {
            add: false,
            disable: true,
            index: index,
            info: {
                free: true,
                eventDuration: 0,
                startEvent: 0,
                originalRewardPerEvent: 0,
                minStakeable: 0,
                maxStakeable: 0,
                renewTimes: 0,
                ammPlugin: VOID_ETHEREUM_ADDRESS,
                liquidityPoolTokenAddress: VOID_ETHEREUM_ADDRESS,
                mainTokenAddress: VOID_ETHEREUM_ADDRESS,
                ethereumAddress: VOID_ETHEREUM_ADDRESS,
                involvingETH: false,
                penaltyFee: 0,
                setupsCount: 0,
                lastSetupIndex: 0,
            }
        }
    ];
    await blockchainCall(farmingGen1Extension.methods.setFarmingSetups, updatedSetups);
    var setups = await farmingGen1Contract.methods.setups().call();
    var setup = setups[index];
    assert.strictEqual(setup.active, false);
}

async function addNewFreeSetup() {
    var startingInfoCount = await farmingGen1Contract.methods._farmingSetupsInfoCount().call();
    var updatedSetups = [
        {
            add: true,
            disable: false,
            index: 0,
            info: {
                free: true,
                eventDuration: 100,
                startEvent: 0,
                originalRewardPerEvent: "500000000000000000",
                minStakeable: "1000000000000000000",
                maxStakeable: 0,
                renewTimes: 2,
                ammPlugin: uniswapAMM.options.address,
                liquidityPoolTokenAddress: liquidityPool.options.address,
                mainTokenAddress: mainToken !== VOID_ETHEREUM_ADDRESS ? mainToken.options.address : wethToken.options.address,
                ethereumAddress: wethToken.options.address,
                involvingETH: mainToken === VOID_ETHEREUM_ADDRESS || secondaryToken === VOID_ETHEREUM_ADDRESS,
                penaltyFee: 0,
                setupsCount: 0,
                lastSetupIndex: 0,
            }
        }
    ];
    await blockchainCall(farmingGen1Extension.methods.setFarmingSetups, updatedSetups);
    var infoCount = await farmingGen1Contract.methods._farmingSetupsInfoCount().call();
    assert.strictEqual(parseInt(infoCount), parseInt(startingInfoCount) + 1);
}

// async function withdrawLiquidity(actor, amount, jump) {
//     var positionLiquidityPoolTokenAmount = actor.position.liquidityPoolTokenAmount;
//     if (!amount) amount = positionLiquidityPoolTokenAmount;
//     var startingFarmTokenBalance = actor.free ? 0 : await farmTokenCollection.methods.balanceOf(actor.address, actor.objectId).call();
//     if (jump) {
//         var setup = (await farmMainContract.methods.setups().call())[actor.setupIndex];
//         await blockchainConnection.jumpToBlock(parseInt(setup.endBlock) + 1);
//     }
//     await farmMainContract.methods.withdrawLiquidity(actor.free ? actor.positionId : 0, !actor.free ? actor.objectId : 0, actor.unwrap, amount).send(actor.from);
//     var endFarmTokenBalance = actor.free ? 0 : await farmTokenCollection.methods.balanceOf(actor.address, actor.objectId).call();
//     if (amount === actor.position.liquidityPoolTokenAmount || actor.free) {
//         var position = await farmMainContract.methods.position(actor.positionId).call();
//         if (actor.free && amount === actor.position.liquidityPoolTokenAmount) {
//             assert.strictEqual(parseInt(position.creationBlock), 0);
//         } else if (actor.free) {
//             assert.strictEqual(utilities.fromDecimals(parseInt(position.liquidityPoolTokenAmount), 18), utilities.fromDecimals(parseInt(positionLiquidityPoolTokenAmount) - parseInt(amount), 18));
//             actor.position = position;
//         }
//         assert.strictEqual(parseInt(endFarmTokenBalance), 0);
//     } else {
//         assert.strictEqual(parseInt(endFarmTokenBalance), parseInt(startingFarmTokenBalance) - parseInt(amount));
//     }
// }

module.exports.test = async function test() {
    console.log("* MULTIVERSE - test() started *");

    console.group("Should activate both the setups");
    await shouldActivateSetup();
    console.groupEnd();
    console.log("");

    console.group("Should not activate a non existing setup info");
    await shouldNotActivateNotExistingSetup();
    console.groupEnd();
    console.log("");

    console.group("Should allow " + actors.Alice.name + " to open a new staking position");
    {
        await createStakingPosition(actors.Alice, 1);
        console.groupEnd();
        console.log("");
    }

    // console.group("Should allow " + actors.Bob.name + " to open a new staking position");
    // {
    //     await createStakingPosition(actors.Bob, 1);
    //     console.groupEnd();
    //     console.log("");
    // }

    // console.group("Should allow " + actors.Carol.name + " to open a new staking position");
    // {
    //     await createStakingPosition(actors.Carol, 1);
    //     console.groupEnd();
    //     console.log("");
    // }
    // console.group("Should allow " + actors.David.name + " to open a new staking position");
    // {
    //     await createStakingPosition(actors.David, 0);
    //     console.groupEnd();
    //     console.log("");
    // }
    // console.group("Should allow " + actors.Eve.name + " to open a new staking position");
    // {
    //     await createStakingPosition(actors.Eve, 0);
    //     console.groupEnd();
    //     console.log("");
    // }
    // console.group("Should allow " + actors.Frank.name + " to open a new staking position");
    // {
    //     await createStakingPosition(actors.Frank, 0);
    //     console.groupEnd();
    //     console.log("");
    // }

    // FIXME asserts fail if other actors open position with same index
    console.group("Should allow " + actors.Alice.name + " to add liquidity");
    await addLiquidity(actors.Alice);
    console.groupEnd();
    console.log("");

    console.group("Should allow the host to disable the free setup");
    await disableSetup(1);
    console.groupEnd();
    console.log("");

    console.group("Should allow the host to add a new free setup");
    await addNewFreeSetup();
    console.groupEnd();
    console.log("");

    console.group("Should activate the new setup");
    await blockchainCall(farmingGen1Contract.methods.activateSetup, 2, { from: tokenHolder });
    var setups = await farmingGen1Contract.methods.setups().call();
    var setup = setups[2];
    assert.strictEqual(setup.active, true);
    console.groupEnd();
    console.log("");


    console.group("Should allow " + actors.Alice.name + " to withdraw");
    await withdrawReward(actors.Alice, 5 * misc.TIME_SLOTS_IN_SECONDS);
    console.groupEnd();
    console.log("");

    // console.group("Should allow " + actors.Bob.name + " to withdraw");
    // await withdrawReward(actors.Alice, 3 * misc.TIME_SLOTS_IN_SECONDS);
    // console.groupEnd();
    // console.log("");

    // console.group("Should allow " + actors.Carol.name + " to withdraw");
    // await withdrawReward(actors.Alice, 5 * misc.TIME_SLOTS_IN_SECONDS);
    // console.groupEnd();
    // console.log("");

    // console.group("Should allow " + actors.Alice.name + " to withdraw liquidity");
    // await withdrawLiquidity(actors.Alice);
    // await withdrawReward(actors.Alice);
    // console.groupEnd();
    // console.log("");



    console.log("* MULTIVERSE - test() - finished *");
};

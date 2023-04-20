var {
    VOID_ETHEREUM_ADDRESS,
    VOID_BYTES32,
    blockchainCall,
    compile,
    deployContract,
    abi,
    MAX_UINT256,
    web3Utils,
    fromDecimals,
    toDecimals,
    sendBlockchainTransaction,
    calculateTransactionFee,
} = require("@ethereansos/multiverse");

var misc = require("../misc");

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
var ethToSpend = 600;
var farmTokenCollection;
var rewardDestination;
var oneHundred;
var extensionOwner = VOID_ETHEREUM_ADDRESS;
var actors = {};
var zeroBlock;

// UTILITIES FUNCTIONS FOR RUN STAGE
async function buyForETH(token, amount, from) {
    var path = [wethToken._address, token.options.address];
    var value = toDecimals(amount.toString(), "18");
    await blockchainCall(
        uniswapV2Router.methods.swapExactETHForTokens,
        1,
        path,
        (from && (from.from || from)) || accounts[0],
        parseInt(new Date().getTime() / 1000 + 1000),
        { value: value }
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

    mainToken !== VOID_ETHEREUM_ADDRESS &&
        (await buyForETH(mainToken, ethToSpend, address));
    secondaryToken !== VOID_ETHEREUM_ADDRESS &&
        (await buyForETH(secondaryToken, ethToSpend, address));
}

async function compileContracts() {
    FarmingGen1 = await misc.compileFarmingContract("FarmingGen1", "gen1/impl");
    FarmingGen1Extension = await misc.compileFarmingContract(
        "FarmingGen1Extension",
        "gen1/impl"
    );

    UniswapV2AMMV1 = await misc.compileAmmAggregatorContractImpl(
        "UniswapV2BasedAMMV1",
        "impl"
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

async function deploySimpleFarmMainContract() {
    var currentBlock = await web3.eth.getBlock(await web3.eth.getBlockNumber());
    var currentTimestamp = currentBlock.timestamp;
    // startEvent : (parseInt(currentTimestamp) + (30 * misc.TIME_SLOTS_IN_SECONDS))
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
            true, // FIXME it was false
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
        payload
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
        await buyForETH(rewardToken, 20000);
        await blockchainCall(
            await rewardToken.methods.transfer,
            farmingGen1Extension._address,
            toDecimals("15000", await blockchainCall(rewardToken.methods.decimals))
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

    // FIXME farmTokenCollection = new web3.eth.Contract(context.INativeV1ABI, await farmingGen1Contract.methods._farmTokenCollection().call());
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

    console.group("Deploying farm factory, extensions and finalize proposals...");
    await deployFactoryAndExtensions();
    console.groupEnd();
    console.log("");

    console.group("Deploying simple farm main contract...");
    await deploySimpleFarmMainContract();
    console.groupEnd();
    console.log("");

    console.log("* MULTIVERSE - run() - finished *");
    console.log("===========================================================");
};

// UTILITIES FUNCTIONS FOR TEST STAGE


// TEST FUNCTIONS

async function shouldActiveSetup() {
    await blockchainCall(farmingGen1Contract.methods.activateSetup, 0);
    await blockchainCall(farmingGen1Contract.methods.activateSetup, 1);
    var availableSetups = await farmingGen1Contract.methods.setups().call();
    await Promise.all(
        availableSetups.map(async (setup) => {
            assert.strictEqual(setup.active, true);
        })
    );
}

async function shouldNotActivateNotExistingSetup() {
    await assert.catchCall(
        blockchainCall(farmingGen1Contract.methods.activateSetup, 2),
        "invalid toggle"
    );
}

async function createStakingPosition(actor, setupIndex, mainTokenAmount) {
    (mainToken !== VOID_ETHEREUM_ADDRESS) &&
        await blockchainCall(
            mainToken.methods.approve, farmingGen1Contract.options.address,
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
        if (mainToken !== VOID_ETHEREUM_ADDRESS) await blockchainCall(mainToken.methods.approve, uniswapV2Router.options.address, await mainToken.methods.totalSupply(), { from: actor.from });
        if (secondaryToken !== VOID_ETHEREUM_ADDRESS) await await blockchainCall(secondaryToken.methods.approve, uniswapV2Router.options.address, await secondaryToken.methods.totalSupply(), { from: actor.from });
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
                (await web3.eth.getBlock(await web3.eth.getBlockNumber())).timestamp + 10000,
                { ...actor.from, value: secondaryToken !== VOID_ETHEREUM_ADDRESS ? mainTokenAmount : secondaryTokenAmount }
            );
        }

        var liquidityPoolTokenContract = new web3.eth.Contract(web3.currentProvider.knowledgeBase.IERC20ABI, liquidityPoolTokenAddress);
        await blockchainCall(liquidityPoolTokenContract.methods.approve, farmingGen1Contract.options.address, await liquidityPoolTokenContract.methods.totalSupply(), { from: actor.from });
        stake.amount = await blockchainCall(liquidityPoolTokenContract.methods.balanceOf, actor.address);
    }

    console.log("-------------- stake ---------------");
    console.table(stake);
    console.log("-------------- actor.from ---------------");
    console.log(actor.from);
    console.log("-------------- value ---------------");
    console.log((!stake.amountIsLiquidityPool && setupInfo.involvingETH) ? mainToken === setupInfo.ethereumAddress ? mainTokenAmount : secondaryTokenAmount : 0);

    // FIXME
    // var result = await blockchainCall(farmingGen1Contract.methods.openPosition, stake,
    //     { ...actor.from, value: (!stake.amountIsLiquidityPool && setupInfo.involvingETH) ? mainToken === setupInfo.ethereumAddress ? mainTokenAmount : secondaryTokenAmount : 0}
    //     );
    // var { positionId } = result.events.Transfer.returnValues;
    // var position = await loadPosition(positionId);

    // actor.setupIndex = setupIndex;
    // actor.position = position;
    // actor.positionId = positionId;
    // console.log("POSITION CREATED FOR ", actor.name);

    // setup = (await farmingGen1Contract.methods.setups().call())[setupIndex];
    // actor.objectId = setup.objectId;
    // assert.strictEqual(setup.lastUpdateEvent, position.creationEvent);
}

module.exports.test = async function test() {
    console.log("* MULTIVERSE - test() started *");

    console.group("Should activate both the setups");
    await shouldActiveSetup();
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

    console.log("* MULTIVERSE - test() - finished *");
};

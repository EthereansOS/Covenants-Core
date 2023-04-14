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
} = require('@ethereansos/multiverse');
var buildOSStuff = require('../../resources/OS/buildOsStuff');
var fs = require('fs');
var misc = require("../misc");
var path = require('path');

var isTesthETH = true;
var printABI = false;

var FarmMain;
var farmMainContract;
var farmMainModel;

var FarmFactory;
var FarmExtension;

var farmMainExtension;

var UniswapV2AMMV1;
var UniswapV3AMMV1;

var uniswapAMM;
var amm;

var uniswapV2Router;
var uniswapV2Factory;
var uniswapV3Pool;
var swapRouter;

var liquidityPool;
var actors = {};
var ethToSpend = 90;
var wethToken;
var rewardToken;
var mainToken;
var secondaryToken;
var setupMainToken;
var rewardDestination;

var univ3PoolAddress = "0xccc42cf5d6a2f3ed8f948541455950ed6ce14707";

async function compileContracts() {
  FarmMain = await misc.compileFarmingContract("FarmMainRegularMinStake", null);
  FarmFactory = await misc.compileFarmingContract("FarmFactory", null);
  FarmExtension = await misc.compileFarmingContract("FarmExtension", null);
  DFOBasedFarmExtensionFactory = await misc.compileFarmingContract("DFOBasedFarmExtensionFactory", "dfo");
  DFOBasedFarmExtension = await misc.compileFarmingContract("DFOBasedFarmExtension", "dfo");

  UniswapV2AMMV1 = await misc.compileAmmAggregatorContract("UniswapV2AMMV1", "models/UniswapV2/1");
  UniswapV3AMMV1 = await misc.compileAmmAggregatorContract("UniswapV3AMMV1", "models/UniswapV3/1");

  uniswapAMM = await deployContract(new web3.eth.Contract(UniswapV3AMMV1.abi), UniswapV3AMMV1.bin,
    [
      web3.currentProvider.knowledgeBase.swapRouterAddress,
      web3.currentProvider.knowledgeBase.uniswapV3NonfungiblePositionManagerAddress,
      web3.currentProvider.knowledgeBase.uniswapV3QuoterAddress,
      "0".toDecimals(18)
    ]
  );
  amm = uniswapAMM;
}

async function createContractsObjects() {
  uniswapV3NonfungiblePositionManager = new web3.eth.Contract((await compile('../node_modules/@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager')).abi, web3.currentProvider.knowledgeBase.uniswapV3NonfungiblePositionManagerAddress);
}

async function prepareTokens() {
  var rewardTokenAddress = web3.currentProvider.knowledgeBase.osTokenAddress;
  rewardToken = new web3.eth.Contract(web3.currentProvider.knowledgeBase.IERC20ABI, rewardTokenAddress);

  if (isTesthETH) {
    mainToken = new web3.eth.Contract(web3.currentProvider.knowledgeBase.IERC20ABI, web3.currentProvider.knowledgeBase.osTokenAddress);
    secondaryToken = VOID_ETHEREUM_ADDRESS;

    assert.equal(secondaryToken, "0x0000000000000000000000000000000000000000");
  } else {
    mainToken = new web3.eth.Contract(web3.currentProvider.knowledgeBase.IERC20ABI, web3.currentProvider.knowledgeBase.osTokenAddress);
    secondaryToken = new web3.eth.Contract(web3.currentProvider.knowledgeBase.IERC20ABI, web3.currentProvider.knowledgeBase.usdcTokenAddress);

    assert.equal(secondaryToken.options.address.toLowerCase(), web3.currentProvider.knowledgeBase.usdcTokenAddress.toLowerCase());
  }

  var wethTokenAddress = await uniswapV2Router.methods.WETH().call();
  wethToken = new web3.eth.Contract(web3.currentProvider.knowledgeBase.IERC20ABI, wethTokenAddress);

  liquidityPool = new web3.eth.Contract(web3.currentProvider.knowledgeBase.uniswapV2PairABI, await uniswapV2Factory.methods.getPair(mainToken !== VOID_ETHEREUM_ADDRESS ? mainToken.options.address : wethToken.options.address, secondaryToken != VOID_ETHEREUM_ADDRESS ? secondaryToken.options.address : wethToken.options.address).call());

  mainToken !== VOID_ETHEREUM_ADDRESS && await buyForETH(mainToken, ethToSpend);
  secondaryToken !== VOID_ETHEREUM_ADDRESS && await buyForETH(secondaryToken, ethToSpend);

  rewardToken !== VOID_ETHEREUM_ADDRESS && await buyForETH(rewardToken, ethToSpend);

  setupMainToken = mainToken === VOID_ETHEREUM_ADDRESS ? wethToken : mainToken;

  assert.notStrictEqual(setupMainToken, undefined);
  assert.notStrictEqual(mainToken, undefined);
  assert.notStrictEqual(wethToken, undefined);
  assert.equal(mainToken.options.address.toLowerCase(), web3.currentProvider.knowledgeBase.osTokenAddress.toLowerCase());

}

async function deployFactoryAndExtensions() {

  farmMainModel = await deployContract(new web3.eth.Contract(FarmMain.abi), FarmMain.bin);
  console.log(`simple farm model deployed at ${farmMainModel.options.address}`);

  var farmExtensionModel = await deployContract(new web3.eth.Contract(FarmExtension.abi), FarmExtension.bin);
  console.log(`farm extension model deployed at ${farmExtensionModel.options.address}`);

  farmFactory = await deployContract(new web3.eth.Contract(FarmFactory.abi), FarmFactory.bin, [VOID_ETHEREUM_ADDRESS, farmMainModel.options.address, farmExtensionModel.options.address, 0, "google.com", "google.com"]);
  console.log(`farm factory deployed at ${farmFactory.options.address}`);

  var transaction = await blockchainCall(farmFactory.methods.cloneFarmDefaultExtension);
  var receipt = await web3.eth.getTransactionReceipt(transaction.transactionHash);
  clonedDefaultFarmExtension = web3.eth.abi.decodeParameter("address", receipt.logs.filter(it => it.topics[0] === web3.utils.sha3('ExtensionCloned(address)'))[0].topics[1])
  console.log(`cloned default farm extension deployed at ${clonedDefaultFarmExtension}`);
  clonedFarmExtension = new web3.eth.Contract(FarmExtension.abi, clonedDefaultFarmExtension);
  console.log(`cloned farm extention deployed at ${clonedFarmExtension.options.address}`);

}

async function deploySimpleFarmMainContract() {
  var currentBlock = await web3.eth.getBlock(await web3.eth.getBlockNumber());
  var currentTimestamp = currentBlock.timestamp;

  if (mainToken != VOID_ETHEREUM_ADDRESS && secondaryToken != VOID_ETHEREUM_ADDRESS) {
    // ERC20 TEST
    var setups = [
      [
        600 * misc.TIME_SLOTS_IN_SECONDS,
        0 * misc.TIME_SLOTS_IN_SECONDS,
        toDecimals(0.001, 18),
        toDecimals(5000, 18),
        5,
        univ3PoolAddress,
        setupMainToken !== VOID_ETHEREUM_ADDRESS ? setupMainToken.options.address : wethToken.options.address,
        mainToken === VOID_ETHEREUM_ADDRESS || secondaryToken === VOID_ETHEREUM_ADDRESS,
        0,
        0, -92000, 92200
      ],
      [
        800 * misc.TIME_SLOTS_IN_SECONDS,
        (parseInt(currentTimestamp) + (30 * misc.TIME_SLOTS_IN_SECONDS)),
        toDecimals(0.003, 18),
        toDecimals(5000, 18),
        1,
        univ3PoolAddress,
        setupMainToken !== VOID_ETHEREUM_ADDRESS ? setupMainToken.options.address : wethToken.options.address,
        mainToken === VOID_ETHEREUM_ADDRESS || secondaryToken === VOID_ETHEREUM_ADDRESS,
        0,
        0, -92000, 92200
      ]
    ];

  } else {
    // ETH TEST
    var setups = [
      [
        600 * misc.TIME_SLOTS_IN_SECONDS,
        0 * misc.TIME_SLOTS_IN_SECONDS,
        toDecimals(0.001, 18),
        toDecimals(5000, 18),
        5,
        univ3PoolAddress,
        setupMainToken !== VOID_ETHEREUM_ADDRESS ? setupMainToken.options.address : wethToken.options.address,
        mainToken === VOID_ETHEREUM_ADDRESS || secondaryToken === VOID_ETHEREUM_ADDRESS,
        0,
        0,
        -92000, 92200
      ],
      [
        800 * misc.TIME_SLOTS_IN_SECONDS,
        (parseInt(currentTimestamp) + (30 * misc.TIME_SLOTS_IN_SECONDS)),
        toDecimals(0.003, 18),
        toDecimals(5000, 18),
        1,
        univ3PoolAddress,
        setupMainToken !== VOID_ETHEREUM_ADDRESS ? setupMainToken.options.address : wethToken.options.address,
        mainToken === VOID_ETHEREUM_ADDRESS || secondaryToken === VOID_ETHEREUM_ADDRESS,
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
    "bytes",
  ];
  var params = [
    clonedDefaultFarmExtension, //liquidityMiningExtension.options.address,
    "0x",
    rewardToken !== VOID_ETHEREUM_ADDRESS ? rewardToken.options.address : VOID_ETHEREUM_ADDRESS,
    abi.encode(["tuple(uint256,uint256,uint256,uint256,uint256,address,address,bool,uint256,uint256,int24,int24)[]"], [setups]),
  ];

  byMint = params[0] !== clonedDefaultFarmExtension;
  // params[1] = farmMainExtension.methods.init(byMint, params[0] === clonedDefaultFarmExtension ? extensionOwner : VOID_ETHEREUM_ADDRESS, params[0] === clonedDefaultFarmExtension ? VOID_ETHEREUM_ADDRESS : VOID_ETHEREUM_ADDRESS).encodeABI()

  var osStuff = await buildOSStuff(rewardToken);
  params[0] = osStuff.farmExtensionAddress;
  params[1] = osStuff.farmExtensionLazyInitData;
  byMint = true;

  var payload = web3.eth.abi.encodeParameters(types, params);
  payload = web3.eth.abi.encodeParameters(["address", "bytes"], [web3.currentProvider.knowledgeBase.uniswapV3NonfungiblePositionManagerAddress, payload]);
  payload = web3.eth.abi.encodeParameters(["bytes"], [payload]);
  payload = web3.utils.sha3(`lazyInit(bytes)`).substring(0, 10) + (payload.substring(2));

  var deployTransaction = await blockchainCall(farmFactory.methods.deploy, payload);
  deployTransaction = await web3.eth.getTransactionReceipt(deployTransaction.transactionHash);
  farmMainContractAddress = web3.eth.abi.decodeParameter("address", deployTransaction.logs.filter(it => it.topics[0] === web3.utils.sha3("FarmMainDeployed(address,address,bytes)"))[0].topics[1]);

  farmMainContract = await new web3.eth.Contract(FarmMain.abi, farmMainContractAddress);
  assert.notStrictEqual(farmMainContract.options.address, VOID_ETHEREUM_ADDRESS);
  oneHundred = await blockchainCall(farmMainContract.methods.ONE_HUNDRED);

  var availableSetups = await blockchainCall(farmMainContract.methods.setups);
  assert.strictEqual(availableSetups.length, setups.length);

  // put reward in the extension
  if (rewardToken !== VOID_ETHEREUM_ADDRESS) {
    await buyForETH(rewardToken, 20000);
    await blockchainCall(await rewardToken.methods.transfer, params[0], toDecimals("15000", await blockchainCall(rewardToken.methods.decimals)));
    console.log("params[0] balanceOf rewardToken: " + await blockchainCall(rewardToken.methods.balanceOf, params[0]));
  } else {
    await sendBlockchainTransaction(
      web3.currentProvider,
      accounts[0],
      params[0],
      "0x",
      toDecimals(20000, 18)
    );
  }
}

async function buyForETH(token, amount, receiver, ammPlugin) {
  var value = toDecimals(amount.toString(), '18');
  if (token.options.address === web3.currentProvider.knowledgeBase.wethTokenAddress) {
      return await sendBlockchainTransaction(
          web3.currentProvider,
          accounts[0],
          web3.currentProvider.knowledgeBase.wethTokenAddress,
          web3.utils.sha3("deposit()").substring(0, 10),
          value
      );
  }
  ammPlugin = ammPlugin || amm;
  var ethereumAddress = (await ammPlugin.methods.data().call())[0];
  var liquidityPoolAddress = (await ammPlugin.methods.byTokens([
    ethereumAddress,
    token.options.address
  ]).call())[2];
  if (liquidityPoolAddress === VOID_ETHEREUM_ADDRESS) {
    return;
  }
  await blockchainCall(ammPlugin.methods.swapLiquidity, {
    amount: value,
    enterInETH: true,
    exitInETH: false,
    liquidityPoolAddresses: [liquidityPoolAddress],
    path: [token.options.address],
    inputToken: ethereumAddress,
    receiver: receiver || VOID_ETHEREUM_ADDRESS
  }, { value: value });
};

async function initActor(name, address, amount0, amount1) {
  actors[name] = {
    name,
    address,
    from: address,
    amount0,
    amount1
  };

  mainToken !== VOID_ETHEREUM_ADDRESS && await buyForETH(mainToken, ethToSpend, address);
  secondaryToken !== VOID_ETHEREUM_ADDRESS && await buyForETH(secondaryToken, ethToSpend, address);

};





module.exports = async function run() {
  debugger;
  console.log("===========================================================");
  console.log("* MULTIVERSE - run() - started *");

  console.log("");
  console.group("Initializing the environment...");
  console.log("Creating contracts objects...");
  uniswapV2Router = misc.deployUniswapV2Router();
  uniswapV2Factory = misc.deployUniswapV2Factory();
  uniswapV3Pool = misc.deployUniswapV3Pool(univ3PoolAddress);
  swapRouter = misc.deploySwapRouter();
  await createContractsObjects();

  console.group("Creating accounts...");
  extensionOwner = accounts[0];
  console.log("extensionOwner done...");
  console.groupEnd();
  console.log("");

  console.group("Preparing contracts...");
  console.log("Compiling...");
  await compileContracts();
  if (printABI) misc.printContractABI(UniswapV3AMMV1);
  console.groupEnd();
  console.log("");

  console.log("Preparing tokens.....");
  await prepareTokens();
  console.groupEnd();
  console.log("");

  console.group("Creating actors...");
  await initActor("Alice", accounts[1], "5000.1", 370);
  console.log("Alice done...");
  await initActor("Bob", accounts[2], 100, 100);
  console.log("Bob done...");
  await initActor("Carol", accounts[3], 500, 500);
  console.log("Carol done...");
  await initActor("David", accounts[4], 50, 50);
  console.log("David done...");
  await initActor("Eve", accounts[5], 75, 75);
  console.log("Eve done...");
  await initActor("Frank", accounts[6], 50, 50);
  console.log("Frank done...");
  await initActor("Grace", accounts[7], 50, 50);
  console.log("Grace done...");
  await initActor("Heidi", accounts[8], 0.01, 0.01);
  console.log("Heidi done...");
  await initActor("Isaac", accounts[9], 50, 50);
  console.log("Isaac done...");
  await initActor("John", accounts[10], 50, 50);
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

// UTILS FOR TEST FUNCTIONS
async function loadPosition(positionId) {
  var originalPosition = await farmMainContract.methods.position(positionId).call();
  var position = {
    liquidityPoolTokenAmount: '0'
  };
  Object.entries(originalPosition).forEach(it => position[it[0]] = it[1]);
  try {
    position.liquidityPoolTokenAmount = await uniswapV3NonfungiblePositionManager.methods.positions(position.tokenId).call();
    position.liquidityPoolTokenAmount = position.liquidityPoolTokenAmount.liquidity;
  } catch (e) {
  }
  return position;
}

async function addLiquidity(actor) {
  var startingSetup = (await farmMainContract.methods.setups().call())[actor.setupIndex];
  var startingPosition = await loadPosition(actor.positionId);

  var mainTokenAmount = toDecimals(actor.amount0, mainToken != VOID_ETHEREUM_ADDRESS ? await mainToken.methods.decimals().call() : 18);
  var secondaryTokenAmount = toDecimals(actor.amount1, secondaryToken != VOID_ETHEREUM_ADDRESS ? await secondaryToken.methods.decimals().call() : 18);
  var { '0': _, '1': setupInfo } = await farmMainContract.methods.setup(actor.setupIndex).call();

  var stake = {
    setupIndex: actor.setupIndex,
    amount0: mainTokenAmount,
    amount1: secondaryTokenAmount,
    positionOwner: VOID_ETHEREUM_ADDRESS,
    amount0Min: 0,// utilities.numberToString(parseInt(mainTokenAmount) * 0.001).split('.')[0],
    amount1Min: 0//utilities.numberToString(parseInt(secondaryTokenAmount) * 0.001).split('.')[0]
  };

  await farmMainContract.methods.addLiquidity(actor.positionId, stake).send({ ...actor.from, value: setupInfo.involvingETH ? mainToken === VOID_ETHEREUM_ADDRESS ? mainTokenAmount : secondaryTokenAmount : 0 });
  var endingSetup = (await farmMainContract.methods.setups().call())[actor.setupIndex];
  var endingPosition = await loadPosition(actor.positionId);
  actor.position = endingPosition;
  assert.strictEqual(web3.utils.toBN(startingPosition.liquidityPoolTokenAmount).mul(web3.utils.toBN(2)).toString(), endingPosition.liquidityPoolTokenAmount);
  assert.strictEqual(endingSetup.totalSupply, web3.utils.toBN(startingSetup.totalSupply).add(web3.utils.toBN(endingPosition.liquidityPoolTokenAmount).sub(web3.utils.toBN(startingPosition.liquidityPoolTokenAmount))).toString());
}

async function createStakingPosition(actor, setupIndex, mainTokenAmount) {
  (mainToken !== VOID_ETHEREUM_ADDRESS) && await mainToken.methods.approve(farmMainContract.options.address, await mainToken.methods.totalSupply().call()).send(actor.from);
  (secondaryToken !== VOID_ETHEREUM_ADDRESS) && await secondaryToken.methods.approve(farmMainContract.options.address, await secondaryToken.methods.totalSupply().call()).send(actor.from);
  mainTokenAmount = mainTokenAmount || toDecimals(actor.amount0, mainToken !== VOID_ETHEREUM_ADDRESS ? await mainToken.methods.decimals().call() : 18);
  var secondaryTokenAmount = toDecimals(actor.amount1, secondaryToken !== VOID_ETHEREUM_ADDRESS ? await secondaryToken.methods.decimals().call() : 18);

  var setups = await farmMainContract.methods.setups().call();
  var setup = setups[setupIndex];
  var setupInfo = (await farmMainContract.methods.setup(setup.infoIndex).call())[1]; //FarmingSetupInfo

  var liquidityPool = new web3.eth.Contract(web3.currentProvider.knowledgeBase.UniswapV3PoolABI, setupInfo.liquidityPoolTokenAddress);

  var token0 = await liquidityPool.methods.token0().call();

  var amount0 = token0.toLowerCase() === ((mainToken.options && mainToken.options.address) || web3.currentProvider.knowledgeBase.wethTokenAddress).toLowerCase() ? mainTokenAmount : secondaryTokenAmount;
  var amount1 = token0.toLowerCase() === ((mainToken.options && mainToken.options.address) || web3.currentProvider.knowledgeBase.wethTokenAddress).toLowerCase() ? secondaryTokenAmount : mainTokenAmount;

  var stake = { //FarmingPositionRequest
    setupIndex,
    amount0,
    amount1,
    positionOwner: VOID_ETHEREUM_ADDRESS,
    amount0Min: utilities.numberToString(parseInt(token0.toLowerCase() === ((mainToken.options && mainToken.options.address) || web3.currentProvider.knowledgeBase.wethTokenAddress).toLowerCase() ? mainTokenAmount : secondaryTokenAmount) * 0.7),
    amount1Min: utilities.numberToString(parseInt(token0.toLowerCase() === ((mainToken.options && mainToken.options.address) || web3.currentProvider.knowledgeBase.wethTokenAddress).toLowerCase() ? secondaryTokenAmount : mainTokenAmount) * 0.7)
  };

  var valueToSend = (setupInfo.involvingETH) ? mainToken === VOID_ETHEREUM_ADDRESS ? mainTokenAmount : secondaryTokenAmount : 0;

  console.log({
    amount0: stake.amount0,
    amount1: stake.amount1,
    amount0Min: stake.amount0Min,
    amount1Min: stake.amount1Min,
    valueToSend
  });

  var result = await farmMainContract.methods.openPosition(stake).send({ ...actor.from, value: valueToSend });
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

async function withdrawReward(actor) {
  var balance = rewardToken !== VOID_ETHEREUM_ADDRESS ? await rewardToken.methods.balanceOf(farmMainContract.options.address).call() : await web3.eth.getBalance(farmMainContract.options.address);
  console.log(`farm main balance is ${balance}`);
  var setup = (await farmMainContract.methods.setups().call())[actor.setupIndex];
  var rew = await farmMainContract.methods.calculateFreeFarmingReward(actor.positionId, false).call();
  console.log(rew)
  var currentBlock = await web3.eth.getBlockNumber();
  await web3.currentProvider.setNextBlockTime(parseInt(currentBlock) || parseInt(setup.endBlock));
  var startingBalance = rewardToken !== VOID_ETHEREUM_ADDRESS ? await rewardToken.methods.balanceOf(actor.address).call() : await web3.eth.getBalance(actor.address);
  var result = await farmMainContract.methods.withdrawReward(actor.positionId).send(actor.from);
  var fee = await calculateTransactionFee(web3, result);
  console.log(fee);
  setup = (await farmMainContract.methods.setups().call())[actor.setupIndex];
  var resultBalance = rewardToken !== VOID_ETHEREUM_ADDRESS ? await rewardToken.methods.balanceOf(actor.address).call() : await web3.eth.getBalance(actor.address);
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
  var availableSetups = await farmMainContract.methods.setups().call();
  if (amount === actor.position.liquidityPoolTokenAmount) {
    assert.strictEqual(parseInt(position.creationBlock), 0);
  } else {
    assert.strictEqual(fromDecimals(parseInt(position.liquidityPoolTokenAmount), 18), fromDecimals(parseInt(positionLiquidityPoolTokenAmount) - parseInt(amount), 18));
    actor.position = position;
  }
  assert.strictEqual(parseInt(endFarmTokenBalance), 0);
}

async function finalFlush() {
  var balance = rewardToken !== VOID_ETHEREUM_ADDRESS ? await rewardToken.methods.balanceOf(farmMainContract.options.address).call() : await web3.eth.getBalance(farmMainContract.options.address);
  var receiver = (await clonedFarmExtension.methods.data().call()).treasury;
  var expectedReceiverBalance = web3.utils.toBN(rewardToken !== VOID_ETHEREUM_ADDRESS ? await rewardToken.methods.balanceOf(receiver).call() : await web3.eth.getBalance(receiver)).add(web3.utils.toBN(balance)).toString();
  var transactionResult = await farmMainContract.methods.finalFlush([rewardToken !== VOID_ETHEREUM_ADDRESS ? rewardToken.options.address : VOID_ETHEREUM_ADDRESS], [balance]).send();
  if (rewardToken == VOID_ETHEREUM_ADDRESS && receiver == accounts[0]) {
    expectedReceiverBalance = web3.utils.toBN(expectedReceiverBalance).sub(web3.utils.toBN(await calculateTransactionFee(web3, transactionResult))).toString();
  }
  assert.strictEqual(rewardToken !== VOID_ETHEREUM_ADDRESS ? await rewardToken.methods.balanceOf(farmMainContract.options.address).call() : await web3.eth.getBalance(farmMainContract.options.address), '0');
  assert.strictEqual(rewardToken !== VOID_ETHEREUM_ADDRESS ? await rewardToken.methods.balanceOf(receiver).call() : await web3.eth.getBalance(receiver), expectedReceiverBalance);
}

// TEST FUNCTIONS

async function shouldActiveSetup() {
  await blockchainCall(farmMainContract.methods.activateSetup, 0);
  await assert.catchCall(blockchainCall(farmMainContract.methods.activateSetup, 1), "too early");
  await web3.currentProvider.setNextBlockTime((await blockchainCall(farmMainContract.methods.setup, 1))[1].startEvent); // FIXME Too early for this setup
  await blockchainCall(farmMainContract.methods.activateSetup, 1);
  var availableSetups = await farmMainContract.methods.setups().call();
  console.log(availableSetups);
  await Promise.all(availableSetups.map(async (setup) => {
    assert.strictEqual(setup.active, true);
  }));
}

async function shouldNotActivateNotExistingSetup() {
  try {
    await farmMainContract.methods.activateSetup(2).send();
    assert(false, "This should not happen");
  } catch (e) {
    assert.notStrictEqual((e.message || e).toLowerCase().indexOf("nvalid toggle"), -1, (e.message || e));
  }
}




module.exports.test = async function test() {
  console.log("* MULTIVERSE - test() started *");

  console.group("Should activate both the setups");
  await shouldActiveSetup();
  console.groupEnd();
  console.log("");

  // console.group("Should not activate a non existing setup info");
  // await shouldNotActivateNotExistingSetup();
  // console.groupEnd();
  // console.log("");


  // Create staking position
  // console.group("Should allow " + actors.Alice.name + " to open a new staking position");
  // {
  //   await catchCall(createStakingPosition(actors.Alice, 0, "4".mul(1e18)), "Invalid liquidity");
  //   await createStakingPosition(actors.Alice, 0);
  //   console.groupEnd();
  //   console.log("");
  // }


  // console.group("Should allow " + actors.Bob.name + " to open a new staking position");
  // {
  //   await createStakingPosition(actors.Bob, 1);
  //   console.groupEnd();
  //   console.log("");
  // }

  // console.group("Should allow " + actors.Carol.name + " to open a new staking position");
  // {
  //   await createStakingPosition(actors.Carol, 0);
  //   console.groupEnd();
  //   console.log("");
  // }

  // console.group("Should allow " + actors.David.name + " to open a new staking position");
  // {
  //   await createStakingPosition(actors.David, 1);
  //   console.groupEnd();
  //   console.log("");
  // }

  // console.group("Should allow " + actors.Eve.name + " to open a new staking position");
  // {
  //   await createStakingPosition(actors.Eve, 0);
  //   console.groupEnd();
  //   console.log("");
  // }

  // console.group("Should allow " + actors.Frank.name + " to open a new staking position");
  // {
  //   await createStakingPosition(actors.Frank, 1);
  //   console.groupEnd();
  //   console.log("");
  // }

  // console.group("Should allow " + actors.Grace.name + " to open a new staking position");
  // {
  //   await createStakingPosition(actors.Grace, 0);
  //   console.groupEnd();
  //   console.log("");
  // }

  // console.group("Should allow " + actors.Heidi.name + " to open a new staking position");
  // {
  //   await createStakingPosition(actors.Heidi, 1);
  //   console.groupEnd();
  //   console.log("");
  // }

  // console.group("Should allow " + actors.Isaac.name + " to open a new staking position");
  // {
  //   await createStakingPosition(actors.Isaac, 0);
  //   console.groupEnd();
  //   console.log("");
  // }

  // console.group("Should allow " + actors.John.name + " to open a new staking position");
  // {
  //   await createStakingPosition(actors.John, 0);
  //   console.groupEnd();
  //   console.log("");
  // }


  console.log("* MULTIVERSE - test() - finished *");
};
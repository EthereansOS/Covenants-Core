require("../../util/mocha");

var blockchainConnection = require("../../util/blockchainConnection");
var buildOSStuff = require('../../resources/OS/buildOsStuff');
var dfoManager = require('../../util/dfo');
var fs = require('fs');
var misc = require("../misc");
var path = require('path');
var utilities = require("../../util/utilities");


var isTesthETH = true;
var printABI = false;

var FarmMain;
var farmMainContract;
var farmMainModel;

var FarmFactory;
var FarmExtension;

var DFOBasedFarmExtensionFactory;
var DFOBasedFarmExtension;

var UniswapV2AMMV1;
var UniswapV3AMMV1;

var uniswapAMM;
var amm;

var uniswapV2Router;
var uniswapV2Factory;
var uniswapV3Pool;
var swapRouter;
var mainDFO;
var dfo;

var liquidityPool;
var actors = {};
var ethToSpend = 90;
var wethToken;
var rewardToken;
var mainToken;
var secondaryToken;
var setupMainToken;
var rewardDestination;

var univ3PoolAddress = "0x77EDFA75eab19b772466a4AFfcF5555b7532BADf";

async function compileContracts() {
  FarmMain = await misc.compileFarmingContract("FarmMainRegularMinStake", null);
  FarmFactory = await misc.compileFarmingContract("FarmFactory", null);
  FarmExtension = await misc.compileFarmingContract("FarmExtension", null);
  DFOBasedFarmExtensionFactory = await misc.compileFarmingContract("DFOBasedFarmExtensionFactory", "dfo");
  DFOBasedFarmExtension = await misc.compileFarmingContract("DFOBasedFarmExtension", "dfo");

  UniswapV2AMMV1 = await misc.compileAmmAggregatorContract("UniswapV2AMMV1", "models/UniswapV2/1");
  UniswapV3AMMV1 = await misc.compileAmmAggregatorContract("UniswapV3AMMV1", "models/UniswapV3/1");
}

async function createContractsObjects() {
  uniswapV3NonfungiblePositionManager = new web3.eth.Contract((await compile('../node_modules/@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager')).abi, knowledgeBase.uniswapV3NonfungiblePositionManagerAddress);
}

async function prepareTokens() {
  var rewardTokenAddress = knowledgeBase.osTokenAddress;
  rewardToken = new web3.eth.Contract(knowledgeBase.IERC20ABI, rewardTokenAddress);

  if (isTesthETH) {
    mainToken = new web3.eth.Contract(knowledgeBase.IERC20ABI, knowledgeBase.osTokenAddress);
    secondaryToken = utilities.voidEthereumAddress;

    assert.equal(secondaryToken, "0x0000000000000000000000000000000000000000");
  } else {
    mainToken = new web3.eth.Contract(knowledgeBase.IERC20ABI, knowledgeBase.osTokenAddress);
    secondaryToken = new web3.eth.Contract(knowledgeBase.IERC20ABI, knowledgeBase.usdcTokenAddress);

    assert.equal(secondaryToken.options.address.toLowerCase(), knowledgeBase.usdcTokenAddress.toLowerCase());
  }

  var wethTokenAddress = await uniswapV2Router.methods.WETH().call();
  wethToken = new web3.eth.Contract(knowledgeBase.IERC20ABI, wethTokenAddress);

  liquidityPool = new web3.eth.Contract(knowledgeBase.uniswapV2PairABI, await uniswapV2Factory.methods.getPair(mainToken !== utilities.voidEthereumAddress ? mainToken.options.address : wethToken.options.address, secondaryToken != utilities.voidEthereumAddress ? secondaryToken.options.address : wethToken.options.address).call());

  mainToken !== utilities.voidEthereumAddress && await buyForETH(mainToken, ethToSpend);
  secondaryToken !== utilities.voidEthereumAddress && await buyForETH(secondaryToken, ethToSpend);
  // FIXME
  // rewardToken !== utilities.voidEthereumAddress && rewardToken.options.address !== dfo.votingTokenAddress && await buyForETH(rewardToken, ethToSpend);
  rewardToken !== utilities.voidEthereumAddress && await buyForETH(rewardToken, ethToSpend);

  setupMainToken = mainToken === utilities.voidEthereumAddress ? wethToken : mainToken;

  assert.notStrictEqual(setupMainToken, undefined);
  assert.notStrictEqual(mainToken, undefined);
  assert.notStrictEqual(wethToken, undefined);
  assert.equal(mainToken.options.address.toLowerCase(), knowledgeBase.osTokenAddress.toLowerCase());

}

async function deployFactoryAndExtensions() {
  // FIXME
  // rewardDestination = dfo.mvdWalletAddress;
  rewardDestination = actors.FactoryDfo.address;

  farmMainModel = await new web3.eth.Contract(FarmMain.abi).deploy({ data: FarmMain.bin }).send(blockchainConnection.getSendingOptions());
  console.log(`simple farm model deployed at ${farmMainModel.options.address}`);

  var farmExtensionModel = await new web3.eth.Contract(FarmExtension.abi).deploy({ data: FarmExtension.bin }).send(blockchainConnection.getSendingOptions());
  console.log(`farm extension model deployed at ${farmExtensionModel.options.address}`);

  // FIXME
  // farmFactory = await new web3.eth.Contract(FarmFactory.abi).deploy({ data: FarmFactory.bin, arguments: [dfo.doubleProxyAddress, farmMainModel.options.address, farmExtensionModel.options.address, 0, "google.com", "google.com"] }).send(blockchainConnection.getSendingOptions());
  farmFactory = await new web3.eth.Contract(FarmFactory.abi).deploy({ data: FarmFactory.bin, arguments: [actors.FactoryDfo.address, farmMainModel.options.address, farmExtensionModel.options.address, 0, "google.com", "google.com"] }).send(blockchainConnection.getSendingOptions());
  console.log(`farm factory deployed at ${farmFactory.options.address}`);

  var dfoFarmExtensionModel = await new web3.eth.Contract(DFOBasedFarmExtension.abi).deploy({ data: DFOBasedFarmExtension.bin }).send(blockchainConnection.getSendingOptions());
  console.log(`dfo farm extension model deployed at ${dfoFarmExtensionModel.options.address}`);
  // FIXME
  // dFOBasedFarmExtensionFactory = await new web3.eth.Contract(DFOBasedFarmExtensionFactory.abi).deploy({ data: DFOBasedFarmExtensionFactory.bin, arguments: [mainDFO.doubleProxyAddress, dfoFarmExtensionModel.options.address] }).send(blockchainConnection.getSendingOptions());
  dFOBasedFarmExtensionFactory = await new web3.eth.Contract(DFOBasedFarmExtensionFactory.abi).deploy({ data: DFOBasedFarmExtensionFactory.bin, arguments: [actors.FactoryMainDfo.address, dfoFarmExtensionModel.options.address] }).send(blockchainConnection.getSendingOptions());
  console.log(`dfo based farm extension factory deployed at ${dFOBasedFarmExtensionFactory.options.address}`);

  var transaction = await dFOBasedFarmExtensionFactory.methods.cloneModel().send(blockchainConnection.getSendingOptions());
  var receipt = await web3.eth.getTransactionReceipt(transaction.transactionHash);
  var farmMainExtensionAddress = web3.eth.abi.decodeParameter("address", receipt.logs.filter(it => it.topics[0] === web3.utils.sha3('ExtensionCloned(address,address)'))[0].topics[1])
  farmMainExtension = new web3.eth.Contract(FarmExtension.abi, farmMainExtensionAddress);
  console.log(`simple farm extension deployed at ${farmMainExtension.options.address}`);

  transaction = await farmFactory.methods.cloneFarmDefaultExtension().send(blockchainConnection.getSendingOptions());
  receipt = await web3.eth.getTransactionReceipt(transaction.transactionHash);
  clonedDefaultFarmExtension = web3.eth.abi.decodeParameter("address", receipt.logs.filter(it => it.topics[0] === web3.utils.sha3('ExtensionCloned(address)'))[0].topics[1])
  console.log(`cloned default farm extension deployed at ${clonedDefaultFarmExtension}`);
  clonedFarmExtension = new web3.eth.Contract(FarmExtension.abi, clonedDefaultFarmExtension);
  console.log(`cloned farm extention deployed at ${clonedFarmExtension.options.address}`);

}

async function deploySimpleFarmMainContract() {
  if (mainToken != utilities.voidEthereumAddress && secondaryToken != utilities.voidEthereumAddress) {
    // ERC20 TEST
    var setups = [
      [
        600 * misc.TIME_SLOTS_IN_SECONDS,
        0 * misc.TIME_SLOTS_IN_SECONDS,
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
        800 * misc.TIME_SLOTS_IN_SECONDS,
        (parseInt(await web3.eth.getBlockNumber()) + 30) * misc.TIME_SLOTS_IN_SECONDS,
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
        600 * misc.TIME_SLOTS_IN_SECONDS,
        0 * misc.TIME_SLOTS_IN_SECONDS,
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
        800 * misc.TIME_SLOTS_IN_SECONDS,
        (parseInt(await web3.eth.getBlockNumber()) + 30) * misc.TIME_SLOTS_IN_SECONDS,
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
  // FIXME
  // params[1] = farmMainExtension.methods.init(byMint, params[0] === clonedDefaultFarmExtension ? extensionOwner : dfo.doubleProxyAddress, params[0] === clonedDefaultFarmExtension ? utilities.voidEthereumAddress : dfo.doubleProxyAddress).encodeABI()

  // FIXME
  var osStuff = await buildOSStuff(rewardToken);
  params[0] = osStuff.farmExtensionAddress;
  params[1] = osStuff.farmExtensionLazyInitData;
  byMint = true;

  var payload = web3.utils.sha3(`init(${types.join(',')})`).substring(0, 10) + (web3.eth.abi.encodeParameters(types, params).substring(2));
  // var deployTransaction = await farmFactory.methods.deploy(payload).send(blockchainConnection.getSendingOptions());
  // deployTransaction = await web3.eth.getTransactionReceipt(deployTransaction.transactionHash);
  // farmMainContractAddress = web3.eth.abi.decodeParameter("address", deployTransaction.logs.filter(it => it.topics[0] === web3.utils.sha3("FarmMainDeployed(address,address,bytes)"))[0].topics[1]);

  // farmMainContract = await new web3.eth.Contract(FarmMain.abi, farmMainContractAddress);
  // assert.notStrictEqual(farmMainContract.options.address, utilities.voidEthereumAddress);
  // oneHundred = await farmMainContract.methods.ONE_HUNDRED().call();

  // var availableSetups = await farmMainContract.methods.setups().call()
  // assert.strictEqual(availableSetups.length, setups.length);

  // // put reward in the extension
  // if (rewardToken !== utilities.voidEthereumAddress) {
  //   await buyForETH(rewardToken, 20000);
  //   await rewardToken.methods.transfer(params[0], utilities.toDecimals("15000", await rewardToken.methods.decimals().call())).send(blockchainConnection.getSendingOptions());
  //   console.log(await rewardToken.methods.balanceOf(clonedDefaultFarmExtension).call());
  // } else {
  //   await web3.eth.sendTransaction(blockchainConnection.getSendingOptions({
  //     to: params[0],
  //     value: utilities.toDecimals(20000, 18)
  //   }));
  // }
}

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

async function buyForETH(token, amount, receiver) {
  var value = utilities.toDecimals(amount.toString(), '18');
  if (token.options.address === knowledgeBase.wethTokenAddress) {
    return await web3.eth.sendTransaction(blockchainConnection.getSendingOptions({
      to: knowledgeBase.wethTokenAddress,
      value,
      data: web3.utils.sha3("deposit()").substring(0, 10)
    }));
  }
};



module.exports = async function run() {
  console.log("===========================================================");
  console.log("* MULTIVERSE - run() - started *");

  await blockchainConnection.init;

  console.log("");
  console.group("Initializing the environment...");
  console.log("Creating contracts objects...");
  uniswapV2Router = misc.deployUniswapV2Router();
  uniswapV2Factory = misc.deployUniswapV2Factory();
  uniswapV3Pool = misc.deployUniswapV3Pool(univ3PoolAddress);
  swapRouter = misc.deploySwapRouter();
  await createContractsObjects();

  console.log("Preparing tokens...");
  await prepareTokens();
  console.groupEnd();
  console.log("");


  console.group("Preparing contracts...");
  console.log("Compiling...");
  await compileContracts();
  if (printABI) misc.printContractABI(UniswapV3AMMV1);

  console.groupEnd();
  console.log("");

  // FIXME
  console.group("Creating accounts...");
  extensionOwner = accounts[0];
  console.log("extensionOwner done...");
  // mainDFO = await dfoManager.createDFO("MyName", "MySymbol", 10000000, 100, 10);
  // console.log("mainDFO done...");
  // dfo = await dfoManager.createDFO("MyName", "MySymbol", 10000000, 100, 10);
  // console.log("dfo done...");
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
  await initActor("FactoryDfo", accounts[11], "5000.1", 370);
  console.log("FactoryDfo done...");
  await initActor("FactoryMainDfo", accounts[12], "5000.1", 370);
  console.log("FactoryMainDfo done...");
  console.groupEnd();
  console.log("");

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

  var mainTokenAmount = utilities.toDecimals(actor.amount0, mainToken != utilities.voidEthereumAddress ? await mainToken.methods.decimals().call() : 18);
  var secondaryTokenAmount = utilities.toDecimals(actor.amount1, secondaryToken != utilities.voidEthereumAddress ? await secondaryToken.methods.decimals().call() : 18);
  var { '0': _, '1': setupInfo } = await farmMainContract.methods.setup(actor.setupIndex).call();

  var stake = {
    setupIndex: actor.setupIndex,
    amount0: mainTokenAmount,
    amount1: secondaryTokenAmount,
    positionOwner: utilities.voidEthereumAddress,
    amount0Min: 0,// utilities.numberToString(parseInt(mainTokenAmount) * 0.001).split('.')[0],
    amount1Min: 0//utilities.numberToString(parseInt(secondaryTokenAmount) * 0.001).split('.')[0]
  };

  await farmMainContract.methods.addLiquidity(actor.positionId, stake).send({ ...actor.from, value: setupInfo.involvingETH ? mainToken === utilities.voidEthereumAddress ? mainTokenAmount : secondaryTokenAmount : 0 });
  var endingSetup = (await farmMainContract.methods.setups().call())[actor.setupIndex];
  var endingPosition = await loadPosition(actor.positionId);
  actor.position = endingPosition;
  assert.strictEqual(web3.utils.toBN(startingPosition.liquidityPoolTokenAmount).mul(web3.utils.toBN(2)).toString(), endingPosition.liquidityPoolTokenAmount);
  assert.strictEqual(endingSetup.totalSupply, web3.utils.toBN(startingSetup.totalSupply).add(web3.utils.toBN(endingPosition.liquidityPoolTokenAmount).sub(web3.utils.toBN(startingPosition.liquidityPoolTokenAmount))).toString());
}

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

// TEST FUNCTIONS

async function shouldActiveSetup() {
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
    }));
}

async function shouldNotActivateNotExistingSetup() {
  try {
    await farmMainContract.methods.activateSetup(2).send(blockchainConnection.getSendingOptions());
    assert(false, "This should not happen");
  } catch (e) {
      assert.notStrictEqual((e.message || e).toLowerCase().indexOf("nvalid toggle"), -1, (e.message || e));
  }
}




module.exports.test = async function test() {
  console.log("* MULTIVERSE - test() started *");

  // console.group("Should activate both the setups");
  // await shouldActiveSetup();
  // console.groupEnd();
  // console.log("");

  // console.group("Should not activate a non existing setup info");
  // await shouldNotActivateNotExistingSetup();
  // console.groupEnd();
  // console.log("");


  // Create staking position
  console.group("Should allow " + actors.Alice.name + " to open a new staking position");
  {
    await catchCall(createStakingPosition(actors.Alice, 0, "4".mul(1e18)), "Invalid liquidity");
    await createStakingPosition(actors.Alice, 0);
    console.groupEnd();
    console.log("");
  }


  console.group("Should allow " + actors.Bob.name + " to open a new staking position");
  {
    await createStakingPosition(actors.Bob, 1);
    console.groupEnd();
    console.log("");
  }

  console.group("Should allow " + actors.Carol.name + " to open a new staking position");
  {
    await createStakingPosition(actors.Carol, 0);
    console.groupEnd();
    console.log("");
  }

  console.group("Should allow " + actors.David.name + " to open a new staking position");
  {
    await createStakingPosition(actors.David, 1);
    console.groupEnd();
    console.log("");
  }

  console.group("Should allow " + actors.Eve.name + " to open a new staking position");
  {
    await createStakingPosition(actors.Eve, 0);
    console.groupEnd();
    console.log("");
  }

  console.group("Should allow " + actors.Frank.name + " to open a new staking position");
  {
    await createStakingPosition(actors.Frank, 1);
    console.groupEnd();
    console.log("");
  }

  console.group("Should allow " + actors.Grace.name + " to open a new staking position");
  {
    await createStakingPosition(actors.Grace, 0);
    console.groupEnd();
    console.log("");
  }

  console.group("Should allow " + actors.Heidi.name + " to open a new staking position");
  {
    await createStakingPosition(actors.Heidi, 1);
    console.groupEnd();
    console.log("");
  }

  console.group("Should allow " + actors.Isaac.name + " to open a new staking position");
  {
    await createStakingPosition(actors.Isaac, 0);
    console.groupEnd();
    console.log("");
  }

  console.group("Should allow " + actors.John.name + " to open a new staking position");
  {
    await createStakingPosition(actors.John, 0);
    console.groupEnd();
    console.log("");
  }


  console.log("* MULTIVERSE - test() - finished *");
};
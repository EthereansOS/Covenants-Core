const LiquidityMiningFactory = artifacts.require("LiquidityMiningFactory");
const LiquidityMining = artifacts.require("LiquidityMining");
const UniswapV2AMMV1 = artifacts.require("UniswapV2AMMV1");

const zero = "0x0000000000000000000000000000000000000000";
// TODO change orchestrator address
const orchestratorAddress = "0x12329b2F9e52C5D3422D6E6C026AA9D5b00CC075";
// TODO change reward token address
const rewardTokenAddress = zero;
// TODO change uniswap address
const uniswapAddress = "0x7a250d5630b4cf539739df2c5dacb4c659f2488d";
// TODO change liquidity pool token address
const liquidityPoolTokenAddress = zero;

contract("LiquidityMining", async accounts => {
    let factoryInstance = await LiquidityMiningFactory.deployed();
    let logicInstance = await LiquidityMining.deployed();
    let ammInstance = await UniswapV2AMMV1.deployed();
})
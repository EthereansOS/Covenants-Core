const { encodeCall } = require('@openzeppelin/upgrades');

const LiquidityMiningFactory = artifacts.require("LiquidityMiningFactory");
const LiquidityMining = artifacts.require("LiquidityMining");
const UniswapV2AMMV1 = artifacts.require("UniswapV2AMMV1");

const zero = "0x0000000000000000000000000000000000000000";
const orchestratorAddress = "0x12329b2F9e52C5D3422D6E6C026AA9D5b00CC075";
const rewardTokenAddress = "0x2823589Ae095D99bD64dEeA80B4690313e2fB519";
const uniswapAddress = "0x7a250d5630b4cf539739df2c5dacb4c659f2488d";
// TODO change liquidity pool token address
const liquidityPoolTokenAddress = zero;

contract("LiquidityMining", (accounts) => {
    let liquidityMiningContract;
    it("owner should deploy a new liquidity mining contract", async () => {
        liquidityMiningContract = await LiquidityMining.new(zero);
        await liquidityMiningContract.initialize(accounts[0], web3.utils.hexToBytes(web3.utils.toHex("")), orchestratorAddress, "TestCollection1", "TSTC", "test", rewardTokenAddress, false, { from: accounts[0] });
        assert.notEqual(liquidityMiningContract, zero);
    });
    it("should retrieve the correct factory address", async () => {
        const factoryAddress = await liquidityMiningContract.FACTORY.call();
        assert.equal(factoryAddress, zero);
    });
    it("should retrieve the position token collection", async () => {
        const positionTokenCollection = await liquidityMiningContract._positionTokenCollection.call();
        assert.notEqual(positionTokenCollection, zero);
    });
})
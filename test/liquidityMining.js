const LiquidityMiningFactory = artifacts.require("LiquidityMiningFactory");
const LiquidityMining = artifacts.require("LiquidityMining");
const UniswapV2AMMV1 = artifacts.require("UniswapV2AMMV1");

const zero = "0x0000000000000000000000000000000000000000";
const orchestratorAddress = "0x12329b2F9e52C5D3422D6E6C026AA9D5b00CC075";
const rewardTokenAddress = "0x2823589Ae095D99bD64dEeA80B4690313e2fB519";
const uniswapAddress = "0x7a250d5630b4cf539739df2c5dacb4c659f2488d";
// TODO change liquidity pool token address
const liquidityPoolTokenAddress = zero;

contract("LiquidityMining", async accounts => {
    const factoryInstance = await LiquidityMiningFactory.deployed();
    const logicInstance = await LiquidityMining.deployed();
    const ammInstance = await UniswapV2AMMV1.deployed();
    it("should set the factory logic address to the new one", async () => {
        assert.equal(factoryInstance.liquidityMiningImplementationAddress, zero);
        // Update the logic address in the factory
        await factoryInstance.updateLogicAddress(logicInstance.address);
        assert.equal(factoryInstance.liquidityMiningImplementationAddress, logicInstance.address);
    })
})
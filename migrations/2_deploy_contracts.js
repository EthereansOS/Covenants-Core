const LiquidityMiningFactory = artifacts.require("LiquidityMiningFactory");
const LiquidityMining = artifacts.require("LiquidityMining");
const AMM = artifacts.require("AMM");

// zero address
const zero = "0x0000000000000000000000000000000000000000";
// TODO change uniswap address
const uniswapAddress = zero;

module.exports = function(deployer) {
    deployer.then(async () => {
        // Deploy LiquidityMiningFactory contract
        await deployer.deploy(LiquidityMiningFactory, zero, zero);
        // Get the factory instance
        const factoryInstance = await LiquidityMiningFactory.deployed();
        // Deploy LiquidityMining contract
        await deployer.deploy(LiquidityMining, factoryInstance.address);
        // Get the logic instance
        const logicInstance = await LiquidityMining.deployed();
        // Update the logic address in the factory
        await factoryInstance.updateLogicAddress(logicInstance.address);
        // Deploy the AMM contract
        await deployer.deploy(AMM, uniswapAddress);
    })
}

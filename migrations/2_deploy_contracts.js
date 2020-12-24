const LiquidityMiningFactory = artifacts.require("LiquidityMiningFactory");
const LiquidityMining = artifacts.require("LiquidityMining");
const UniswapV2AMMV1 = artifacts.require("UniswapV2AMMV1");
const MainToken = artifacts.require("MainToken");
const SecondaryToken = artifacts.require("SecondaryToken");
const RewardToken = artifacts.require("RewardToken");

// zero address
const zero = "0x0000000000000000000000000000000000000000";
const uniswapAddress = "0x7a250d5630b4cf539739df2c5dacb4c659f2488d";

module.exports = function(deployer) {
    deployer.then(async () => {
        // Deploy the UniswapV2AMMV1 contract
        await deployer.deploy(UniswapV2AMMV1, uniswapAddress);
        // Deploy LiquidityMiningFactory contract
        await deployer.deploy(LiquidityMiningFactory, zero, zero);
        // Get the factory instance
        const factoryInstance = await LiquidityMiningFactory.deployed();
        // Deploy LiquidityMining contract
        await deployer.deploy(LiquidityMining, factoryInstance.address);
        // Deploy the MainToken contract
        await deployer.deploy(MainToken, web3.eth.accounts[1], web3.eth.accounts[2]);
        // Deploy the SecondaryToken contract
        await deployer.deploy(SecondaryToken, web3.eth.accounts[1], web3.eth.accounts[2]);
        // Deploy the RewardToken contract
        await deployer.deploy(RewardToken)
    })
}

const { encodeCall } = require('@openzeppelin/upgrades');

const LiquidityMiningFactory = artifacts.require("LiquidityMiningFactory");
const LiquidityMining = artifacts.require("LiquidityMining");
const UniswapV2AMMV1 = artifacts.require("UniswapV2AMMV1");

const zero = "0x0000000000000000000000000000000000000000";
const orchestratorAddress = "0x12329b2F9e52C5D3422D6E6C026AA9D5b00CC075";
const rewardTokenAddress = "0x2823589Ae095D99bD64dEeA80B4690313e2fB519";
const mainTokenAddress = zero;
// TODO change liquidity pool token address
const liquidityPoolTokenAddress = zero;

contract("LiquidityMining", (accounts) => {
    let liquidityMiningContract;
    let ammInstance;
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
    it("should get the 0 exit fee", async () => {
        const exitFee = await liquidityMiningContract._exitFee.call();
        assert.equal(exitFee, 0);
    });
    it("should update the exit fee", async () => {
        await liquidityMiningContract.setExitFee(1, { from: accounts[0] });
        const exitFee = await liquidityMiningContract._exitFee.call();
        assert.equal(exitFee, 1);
    });
    it("should not update the exit fee", async () => {
        try {
            await liquidityMiningContract.setExitFee(0, { from: accounts[1] });
            assert.equal(true, false);
        } catch (error) {
            assert(error, "Only the owner can update the exit fee.");
        }
    });
    it("should set the farming setups", async () => {
        ammInstance = await UniswapV2AMMV1.deployed();
        const startBlock = await web3.eth.getBlockNumber() + 1;
        const endBlock = startBlock + 9999;
        const rewardPerBlock = 1500;
        const setups = [
            {
                ammPlugin: ammInstance.address, 
                liquidityPoolTokenAddress: zero, 
                startBlock: startBlock, 
                endBlock: endBlock, 
                rewardPerBlock: rewardPerBlock, 
                maximumLiquidity: rewardPerBlock * (endBlock - startBlock), 
                totalSupply: 0, 
                lastBlockUpdate: currentBlock + 1, 
                mainTokenAddress: mainTokenAddress, 
                secondaryTokenAddresses: [zero], 
                free: false
            }
        ];
        const result = await liquidityMiningContract.setFarmingSetups(setups, { from: accounts[0] });
        assert.notEqual(result, null);
    });
    it("should not set the farming setups", async () => {
        try {
            const setups = [
                {
                    ammPlugin: zero, 
                    liquidityPoolTokenAddress: zero, 
                    startBlock: 0, 
                    endBlock: 1, 
                    rewardPerBlock: 0, 
                    maximumLiquidity: 0, 
                    totalSupply: 0, 
                    lastBlockUpdate: 0, 
                    mainTokenAddress: zero, 
                    secondaryTokenAddresses: [zero], 
                    free: false
                }
            ];            
            await liquidityMiningContract.setFarmingSetups(setups, { from: accounts[1] });
            assert.equal(true, false);
        } catch (error) {
            assert(error, "Only the owner can set the farming setups.");
        }
    });
    it("should set a new staking position", async () => {

    });
})
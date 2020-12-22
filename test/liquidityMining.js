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

const initializeFunctionInterface = require('./function.json');

let factoryInstance;
let logicInstance;

contract("LiquidityMiningFactory", (accounts) => {
    it("should set the factory logic address to the new one", async () => {
        factoryInstance = await LiquidityMiningFactory.deployed();
        logicInstance = await LiquidityMining.deployed();
        let currentLogicAddress = await factoryInstance.liquidityMiningImplementationAddress.call();
        assert.equal(currentLogicAddress, zero);
        // Update the logic address in the factory
        await factoryInstance.updateLogicAddress(logicInstance.address);
        currentLogicAddress = await factoryInstance.liquidityMiningImplementationAddress.call();
        assert.equal(currentLogicAddress, logicInstance.address);
    });
    it("not owner should not update logic implementation address", async () => {
        try {
            await factoryInstance.updateLogicAddress(zero)
        } catch (error) {
            assert(error, "Expected error.");
        }
    })
});

contract("LiquidityMining", (accounts) => {
    let liquidityMiningContract;
    let clonedAddress;
    it("owner should deploy a new liquidity mining contract", async () => {
        const encodedFunctionCall = encodeCall(
            'initialize',
            [
                'address',
                'bytes',
                'address',
                'string',
                'string',
                'string',
                'address',
                'bool'
            ],
            [
                accounts[0],
                web3.utils.hexToBytes(web3.utils.toHex("")),
                orchestratorAddress,
                "TestCollection1",
                "TSTC",
                "",
                rewardTokenAddress,
                false
            ]
        );
        console.log(encodedFunctionCall);
        const newClonedResult = await factoryInstance.deploy(encodedFunctionCall, { from: accounts[0] });
        clonedAddress = newClonedResult.logs[0].args.contractAddress;
        console.log(clonedAddress);
        assert.notEqual(clonedAddress, zero);
    });
    it("should retrieve the clone contract at the given address", async () => {
        liquidityMiningContract = await LiquidityMining.at(clonedAddress);
        assert.notEqual(liquidityMiningContract, null);
    });
    it("should retrieve the correct factory address", async () => {
        liquidityMiningContract = await LiquidityMining.at(clonedAddress);
        const factoryAddress = await liquidityMiningContract.FACTORY.call();
        console.log(factoryAddress);
        assert.equal(factoryAddress, factoryInstance.address);
    });
    it("should retrieve the position token collection", async () => {
        liquidityMiningContract = await LiquidityMining.at(clonedAddress);
        const positionTokenCollection = await liquidityMiningContract._positionTokenCollection.call();
        console.log(positionTokenCollection);
        assert.notEqual(positionTokenCollection, zero);
    });
})
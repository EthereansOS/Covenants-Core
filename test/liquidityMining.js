const LiquidityMiningFactory = artifacts.require("LiquidityMiningFactory");
const LiquidityMining = artifacts.require("LiquidityMining");
const AMM = artifacts.require("AMM");

const zero = "0x0000000000000000000000000000000000000000";
const initializeInputs = [
    {
      "internalType": "address",
      "name": "owner",
      "type": "address"
    },
    {
      "internalType": "bytes",
      "name": "ownerInitData",
      "type": "bytes"
    },
    {
      "internalType": "address",
      "name": "orchestrator",
      "type": "address"
    },
    {
      "internalType": "string",
      "name": "name",
      "type": "string"
    },
    {
      "internalType": "string",
      "name": "symbol",
      "type": "string"
    },
    {
      "internalType": "string",
      "name": "collectionUri",
      "type": "string"
    },
    {
      "internalType": "address",
      "name": "rewardTokenAddress",
      "type": "address"
    },
    {
      "internalType": "bool",
      "name": "byMint",
      "type": "bool"
    },
    {
      "components": [
        {
          "internalType": "address",
          "name": "ammPlugin",
          "type": "address"
        },
        {
          "internalType": "address",
          "name": "liquidityPoolTokenAddress",
          "type": "address"
        },
        {
          "internalType": "uint256",
          "name": "startBlock",
          "type": "uint256"
        },
        {
          "internalType": "uint256",
          "name": "endBlock",
          "type": "uint256"
        },
        {
          "internalType": "uint256",
          "name": "rewardPerBlock",
          "type": "uint256"
        },
        {
          "internalType": "uint256",
          "name": "maximumLiquidity",
          "type": "uint256"
        },
        {
          "internalType": "uint256",
          "name": "totalSupply",
          "type": "uint256"
        },
        {
          "internalType": "uint256",
          "name": "rewardPerToken",
          "type": "uint256"
        },
        {
          "internalType": "uint256",
          "name": "lastBlockUpdate",
          "type": "uint256"
        },
        {
          "internalType": "address",
          "name": "mainTokenAddress",
          "type": "address"
        },
        {
          "internalType": "address[]",
          "name": "secondaryTokenAddresses",
          "type": "address[]"
        },
        {
          "internalType": "bool",
          "name": "free",
          "type": "bool"
        },
        {
          "internalType": "bool",
          "name": "pinned",
          "type": "bool"
        }
      ],
      "internalType": "struct LiquidityMining.FarmingSetup[]",
      "name": "farmingSetups",
      "type": "tuple[]"
    }
];
// TODO change orchestrator address
const orchestratorAddress = zero;
// TODO change reward token address
const rewardTokenAddress = zero;
// TODO change uniswap address
const uniswapAddress = zero;
// TODO change liquidity pool token address
const liquidityPoolTokenAddress = zero;

contract("LiquidityMining", async accounts => {
    let factoryInstance;
    let logicInstance;
    let cloneInstanceAddress;
    let ammInstance;
    it("should deploy an AMM instance", async () => {
      ammInstance = await AMM.deployed(uniswapAddress);
    })
    it("should deploy a LiquidityMiningFactory instance", async () => {
        factoryInstance = await LiquidityMiningFactory.deployed(zero, zero);
        assert.equal(factoryInstance.liquidityMiningImplementationAddress, zero);
    });
    it("should deploy a LiquidityMining logic contract instance", async () => {
        logicInstance = await LiquidityMining.deployed(factoryInstance.address);
        assert.equal(logicInstance.FACTORY, factoryInstance.address);
    });
    it("should set the LiquidityMining logic contract address into the factory", async () => {
        await LiquidityMiningFactory.updateLogicAddress(logicInstance.address);
    });
    it("should deploy a LiquidityMining contract clone using the factory", async () => {
        const initializationCall = web3.eth.encodeFunctionCall({
            name: 'initialize',
            type: 'function',
            inputs: initializeInputs,
        }, [accounts[0], "", orchestratorAddress, "Collection", "LMC", "", true, []]);
        cloneInstanceAddress = await factoryInstance.deploy.call(initializationCall);
    })
})
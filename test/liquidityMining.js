const LiquidityMining = artifacts.require("LiquidityMining");
const UniswapV2AMMV1 = artifacts.require("UniswapV2AMMV1");
const MainToken = artifacts.require("MainToken");
const RewardToken = artifacts.require("RewardToken");
const SecondaryToken = artifacts.require("SecondaryToken");

const zero = "0x0000000000000000000000000000000000000000";
const orchestratorAddress = "0x12329b2F9e52C5D3422D6E6C026AA9D5b00CC075";
const uniswapFactoryAddress = "0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f";
const uniswapFactoryAbi = {
    "abi": [
      {
        "anonymous": false,
        "inputs": [
          {
            "indexed": true,
            "internalType": "address",
            "name": "token0",
            "type": "address"
          },
          {
            "indexed": true,
            "internalType": "address",
            "name": "token1",
            "type": "address"
          },
          {
            "indexed": false,
            "internalType": "address",
            "name": "pair",
            "type": "address"
          },
          {
            "indexed": false,
            "internalType": "uint256",
            "name": "",
            "type": "uint256"
          }
        ],
        "name": "PairCreated",
        "type": "event"
      },
      {
        "constant": true,
        "inputs": [
          {
            "internalType": "uint256",
            "name": "",
            "type": "uint256"
          }
        ],
        "name": "allPairs",
        "outputs": [
          {
            "internalType": "address",
            "name": "pair",
            "type": "address"
          }
        ],
        "payable": false,
        "stateMutability": "view",
        "type": "function"
      },
      {
        "constant": true,
        "inputs": [],
        "name": "allPairsLength",
        "outputs": [
          {
            "internalType": "uint256",
            "name": "",
            "type": "uint256"
          }
        ],
        "payable": false,
        "stateMutability": "view",
        "type": "function"
      },
      {
        "constant": false,
        "inputs": [
          {
            "internalType": "address",
            "name": "tokenA",
            "type": "address"
          },
          {
            "internalType": "address",
            "name": "tokenB",
            "type": "address"
          }
        ],
        "name": "createPair",
        "outputs": [
          {
            "internalType": "address",
            "name": "pair",
            "type": "address"
          }
        ],
        "payable": false,
        "stateMutability": "nonpayable",
        "type": "function"
      },
      {
        "constant": true,
        "inputs": [],
        "name": "feeTo",
        "outputs": [
          {
            "internalType": "address",
            "name": "",
            "type": "address"
          }
        ],
        "payable": false,
        "stateMutability": "view",
        "type": "function"
      },
      {
        "constant": true,
        "inputs": [],
        "name": "feeToSetter",
        "outputs": [
          {
            "internalType": "address",
            "name": "",
            "type": "address"
          }
        ],
        "payable": false,
        "stateMutability": "view",
        "type": "function"
      },
      {
        "constant": true,
        "inputs": [
          {
            "internalType": "address",
            "name": "tokenA",
            "type": "address"
          },
          {
            "internalType": "address",
            "name": "tokenB",
            "type": "address"
          }
        ],
        "name": "getPair",
        "outputs": [
          {
            "internalType": "address",
            "name": "pair",
            "type": "address"
          }
        ],
        "payable": false,
        "stateMutability": "view",
        "type": "function"
      },
      {
        "constant": false,
        "inputs": [
          {
            "internalType": "address",
            "name": "",
            "type": "address"
          }
        ],
        "name": "setFeeTo",
        "outputs": [],
        "payable": false,
        "stateMutability": "nonpayable",
        "type": "function"
      },
      {
        "constant": false,
        "inputs": [
          {
            "internalType": "address",
            "name": "",
            "type": "address"
          }
        ],
        "name": "setFeeToSetter",
        "outputs": [],
        "payable": false,
        "stateMutability": "nonpayable",
        "type": "function"
      }
    ],
    "evm": {
      "bytecode": {
        "linkReferences": {},
        "object": "",
        "opcodes": "",
        "sourceMap": ""
      },
      "deployedBytecode": {
        "linkReferences": {},
        "object": "",
        "opcodes": "",
        "sourceMap": ""
      }
    },
    "interface": [
      {
        "anonymous": false,
        "inputs": [
          {
            "indexed": true,
            "internalType": "address",
            "name": "token0",
            "type": "address"
          },
          {
            "indexed": true,
            "internalType": "address",
            "name": "token1",
            "type": "address"
          },
          {
            "indexed": false,
            "internalType": "address",
            "name": "pair",
            "type": "address"
          },
          {
            "indexed": false,
            "internalType": "uint256",
            "name": "",
            "type": "uint256"
          }
        ],
        "name": "PairCreated",
        "type": "event"
      },
      {
        "constant": true,
        "inputs": [
          {
            "internalType": "uint256",
            "name": "",
            "type": "uint256"
          }
        ],
        "name": "allPairs",
        "outputs": [
          {
            "internalType": "address",
            "name": "pair",
            "type": "address"
          }
        ],
        "payable": false,
        "stateMutability": "view",
        "type": "function"
      },
      {
        "constant": true,
        "inputs": [],
        "name": "allPairsLength",
        "outputs": [
          {
            "internalType": "uint256",
            "name": "",
            "type": "uint256"
          }
        ],
        "payable": false,
        "stateMutability": "view",
        "type": "function"
      },
      {
        "constant": false,
        "inputs": [
          {
            "internalType": "address",
            "name": "tokenA",
            "type": "address"
          },
          {
            "internalType": "address",
            "name": "tokenB",
            "type": "address"
          }
        ],
        "name": "createPair",
        "outputs": [
          {
            "internalType": "address",
            "name": "pair",
            "type": "address"
          }
        ],
        "payable": false,
        "stateMutability": "nonpayable",
        "type": "function"
      },
      {
        "constant": true,
        "inputs": [],
        "name": "feeTo",
        "outputs": [
          {
            "internalType": "address",
            "name": "",
            "type": "address"
          }
        ],
        "payable": false,
        "stateMutability": "view",
        "type": "function"
      },
      {
        "constant": true,
        "inputs": [],
        "name": "feeToSetter",
        "outputs": [
          {
            "internalType": "address",
            "name": "",
            "type": "address"
          }
        ],
        "payable": false,
        "stateMutability": "view",
        "type": "function"
      },
      {
        "constant": true,
        "inputs": [
          {
            "internalType": "address",
            "name": "tokenA",
            "type": "address"
          },
          {
            "internalType": "address",
            "name": "tokenB",
            "type": "address"
          }
        ],
        "name": "getPair",
        "outputs": [
          {
            "internalType": "address",
            "name": "pair",
            "type": "address"
          }
        ],
        "payable": false,
        "stateMutability": "view",
        "type": "function"
      },
      {
        "constant": false,
        "inputs": [
          {
            "internalType": "address",
            "name": "",
            "type": "address"
          }
        ],
        "name": "setFeeTo",
        "outputs": [],
        "payable": false,
        "stateMutability": "nonpayable",
        "type": "function"
      },
      {
        "constant": false,
        "inputs": [
          {
            "internalType": "address",
            "name": "",
            "type": "address"
          }
        ],
        "name": "setFeeToSetter",
        "outputs": [],
        "payable": false,
        "stateMutability": "nonpayable",
        "type": "function"
      }
    ],
    "bytecode": ""
  };

contract("LiquidityMining", (accounts) => {
    let liquidityMiningContract;
    let ammInstance;
    let mainTokenInstance;
    let secondaryTokenInstance;
    let rewardTokenInstance;
    let uniswapFactoryContract;
    let liquidityPoolTokenAddress = zero;
    it("owner should deploy a new liquidity mining contract", async () => {
        liquidityMiningContract = await LiquidityMining.new(zero);
        rewardTokenInstance = await RewardToken.deployed();
        await liquidityMiningContract.initialize(accounts[0], web3.utils.hexToBytes(web3.utils.toHex("")), orchestratorAddress, "TestCollection1", "TSTC", "test", rewardTokenInstance.address, false, { from: accounts[0] });
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
        mainTokenInstance = await MainToken.deployed();
        secondaryTokenInstance = await SecondaryToken.deployed();
        mainTokenInstance.approve(liquidityMiningContract.address, await mainTokenInstance.balanceOf(accounts[1]), { from: accounts[1] });
        secondaryTokenInstance.approve(liquidityMiningContract.address, await secondaryTokenInstance.balanceOf(accounts[1]), { from: accounts[1] });
        uniswapFactoryContract = new web3.eth.Contract(uniswapFactoryAbi.abi, uniswapFactoryAddress);
        try {
            await uniswapFactoryContract.methods.createPair(mainTokenInstance.address, secondaryTokenInstance.address).send({ from: accounts[0], gas: 67219750 });
            liquidityPoolTokenAddress = await uniswapFactoryContract.methods.getPair(mainTokenInstance.address, secondaryTokenInstance.address).call(); 
        } catch (error) {
            liquidityPoolTokenAddress = await uniswapFactoryContract.methods.getPair(mainTokenInstance.address, secondaryTokenInstance.address).call(); 
        }
        const startBlock = await web3.eth.getBlockNumber() + 1;
        const endBlock = startBlock + 9999;
        const rewardPerBlock = 1500;
        const setups = [
            {
                ammPlugin: ammInstance.address, 
                liquidityPoolTokenAddress, 
                startBlock: startBlock, 
                endBlock: endBlock, 
                rewardPerBlock: rewardPerBlock, 
                maximumLiquidity: rewardPerBlock * (endBlock - startBlock), 
                totalSupply: 0, 
                lastBlockUpdate: 0, 
                mainTokenAddress: mainTokenInstance.address, 
                secondaryTokenAddresses: [secondaryTokenInstance.address], 
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
        const mainTokenAmount = web3.utils.toWei('100', 'ether');
        const secondaryTokenAmount = web3.utils.toWei('0.1', 'ether');
        const stake = {
            setupIndex: 0,
            secondaryTokenAddress: secondaryTokenInstance.address,
            liquidityPoolTokenAmount: 0,
            mainTokenAmount,
            secondaryTokenAmount,
            positionOwner: zero,
            mintPositionToken: false,
        };
        const result = await liquidityMiningContract.stake(stake, { from: accounts[1] });
        assert.notEqual(result, null);
    });
})
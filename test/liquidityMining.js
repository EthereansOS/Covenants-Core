const LiquidityMiningFactory = artifacts.require("LiquidityMiningFactory");
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
    let liquidityMiningInstance;
    let ammInstance;
    let factoryInstance;
    let mainTokenInstance;
    let secondaryTokenInstance;
    let rewardTokenInstance;
    let uniswapFactoryContract;
    let liquidityPoolTokenAddress = zero;
    it("owner should deploy a new liquidity mining contract", async () => {
        liquidityMiningInstance = await LiquidityMining.deployed();
        rewardTokenInstance = await RewardToken.deployed();
        await liquidityMiningInstance.initialize(accounts[0], web3.utils.hexToBytes(web3.utils.randomHex(32)), orchestratorAddress, "TestCollection1", "TSTC", "test", rewardTokenInstance.address, false, { from: accounts[0] });
        assert.notEqual(liquidityMiningInstance, zero);
    });
    it("should retrieve the correct factory address", async () => {
      factoryInstance = await LiquidityMiningFactory.deployed();
        const factoryAddress = await liquidityMiningInstance.FACTORY.call();
        assert.equal(factoryAddress, factoryInstance.address);
    });
    it("should retrieve the position token collection", async () => {
        const positionTokenCollection = await liquidityMiningInstance._positionTokenCollection.call();
        assert.notEqual(positionTokenCollection, zero);
    });
    it("should get the 0 exit fee", async () => {
        const exitFee = await liquidityMiningInstance._exitFee.call();
        assert.equal(exitFee, 0);
    });
    it("should update the exit fee", async () => {
        await liquidityMiningInstance.setExitFee(1, { from: accounts[0] });
        const exitFee = await liquidityMiningInstance._exitFee.call();
        assert.equal(exitFee, 1);
    });
    it("should not update the exit fee", async () => {
        try {
            await liquidityMiningInstance.setExitFee(0, { from: accounts[1] });
            assert.equal(true, false);
        } catch (error) {
            assert(error, "Only the owner can update the exit fee.");
        }
    });
    it("should set the farming setups", async () => {
        ammInstance = await UniswapV2AMMV1.deployed();
        mainTokenInstance = await MainToken.deployed();
        secondaryTokenInstance = await SecondaryToken.deployed();
        const mainTokenBalance = await mainTokenInstance.balanceOf(accounts[1]);
        const secondaryTokenBalance = await secondaryTokenInstance.balanceOf(accounts[1]);
        mainTokenInstance.approve(liquidityMiningInstance.address, mainTokenBalance, { from: accounts[1] });
        secondaryTokenInstance.approve(liquidityMiningInstance.address, secondaryTokenBalance, { from: accounts[1] });
        uniswapFactoryContract = new web3.eth.Contract(uniswapFactoryAbi.abi, uniswapFactoryAddress);
        try {
            await uniswapFactoryContract.methods.createPair(mainTokenInstance.address, secondaryTokenInstance.address).send({ from: accounts[0], gas: 67219750 });
            liquidityPoolTokenAddress = await uniswapFactoryContract.methods.getPair(mainTokenInstance.address, secondaryTokenInstance.address).call(); 
        } catch (error) {
            liquidityPoolTokenAddress = await uniswapFactoryContract.methods.getPair(mainTokenInstance.address, secondaryTokenInstance.address).call(); 
        }
        const startBlock = await web3.eth.getBlockNumber() + 1;
        const endBlock = startBlock + 9999;
        const rewardPerBlock = parseInt(web3.utils.toWei('0.001', 'ether'));
        const setups = [
            {
                ammPlugin: ammInstance.address, 
                liquidityPoolTokenAddress, 
                startBlock: startBlock, 
                endBlock: endBlock, 
                rewardPerBlock: rewardPerBlock, 
                maximumLiquidity: (rewardPerBlock * (endBlock - startBlock)).toString(), 
                totalSupply: 0, 
                lastBlockUpdate: 0, 
                mainTokenAddress: mainTokenInstance.address, 
                secondaryTokenAddresses: [secondaryTokenInstance.address], 
                free: false
            }
        ];
        const result = await liquidityMiningInstance.setFarmingSetups(setups, { from: accounts[0] });
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
            await liquidityMiningInstance.setFarmingSetups(setups, { from: accounts[1] });
            assert.equal(true, false);
        } catch (error) {
            assert(error, "Only the owner can set the farming setups.");
        }
    });
    it("should set a new staking position", async () => {
        const mainTokenAmount = web3.utils.toWei('0.001', 'ether');
        const secondaryTokenAmount = web3.utils.toWei('0.001', 'ether');
        const stake = {
            setupIndex: 0,
            secondaryTokenAddress: secondaryTokenInstance.address,
            liquidityPoolTokenAmount: 0,
            mainTokenAmount,
            secondaryTokenAmount,
            positionOwner: zero,
            mintPositionToken: false,
        };
        const result = await liquidityMiningInstance.stake(stake, { from: accounts[1] });
        assert.notEqual(result, null);
    });
})
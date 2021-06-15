var assert = require("assert");
var utilities = require("../util/utilities");
var context = require("../util/context.json");
var compile = require("../util/compile");
var blockchainConnection = require("../util/blockchainConnection");
var dfoManager = require('../util/dfo');
var dfoHubManager = require('../util/dfoHub');
var ethers = require('ethers');
var abi = new ethers.utils.AbiCoder();
var path = require('path');
var fs = require('fs');

describe('disableOldSetup', () => {

    var IFarmExtension;
    var FarmMain;

    before(async () => {
        await blockchainConnection.init;
        await dfoHubManager.init;
        IFarmExtension = await compile('farming/IFarmExtension');
        FarmMain = await compile('farming/FarmMain');
    });

    async function disable(dfoName, list, disable) {
        var stateHolder = dfoHubManager.dfos[dfoName].stateHolder;
        var toDisable = {};
        var balances = {};
        for(var host of list) {
            toDisable[host] = toDisable[host] || [];
            //assert(await stateHolder.methods.getBool('farming.authorized.' + host.toLowerCase()).call());
            var ext = new web3.eth.Contract(IFarmExtension.abi, host);
            var data = await ext.methods.data().call();
            var farmMainContractAddress = data[0];
            var farmMain = new web3.eth.Contract(FarmMain.abi, farmMainContractAddress);
            var rewardTokenAddress = await farmMain.methods._rewardTokenAddress().call();
            var rewardToken = new web3.eth.Contract(context.IERC20ABI, rewardTokenAddress);
            balances[farmMainContractAddress] = {
                rewardToken,
                before : await rewardToken.methods.balanceOf(farmMainContractAddress).call()
            }
            var _farmingSetupsCount = await farmMain.methods._farmingSetupsCount().call();
            for(var i = 0; i < _farmingSetupsCount; i++) {
                var setupData = await loadFarmingSetup(farmMain, i);
                if(setupData[0].active === 'false' || setupData[1].renewTimes === '0') {
                    continue;
                }
                if(toDisable[host].filter(it => it[1].lastSetupIndex === setupData[1].lastSetupIndex).length === 0) {
                    var st = setupData[1].lastSetupIndex === (i + '') ? setupData : await loadFarmingSetup(farmMain, setupData[1].lastSetupIndex);
                    setupData[0] = st[0];
                    toDisable[host].push(setupData);
                }
            }
        }
        /*if(disable && disable.length > 0) {
            for(var d of disable) {
                assert(await stateHolder.methods.getBool('farming.authorized.' + d.toLowerCase()).call());
            }
        }*/
        var index = 0;
        var keys = Object.keys(toDisable);
        var calls = [];
        var methods = [];
        for(var host of keys) {
            if(toDisable[host].length === 0) {
                continue;
            }
            var setupDatas = toDisable[host];
            var pos = index++;
            calls.push('_meth_' + pos + '();');
            var suffix = setupDatas[0][1].old ? 'Old' : '';
            var method = 'function _meth_' + pos + '() private {\n';
            method += `        FarmingSetupConfiguration${suffix}[] memory configurations = new FarmingSetupConfiguration${suffix}[](${setupDatas.length});\n`
            for(var i in setupDatas) {
                var info = setupDatas[i][1];
                method += `        configurations[${i}] = FarmingSetupConfiguration${suffix}(false, false, ${info.lastSetupIndex}, FarmingSetupInfo${suffix}(${info.free}, ${info.blockDuration}, ${suffix ? '' : info.startBlock + ', '}${info.originalRewardPerBlock}, ${info.minStakeable}, ${info.maxStakeable}, 0, ${web3.utils.toChecksumAddress(info.ammPlugin)}, ${web3.utils.toChecksumAddress(info.liquidityPoolTokenAddress)}, ${web3.utils.toChecksumAddress(info.mainTokenAddress)}, ${web3.utils.toChecksumAddress(info.ethereumAddress)}, ${info.involvingETH}, ${info.penaltyFee}, ${info.setupsCount}, ${info.lastSetupIndex}));\n`
            }
            method += `        IFarmExtension${suffix}(${web3.utils.toChecksumAddress(host)}).setFarmingSetups(configurations);`
            methods.push(method + '\n    }')
        }

        /*if(disable && disable.length > 0) {
            calls.push('IStateHolder stateHolder = IStateHolder(IMVDProxy(msg.sender).getStateHolderAddress());');
            for(var d of disable) {
                calls.push(`stateHolder.setBool("farming.authorized.${d.toLowerCase()}", false);`);
            }
        }*/

        var code = `/* Discussion:
 * //discord.com/invite/66tafq3
 */
/* Description:
 * Preparation to Uniswap V3 farm
 */
//SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma abicoder v2;

contract ProposalCode {
    string private _metadataLink;

    constructor(string memory metadataLink) {
        _metadataLink = metadataLink;
    }

    function getMetadataLink() public view returns (string memory) {
        return _metadataLink;
    }

    function callOneTime(address) public {
        ${calls.join('\n        ')}
    }

    ${methods.join('\n\n    ')}
}

interface IMVDProxy {
    function getStateHolderAddress() external view returns(address);
}

interface IStateHolder {
    function setBool(string calldata varName, bool val) external returns(bool);
}

struct FarmingSetupInfo {
    bool free; // if the setup is a free farming setup or a locked one.
    uint256 blockDuration; // duration of setup
    uint256 startBlock; // optional start block used for the delayed activation of the first setup
    uint256 originalRewardPerBlock;
    uint256 minStakeable; // minimum amount of staking tokens.
    uint256 maxStakeable; // maximum amount stakeable in the setup (used only if free is false).
    uint256 renewTimes; // if the setup is renewable or if it's one time.
    address ammPlugin; // amm plugin address used for this setup (eg. uniswap amm plugin address).
    address liquidityPoolTokenAddress; // address of the liquidity pool token
    address mainTokenAddress; // eg. buidl address.
    address ethereumAddress;
    bool involvingETH; // if the setup involves ETH or not.
    uint256 penaltyFee; // fee paid when the user exits a still active locked farming setup (used only if free is false).
    uint256 setupsCount; // number of setups created by this info.
    uint256 lastSetupIndex; // index of last setup;
}

struct FarmingSetupInfoOld {
    bool free; // if the setup is a free farming setup or a locked one.
    uint256 blockDuration; // duration of setup
    uint256 originalRewardPerBlock;
    uint256 minStakeable; // minimum amount of staking tokens.
    uint256 maxStakeable; // maximum amount stakeable in the setup (used only if free is false).
    uint256 renewTimes; // if the setup is renewable or if it's one time.
    address ammPlugin; // amm plugin address used for this setup (eg. uniswap amm plugin address).
    address liquidityPoolTokenAddress; // address of the liquidity pool token
    address mainTokenAddress; // eg. buidl address.
    address ethereumAddress;
    bool involvingETH; // if the setup involves ETH or not.
    uint256 penaltyFee; // fee paid when the user exits a still active locked farming setup (used only if free is false).
    uint256 setupsCount; // number of setups created by this info.
    uint256 lastSetupIndex; // index of last setup;
}

struct FarmingSetupConfiguration {
    bool add; // true if we're adding a new setup, false we're updating it.
    bool disable;
    uint256 index; // index of the setup we're updating.
    FarmingSetupInfo info; // data of the new or updated setup
}

struct FarmingSetupConfigurationOld {
    bool add; // true if we're adding a new setup, false we're updating it.
    bool disable;
    uint256 index; // index of the setup we're updating.
    FarmingSetupInfoOld info; // data of the new or updated setup
}

interface IFarmExtension {
    function setFarmingSetups(FarmingSetupConfiguration[] memory farmingSetups) external;
}

interface IFarmExtensionOld {
    function setFarmingSetups(FarmingSetupConfigurationOld[] memory farmingSetups) external;
}`;

        console.log(`==== ${dfoName} ====`);
        console.log(code);

        var proposal = await dfoHubManager.createProposal(dfoName, '', true, code, 'callOneTime(address)');
        await dfoHubManager.finalizeProposal(proposal);

        /*for(var host of list) {
            if(!disable || disable.length === 0 || disable.filter(it => it.toLowerCase() === host.toLowerCase()).length === 0) {
                assert(await stateHolder.methods.getBool('farming.authorized.' + host.toLowerCase()).call());
            }
            var ext = new web3.eth.Contract(IFarmExtension.abi, host);
            var data = await ext.methods.data().call();
            var farmMainContractAddress = data[0];
            var farmMain = new web3.eth.Contract(FarmMain.abi, farmMainContractAddress);
            var _farmingSetupsCount = await farmMain.methods._farmingSetupsCount().call();
            assert.strictEqual(balances[farmMainContractAddress].before, await balances[farmMainContractAddress].rewardToken.methods.balanceOf(farmMainContractAddress).call());
            for(var i = 0; i < _farmingSetupsCount; i++) {
                var setupData = await loadFarmingSetup(farmMain, i);
                assert.strictEqual(setupData[1].renewTimes, '0');
                if(toDisable[host] && toDisable[host].length > 0 && toDisable[host].filter(it => it[1].lastSetupIndex === (i + '')).length > 0) {
                    var setup = toDisable[host].filter(it => it[1].lastSetupIndex === (i + ''))[0][0];
                    assert.strictEqual(JSON.stringify(setup), JSON.stringify(setupData[0]));
                }
            }
        }

        if(disable && disable.length > 0) {
            for(var d of disable) {
                assert(!(await stateHolder.methods.getBool('farming.authorized.' + d.toLowerCase()).call()));
            }
        }*/
    };

    async function loadFarmingSetup(contract, i) {

        try {
            return await contract.methods.setup(i).call();
        } catch(e) {
        }

        var models = {
            setup : {
                types : [
                    "uint256",
                    "bool",
                    "uint256",
                    "uint256",
                    "uint256",
                    "uint256",
                    "uint256",
                    "uint256"
                ],
                names : [
                    "infoIndex",
                    "active",
                    "startBlock",
                    "endBlock",
                    "lastUpdateBlock",
                    "objectId",
                    "rewardPerBlock",
                    "totalSupply"
                ]
            },
            info : {
                types : [
                    "bool",
                    "uint256",
                    "uint256",
                    "uint256",
                    "uint256",
                    "uint256",
                    "address",
                    "address",
                    "address",
                    "address",
                    "bool",
                    "uint256",
                    "uint256",
                    "uint256"
                ],
                names : [
                    "free",
                    "blockDuration",
                    "originalRewardPerBlock",
                    "minStakeable",
                    "maxStakeable",
                    "renewTimes",
                    "ammPlugin",
                    "liquidityPoolTokenAddress",
                    "mainTokenAddress",
                    "ethereumAddress",
                    "involvingETH",
                    "penaltyFee",
                    "setupsCount",
                    "lastSetupIndex"
                ]
            }
        };
        var data = await this.web3.eth.call({
            to : contract.options.address,
            data : contract.methods.setup(i).encodeABI()
        });
        var types = [
            `tuple(${models.setup.types.join(',')})`,
            `tuple(${models.info.types.join(',')})`
        ];
        try {
            data = abi.decode(types, data);
        } catch(e) {
        }
        var setup = {};
        for(var i in models.setup.names) {
            var name = models.setup.names[i];
            var value = data[0][i];
            value !== true && value !== false && (value = value.toString());
            setup[name] = value;
        }
        var info = {};
        for(var i in models.info.names) {
            var name = models.info.names[i];
            var value = data[1][i];
            value !== true && value !== false && (value = value.toString());
            info[name] = value;
        }
        info.old = info.startBlock === undefined || info.startBlock === null;
        info.startBlock = info.startBlock || "0";
        return [setup, info];
    };

    it('Disable Renew Times', async () => {
        await disable('dfoHub', ['0x4b508bfcdadddbe752d85ba2fd2b5e1c7c99ba7b','0xdf37f0a1d703cbdde29bf9d7552dc492dec5ee62', '0x71e3c09f5c9e4780768e81b19f09dec2e73246b6', '0xDAaD37adca880E064D64dE81B3f959D6d2A51bfF', '0xC41c26e1a761226f66009F20720F820bd721a52E']);
        await disable('covenants', ['0xc90825B09B1F31D2872788CdaBb1A259F110D30F','0xB00F2EfcEB0B1155f909Aba4e046534DaDf42166'], ['0xc90825B09B1F31D2872788CdaBb1A259F110D30F']);
        await disable('item', ['0xD6bd9fc2Ad393a6EeF0184028751dFC112dA8810']);
//        var hosts = ['0x4b508bfcdadddbe752d85ba2fd2b5e1c7c99ba7b','0xdf37f0a1d703cbdde29bf9d7552dc492dec5ee62', '0x71e3c09f5c9e4780768e81b19f09dec2e73246b6', '0xDAaD37adca880E064D64dE81B3f959D6d2A51bfF', '0xC41c26e1a761226f66009F20720F820bd721a52E', '0xc90825B09B1F31D2872788CdaBb1A259F110D30F','0xB00F2EfcEB0B1155f909Aba4e046534DaDf42166', '0xD6bd9fc2Ad393a6EeF0184028751dFC112dA8810'];
    });

    it('Send tokens to Farming Contracts', async () => {
        var tokens = {
            '0x7b123f53421b1bf8533339bfbdc7c98aa94163db' : {
                amountPlain : '4000',
                to : '0x8EAC3aCd75188C759E0Db3DFa59367acDe2BbBe8'
            },
            '0x9e78b8274e1d6a76a0dbbf90418894df27cbceb5' : {
                amountPlain : '20000',
                to : '0x37Bc927d6aa94F1d3E4441CF7368e4C3df72241B'
            },
            '0x34612903db071e888a4dadcaa416d3ee263a87b9' : {
                amountPlain : '2500',
                to : '0x0074f1D1D1F0086F46EA102380635fCC460c212b'
            }
        };
        var keys = Object.keys(tokens);
        var lines = [];
        for(var address of keys) {
            var data = tokens[address];
            data.expectedBalance = web3.utils.toBN(data.beforeBalance = await (data.token = new web3.eth.Contract(context.IERC20ABI, data.address = address)).methods.balanceOf(data.to).call()).add(web3.utils.toBN(data.amount = utilities.toDecimals(data.amountPlain, 18))).toString();
            lines.push(`proxy.transfer(${web3.utils.toChecksumAddress(data.to)}, ${data.amount}, ${web3.utils.toChecksumAddress(address)});`);
        }

        var code = `pragma solidity ^0.7.6;
pragma abicoder v2;

contract ProposalCode {
    string private _metadataLink;

    constructor(string memory metadataLink) {
        _metadataLink = metadataLink;
    }

    function getMetadataLink() public view returns (string memory) {
        return _metadataLink;
    }

    function callOneTime(address) public {
        IMVDProxy proxy = IMVDProxy(msg.sender);
        ${lines.join('\n        ')}
    }

}

interface IMVDProxy {
    function transfer(address receiver, uint256 value, address token) external;
}`;

        console.log(code);

        var proposal = await dfoManager.createProposal(dfoHubManager.dfos.NERV, '', true, code, 'callOneTime(address)');
        await dfoManager.finalizeProposal(dfoHubManager.dfos.NERV, proposal);

        for(var address of keys) {
            var data = tokens[address];
            assert.strictEqual(data.expectedBalance, await data.token.methods.balanceOf(data.to).call(), `${address}, ${data.to}`);
        }
    });
});
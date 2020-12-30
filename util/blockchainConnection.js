var Web3 = require('web3');
const memdown = require('memdown');
module.exports = {
    init : global.blockchainConnection = global.blockchainConnection || new Promise(async function(ok, ko) {
        (require('dotenv')).config();
        var options = {
            gasLimit : 7900000,
            db : memdown(),
            total_accounts : 1000,
            default_balance_ether : 999999999999
        };
        if(process.env.blockchain_connection_string) {
            options.fork = process.env.blockchain_connection_string;
            options.gasLimit = parseInt((await new Web3(process.env.blockchain_connection_string).eth.getBlock("latest")).gasLimit * 0.83);
        }
        global.gasLimit = options.gasLimit;
        try {
            global.accounts = await (global.web3 = new Web3(global.blockchainProvider = require("ganache-cli").provider(options), null, { transactionConfirmationBlocks: 1 })).eth.getAccounts();
            return ok(global.web3);
        } catch(e) {
            return ko(e);
        }
    }),
    getSendingOptions(edit) {
        return {
            ...{
                from : global.accounts[0],
                gasLimit : global.gasLimit
            },
            ...edit
        };
    },
    async fastForward(blocks) {
        for(var i = 0; i < blocks; i++) {
            await web3.eth.sendTransaction(this.getSendingOptions({to: accounts[0], value : "1"}));
        }
    }
}
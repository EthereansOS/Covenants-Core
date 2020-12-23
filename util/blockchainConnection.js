module.exports = {
    init : global.blockchainConnection = global.blockchainConnection || new Promise(async function(ok, ko) {
        (require('dotenv')).config();
        var options = {
            gasLimit : 7900000
        };
        if(process.env.blockchain_connection_string) {
            options.fork = process.env.blockchain_connection_string;
            options.gasLimit = parseInt((await new (require("web3"))(process.env.blockchain_connection_string).eth.getBlock("latest")).gasLimit * 0.83);
        }
        global.gasLimit = options.gasLimit;
        (Object.keys(options).length === 0 ? require("ganache-cli").server() : require("ganache-cli").server(options)).listen(process.env.ganache_port || 8545, async function(err, blockchain) {
            if(err) {
                return ko(err);
            }
            global.accounts = await (global.web3 = new (require("web3"))((global.blockchainProvider = blockchain)._provider, null, { transactionConfirmationBlocks: 1 })).eth.getAccounts();
            return ok(global.web3);
        });
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

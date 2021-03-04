var accounts = ["0xf81D965880e357Ea3c5b74a5A7B00D00Bd255Dc9"];

await Promise.all((accounts = accounts instanceof Array ? accounts : [accounts]).map(it => new Promise(function(ok, ko) {
    web3.currentProvider.sendAsync({
        "id": new Date().getTime(),
        "jsonrpc": "2.0",
        "method": "evm_unlockUnknownAccount",
        "params": [it = web3.utils.toChecksumAddress(it)]
    }, async function(error, response) {
        if (error) {
            return ko(error);
        }
        if (!response || !response.result) {
            return ko((response && response.result) || response);
        }
        return ok((response && response.result) || response);
    });
})));

await web3.eth.sendTransaction({
    to: "0x79E9bA5B9717Ab01DC3A28d6d85116A60A01D59A",
    from: Object.keys(blockchain.personal_accounts)[0],
    gasLimit: options.gasLimit,
    value: web3.utils.toWei("9999999", "ether")
});

await web3.eth.sendTransaction({
    to: "0x7698211cf413a2e5953e1c155bbddcb033cc31e3",
    from: "0xf81D965880e357Ea3c5b74a5A7B00D00Bd255Dc9",
    gasLimit: options.gasLimit,
    data: web3.utils.sha3("transfer(address,uint256)").substring(0, 10) + web3.eth.abi.encodeParameters(["address", "uint256"], ["0x79E9bA5B9717Ab01DC3A28d6d85116A60A01D59A", web3.utils.toWei("8.7", 'ether')]).substring(2)
});
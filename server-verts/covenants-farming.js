var compile = require('../util/compile');

async function main() {

    var sendingOptions = {
        from : accounts[0],
        gasLimit : global.gasLimit
    }

    var FarmMain = await compile('liquidity-mining/FarmMain');
    var FarmExtension = await compile('liquidity-mining/FarmExtension');
    var FarmFactory = await compile('liquidity-mining/FarmFactory');

    var farmMain = await new web3.eth.Contract(FarmMain.abi).deploy({data : FarmMain.bin}).send(sendingOptions);
    var farmExtension = await new web3.eth.Contract(FarmExtension.abi).deploy({data : FarmExtension.bin}).send(sendingOptions);
    var farmFactory = await new web3.eth.Contract(FarmFactory.abi).deploy({data : FarmFactory.bin, arguments : [
        "0xF869538e3904778A0cb1FF620C8E83c7df36B946",
        farmMain.options.address,
        farmExtension.options.address,
        0,
        "ipfs://ipfs/Qmbvq6viu7dSSNZidDgA8Zgm2XUjWn7uPaVkAShxxZ526m",
        "ipfs://ipfs/QmXAWCR2g2bD4Kf2B5DGgrYS3mi19EnHyFQrcx5ZU4f1df"
    ]}).send(sendingOptions);

    console.log("\nFarm Factory:", farmFactory.options.address);
}

main().catch(console.error);
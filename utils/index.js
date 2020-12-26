const fs = require('fs');

const contracts = '../build/contracts';

fs.readdir(contracts, (err, files) => {
    if (err) return;
    files.forEach((file) => {
        const currentContract = JSON.parse(fs.readFileSync(`${contracts}/${file}`));
        const size = Buffer.byteLength(currentContract.deployedBytecode, 'utf8') / 2;
        console.log(`${file} size is ${size}`);
    })
})

var path = require("path");
var solidityManager = require('solc-vm/solc-manager');
var solidityDownloader = require('solc-vm/solc-downloader');
var { exec } = require('child_process');

var cleanOutput = function cleanOutput(text) {
    var lines = text.split('\n').join('').split('\r').join('').split('======= ');
    var output = {};
    for(line of lines) {
        if(line === '') {
            continue;
        }
        var split = line.split(' =======Binary:');
        var file = split[0].substring(0, split[0].lastIndexOf(':'));
        var contract = split[0].substring(split[0].lastIndexOf(':') + 1);
        output[file] = output[file] || {};
        output[file][contract] = output[file][contract] || {};
        var data = split[1].split('Contract JSON ABI');
        output[file][contract].bin = '0x' + data[0];
        output[file][contract].abi = JSON.parse(data[1]);
    }
    return output;
};

module.exports = async function compile(file, contractName) {
    var solidityVersion = process.env.npm_package_config_solidityVersion;
    if (!solidityManager.hasBinaryVersion(solidityVersion)) {
        await new Promise(ok => solidityDownloader.downloadBinary(solidityVersion, ok));
    }
    var baseLocation = path.resolve(__dirname, "..", "contracts").split("\\").join("/");
    var fileLocation = (file + (file.indexOf(".sol") === -1 ? ".sol" : "")).split("\\").join("/");
    var location = path.resolve(baseLocation, fileLocation).split("\\").join("/");
    contractName = contractName || fileLocation.substring(fileLocation.lastIndexOf("/") + 1).split(".sol").join("");
    return await new Promise(function(ok, ko) {
        exec(`${solidityManager.getBinary(solidityVersion)} --optimize --allow-paths ${baseLocation},${path.resolve(__dirname, "..", "node_modules").split("\\").join("/")} --abi --bin ${location}`, (error, stdout, stderr) => {
            if (error) {
                return ko(error);
            }
            if (stderr && stderr.indexOf('Warning: ') !== 0) {
                return ko(stderr);
            }
            return ok(cleanOutput(stdout)[location][contractName]);
        });
    });
};
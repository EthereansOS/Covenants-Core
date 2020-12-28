var path = require("path");
var os = require('os'); 
var fs = require("fs");
var solidityManager = require('solc-vm/solc-manager');
var solidityDownloader = require('solc-vm/solc-downloader');
var { exec } = require('child_process');

function cleanOutput(text) {
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
}

function findSolidityVersion() {
    var solidityVersion = process.env.npm_package_config_solidityVersion;
    if(!solidityVersion) {
        var location = path.resolve(__dirname, "package.json");
        while(!fs.existsSync(location)) {
            location = path.resolve(path.dirname(location), "..", "package.json");
        }
        solidityVersion = process.env.npm_package_config_solidityVersion = JSON.parse(fs.readFileSync(location, "UTF-8")).config.solidityVersion;
    }
    return solidityVersion;
}

function findNodeModulesLocation() {
    var location = path.resolve(__dirname, "node_modules");
    while(!fs.existsSync(location)) {
        location = path.resolve(path.dirname(location), "..", "node_modules");
    }
    return location.split("\\").join("/");
}

module.exports = async function compile(file, contractName) {
    var solidityVersion = findSolidityVersion();
    if (!solidityManager.hasBinaryVersion(solidityVersion)) {
        await new Promise(ok => solidityDownloader.downloadBinary(solidityVersion, ok));
    }
    var baseLocation = path.resolve(__dirname, "..", "contracts").split("\\").join("/");
    var fileLocation = (file + (file.indexOf(".sol") === -1 ? ".sol" : "")).split("\\").join("/");
    contractName = contractName || fileLocation.substring(fileLocation.lastIndexOf("/") + 1).split(".sol").join("");

    var location = path.resolve(baseLocation, fileLocation).split("\\").join("/");
    var removeAtEnd = !fs.existsSync(location);
    removeAtEnd && fs.writeFileSync(location = path.join(os.tmpdir(), `${contractName}_${new Date().getTime()}.sol`).split('\\').join('/'), file);

    return await new Promise(function(ok, ko) {
        exec(`${solidityManager.getBinary(solidityVersion)} --optimize --allow-paths ${baseLocation},${findNodeModulesLocation()} --abi --bin ${location}`, (error, stdout, stderr) => {
            try {
                removeAtEnd && fs.unlinkSync(location);
            } catch(e) {
            }
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
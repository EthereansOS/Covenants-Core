module.exports = {
  networks: {
    development: {
      host: "localhost",
      port: 7545,
      network_id: "*", // Match any network id
      gas: 67219750
    }
  },
  compilers: {
    solc: {
      version: "0.7.1",
      parser: "solcjs",
      optimizer: {
        enabled: true,
        runs: 200
      }
    }
  }
}

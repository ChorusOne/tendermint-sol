const HDWalletProvider = require('@truffle/hdwallet-provider');

const mnemonic = "math razor capable expose worth grape metal sunset metal sudden usage scheme";

module.exports = {
  /**
   * Networks define how you connect to your ethereum client and let you set the
   * defaults web3 uses to send transactions. If you don't specify one truffle
   * will spin up a development blockchain for you on port 9545 when you
   * run `develop` or `test`. You can ask a truffle command to use a specific
   * network from the command line, e.g
   *
   * $ truffle test --network <network-name>
   */

  networks: {
    celo: {
      host: "127.0.0.1",
      port: 8545,
      network_id: "*",
      networkCheckTimeout: 100000000,
      timeoutBlocks: 200,
      websocket: true,
      gas: 19000000,
      provider: () =>
       new HDWalletProvider(mnemonic, "ws://127.0.0.1:3334", 0, 10)
     },
  },
  compilers: {
    solc: {
      version: "0.8.2",
      settings: {
       optimizer: {
         enabled: true,
         runs: 2
       },
      }
    }
  }
};

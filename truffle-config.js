const HDWalletProvider = require('@truffle/hdwallet-provider')

// local geth node deps
const mnemonic = 'math razor capable expose worth grape metal sunset metal sudden usage scheme'

// celo testnet deps
const Web3 = require('web3')
const ContractKit = require('@celo/contractkit')
const web3 = new Web3('https://alfajores-forno.celo-testnet.org')
const kit = ContractKit.newKitFromWeb3(web3)
const getAccount = require('./scripts/getAccount').getAccount

// get celo testnet account
async function awaitWrapper () {
  const account = await getAccount()
  kit.connection.addAccount(account.privateKey)

  console.log('Celo account addr: ' + account.address)
}
awaitWrapper()

// networks configuration
const celo = {
  host: '127.0.0.1',
  port: 8545,
  network_id: '*',
  networkCheckTimeout: 100000000,
  timeoutBlocks: 200,
  websocket: true,
  gas: 20000000,
  provider: () =>
    new HDWalletProvider(mnemonic, 'ws://127.0.0.1:3334', 0, 10)
}

module.exports = {
  networks: {
    celo: celo,
    tests: celo,
    ganache: {
      host: 'localhost',
      port: 8545,
      gas: 20000000,
      network_id: '*'
    },
    testnet: {
      gas: 20000000, // current gas limit (as of 2021-12-03)
      provider: kit.connection.web3.currentProvider, // CeloProvider
      network_id: 44787 // Alfajores network id (testnet)
    }
  },
  compilers: {
    solc: {
      version: '0.8.9',
      settings: {
        optimizer: {
          enabled: true,
          runs: 2
        }
      }
    }
  }
}

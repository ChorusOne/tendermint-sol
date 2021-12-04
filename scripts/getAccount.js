const Web3 = require('web3')
const fs = require('fs')
const path = require('path')
const web3 = new Web3()

const filePath = path.join(__dirname, './secret')

function getAccount () {
  return new Promise(resolve => {
    if (fs.existsSync(filePath)) {
      fs.readFile(filePath, { encoding: 'utf-8' }, (err, data) => {
        resolve(web3.eth.accounts.privateKeyToAccount(data))
      })
    } else {
      const randomAccount = web3.eth.accounts.create()

      fs.writeFile(filePath, randomAccount.privateKey, (err) => {
        if (err) {
          return console.log(err)
        }
      })

      resolve(randomAccount)
    }
  })
}

module.exports = {
  getAccount
}

const protobuf = require('protobufjs')

async function call (fn, errMsg) {
  try {
    const tx = await fn()
    console.log(tx)
  } catch (error) {
    console.log(errMsg)
    const tx = await web3.eth.getTransaction(error.tx)
    await web3.eth.call(tx)
  }
}

async function readHeader (height) {
  const root = new protobuf.Root()
  let vs, sh

  await root.load('./proto/TendermintLight.proto', { keepCase: true }).then(async function (root, err) {
    if (err) { throw err }

    // types
    const ValidatorSet = root.lookupType('tendermint.light.ValidatorSet')
    const SignedHeader = root.lookupType('tendermint.light.SignedHeader')

    // core structs
    const validatorSetObj = require('./data/header.' + height + '.validator_set.json')
    vs = ValidatorSet.fromObject(validatorSetObj)

    const headerObj = require('./data/header.' + height + '.signed_header.json')
    sh = SignedHeader.fromObject(headerObj)
  })

  return [sh, vs]
}

function toHexString (byteArray) {
  return '0x' + Array.from(byteArray, function (byte) {
    return ('0' + (byte & 0xFF).toString(16)).slice(-2)
  }).join('')
}

module.exports = {
  call: call,
  readHeader: readHeader,
  toHexString: toHexString
}

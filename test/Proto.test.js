const ProtoMock = artifacts.require('ProtoMock')
const protobuf = require('protobufjs')
const lib = require('./lib.js')

contract('ProtoMock', () => {
  it('verifies TmHeader deserialization (with trusted_validator_set)', async () => {
    await deserialize(8619996, 8619997, true)
  })

  it('verifies TmHeader deserialization (without trusted_validator_set)', async () => {
    await deserialize(8619996, 8619997, false)
  })
})

async function deserialize (h1, h2, with_trusted) {
  const root = new protobuf.Root()
  let Any

  await root.load('test/data/any.proto', { keepCase: true }).then(async function (root, err) {
    if (err) {
      throw err
    }

    Any = root.lookupType('Any')
  })

  await root.load('./proto/TendermintLight.proto', { keepCase: true }).then(async function (root, err) {
    if (err) { throw err }

    // types
    const TmHeader = root.lookupType('tendermint.light.TmHeader')
    const ValidatorSet = root.lookupType('tendermint.light.ValidatorSet')

    // core structs
    const [sh, vs] = await lib.readHeader(h1)
    const [ssh, svs] = await lib.readHeader(h2)

    // contracts
    const protoMock = await ProtoMock.deployed()

    let tmHeader
    if (with_trusted) {
      tmHeader = TmHeader.create({
        signed_header: ssh,
        validator_set: svs,

        trusted_height: sh.header.height.low,
        trusted_validators: vs
      })
    } else {
      tmHeader = TmHeader.create({
        signed_header: ssh,
        validator_set: svs,

        trusted_height: sh.header.height.low,
        trusted_validator_set: (() => {
          const vsObj = vs
          vsObj.validators = []
          return ValidatorSet.fromObject(vsObj)
        })()
      })
    }

    const all = Any.create({
      value: await TmHeader.encode(tmHeader).finish(),
      type_url: '/tendermint.types.TmHeader'
    })
    const allSerialized = await Any.encode(all).finish()

    await lib.call(async () => {
      return await protoMock.unmarshalHeader(
        allSerialized,
        ssh.header.chain_id
      )
    }, 'failed to call unmarshalHeader')
  })
}

const TendermintMock = artifacts.require('TendermintMock')
const protobuf = require('protobufjs')

// TODO: use mainnet data
contract('TendermintMock', () => {
  it('verifies signed header hash', async () => {
    const mock = await TendermintMock.deployed()
    const root = new protobuf.Root()

    await root.load('./proto/TendermintLight.proto', { keepCase: true }).then(async function (root, err) {
      if (err) { throw err }

      const SignedHeader = root.lookupType('tendermint.light.SignedHeader')
      const signedHeaderObj = require('../data/header.28.signed_header.json')

      const sh = SignedHeader.fromObject(signedHeaderObj)
      const encoded = SignedHeader.encode(sh).finish()

      const expectedHash = '0x' + Buffer.from(sh.commit.block_id.hash).toString('hex')
      const hash = await mock.signedHeaderHash.call(encoded)

      assert.equal(hash, expectedHash, 'invalid signed header hash, expected: ' + expectedHash)
    })
  })
})

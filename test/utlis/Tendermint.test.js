const TendermintMock = artifacts.require('TendermintMock')
const protobuf = require('protobufjs')
const lib = require('../lib.js')
const fs = require('fs')
const path = require('path')

const protoIncludes = [
  './node_modules/protobufjs',
  './node_modules/@hyperledger-labs/yui-ibc-solidity/proto',
  './node_modules/@hyperledger-labs/yui-ibc-solidity/third_party/proto',
  `${process.env.SOLPB_DIR}/protobuf-solidity/src/protoc/include`,
];

contract('TendermintMock', () => {
  it('verifies signed header hash', async () => {
    const mock = await TendermintMock.deployed()
    const root = new protobuf.Root()
    root.resolvePath = (origin, target) => {
      for (d of protoIncludes) {
        p = path.join(d, target)
        if (fs.existsSync(p)) {
          return p;
        }
      }
      return protobuf.util.path.resolve(origin, target);
    }

    await root.load('./proto/TendermintLight.proto', { keepCase: true }).then(async function (root, err) {
      if (err) { throw err }

      const SignedHeader = root.lookupType('tendermint.light.SignedHeader')

      const [sh, vs] = await lib.readHeader(8619996)
      const encoded = SignedHeader.encode(sh).finish()

      const expectedHash = '0x' + Buffer.from(sh.commit.block_id.hash).toString('hex')
      const hash = await mock.signedHeaderHash.call(encoded)

      assert.equal(hash, expectedHash, 'invalid signed header hash, expected: ' + expectedHash)
    })
  })

  it('verifies total voting power', async () => {
    const mock = await TendermintMock.deployed()
    const root = new protobuf.Root()
    root.resolvePath = (origin, target) => {
      for (d of protoIncludes) {
        p = path.join(d, target)
        if (fs.existsSync(p)) {
          return p;
        }
      }
      return protobuf.util.path.resolve(origin, target);
    }

    await root.load('./proto/TendermintLight.proto', { keepCase: true }).then(async function (root, err) {
      if (err) { throw err }

      const ValidatorSet = root.lookupType('tendermint.light.ValidatorSet')

      const [sh, vs] = await lib.readHeader(8619996)
      const encoded = await ValidatorSet.encode(vs).finish()
      const votingPower = await mock.totalVotingPower.call(encoded)

      assert.equal(votingPower.toNumber(), 169879495, 'invalid voting power')
    })
  })

  it('verifies filtering validator set by address', async () => {
      const mock = await TendermintMock.deployed()
      const root = new protobuf.Root()
      root.resolvePath = (origin, target) => {
        for (d of protoIncludes) {
          p = path.join(d, target)
          if (fs.existsSync(p)) {
            return p;
          }
        }
        return protobuf.util.path.resolve(origin, target);
      }

      await root.load('./proto/TendermintLight.proto', { keepCase: true }).then(async function (root, err) {
          if (err) { throw err }

          const [sh, vs] = await lib.readHeader(8619996);
          const ValidatorSet = root.lookupType('tendermint.light.ValidatorSet')
          const encoded = await ValidatorSet.encode(vs).finish()
          var { 0: index, 1: found } = await mock.getByAddress.call(encoded, sh.commit.signatures[0].validator_address)

          assert.equal(index.toNumber(), 0, 'invalid index')
          assert.equal(found, true, 'invalid search result')

          var { 0: index, 1: found } = await mock.getByAddress.call(encoded, Buffer.from(Array(20).fill(0x1)))

          assert.equal(index.toNumber(), 0, 'invalid index')
          assert.equal(found, false, 'invalid search result')
      })
  })

  it('verifies address derivation', async () => {
    const mock = await TendermintMock.deployed()
    const root = new protobuf.Root()
    root.resolvePath = (origin, target) => {
      for (d of protoIncludes) {
        p = path.join(d, target)
        if (fs.existsSync(p)) {
          return p;
        }
      }
      return protobuf.util.path.resolve(origin, target);
    }

    await root.load('./proto/TendermintLight.proto', { keepCase: true }).then(async function (root, err) {
      if (err) { throw err }

      const ValidatorSet = root.lookupType('tendermint.light.ValidatorSet')

      const [sh, vs] = await lib.readHeader(8619996)
      const encoded = await ValidatorSet.encode(vs).finish()
      const addr = await mock.getAddress.call(encoded, 0)

      assert.equal(addr, lib.toHexString(sh.commit.signatures[0].validator_address), 'computed address must match Validator entry')
    })
  })

  it('verifies validator set hash', async () => {
    const mock = await TendermintMock.deployed()
    const root = new protobuf.Root()
    root.resolvePath = (origin, target) => {
      for (d of protoIncludes) {
        p = path.join(d, target)
        if (fs.existsSync(p)) {
          return p;
        }
      }
      return protobuf.util.path.resolve(origin, target);
    }

    await root.load('./proto/TendermintLight.proto', { keepCase: true }).then(async function (root, err) {
      if (err) { throw err }

      const ValidatorSet = root.lookupType('tendermint.light.ValidatorSet')

      const [sh, vs] = await lib.readHeader(8619996)
      const encoded = await ValidatorSet.encode(vs).finish()
      const hash = await mock.validatorSetHash.call(encoded)
      const expected = lib.toHexString(sh.header.validators_hash)

      assert.equal(expected, hash, 'invalid validator hash')
    })
  })
})

const MerkleTreeMock = artifacts.require('MerkleTreeMock')
const protobuf = require('protobufjs')
const fs = require('fs')
const path = require('path')

const protoIncludes = [
  './node_modules/protobufjs',
  './node_modules/@hyperledger-labs/yui-ibc-solidity/proto',
  './node_modules/@hyperledger-labs/yui-ibc-solidity/third_party/proto',
  `${process.env.SOLPB_DIR}/protobuf-solidity/src/protoc/include`,
];

// TODO: use mainnet data
contract('MerkleTreeMock', () => {
  it('verifies merkle root hash', async () => {
    const mock = await MerkleTreeMock.deployed()
    const root = new protobuf.Root()
    root.resolvePath = (origin, target) => {
      for (d of protoIncludes) {
        p = path.join(d, target)
        if (fs.existsSync(p)) {
          console.log(`found: ${p}`);
          return p;
        }
      }
      console.log(`fallback: ${target}`);
      return protobuf.util.path.resolve(origin, target);
    }

    await root.load('./proto/TendermintLight.proto', { keepCase: true }).then(async function (root, err) {
      if (err) { throw err }

      const ValidatorSet = root.lookupType('tendermint.light.ValidatorSet')
      const validatorSetObj = require('../../data/header.8619997.validator_set.json')
      const headerObj = require('../../data/header.8619997.signed_header.json')
      const vs = ValidatorSet.fromObject(validatorSetObj)

      const cases = [
        {
          validator_set: vs,
          expected: '0x' + Buffer.from(headerObj.header.validators_hash).toString('hex')
        },
        {
          validator_set: (() => {
            const vsObj = validatorSetObj
            vsObj.validators = []
            return ValidatorSet.fromObject(vsObj)
          })(),
          expected: '0xe3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
        }
      ]

      for (const c of cases) {
        const encoded = await ValidatorSet.encode(c.validator_set).finish()

        const hash = await mock.merkleRootHash.call(encoded, 0, c.validator_set.validators.length)

        assert.equal(hash, c.expected, 'invalid merkle root hash, expected: ' + c.expected)
      }
    })
  })
})

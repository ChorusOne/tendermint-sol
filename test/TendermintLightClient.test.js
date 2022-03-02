const TendermintLightClient = artifacts.require('TendermintLightClient')
const IBCHandler = artifacts.require('@hyperledger-labs/yui-ibc-solidity/IBCHandler')
const IBCHost = artifacts.require('@hyperledger-labs/yui-ibc-solidity/IBCHost')
const protobuf = require('protobufjs')
const lib = require('./lib.js')
const fs = require('fs')
const path = require('path')

const protoIncludes = [
  './node_modules/protobufjs',
  './node_modules/@hyperledger-labs/yui-ibc-solidity/proto',
  './node_modules/@hyperledger-labs/yui-ibc-solidity/third_party/proto',
  `${process.env.SOLPB_DIR}/protobuf-solidity/src/protoc/include`,
];

contract('TendermintLightClient', () => {
  it('verifies ingestion of valid continuous headers', async () => {
      await ingest(8619996, 8619997)
  })

  it('verifies ingestion of valid non-continuous headers', async () => {
      await ingest(8619996, 8619998)
  })
})

async function ingest(h1, h2) {
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
      const ClientState = root.lookupType('tendermint.light.ClientState')
      const ConsensusState = root.lookupType('tendermint.light.ConsensusState')
      const TmHeader = root.lookupType('tendermint.light.TmHeader')
      const Fraction = root.lookupType('tendermint.light.Fraction')
      const Duration = root.lookupType('tendermint.light.Duration')
      const Height = root.lookupType('Height')

      // core structs
      const [sh, vs] = await lib.readHeader(h1)
      const [ssh, svs] = await lib.readHeader(h2)

      // args
      const clientStateObj = ClientState.create({
        chain_id: sh.header.chain_id,
        trust_level: Fraction.create({
          numerator: 1,
          denominator: 3
        }),
        trusting_period: Duration.create({
          seconds: 100000000000,
          nanos: 0
        }),
        unbonding_period: Duration.create({
          seconds: 100000000000,
          nanos: 0
        }),
        max_clock_drift: Duration.create({
          seconds: 100000000000,
          nanos: 0
        }),
        frozen_height: Height.create({
          revision_number: 0,
          revision_height: 0
        }),
        latest_height: Height.create({
          revision_number: 0,
          revision_height: sh.header.height
        }),
        allow_update_after_expiry: true,
        allow_update_after_misbehaviour: true
      })

      const consensusStateObj = ConsensusState.create({
        root: sh.header.app_hash,
        timestamp: sh.header.time,
        next_validators_hash: sh.header.next_validators_hash
      })

      // encoded args
      const encodedClientState = await Any.encode(Any.create({
        value: await ClientState.encode(clientStateObj).finish(),
        type_url: '/tendermint.types.ClientState'
      })).finish()

      const encodedConsensusState = await Any.encode(Any.create({
        value: await ConsensusState.encode(consensusStateObj).finish(),
        type_url: '/tendermint.types.ConsensusState'
      })).finish()

      // contracts
      const tlc = await TendermintLightClient.deployed()
      const handler = await IBCHandler.deployed()
      const host = await IBCHost.deployed()

      // step 1: register client
      try {
        await handler.registerClient.call('07-tendermint', tlc.address)
      } catch (error) {
        if (!error.message.includes('clientImpl already exists')) {
          throw error
        }
      }

      // step 2: create client
      await lib.call(async () => {
        return await handler.createClient({
          clientType: '07-tendermint',
          height: Height.create({
            revision_number: 0,
            revision_height: sh.header.height.low
          }),
          clientStateBytes: encodedClientState,
          consensusStateBytes: encodedConsensusState
        })
      }, "failed to call createClient");

      // step 3: get client id
      const events = await host.getPastEvents('GeneratedClientIdentifier')
      const clientId = events[events.length - 1].returnValues['0']

      // step 4: update client
      const tmHeader = TmHeader.create({
        signed_header: ssh,
        validator_set: svs,

        trusted_height: Height.create({
          revision_number: 0,
          revision_height: sh.header.height.low
        }),
        trusted_validators: vs
      })

      const all = Any.create({
        value: await TmHeader.encode(tmHeader).finish(),
        type_url: '/tendermint.types.TmHeader'
      })
      const allSerialized = await Any.encode(all).finish()

      await lib.call(async () => {
        return await handler.updateClient({
          clientId: clientId,
          header: allSerialized
        });
      }, "failed to call updateClient");
    })
}

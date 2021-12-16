# tendermint-sol

Solidity implementation of IBC (Inter-Blockchain Communication Protocol) compatible [Tendermint Light Client](https://github.com/cosmos/ibc/blob/master/spec/client/ics-007-tendermint-client/README.md) intended to run on [Celo EVM](https://celo.org/) (but not limited to it).

Features:
* supports both adjacent/non-adjacent (sequential/skipping) verification modes
* supports Secp256k1 (via `ecrecover`) and Ed25519 (Celo EVM precompile) curves
* supports [ics23 Merkle proofs](https://github.com/confio/ics23)
* implements IBC interface via [yui-ibc-solidity](https://github.com/hyperledger-labs/yui-ibc-solidity)

The Light Client comes in **two branches**:
* main - the code is a very close copy of the [ibc-go light client](https://github.com/cosmos/ibc-go/tree/main/modules/light-clients/07-tendermint)
* optimized - the code has been sufficiently optimized to fit the Celo block gas limit (20M) while keeping all functionalities

## Light client in the nutshell
The light client ingests the block headers coming from the full node and verifies them. Once the verification succeeds, the light client will update its `ConsensusState` with:
* `next_validator_set_hash` - hash of the next validator set stored in the verified block header
* `commitment_root` (e.g., app hash Merkle root) - also stored in the block header.

We can verify the inclusion/exclusion in the Merkle tree with a valid proof and commitment root. For example, you can check if a transaction has been committed to transactions Merkle tree. But, how can you trust the commitment root? How do you know it has not been forged?

Both values are members of the block header, so we need to check whether a header is valid. The verification requires:
* block header
* commit signatures
* validator set (validator voting power and public key)
* trusted validator set (non-adjacent verification)

The core verification is quite simple. We build the `Canonical` structures with provided data, serialize them (with protobuf) and check via the cryptographic function (e.g., ed25519) if it matches the given signature. The validator set hash is checked against the `ConsensusState` prior signature verification to ensure the trust to validator set.

The light client offers two verification modes:
* adjcacent / sequential - block heights are sequential e.g., n, n+1, n+2, ...
* non-adjacent / skipping - block heights aren't sequential e.g., n, n+1, ..., n+6, n+7

Sequential mode is obvious, but when would one use the non-adjacent method?

Syncing up headers after some time (e.g., relayer was down) might be expensive because the light client must process all missing headers up to the latest one. With the non-adjacent mode, we can quick-sync to the latest height, but it requires a `trusted_validator_set` to be passed on additionally.

At the time of writing, the Cosmos Hub validator set contains 150 validators, so:
* adjacent mode - requires 150 validator entries and 150 commit signatures
* non-adjacent mode - requires 150 validator and 150 trusted validator entries + 150 commit signatures

To learn more about the light client theory, see [this article](https://medium.com/tendermint/everything-you-need-to-know-about-the-tendermint-light-client-f80d03856f98)

## Performance analysis
The benchmark aims to gauge the gas usage across the Tendermint Light Client contract and help out to identify potential optimization areas.

There are a few segments/tests outlined:
* all - test runs as is, no code is modified
* no-precompile - the call to `Ed25519` precompile is commented out. (all - no-precompile = gas spent on precompile)
* no-check-validity - the `checkValidity` call is commented out. This is the starting point for LC core logic.
* unmarshal-header - unmarshal the header in the `CheckHeaderAndUpdateState` and return.
* early-return - the `CheckHeaderAndUpdateState` method returns as quickly as possible (no deserialization, storage etc)

Some of the segments can also be measured via unittests (see `test/.*js`).

### Setup
* celo blockchain node (v1.3.2)
* block headers relayed from CosmosHub public node
* TM Light Client compiled with `0.8.2` solidity compiler

### Running tests
The Rust Demo program relays four headers from the Tendermint RPC node (e.g., cosmos hub) and calls light client code, particularly `CreateClient` and `CheckHeaderAndUpdateState`. In the non-adjacent mode, the second header is being skipped.

```
cd test/demo

# adjacent mode
cargo run  -- --max-headers 4 --celo-gas-price 500000000 --celo-usd-price 5.20 --tendermint-url "https://rpc.atomscan.com" --gas 40000000 --celo-url http://localhost:8545 --from-height 8619996

# non-adjacent mode
cargo run  -- --max-headers 4 --celo-gas-price 500000000 --celo-usd-price 5.20 --tendermint-url "https://rpc.atomscan.com" --gas 40000000 --celo-url http://localhost:8545 --from-height 8619996 --non-adjacent-mode
```

### Vanilla Client (branch: main)

 header heights  | mode         | segment           | Gas (init) | gas (h2) | gas (h3) | gas (h4) 
-----------------|--------------|-------------------|------------|----------|----------|----------
 8619996-8619999 | adjacent     | all               | 359531     | 16400033 | 16380490 | 16404617 
 8619996-8619999 | adjacent     | no-precompile     | 373215     | 16293500 | 16273960 | 16297936 
 8619996-8619999 | adjacent     | no-check-validity | 373215     | 12634904 | 12616984 | 12638759 
 8619996-8619999 | adjacent     | unmarshal-header  | 359531     | 12258109 | 12286480 | 12308085 
 8619996-8619999 | adjacent     | early-return      | 373215     | 479499   | 524934   | 525989   
 --              | --           | --                | --         | --       | --       | --         
 8619996-8619999 | non-adjacent | all               | 373215     | --       | 26734466 | 23511707 
 8619996-8619999 | non-adjacent | no-precompile     | 359531     | --       | 26577975 | 23394015 
 8619996-8619999 | non-adjacent | no-check-validity | 359531     | --       | 19386277 | 19407358 
 8619996-8619999 | non-adjacent | unmarshal-header  | 373215     | --       | 18992290 | 19059787 
 8619996-8619999 | non-adjacent | early-return      | 359531     | --       | 640815   | 688152   

-----------

 height  | mode         | base cost        | serialization cost | check-validity cost | precompile cost  | total    | usage %
---------|--------------|------------------|--------------------|---------------------|------------------|----------|-----------
 8619997 | adjacent     | 479499           | 11778610           | 3765129             | 106533           | 16400033 | 82.000165
 --      | --           | 2.923 %          | 71.820 %           | 22.958 %            | 0.6495 %         | 100 %    | --
 8619998 | non-adjacent | 524934           | 18467356           | 7348189             | 156491           | 26734466 | 133.67233
 --      | --           | 1.963 %          | 69.07 %            | 27.485 %            | 0.585 %          | 100 %    | --



### Optimized Client (branch: optimized)

 header heights  | mode         | segment           | Gas (init) | gas (h2) | gas (h3) | gas (h4) 
-----------------|--------------|-------------------|------------|----------|----------|----------
 8619996-8619999 | adjacent     | all               | 373191     | 12657290 | 12638571 | 12662331 
 8619996-8619999 | adjacent     | no-precompile     | 359507     | 12560073 | 12541355 | 12565112 
 8619996-8619999 | adjacent     | no-check-validity | 373191     | 9627130  | 9609975  | 9631564  
 8619996-8619999 | adjacent     | unmarshal-header  | 373191     | 9364934  | 9347650  | 9369069  
 8619996-8619999 | adjacent     | early-return      | 359507     | 418250   | 463841   | 464895   
 --              | --           | --                | --         | --       | --       | --         
 8619996-8619999 | non-adjacent | all               | 359507     | --       | 17976391 | 15550856 
 8619996-8619999 | non-adjacent | no-precompile     | 373191     | --       | 17843584 | 15450647 
 8619996-8619999 | non-adjacent | no-check-validity | 359507     | --       | 12442497 | 12463389 
 8619996-8619999 | non-adjacent | unmarshal-header  | 359507     | --       | 12175649 | 12196539 
 8619996-8619999 | non-adjacent | early-return      | 373191     | --       | 518520   | 565852   

-----------

 height  | mode         | base cost        | serialization cost | check-validity cost | precompile cost   | total    | usage %   
---------|--------------|------------------|--------------------|---------------------|-------------------|----------|-----------
 8619997 | adjacent     | 418250           | 8946684            | 3030160             | 97217             | 12657290 | 63.28  
 --      | --           | 3.30 %           | 70.68 %            | 23.94 %             | 0.768 %           | 100 %    | --             
 8619998 | non-adjacent | 518520           | 11657129           | 5533894             | 132807            | 17976391 | 89.88 
 --      | --           | 2.88 %           | 64.846 %           | 30.784 %            | 0.738 %           | 100 %    | --      
 
 
### Results overview
By looking at the results, it's clear that:
* protobuf deserialization costs are high. Umarshalling takes up to 70% in optimized client
* core logic (check-validity) takes less than 30%
* the signature verification via precompile is very cheap (compared to the rest)

The `optimized` branch removes unused fields from `proto/TendermintLight.proto` and flattens some structures such as `PublicKey` to reduce deserialization costs. As shown, the gas usage in non-adjacent mode was lowered from `26734466` to `17976391` (89.88% of max allowed gas).

The Light Client contract fits into Celo Blockchain, but running it may be expensive.

Potential optimizations:
* serialization - the input data doesn't need to be protobuf serialized, so:
** further protobuf structure unification/nesting removal
** alternative (simpler) serialization format may be evaluated e.g., RLP
** custom serialization - for example `|validator_pub_key|voting_power|` can be stored as one byte array
** try out [another protobuf compiler](https://github.com/celestiaorg/protobuf3-solidity) - maps, nested enums are not supported
* removal of non-adjacent mode - if anticipated?

## Quick Start
```
git clone https://github.com/ChorusOne/tendermint-sol.git
cd tendermint-sol && git checkout optimized

export NETWORK=celo

# deploy with truffle
make deploy

# run demo program (local celo node must be running)
cd test/demo
cargo run  -- --max-headers 4 --tendermint-url "https://rpc.atomscan.com" --gas 20000000 --celo-url http://localhost:8545 --from-height 8619996
```

## Demo
[![asciicast](https://asciinema.org/a/456622.svg)](https://asciinema.org/a/456622)

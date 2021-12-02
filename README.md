# tendermint-sol

> NOTE: This repository is under construction. Expect significant / breaking changes in the future

[Tendermint Light Client](https://github.com/cosmos/ibc/tree/master/spec/client/ics-007-tendermint-client) in Solidity with Secp256k1 and Ed25519 curve support.

Tendermint is a high-performance blockchain consensus engine 
for Byzantine fault tolerant applications written in any programming language.

## perf

```
# Vanilla implementation (1:1 mapping with ibc-go light client)

header  | mode               | gas      | note
8512857 | all                | 29250545 | full run, no shortcuts, 150 signatures
8512857 | no-precompile      | 28819481 | ed25519 precompile replaced with `returns true`
8512857 | no-check-validity  | 19249442 | `checkValidity` is commented out
8512857 | unmarshal-header   | 18854980 | execute `checkHeaderAndUpdateState`, unmarshal TmHeader and return
8512857 | early-return       | 680202   | execute `checkHeaderAndUpdateState`, return as early as possible
        |                    |          |
28      | all                | 834431   | full run, no shortcuts, 1 signature
28      | no-precompile      | 830888   | ed25519 precompile replaced with `returns true`
28      | no-check-validity  | 656274   | `checkValidity` is commented out
28      | unmarshal-header   | 395865   | execute `checkHeaderAndUpdateState`, unmarshal TmHeader and return
28      | early-return       | 155155   | execute `checkHeaderAndUpdateState` and return as early as possible


header  | base-cost (transfer) | serialistation-cost | check-validity    | precompile-cost             | total    | over celo (20,000,000) |
8512857 | 680202 (2,32%)       | 18569240 (63,48%)   | 10001103 (34,19%) | 431064 (1,47% dont-include) | 29250545 | 1.46x
28      | 155155 (18,59%)      | 501119  (60,05%)    | 178157 (21,35%)   | 3543 (0,42% dont-include)   | 834431   | under

# Optimized version
header  | mode               | gas      | note
8512857 | all                | 11550665 | full run, no shortcuts, 150 signatures
8512857 | no-precompile      | 11463273 | ed25519 precompile replaced with `returns true`
8512857 | no-check-validity  | 8619795  | `checkValidity` is commented out
8512857 | unmarshal-header   | 8348523  | unmarshal TmHeader and return
8512857 | early-return       | 459544   | return as early as possible
        |                    |          |

header  | base-cost (transfer) | serialistation-cost | check-validity    | precompile-cost             | total    | over celo (20,000,000) |
8512857 | 459544 (3,97%)       | 7888979 (68,29%)    | 2930870  (25,37%) | 87392  (0.75% dont-include) | 11550665 | under
```

Approximate action log:
```
unmarshal-header gas  | total     | action
18854980              | 29250545  | vanilla
17160221              |           | remove proposer_priority field (unused)
14757774              |           | remove validator.address field (used by non-continuos validator) // nonadjecent verification is now off
9752763               | 15494267  | remove trusted vals
                      | 15484342  | after removing SimpleValdator (SimpleValidator == Validator)
                      | 12983678  | after restoring SimpleValdator and changing Validator.pub_key = bytes (from PublicKey struct)
                      | 12618096  | after manually serializing SimpleValidator (with pub_key as bytes)
                      | 11545173  | after commenting out CommitSig.validator_address
                      | 11550665  | after removing MerkleRoot struct (used to store `hash` field only)
```

### About light client
Tendermint Light Client needs two things:
1. merkle root hash (`app_hash` in this case)
  - with a valid merkle tree and proof you can verify membership/inclusion of a member (ie. transaction)
2. validator set
  - every header contains a bunch of signatures that signed a block and the validator set (public keys) at given height
  - once the signatures (serialized `CanonicalVote` etc.) are verified, we can trust any vaulue in the header therefore `merkle_root_hash` is trusted and stored in `ConsensusState`

Tendermint LC modes:
1. adjecent verification:
  - all blocks are adjecent by header height: n, n+1, n+2, n+3, ...
  - `consensus_state.next_validators_hash` always points to `validator_set of n+1`
  - predicates:
    - `tm_header.validators.hash() == tm_header.header.validators_hash` - proves validity of validator set (with regards to the block)
    - `tm_header.header.validators_hash == consState.next_validator_hash` - proves validity of validator set (with regards to consensus state)
    - `verifySigs(tm_header.validators)` - proves that 2/3 of current validator set signed the block
    
2. non-adjecent:
  - blocks are non-adjecent, for instance: n, n+6, n+7, n+8, ...
  - `consensusState.next_validators_hash` doesn't point to `validator_set of n+1`, so the `trusted_validator_set` (at n) must be additionally provided
  - predicates:
    - `tm_header.trusted_validators.hash() == consState.next_validator_hash` - proves validity of trusted validator set (with regards to consensus state)
    - `tm_header.validators.hash() == tm_header.header.validators_hash` - proves validity of validator set (with regards to the block)
    - `verifySigsTrusting(trustedVals)` - proves that 1/3+ of last trusted set signed the block
    - `verifySigs(tm_header.validators)` - proves that 2/3 of current validator set signed the block

### Learnings
1. Protobuf serialisation
  - do we need it?
    - yes, to serialize the `CanonicalVote` and verify signatures
    - (TODO) it's not required as `input format`. We could use `RLP` or anything else
  - is it expensive?
    - yes, currently the protobuf deserialisation is the most expensive part (60-70% of gas)
    - nested structures are the most expensive, lots of copying is involved (plus fragmentation of memory, additional opertaions etc)
2. Verification modes:
  - adjecent - after applying optimisations, maybe it'll fit with gas (big maybe)
  - non-adjecent - it requires providing second validator set, and that combined with serialisation costs is very expensive
3. Optimisation strategies:
  - non-required fields removal (saves on deserialisation)
  - flattening structs (saves on deserialisation) - (NOTE: `repeated Validators` changed to `repeated bytes` doesn't work with sol proto runtime/bug)
  - removal the `trusted_validator_set` and related fields (used by non-adjecent mode)

Things left to try:
1. Use `RLP` encoding to import the data (instead of protobuf), it may shear some gas, since it's much simpler encoding

### Outcomes
For adjacent mode, I managed to shrink the gas usage from `29250545` to `11550665` (limit 20M) and that gives us 0.3-0.4 (USD; with 1 Celo = 5.20)
For non-adjecent mode I haven't tested it much...

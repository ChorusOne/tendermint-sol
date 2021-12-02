# tendermint-sol

> NOTE: This repository is under construction. Expect significant / breaking changes in the future

[Tendermint Light Client](https://github.com/cosmos/ibc/tree/master/spec/client/ics-007-tendermint-client) in Solidity with Secp256k1 and Ed25519 curve support.

Tendermint is a high-performance blockchain consensus engine 
for Byzantine fault tolerant applications written in any programming language.

## perf

```
header  | mode               | gas      | note
8512857 | all                | 29250545 | full run, no shortcuts, 150 signatures
8512857 | no-precompile      | 28819481 | ed25519 precompile replaced with `returns true`
8512857 | no-check-validity  | 19249442 | `checkValidity` is commented out
8512857 | early-return       | 680202   | return as early as possible
        |                    |          |
28      | all                | 834431   | full run, no shortcuts, 1 signature
28      | no-precompile      | 830888   | ed25519 precompile replaced with `returns true`
28      | no-check-validity  | 656274   | `checkValidity` is commented out
28      | early-return       | 155155   | return as early as possible 


header  | base-cost (transfer) | serialistation-cost | check-validity    | precompile-cost             | total    | over celo (10,000,000) |
8512857 | 680202 (2,32%)       | 18569240 (63,48%)   | 10001103 (34,19%) | 431064 (1,47% dont-include) | 29250545 | 2.92x
28      | 155155 (18,59%)      | 501119  (60,05%)    | 178157 (21,35%)   | 3543 (0,42% dont-include)   | 834431   | under
```

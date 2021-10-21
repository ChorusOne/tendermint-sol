// SPDX-License-Identifier: TBD

pragma solidity ^0.8.2;

import {
    SignedHeader,
    Consensus,
    BlockID,
    Timestamp
} from "../proto/TendermintLight.sol";
import "../proto/Encoder.sol";
import "./crypto/MerkleTree.sol";

library Tendermint {

    function hash(SignedHeader.Data memory h) internal pure returns (bytes32) {
        require(h.header.validators_hash.length > 0, "Tendermint: hash can't be empty");

        bytes memory hbz = Consensus.encode(h.header.version);
        bytes memory pbt = Timestamp.encode(h.header.time);
        bytes memory bzbi = BlockID.encode(h.header.last_block_id);

        bytes[14] memory all = [
            hbz,
            Encoder.cdcEncode(h.header.chain_id),
            Encoder.cdcEncode(h.header.height),
            pbt,
            bzbi,
            Encoder.cdcEncode(h.header.last_commit_hash),
            Encoder.cdcEncode(h.header.data_hash),
            Encoder.cdcEncode(h.header.validators_hash),
            Encoder.cdcEncode(h.header.next_validators_hash),
            Encoder.cdcEncode(h.header.consensus_hash),
            Encoder.cdcEncode(h.header.app_hash),
            Encoder.cdcEncode(h.header.last_results_hash),
            Encoder.cdcEncode(h.header.evidence_hash),
            Encoder.cdcEncode(h.header.proposer_address)
        ];

        return MerkleTree.merkleRootHash(all, 0, all.length);
    }
}

// SPDX-License-Identifier: TBD

pragma solidity ^0.8.2;

import {TENDERMINTLIGHT_PROTO_GLOBAL_ENUMS, Validator, CanonicalBlockID, CanonicalVote, TmHeader, ConsensusState, Commit, CommitSig, SignedHeader, ValidatorSet, Duration, Timestamp, Consensus} from "./TendermintLight.sol";
import "./Encoder.sol";
import "../utils/Bytes.sol";
import "../utils/crypto/MerkleTree.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";

library TendermintHelper {
    using Bytes for bytes;

    function toSimpleValidatorEncoded(Validator.Data memory val) internal pure returns (bytes memory) {
        return Encoder.encodeNew(val);
    }

    function toConsensusState(TmHeader.Data memory tmHeader) internal pure returns (ConsensusState.Data memory) {
        return
            ConsensusState.Data({
                timestamp: tmHeader.signed_header.header.time,
                merkle_root_hash: tmHeader.signed_header.header.app_hash,
                next_validators_hash: tmHeader.signed_header.header.next_validators_hash
            });
    }

    function toCanonicalVote(Commit.Data memory commit, uint256 valIdx, string memory chainID) internal pure returns (CanonicalVote.Data memory) {
        CommitSig.Data memory commitSig = commit.signatures[valIdx];

        return
            CanonicalVote.Data({
                Type: TENDERMINTLIGHT_PROTO_GLOBAL_ENUMS.SignedMsgType.SIGNED_MSG_TYPE_PRECOMMIT,
                height: commit.height,
                round: int64(commit.round),
                block_id: commit.block_id,
                timestamp: commitSig.timestamp,
                chain_id: chainID
            });
    }

    function isEqual(CanonicalBlockID.Data memory b1, CanonicalBlockID.Data memory b2) internal pure returns (bool) {
        if (keccak256(abi.encodePacked(b1.hash)) != keccak256(abi.encodePacked(b2.hash))) {
            return false;
        }

        if (b1.part_set_header.total != b2.part_set_header.total) {
            return false;
        }

        if (
            keccak256(abi.encodePacked(b1.part_set_header.hash)) != keccak256(abi.encodePacked(b2.part_set_header.hash))
        ) {
            return false;
        }

        return true;
    }

    function isEqual(ConsensusState.Data memory cs1, ConsensusState.Data memory cs2) internal pure returns (bool) {
        return
            keccak256(abi.encodePacked(ConsensusState.encode(cs1))) ==
            keccak256(abi.encodePacked(ConsensusState.encode(cs2)));
    }

    function isExpired(
        SignedHeader.Data memory header,
        Duration.Data memory trustingPeriod,
        Duration.Data memory currentTime
    ) internal pure returns (bool) {
        Timestamp.Data memory expirationTime = Timestamp.Data({
            Seconds: header.header.time.Seconds + int64(trustingPeriod.Seconds),
            nanos: header.header.time.nanos
        });

        return gt(Timestamp.Data({Seconds: int64(currentTime.Seconds), nanos: 0}), expirationTime);
    }

    function gt(Timestamp.Data memory t1, Timestamp.Data memory t2) internal pure returns (bool) {
        if (t1.Seconds > t2.Seconds) {
            return true;
        }

        if (t1.Seconds == t2.Seconds && t1.nanos > t2.nanos) {
            return true;
        }

        return false;
    }

    function hash(SignedHeader.Data memory h) internal pure returns (bytes32) {
        require(h.header.validators_hash.length > 0, "Tendermint: hash can't be empty");

        bytes memory hbz = Consensus.encode(h.header.version);
        bytes memory pbt = Timestamp.encode(h.header.time);
        bytes memory bzbi = CanonicalBlockID.encode(h.header.last_block_id);

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

    function hash(ValidatorSet.Data memory vs) internal pure returns (bytes32) {
        return MerkleTree.merkleRootHash(vs.validators, 0, vs.validators.length);
    }

    function getByAddress(ValidatorSet.Data memory vals, bytes memory addr)
        internal
        pure
        returns (uint256 index, bool found)
    {
        bytes20 rawAddr = addr.toBytes20();
        for (uint256 idx; idx < vals.validators.length; idx++) {
            if (vals.validators[idx].pub_key.toTmAddress() == rawAddr) {
                return (idx, true);
            }
        }

        return (0, false);
    }

    function getTotalVotingPower(ValidatorSet.Data memory vals) internal pure returns (int64) {
        if (vals.total_voting_power == 0) {
            uint256 sum = 0;
            uint256 maxInt64 = 1 << (63 - 1);
            uint256 maxTotalVotingPower = maxInt64 / 8;

            for (uint256 i = 0; i < vals.validators.length; i++) {
                sum += (SafeCast.toUint256(int256(vals.validators[i].voting_power)));
                require(sum <= maxTotalVotingPower, "total voting power should be guarded to not exceed");
            }

            vals.total_voting_power = SafeCast.toInt64(int256(sum));
        }

        return vals.total_voting_power;
    }
}

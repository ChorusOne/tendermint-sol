// SPDX-License-Identifier: TBD

pragma solidity ^0.8.2;

import { 
    TENDERMINTLIGHT_PROTO_GLOBAL_ENUMS,
    Validator,
    SimpleValidator,
    BlockID,
    Vote,
    CanonicalBlockID,
    CanonicalPartSetHeader,
    CanonicalVote,
    TmHeader as LightBlock,
    ConsensusState,
    MerkleRoot,
    Commit,
    CommitSig
} from "./TendermintLight.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";

library TendermintHelper {

    function toSimpleValidator(Validator.Data memory val) internal pure returns (SimpleValidator.Data memory) {
        return SimpleValidator.Data({
            pub_key: val.pub_key,
            voting_power: val.voting_power
        });
    }

    function toCanonicalBlockID(BlockID.Data memory blockID) internal pure returns (CanonicalBlockID.Data memory) {
        return CanonicalBlockID.Data({
            hash: blockID.hash,
            part_set_header: CanonicalPartSetHeader.Data({
                total: blockID.part_set_header.total,
                hash: blockID.part_set_header.hash
            })
        });
    }

    function toCanonicalVote(Vote.Data memory vote, string memory chainID) internal pure returns (CanonicalVote.Data memory) {
        return CanonicalVote.Data({
            Type: vote.Type,
            height: vote.height,
            round: int64(vote.round),
            block_id: toCanonicalBlockID(vote.block_id),
            timestamp: vote.timestamp,
            chain_id: chainID
        });
    }

    function toConsensusState(LightBlock.Data memory lightBlock) internal pure returns (ConsensusState.Data memory){
        return ConsensusState.Data({
            timestamp: lightBlock.signed_header.header.time,
            root: MerkleRoot.Data({ hash: lightBlock.signed_header.header.app_hash }),
            next_validators_hash: lightBlock.signed_header.header.next_validators_hash
        });
    }

    function toVote(Commit.Data memory commit, uint valIdx) internal pure returns (Vote.Data memory) {
        CommitSig.Data memory commitSig = commit.signatures[valIdx];

        return Vote.Data({
            Type: TENDERMINTLIGHT_PROTO_GLOBAL_ENUMS.SignedMsgType.SIGNED_MSG_TYPE_PRECOMMIT,
            height: commit.height,
            round: commit.round,
            block_id: commit.block_id, // TODO: this is not exact copy
            timestamp: commitSig.timestamp,
            validator_address: commitSig.validator_address,
            validator_index: SafeCast.toInt32(int(valIdx)),
            signature: commitSig.signature
        });
    }
}

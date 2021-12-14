// SPDX-License-Identifier: TBD

pragma solidity ^0.8.2;

import {TENDERMINTLIGHT_PROTO_GLOBAL_ENUMS, SignedHeader, BlockID, Timestamp, ValidatorSet, Duration, Fraction, Commit, Validator, CommitSig, CanonicalVote, Vote} from "../proto/TendermintLight.sol";
import "../proto/TendermintHelper.sol";
import "../proto/Encoder.sol";
import "./crypto/Ed25519.sol";
import "./crypto/Secp256k1.sol";
import "./Bytes.sol";

library Tendermint {
    using Bytes for bytes;
    using TendermintHelper for ValidatorSet.Data;
    using TendermintHelper for SignedHeader.Data;
    using TendermintHelper for Timestamp.Data;
    using TendermintHelper for BlockID.Data;
    using TendermintHelper for Commit.Data;
    using TendermintHelper for Vote.Data;

    function verify(
        Duration.Data memory trustingPeriod,
        Duration.Data memory maxClockDrift,
        Fraction.Data memory trustLevel,
        SignedHeader.Data memory trustedHeader,
        ValidatorSet.Data memory trustedVals,
        SignedHeader.Data memory untrustedHeader,
        ValidatorSet.Data memory untrustedVals,
        Duration.Data memory currentTime
    ) internal view returns (bool) {
        if (untrustedHeader.header.height != trustedHeader.header.height + 1) {
            return
                verifyNonAdjacent(
                    trustedHeader,
                    trustedVals,
                    untrustedHeader,
                    untrustedVals,
                    trustingPeriod,
                    currentTime,
                    maxClockDrift,
                    trustLevel
                );
        }

        return
            verifyAdjacent(trustedHeader, untrustedHeader, untrustedVals, trustingPeriod, currentTime, maxClockDrift);
    }

    function verifyAdjacent(
        SignedHeader.Data memory trustedHeader,
        SignedHeader.Data memory untrustedHeader,
        ValidatorSet.Data memory untrustedVals,
        Duration.Data memory trustingPeriod,
        Duration.Data memory currentTime,
        Duration.Data memory maxClockDrift
    ) internal view returns (bool) {
        require(untrustedHeader.header.height == trustedHeader.header.height + 1, "headers must be adjacent in height");

        require(!trustedHeader.isExpired(trustingPeriod, currentTime), "header can't be expired");

        verifyNewHeaderAndVals(untrustedHeader, untrustedVals, trustedHeader, currentTime, maxClockDrift);

        // Check the validator hashes are the same
        require(
            untrustedHeader.header.validators_hash.toBytes32() == trustedHeader.header.next_validators_hash.toBytes32(),
            "expected old header next validators to match those from new header"
        );

        // Ensure that +2/3 of new validators signed correctly.
        bool ok = verifyCommitLight(
            untrustedVals,
            trustedHeader.header.chain_id,
            untrustedHeader.commit.block_id,
            untrustedHeader.header.height,
            untrustedHeader.commit
        );

        return ok;
    }

    function verifyNonAdjacent(
        SignedHeader.Data memory trustedHeader,
        ValidatorSet.Data memory trustedVals,
        SignedHeader.Data memory untrustedHeader,
        ValidatorSet.Data memory untrustedVals,
        Duration.Data memory trustingPeriod,
        Duration.Data memory currentTime,
        Duration.Data memory maxClockDrift,
        Fraction.Data memory trustLevel
    ) internal view returns (bool) {
        require(
            untrustedHeader.header.height != trustedHeader.header.height + 1,
            "LC: headers must be non adjacent in height"
        );

        // assert that trustedVals is NextValidators of last trusted header
        // to do this, we check that trustedVals.Hash() == consState.NextValidatorsHash
        require(
            trustedVals.hash() == trustedHeader.header.next_validators_hash.toBytes32(),
            "LC: headers trusted validators does not hash to latest trusted validators"
        );

        require(!trustedHeader.isExpired(trustingPeriod, currentTime), "header can't be expired");

        verifyNewHeaderAndVals(untrustedHeader, untrustedVals, trustedHeader, currentTime, maxClockDrift);

        // Ensure that +`trustLevel` (default 1/3) or more of last trusted validators signed correctly.
        verifyCommitLightTrusting(trustedVals, trustedHeader.header.chain_id, untrustedHeader.commit, trustLevel);

        // Ensure that +2/3 of new validators signed correctly.
        bool ok = verifyCommitLight(
            untrustedVals,
            trustedHeader.header.chain_id,
            untrustedHeader.commit.block_id,
            untrustedHeader.header.height,
            untrustedHeader.commit
        );

        return ok;
    }

    function verifyNewHeaderAndVals(
        SignedHeader.Data memory untrustedHeader,
        ValidatorSet.Data memory untrustedVals,
        SignedHeader.Data memory trustedHeader,
        Duration.Data memory currentTime,
        Duration.Data memory maxClockDrift
    ) internal pure {
        // SignedHeader validate basic
        require(
            keccak256(abi.encodePacked(untrustedHeader.header.chain_id)) ==
                keccak256(abi.encodePacked(trustedHeader.header.chain_id)),
            "header belongs to another chain"
        );
        require(untrustedHeader.commit.height == untrustedHeader.header.height, "header and commit height mismatch");

        bytes32 untrustedHeaderBlockHash = untrustedHeader.hash();
        require(
            untrustedHeaderBlockHash == untrustedHeader.commit.block_id.hash.toBytes32(),
            "commit signs signs block failed"
        );

        require(
            untrustedHeader.header.height > trustedHeader.header.height,
            "expected new header height to be greater than one of old header"
        );
        require(
            untrustedHeader.header.time.gt(trustedHeader.header.time),
            "expected new header time to be after old header time"
        );
        require(
            Timestamp
                .Data({
                    Seconds: int64(currentTime.Seconds) + int64(maxClockDrift.Seconds),
                    nanos: int32(currentTime.nanos) + int32(maxClockDrift.nanos)
                })
                .gt(untrustedHeader.header.time),
            "new header has time from the future"
        );

        bytes32 validatorsHash = untrustedVals.hash();
        require(
            untrustedHeader.header.validators_hash.toBytes32() == validatorsHash,
            "expected new header validators to match those that were supplied at height XX"
        );
    }

    function verifyCommitLightTrusting(
        ValidatorSet.Data memory trustedVals,
        string memory chainID,
        Commit.Data memory commit,
        Fraction.Data memory trustLevel
    ) internal view returns (bool) {
        // sanity check
        require(trustLevel.denominator != 0, "trustLevel has zero Denominator");

        int64 talliedVotingPower = 0;
        bool[] memory seenVals = new bool[](trustedVals.validators.length);

        // TODO: unsafe multiplication?
        CommitSig.Data memory commitSig;
        int256 totalVotingPowerMulByNumerator = trustedVals.getTotalVotingPower() * int64(trustLevel.numerator);
        int256 votingPowerNeeded = totalVotingPowerMulByNumerator / int64(trustLevel.denominator);

        for (uint256 idx = 0; idx < commit.signatures.length; idx++) {
            commitSig = commit.signatures[idx];

            // no need to verify absent or nil votes.
            if (commitSig.block_id_flag != TENDERMINTLIGHT_PROTO_GLOBAL_ENUMS.BlockIDFlag.BLOCK_ID_FLAG_COMMIT) {
                continue;
            }

            // We don't know the validators that committed this block, so we have to
            // check for each vote if its validator is already known.
            // TODO: O(n^2)
            (uint256 valIdx, bool found) = trustedVals.getByAddress(commitSig.validator_address);
            if (found) {
                // check for double vote of validator on the same commit
                require(!seenVals[valIdx], "double vote of validator on the same commit");
                seenVals[valIdx] = true;

                Validator.Data memory val = trustedVals.validators[valIdx];

                // validate signature
                bytes memory message = voteSignBytesDelim(commit, chainID, idx);
                bytes memory sig = commitSig.signature;

                if (!verifySig(val, message, sig)) {
                    return false;
                }

                talliedVotingPower += val.voting_power;

                if (talliedVotingPower > votingPowerNeeded) {
                    return true;
                }
            }
        }

        return false;
    }

    // VerifyCommitLight verifies +2/3 of the set had signed the given commit.
    //
    // This method is primarily used by the light client and does not check all the
    // signatures.
    function verifyCommitLight(
        ValidatorSet.Data memory vals,
        string memory chainID,
        BlockID.Data memory blockID,
        int64 height,
        Commit.Data memory commit
    ) internal view returns (bool) {
        require(vals.validators.length == commit.signatures.length, "invalid commmit signatures");

        require(height == commit.height, "invalid commit height");

        require(commit.block_id.isEqual(blockID), "invalid commit -- wrong block ID");

        Validator.Data memory val;
        CommitSig.Data memory commitSig;

        int64 talliedVotingPower = 0;
        int64 votingPowerNeeded = (vals.getTotalVotingPower() * 2) / 3;

        for (uint256 i = 0; i < commit.signatures.length; i++) {
            commitSig = commit.signatures[i];

            // no need to verify absent or nil votes.
            if (commitSig.block_id_flag != TENDERMINTLIGHT_PROTO_GLOBAL_ENUMS.BlockIDFlag.BLOCK_ID_FLAG_COMMIT) {
                continue;
            }

            val = vals.validators[i];

            // validate signature
            bytes memory message = Encoder.encodeDelim(voteSignBytes(commit, chainID, i));
            bytes memory sig = commitSig.signature;

            if (!verifySig(val, message, sig)) {
                return false;
            }

            talliedVotingPower += val.voting_power;

            if (talliedVotingPower > votingPowerNeeded) {
                return true;
            }
        }

        return false;
    }

    function verifySig(
        Validator.Data memory val,
        bytes memory message,
        bytes memory sig
    ) internal view returns (bool) {
        bytes memory pubkey;

        if (val.pub_key.ed25519.length > 0) {
            pubkey = val.pub_key.ed25519;
            return Ed25519.verify(message, pubkey, sig);
        } else if (val.pub_key.secp256k1.length > 0) {
            pubkey = val.pub_key.secp256k1;
            return Secp256k1.verify(message, pubkey, sig);
        }

        return false;
    }

    function voteSignBytes(
        Commit.Data memory commit,
        string memory chainID,
        uint256 idx
    ) internal pure returns (bytes memory) {
        Vote.Data memory vote;
        vote = commit.toVote(idx);

        return (CanonicalVote.encode(vote.toCanonicalVote(chainID)));
    }

    function voteSignBytesDelim(
        Commit.Data memory commit,
        string memory chainID,
        uint256 idx
    ) internal pure returns (bytes memory) {
        return Encoder.encodeDelim(voteSignBytes(commit, chainID, idx));
    }
}

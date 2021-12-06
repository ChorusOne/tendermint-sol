use std::convert::TryInto;
use web3::types::H160;

use crate::proto::tendermint::light::{
    CanonicalPartSetHeader, BlockIdFlag, CommitSig, Consensus, Duration, SignedHeader,
    Timestamp, TmHeader, Validator, ValidatorSet, CanonicalBlockId
};

pub fn to_part_set_header(part_set_header: &tendermint::block::parts::Header) -> CanonicalPartSetHeader {
    CanonicalPartSetHeader {
        total: part_set_header.total,
        hash: part_set_header.hash.as_bytes().to_vec(),
    }
}

pub fn to_block_id(last_block_id: &tendermint::block::Id) -> CanonicalBlockId {
    CanonicalBlockId {
        hash: last_block_id.hash.as_bytes().to_vec(),
        part_set_header: Some(to_part_set_header(&last_block_id.part_set_header)),
    }
}

pub fn to_timestamp(timestamp: &tendermint::time::Time) -> Timestamp {
    let nanos = timestamp.0.timestamp_subsec_nanos().try_into().unwrap_or(0);
    let seconds = timestamp.0.timestamp();
    Timestamp {
        seconds: seconds,
        nanos: nanos,
    }
}

pub fn to_version(version: &tendermint::block::header::Version) -> Consensus {
    Consensus {
        block: version.block,
        app: version.app,
    }
}

pub fn to_sig(sig: &tendermint::block::commit_sig::CommitSig) -> CommitSig {
    match sig {
        tendermint::block::commit_sig::CommitSig::BlockIdFlagAbsent => CommitSig {
            block_id_flag: BlockIdFlag::Absent.into(),
            validator_address: Vec::new(),
            timestamp: None,
            signature: Vec::new(),
        },
        tendermint::block::commit_sig::CommitSig::BlockIdFlagNil {
            validator_address,
            timestamp,
            signature,
        } => CommitSig {
            block_id_flag: BlockIdFlag::Nil.into(),
            validator_address: validator_address.to_owned().into(),
            timestamp: Some(to_timestamp(&timestamp)),
            signature: signature.to_owned().unwrap().into(),
        },
        tendermint::block::commit_sig::CommitSig::BlockIdFlagCommit {
            validator_address,
            timestamp,
            signature,
        } => CommitSig {
            block_id_flag: BlockIdFlag::Commit.into(),
            validator_address: validator_address.to_owned().into(),
            timestamp: Some(to_timestamp(&timestamp)),
            signature: signature.to_owned().unwrap().into(),
        },
    }
}

pub fn to_signed_header(
    signed_header: &tendermint::block::signed_header::SignedHeader,
) -> SignedHeader {
    let header = &signed_header.header;
    let commit = &signed_header.commit;

    SignedHeader {
        header: Some(crate::proto::tendermint::light::LightHeader {
            chain_id: header.chain_id.to_string(),
            time: Some(to_timestamp(&header.time)),
            height: header.height.into(),
            next_validators_hash: header.next_validators_hash.into(),
            validators_hash: header.validators_hash.into(),
            app_hash: header.app_hash.to_owned().into(),
            consensus_hash: header.consensus_hash.into(),
            data_hash: header.data_hash.unwrap().into(),
            evidence_hash: header.evidence_hash.unwrap().into(),
            last_block_id: Some(to_block_id(&header.last_block_id.unwrap())),
            last_commit_hash: header.last_commit_hash.unwrap().into(),
            last_results_hash: header.last_results_hash.unwrap().into(),
            proposer_address: header.proposer_address.into(),
            version: Some(to_version(&header.version)),
        }),
        commit: Some(crate::proto::tendermint::light::Commit {
            height: commit.height.into(),
            round: commit.round.into(),
            block_id: Some(to_block_id(&commit.block_id)),
            signatures: commit.signatures.iter().map(|sig| to_sig(sig)).collect(),
        }),
    }
}

pub fn to_validator_set(validators: &[tendermint::validator::Info]) -> ValidatorSet {
    ValidatorSet {
        validators: validators
            .iter()
            .map(|validator| Validator {
                address: validator.address.into(),
                pub_key: validator.pub_key.to_bytes().to_vec(),
                voting_power: validator.power.into(),
            })
            .collect(),
        total_voting_power: 0,
    }
}

pub fn to_light_block(signed_header: &SignedHeader, validator_set: &ValidatorSet) -> TmHeader {
    TmHeader {
        trusted_validators: None,
        trusted_height: 0,
        signed_header: Some(signed_header.to_owned()),
        validator_set: Some(validator_set.to_owned()),
    }
}

pub fn to_duration(seconds: i64, nanos: i32) -> Duration {
    Duration { seconds, nanos }
}

pub fn to_addr(address: String) -> H160 {
    let stripped: Vec<u8> = hex::decode(&address[2..address.len()]).unwrap();
    let mut addr: [u8; 20] = Default::default();
    addr.copy_from_slice(&stripped[0..20]);

    H160::from(&addr)
}

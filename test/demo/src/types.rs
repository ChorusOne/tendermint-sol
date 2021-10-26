use web3::types::H160;
use std::error::Error;
use std::fmt;

#[derive(Debug)]
pub struct SimpleError {
	details: String
}

impl SimpleError {
	pub fn new(msg: &str) -> SimpleError {
		SimpleError{details: msg.to_string()}
	}
}

impl fmt::Display for SimpleError {
	fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
		write!(f,"{}",self.details)
	}
}

impl Error for SimpleError {
	fn description(&self) -> &str {
		&self.details
	}
}

pub fn to_part_set_header(part_set_header: tendermint::block::parts::Header) -> crate::proto::tendermint::light::PartSetHeader {
	crate::proto::tendermint::light::PartSetHeader {
		total: part_set_header.total,
		hash: part_set_header.hash.as_bytes().to_vec(),
	}
}

pub fn to_block_id(last_block_id: tendermint::block::Id) -> crate::proto::tendermint::light::BlockId {
	crate::proto::tendermint::light::BlockId {
		hash: last_block_id.hash.as_bytes().to_vec(),
		part_set_header: Some(to_part_set_header(last_block_id.part_set_header)),
	}
}

pub fn to_timestamp(timestamp: tendermint::time::Time) -> crate::proto::tendermint::light::Timestamp {
	let proto_time = prost_types::Timestamp::from(std::time::SystemTime::from(timestamp));
	crate::proto::tendermint::light::Timestamp {
		seconds: proto_time.seconds,
		nanos: proto_time.nanos
	}
}

pub fn to_version(version: tendermint::block::header::Version) -> crate::proto::tendermint::light::Consensus {
	crate::proto::tendermint::light::Consensus {
		block: version.block,
		app: version.app
	}
}

pub fn to_sig(sig: tendermint::block::commit_sig::CommitSig) -> crate::proto::tendermint::light::CommitSig {
	match sig {
		tendermint::block::commit_sig::CommitSig::BlockIDFlagAbsent => crate::proto::tendermint::light::CommitSig {
			block_id_flag: crate::proto::tendermint::light::BlockIdFlag::Absent.into(),
			validator_address: Vec::new(),
			timestamp: None,
			signature: Vec::new(),
		},
		tendermint::block::commit_sig::CommitSig::BlockIDFlagNil {
			validator_address,
			timestamp,
			signature,
		} => crate::proto::tendermint::light::CommitSig {
			block_id_flag: crate::proto::tendermint::light::BlockIdFlag::Nil.into(),
			validator_address: validator_address.into(),
			timestamp: Some(to_timestamp(timestamp)),
			signature: signature.into(),
		},
		tendermint::block::commit_sig::CommitSig::BlockIDFlagCommit {
			validator_address,
			timestamp,
			signature,
		} => crate::proto::tendermint::light::CommitSig {
			block_id_flag: crate::proto::tendermint::light::BlockIdFlag::Commit.into(),
			validator_address: validator_address.into(),
			timestamp: Some(to_timestamp(timestamp)),
			signature: signature.into(),
		},
	}
}

pub fn to_signed_header(signed_header: tendermint::block::signed_header::SignedHeader) -> crate::proto::tendermint::light::SignedHeader {
    let header = signed_header.header;
    let commit = signed_header.commit;

    crate::proto::tendermint::light::SignedHeader {
        header: Some(crate::proto::tendermint::light::LightHeader {
            chain_id: header.chain_id.to_string(),
            time: Some(to_timestamp(header.time)),
            height: header.height.into(),
            next_validators_hash: header.next_validators_hash.into(),
            validators_hash: header.validators_hash.into(),
            app_hash: header.app_hash.into(),
            consensus_hash: header.consensus_hash.into(),
            data_hash: header.data_hash.unwrap().into(),
            evidence_hash: header.evidence_hash.unwrap().into(),
            last_block_id: Some(to_block_id(header.last_block_id.unwrap())),
            last_commit_hash: header.last_commit_hash.unwrap().into(),
            last_results_hash: header.last_results_hash.unwrap().into(),
            proposer_address: header.proposer_address.into(),
            version: Some(to_version(header.version)),

        }),
        commit: Some(crate::proto::tendermint::light::Commit {
            height: commit.height.into(),
            round: commit.round.into(),
            block_id: Some(to_block_id(commit.block_id)),
            //block_id: Some(to_block_id(signed_header_response.signed_header.commit.block_id.clone())),
            //signatures: signed_header_response.signed_header.commit.signatures.iter().map(
            signatures: commit.signatures.iter().map(
                |sig| to_sig(sig.to_owned())
            ).collect()
        }),
    }
}

pub fn to_validator_set(validators: Vec<tendermint::validator::Info>) -> crate::proto::tendermint::light::ValidatorSet {
    crate::proto::tendermint::light::ValidatorSet {
        validators: validators.iter().map(|&validator| crate::proto::tendermint::light::Validator {
            address: validator.address.into(),
            pub_key: Some(crate::proto::tendermint::light::PublicKey{ 
                sum : Some(crate::proto::tendermint::light::public_key::Sum::Ed25519(validator.pub_key.as_bytes().to_vec()))
            }),
            voting_power: validator.voting_power.into(),
            proposer_priority: validator.proposer_priority.into(),
        }).collect(),
        proposer: None,
        total_voting_power: 0
    }
}

pub fn to_light_block(
    signed_header: crate::proto::tendermint::light::SignedHeader,
    validator_set: crate::proto::tendermint::light::ValidatorSet,
) -> crate::proto::tendermint::light::LightBlock {
    crate::proto::tendermint::light::LightBlock {
        signed_header: Some(signed_header),
        validator_set: Some(validator_set),
    }
}

pub fn to_addr(address: String) -> H160 {
	let tt: Vec<u8> = hex::decode(&address[2..address.len()]).unwrap();
	let mut addr: [u8; 20] = Default::default();
	addr.copy_from_slice(&tt[0..20]);

	H160::from(&addr)
}

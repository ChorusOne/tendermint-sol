use serde::{Deserialize, Serialize};
use std::error::Error;
use std::fs::File;
use std::io::BufReader;
use std::path::Path;
use web3::{contract::Contract, types::H160};

#[derive(Deserialize, Serialize, Debug)]
pub struct ABI {
    abi: Vec<serde_json::Value>,
}

pub fn read_abi_from_file<P: AsRef<Path>>(path: P) -> Result<ABI, Box<dyn Error>> {
    let file = File::open(path)?;
    let reader = BufReader::new(file);

    let abi: ABI = serde_json::from_reader(reader)?;

    Ok(abi)
}

pub fn load_contract<'a, T: web3::Transport>(
    transport: &'a T,
    abipath: &'static str,
    address: &'static str,
) -> Contract<&'a T> {
    let web3 = web3::Web3::new(transport);
    let abi = read_abi_from_file(abipath).unwrap();
    let serialized_abi: Vec<u8> = serde_json::to_vec(&abi.abi).unwrap();

    let raw: Vec<u8> = hex::decode(&address[2..address.len()]).unwrap();
    let mut addr: [u8; 20] = Default::default();
    addr.copy_from_slice(&raw[0..20]);

    Contract::from_json(web3.eth(), H160::from(&addr), &serialized_abi).unwrap()
}

pub async fn get_client_ids<'a, T: web3::Transport>(
    transport: &'a T,
    contract: &Contract<&'a T>,
) -> Result<Vec<String>, web3::contract::Error> {
    let res = contract
        .abi()
        .event("GeneratedClientIdentifier")
        .and_then(|ev| {
            let filter = ev.filter(ethabi::RawTopicFilter {
                topic0: ethabi::Topic::Any,
                topic1: ethabi::Topic::Any,
                topic2: ethabi::Topic::Any,
            })?;
            Ok((ev.clone(), filter))
        });

    let (ev, filter) = match res {
        Ok(x) => x,
        Err(e) => return Err(e.into()),
    };

    let logs = web3::Web3::new(transport)
        .eth()
        .logs(
            web3::types::FilterBuilder::default()
                .address(vec![contract.address()])
                .from_block(web3::types::BlockNumber::from(0))
                .topic_filter(filter)
                .build(),
        )
        .await?;

    logs.into_iter()
        .map(move |l| {
            let log = ev.parse_log(ethabi::RawLog {
                topics: l.topics,
                data: l.data.0,
            })?;

            Ok(
                log.params.into_iter().map(|x| x.value).collect::<Vec<_>>()[0]
                    .clone()
                    .to_string(),
            )
        })
        .collect::<Result<Vec<String>, web3::contract::Error>>()
}

// TODO: Cheatsheet
//let ev = host_contract.abi().event("GeneratedClientIdentifier").unwrap();
//let ev_hash = ev.signature();
//let log = create_client_reciept.logs.iter().find(|log| {
//log.topics.iter().find(|topic| topic == &&ev_hash).is_some()
//});

//let l = match log {
//Some(l) => {
//Some(ev.parse_log(ethabi::RawLog {
//topics: vec![ ev_hash ],
//data: l.data.clone().0
//}).unwrap())
//},
//None => None
//};

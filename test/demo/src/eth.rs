use serde::{Deserialize, Serialize};
use std::{error::Error, fs::File, io::BufReader, path::Path};
use web3::{contract::Contract, types::H160};

#[derive(Deserialize, Serialize, Debug)]
pub struct ABI {
    abi: Vec<serde_json::Value>,
}

pub fn read_abi_from_file<P: AsRef<Path>>(path: P) -> Result<ABI, Box<dyn Error>> {
    let file = File::open(path)?;
    let reader = BufReader::new(file);

    Ok(serde_json::from_reader(reader)?)
}

pub fn load_contract<'a, T: web3::Transport>(
    transport: &'a T,
    abipath: &'static str,
    address: &'static str,
) -> Result<Contract<&'a T>, Box<dyn Error>> {
    let web3 = web3::Web3::new(transport);
    let abi = read_abi_from_file(abipath)?;
    let serialized_abi: Vec<u8> = serde_json::to_vec(&abi.abi)?;

    let raw: Vec<u8> = hex::decode(&address[2..address.len()])?;
    let mut addr: [u8; 20] = Default::default();
    addr.copy_from_slice(&raw[0..20]);

    Ok(Contract::from_json(web3.eth(), H160::from(&addr), &serialized_abi)?)
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

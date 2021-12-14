mod consts;
mod eth;
mod proto;
mod types;
mod util;

extern crate clap;
use clap::{App, Arg};

use tokio::time::{sleep, Duration};
use web3::{contract::Options, signing::Key, types::U256};

use ethabi::Token;
use ibc;
use std::{error::Error, fs::File, io::Write};

use proto::tendermint::light::{
    ClientState, ConsensusState, Fraction, SignedHeader, TmHeader, ValidatorSet,
};
use tendermint_rpc::{Client, HttpClient};

use consts::{IBC_HANDLER_ADDRESS, IBC_HOST_ADDRESS, TENDERMINT_LIGHT_CLIENT_ADDRESS};

async fn recv_data_httpclient(
    height: i64,
    client: &mut HttpClient,
    save_header: bool,
) -> Result<TmHeader, Box<dyn Error>> {
    let vs = fetch_validator_set(client, height, save_header).await?;
    let sh = fetch_signed_header(client, height, save_header).await?;

    Ok(types::to_light_block(&sh, &vs))
}

async fn fetch_validator_set(
    client: &mut tendermint_rpc::HttpClient,
    height: i64,
    save_header: bool,
) -> Result<ValidatorSet, Box<dyn Error>> {
    let validator_set_future = client
        .validators(
            tendermint::block::Height::from(height as u32),
            tendermint_rpc::Paging::All,
        )
        .await?;

    let vs = types::to_validator_set(&validator_set_future.validators);

    if save_header {
        let path = format!("../data/header.{}.validator_set.json", height);
        let mut output = File::create(path)?;
        let data = serde_json::to_vec_pretty(&vs)?;
        output.write_all(&data)?;
    }

    Ok(vs)
}

async fn fetch_signed_header(
    client: &mut tendermint_rpc::HttpClient,
    height: i64,
    save_header: bool,
) -> Result<SignedHeader, Box<dyn Error>> {
    let commit_future = client
        .commit(tendermint::block::Height::from(height as u32))
        .await?;

    let sh = types::to_signed_header(&commit_future.signed_header);

    if save_header {
        let path = format!("../data/header.{}.signed_header.json", height);
        let mut output = File::create(path)?;
        let data = serde_json::to_vec_pretty(&sh)?;
        output.write_all(&data)?;
    }

    Ok(sh)
}

async fn handle_header<'a, T: web3::Transport>(
    client: &'a mut tendermint_rpc::HttpClient,
    transport: &'a T,
    trusted_tm_header: Option<TmHeader>,
    tm_header: TmHeader,
    cnt: u64,
    non_adjecent_test: bool,
    gas: u64,
    celo_usd_price: f64,
    celo_gas_price: f64,
    celo_private_key_path: &str,
    client_id: Option<&str>,
) -> Result<TmHeader, Box<dyn Error>> {
    let trusted_height = match trusted_tm_header.as_ref() {
        Some(trusted_header) => {
            trusted_header
                .signed_header
                .as_ref()
                .unwrap()
                .header
                .as_ref()
                .unwrap()
                .height
        }
        None => 0,
    };

    let signed_header = tm_header.signed_header.as_ref().unwrap();
    let header = signed_header.header.as_ref().unwrap();

    println!(
        "\n[0][header] height = {:?} cnt = {:?} trusted_height = {:?}",
        header.height, cnt, trusted_height
    );

    let mut options = Options::default();
    options.gas = Some(U256::from(gas as i64));

    let key = util::get_celo_private_key(&celo_private_key_path)?;
    println!(
        "[0] Celo account address: {:?}",
        web3::signing::SecretKeyRef::new(&key).address()
    );

    // test
    let handler_contract = eth::load_contract(
        &transport,
        "../../build/contracts/IBCHandler.json",
        IBC_HANDLER_ADDRESS,
    )?;
    let host_contract = eth::load_contract(
        &transport,
        "../../build/contracts/IBCHost.json",
        IBC_HOST_ADDRESS,
    )?;
    let _tendermint_contract = eth::load_contract(
        &transport,
        "../../build/contracts/TendermintLightClient.json",
        TENDERMINT_LIGHT_CLIENT_ADDRESS,
    );

    // create client
    if cnt == 0 {
        let register_client_response = handler_contract.signed_call_with_confirmations(
            "registerClient",
            (
                "07-tendermint".to_string(),
                types::to_addr(TENDERMINT_LIGHT_CLIENT_ADDRESS.to_string()),
            ),
            options.clone(),
            1,
            web3::signing::SecretKeyRef::new(&key),
        );

        let register_client_reciept: web3::types::TransactionReceipt =
            register_client_response.await?;

        match register_client_reciept.status {
            Some(status) => {
                if status == web3::types::U64([1 as u64]) {
                    println!(
                        "[1][register-client][] New client: {} registered",
                        "07-tendermint"
                    );
                } else {
                    println!(
                        "[1][register-client][] Warning client: {} already registered",
                        "07-tendermint"
                    );
                }
                util::calculate_and_display_fee(
                    "[1][register-client][]",
                    "".to_string(),
                    &transport,
                    &register_client_reciept,
                    celo_usd_price,
                    celo_gas_price,
                )
                .await;
            }
            None => panic!("unkown outcome - cannot determine if client is registered already?"),
        };

        let client_state = ClientState {
            chain_id: header.chain_id.to_owned(),
            trust_level: Some(Fraction {
                numerator: 1,
                denominator: 3,
            }),
            trusting_period: Some(types::to_duration(100000000000, 0)),
            unbonding_period: Some(types::to_duration(100000000000, 0)),
            max_clock_drift: Some(types::to_duration(100000000000, 0)),
            frozen_height: 0,
            latest_height: header.height,
            allow_update_after_expiry: true,
            allow_update_after_misbehaviour: true,
        };

        let consensus_state = ConsensusState {
            root: Some(proto::tendermint::light::MerkleRoot {
                hash: header.app_hash.to_owned(),
            }),
            timestamp: header.time.to_owned(),
            next_validators_hash: header.next_validators_hash.to_owned(),
        };

        let consensus_state_bytes =
            proto::prost_serialize_any(&consensus_state, "/tendermint.types.ConsensusState")?;

        let client_state_bytes =
            proto::prost_serialize_any(&client_state, "/tendermint.types.ClientState")?;

        // MsgCreateClient
        let tok = ethabi::Token::Tuple(vec![
            Token::String("07-tendermint".to_string()),
            Token::Uint(U256::from(header.height)),
            Token::Bytes(client_state_bytes),
            Token::Bytes(consensus_state_bytes),
        ]);

        let create_client_result = handler_contract.signed_call_with_confirmations(
            "createClient",
            tok,
            options.clone(),
            1,
            web3::signing::SecretKeyRef::new(&key),
        );
        let create_client_reciept: web3::types::TransactionReceipt = create_client_result.await?;
        match create_client_reciept.status {
            Some(status) => {
                if status == web3::types::U64([1 as u64]) {
                    println!(
                        "[2][create-client][] new client instance: {} registered",
                        "07-tendermint"
                    );
                } else {
                    println!(
                        "[2][create-client][] failed to create new client instance: {}",
                        "07-tendermint"
                    );
                }
                util::calculate_and_display_fee(
                    "[2][create-client]",
                    "".to_string(),
                    &transport,
                    &create_client_reciept,
                    celo_usd_price,
                    celo_gas_price,
                )
                .await;
            }
            None => panic!("unkown outcome - dunno "),
        };

        Ok(tm_header)
    } else if cnt == 1 && non_adjecent_test {
        Ok(trusted_tm_header.unwrap())
    } else {
        let client_id = match client_id {
            Some(id) => id.to_string(),
            None => eth::get_client_ids(&transport, &host_contract)
                .await?
                .last()
                .unwrap()
                .to_string(),
        };

        // TODO: proofs
        //const IBC_QUERY_PATH: &str = "store/ibc/key";
        //let path = tendermint::abci::Path::from_str(IBC_QUERY_PATH).unwrap();
        //let _client_id = ibc::ics24_host::identifier::ClientId::new(ibc::ics02_client::client_type::ClientType::Tendermint, next_client_seq - 1).unwrap();
        //let client_state_path = ibc::ics24_host::Path::ClientState(_client_id.clone());
        //println!("CLIENT: {:?}", _client_id);
        //println!("CLIENT STATE PATH: {:?}", client_state_path.clone().to_string());

        //let abci_response = client
        //.abci_query(Some(path), client_state_path.into_bytes(), Some(tendermint::block::Height::from(trusted_height as u32)), true)
        //.await.unwrap();

        // sending trusted validators is required only for non-adjecent test,
        // because tm_header.validator_set.hash() == consensusState.next_validators_hash (adjecent case)
        let trusted_validator_set = match non_adjecent_test {
            true => fetch_validator_set(client, trusted_height + 1, false).await?,
            false => ValidatorSet::default(),
        };

        let tm_header = TmHeader {
            signed_header: Some(signed_header.to_owned()),
            validator_set: tm_header.validator_set.to_owned(),
            trusted_height: trusted_height,
            trusted_validators: Some(trusted_validator_set),
        };

        let serialized_header =
            proto::prost_serialize_any(&tm_header, "/tendermint.types.TmHeader")?;

        // MsgUpdateClient
        let tok = ethabi::Token::Tuple(vec![
            Token::String(client_id.clone()),
            Token::Bytes(serialized_header),
        ]);
        let update_client_result = handler_contract.signed_call_with_confirmations(
            "updateClient",
            tok,
            options.clone(),
            1,
            web3::signing::SecretKeyRef::new(&key),
        );
        let update_client_reciept: web3::types::TransactionReceipt = update_client_result.await?;

        match update_client_reciept.status {
            Some(status) => {
                if status == web3::types::U64([1 as u64]) {
                    println!(
                        "[3][update-client][{}] updated client tx: {:?}",
                        client_id, update_client_reciept.transaction_hash
                    );
                } else {
                    println!(
                        "[3][update-client][{}] failed to update client tx: {:?}",
                        client_id, update_client_reciept.transaction_hash
                    );
                }
                util::calculate_and_display_fee(
                    "[3][update-client]",
                    client_id,
                    &transport,
                    &update_client_reciept,
                    celo_usd_price,
                    celo_gas_price,
                )
                .await;
            }
            None => panic!("unkown outcome - dunno "),
        };

        Ok(tm_header)
    }
}

#[tokio::main]
async fn main() -> web3::Result<()> {
    let matches = App::new("Tendermint Light Client demo program")
		.version("1.0")
		.arg(Arg::with_name("max-headers")
			.long("max-headers")
			.value_name("NUM")
			.default_value("3")
			.required(true)
			.help("Maximum amount of tendermint headers to be processed")
			.takes_value(true))
		.arg(Arg::with_name("celo-gas-price")
			.long("celo-gas-price")
			.value_name("NUM")
			.default_value("0")
			.required(true)
			.help("Celo gas price in wei (see: https://stats.celo.org/)")
			.takes_value(true))
		.arg(Arg::with_name("celo-usd-price")
			.long("celo-usd-price")
			.value_name("NUM")
			.default_value("0")
			.required(true)
			.help("Celo usd price (see: http://usdt.rate.sx/1CELO)")
			.takes_value(true))
		.arg(Arg::with_name("celo-url")
			.long("celo-url")
			.value_name("URL")
			.default_value("http://localhost:8545")
			.required(true)
			.help("Celo RPC endpoint")
			.takes_value(true))
		.arg(Arg::with_name("gas")
			.long("gas")
			.value_name("GAS")
			.default_value("20000000")
			.required(true)
			.help("Maximum tx gas")
			.takes_value(true))
		.arg(Arg::with_name("tendermint-url")
			.long("tendermint-url")
			.value_name("URL")
			.default_value("http://localhost:26657")
			.required(true)
			.help("Tendermint RPC endpoint")
			.takes_value(true))
		.arg(Arg::with_name("celo-private-key")
			.long("celo-private-key")
			.value_name("URL")
			.default_value("../../scripts/secret")
			.required(true)
			.help("Celo secp256k1 private key")
			.takes_value(true))
		.arg(Arg::with_name("non-adjecent-mode")
			.long("non-adjecent-mode")
			.short("n")
			.help("If present, the program skips 2nd header to verify that non-adjecent mode works")
			.takes_value(false))
		.arg(Arg::with_name("save")
			.long("save")
			.short("s")
			.help("If present, block headers and validator set are saved to file")
			.takes_value(false))
		.arg(Arg::with_name("client-id")
			.long("client-id")
			.value_name("CLIENT_ID")
			.required(false)
			.help("IBC Client ID")
			.takes_value(true))
		.arg(Arg::with_name("from-height")
			.long("from-height")
			.value_name("HEIGHT")
			.required(false)
			.help("Start form given block height")
			.takes_value(true))
		.get_matches();

    let max_headers = matches
        .value_of("max-headers")
        .unwrap()
        .parse::<u64>()
        .unwrap();
    let non_adjecent_test = matches.occurrences_of("non-adjecent-mode") > 0;
    let save_header = matches.occurrences_of("save") > 0;
    let tendermint_url = matches.value_of("tendermint-url").unwrap();
    let celo_private_key_path = matches.value_of("celo-private-key").unwrap();
    let celo_url = matches.value_of("celo-url").unwrap();
    let client_id = matches.value_of("client-id");
    let from_height = matches.value_of("from-height");
    let gas = matches.value_of("gas").unwrap().parse::<u64>().unwrap();
    let celo_gas_price = matches
        .value_of("celo-gas-price")
        .unwrap()
        .parse::<f64>()
        .unwrap();
    let celo_usd_price = matches
        .value_of("celo-usd-price")
        .unwrap()
        .parse::<f64>()
        .unwrap();

    // Setup eth client
    let transport = web3::transports::Http::new(celo_url).unwrap();
    let mut client = tendermint_rpc::HttpClient::new(tendermint_url).unwrap();

    let mut cnt: u64 = 0;
    let last_height: u64 = match from_height {
        Some(height) => client.block(tendermint::block::Height::from(
            height.parse::<u64>().unwrap() as u32,
        )),
        None => client.latest_block(),
    }
    .await
    .unwrap()
    .block
    .header
    .height
    .into();

    let mut header: Option<TmHeader> = None;
    for h in last_height..last_height + max_headers {
        let mut block: Option<tendermint::block::Block> = None;

        // try 10 times to get next header
        // NOTE: we could use websocket client subscription, but public node providers doesn't seem
        // to expose the websocket endpoint, so this is more universal approach
        for _ in 1..10 {
            let r = client
                .block(tendermint::block::Height::from(h as u32))
                .await;

            if r.is_err() {
                sleep(Duration::from_secs(2)).await;
            } else {
                block = Some(r.unwrap().block);
            }
        }

        if block.is_none() {
            break;
        }

        let response = recv_data_httpclient(
            block.unwrap().header.height.into(),
            &mut client,
            save_header,
        )
        .await;

        header = Some(
            handle_header(
                &mut client,
                &transport,
                header,
                response.unwrap(),
                cnt,
                non_adjecent_test,
                gas,
                celo_usd_price,
                celo_gas_price,
                celo_private_key_path,
                client_id,
            )
            .await
            .unwrap(),
        );
        cnt += 1;
    }

    Ok(())
}

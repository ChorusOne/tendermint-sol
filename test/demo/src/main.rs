mod consts;
mod eth;
mod proto;
mod types;

extern crate clap;
use clap::{App, Arg};

use tokio::time::{sleep, Duration};
use web3::{
    contract::tokens::Detokenize,
    contract::Options,
    types::{H256, U256},
};

use ethabi::Token;
use ibc;
use std::fs::File;
use std::io::Read;
use std::io::Write;
use std::str::FromStr;

use futures::try_join;
use std::error::Error;
use tendermint_rpc::{Client, HttpClient};

use consts::{IBC_HANDLER_ADDRESS, IBC_HOST_ADDRESS, TENDERMINT_LIGHT_CLIENT_ADDRESS};

async fn recv_data_httpclient(
    block: &tendermint::block::Block,
    client: &mut HttpClient,
    _cnt: u64,
    save_header: bool,
) -> Result<proto::tendermint::light::TmHeader, Box<dyn Error>> {
    let commit_future = client.commit(block.header.height);
    let validator_set_future = client.validators(block.header.height, tendermint_rpc::Paging::All);

    let (signed_header_response, validator_set_response) =
        try_join!(commit_future, validator_set_future)?;

    recv_data(
        block,
        signed_header_response,
        validator_set_response,
        _cnt,
        save_header,
    )
    .await
}

async fn recv_data(
    block: &tendermint::block::Block,
    signed_header_response: tendermint_rpc::endpoint::commit::Response,
    validator_set_response: tendermint_rpc::endpoint::validators::Response,
    _cnt: u64,
    save_header: bool,
) -> Result<proto::tendermint::light::TmHeader, Box<dyn Error>> {
    if save_header {
        let path = format!("./header.{}.signed_header.json", block.header.height);
        let mut output = File::create(path)?;
        let data = serde_json::to_vec_pretty(&signed_header_response.signed_header)?;
        output.write_all(&data).unwrap();

        let path = format!("./header.{}.validator_set.json", block.header.height);
        let mut output = File::create(path)?;
        let data = serde_json::to_vec_pretty(&validator_set_response.validators)?;
        output.write_all(&data).unwrap();
    }

    /* READ FROM FILE
    let mut input = String::new();
    let mut input2 = String::new();
    if _cnt == 0 {
    let mut ifile = File::open("./header.1358.signed_header.json").expect("unable to open file");
    ifile.read_to_string(&mut input).expect("unable to read");

    let mut ifile = File::open("./header.1358.validator_set.json").expect("unable to open file");
    ifile.read_to_string(&mut input2).expect("unable to read");

    } else {
    let mut ifile = File::open("./header.1359.signed_header.json").expect("unable to open file");
    ifile.read_to_string(&mut input).expect("unable to read");

    let mut ifile = File::open("./header.1359.validator_set.json").expect("unable to open file");
    ifile.read_to_string(&mut input2).expect("unable to read");
    }

    let sh = types::to_signed_header(serde_json::from_str(input.as_str()).unwrap());
    let vs = types::to_validator_set(serde_json::from_str(input2.as_str()).unwrap());
    */

    let sh = types::to_signed_header(signed_header_response.signed_header);
    let vs = types::to_validator_set(validator_set_response.validators);

    let header = types::to_light_block(sh, vs);

    Ok(header)
}

async fn handle_header<'a, T: web3::Transport>(
    transport: &'a T,
    trusted_header: Option<proto::tendermint::light::TmHeader>,
    header: proto::tendermint::light::TmHeader,
    cnt: u64,
    non_adjecent_test: bool,
    gas: u64,
    celo_usd_price: f64,
    celo_gas_price: f64,
) -> Result<proto::tendermint::light::TmHeader, Box<dyn Error>> {
    let trusted_height = match trusted_header.clone() {
        Some(trusted_header) => trusted_header.signed_header.unwrap().header.unwrap().height,
        None => 0,
    };

    println!(
        "\n[0][header] height = {:?} cnt = {:?} trusted_height = {:?}",
        header.clone().signed_header.unwrap().header.unwrap().height,
        cnt,
        trusted_height
    );

    let sender = types::to_addr("0x47e172F6CfB6c7D01C1574fa3E2Be7CC73269D95".to_string());
    //let sender = to_addr("0xa89f47c6b463f74d87572b058427da0a13ec5425".to_string());
    let mut options = Options::default();
    options.gas_price = Some(U256::from("0"));
    options.gas = Some(U256::from(gas as i64));

    // test
    let handler_contract = eth::load_contract(
        &transport,
        "../../build/contracts/IBCHandler.json",
        IBC_HANDLER_ADDRESS,
    );
    let host_contract = eth::load_contract(
        &transport,
        "../../build/contracts/IBCHost.json",
        IBC_HOST_ADDRESS,
    );
    let _tendermint_contract = eth::load_contract(
        &transport,
        "../../build/contracts/TendermintLightClient.json",
        TENDERMINT_LIGHT_CLIENT_ADDRESS,
    );

    // create client
    if cnt == 0 {
        let register_client_response = handler_contract.call_with_confirmations(
            "registerClient",
            (
                "07-tendermint".to_string(),
                types::to_addr(TENDERMINT_LIGHT_CLIENT_ADDRESS.to_string()),
            ),
            sender,
            options.clone(),
            1,
        );
        let register_client_reciept: web3::types::TransactionReceipt =
            register_client_response.await.unwrap();

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
                calculate_and_display_fee(
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

        let client_state = proto::tendermint::light::ClientState {
            chain_id: header.signed_header.clone().unwrap().header.unwrap().chain_id,
            trust_level: Some(proto::tendermint::light::Fraction {
                numerator: 1,
                denominator: 3,
            }),
            trusting_period: Some(proto::tendermint::light::Duration {
                seconds: 100000000000,
                nanos: 0,
            }),
            unbonding_period: Some(proto::tendermint::light::Duration {
                seconds: 100000000000,
                nanos: 0,
            }),
            max_clock_drift: Some(proto::tendermint::light::Duration {
                seconds: 100000000000,
                nanos: 0,
            }),
            frozen_height: 0,
            latest_height: header.signed_header.clone().unwrap().header.unwrap().height,
            allow_update_after_expiry: true,
            allow_update_after_misbehaviour: true,
        };

        let consensus_state = proto::tendermint::light::ConsensusState {
            root: Some(proto::tendermint::light::MerkleRoot {
                hash: header
                    .clone()
                    .signed_header
                    .unwrap()
                    .header
                    .unwrap()
                    .app_hash,
            }),
            timestamp: header.clone().signed_header.unwrap().header.unwrap().time,
            next_validators_hash: header
                .clone()
                .signed_header
                .unwrap()
                .header
                .unwrap()
                .next_validators_hash,
        };

        let consensus_state_bytes =
            proto::prost_serialize_any(&consensus_state, "/tendermint.types.ConsensusState")
                .unwrap();
        let client_state_bytes =
            proto::prost_serialize_any(&client_state, "/tendermint.types.ClientState").unwrap();

        // MsgCreateClient
        let tok = ethabi::Token::Tuple(vec![
            Token::String("07-tendermint".to_string()),
            Token::Uint(U256::from(
                header.clone().signed_header.unwrap().header.unwrap().height,
            )),
            Token::Bytes(client_state_bytes),
            Token::Bytes(consensus_state_bytes),
        ]);

        let create_client_result = handler_contract.call_with_confirmations(
            "createClient",
            tok,
            sender,
            options.clone(),
            1,
        );
        let create_client_reciept: web3::types::TransactionReceipt =
            create_client_result.await.unwrap();
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
                calculate_and_display_fee(
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

        Ok(header)
    } else if cnt == 1 && non_adjecent_test {
        Ok(trusted_header.unwrap())
    } else {
        let client_id = eth::get_client_ids(&transport, &host_contract)
            .await?
            .last()
            .unwrap()
            .to_string();

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

        let trusted = trusted_header.unwrap();
        let tm_header = proto::tendermint::light::TmHeader {
            signed_header: header.signed_header.clone(),
            validator_set: header.validator_set.clone(),
            trusted_height: trusted_height,
            trusted_validators: trusted.validator_set.clone(),
        };

        let serialized_header =
            proto::prost_serialize_any(&tm_header, "/tendermint.types.TmHeader").unwrap();

        // MsgUpdateClient
        let tok = ethabi::Token::Tuple(vec![
            Token::String(client_id.clone()),
            Token::Bytes(serialized_header),
        ]);
        let update_client_result = handler_contract.call_with_confirmations(
            "updateClient",
            tok,
            sender,
            options.clone(),
            1,
        );
        let update_client_reciept: web3::types::TransactionReceipt =
            update_client_result.await.unwrap();

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
                calculate_and_display_fee(
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

        Ok(header)
    }
}

async fn calculate_and_display_fee<'a, T: web3::Transport>(
    prefix: &'a str,
    client_id: String,
    transport: &T,
    reciept: &web3::types::TransactionReceipt,
    celo_usd_price: f64,
    celo_gas_price: f64,
) {
    let web3 = web3::Web3::new(&transport);
    let tx: web3::types::Transaction = web3
        .eth()
        .transaction(web3::types::TransactionId::Hash(reciept.transaction_hash))
        .await
        .unwrap()
        .unwrap();

    let gas_price = if tx.gas_price.as_u64() == 0 {
        celo_gas_price
    } else {
        tx.gas_price.as_u64() as f64
    }; // wei
    let gas_used = reciept.gas_used.unwrap().as_u64();
    let fee = (gas_price * gas_used as f64) / 1e18;
    let fee_usd = celo_usd_price * fee;

    println!(
        "{}[{}] gas: {}, gas_used: {}; gas_price: {}; fee(CELO): {}; fee(USD): {}",
        prefix, client_id, tx.gas, gas_used, gas_price, fee, fee_usd
    );
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
		.get_matches();

    let max_headers = matches
        .value_of("max-headers")
        .unwrap()
        .parse::<u64>()
        .unwrap();
    let non_adjecent_test = matches.occurrences_of("non-adjecent-mode") > 0;
    let save_header = matches.occurrences_of("save") > 0;
    let tendermint_url = matches.value_of("tendermint-url").unwrap();
    let celo_url = matches.value_of("celo-url").unwrap();
    let gas = matches
        .value_of("gas")
        .unwrap()
        .parse::<u64>()
        .unwrap();
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

    let mut last_height: u64 = 0;
    let mut header: Option<proto::tendermint::light::TmHeader> = None;
    for cnt in 0..max_headers {
        let mut block = client.latest_block().await.unwrap().block;

        let mut header_height: u64 = block.header.height.into();

        // try 10 times to get next header
        // NOTE: we could use websocket client subscription, but public node providers doesn't seem
        // to expose the websocket endpoint, so this is more universal approach
        for _ in 1..10 {
            if last_height == 0 {
                break;
            }

            sleep(Duration::from_secs(2)).await;

            if header_height <= last_height {
                block = client.latest_block().await.unwrap().block;

                header_height = block.header.height.into();
            } else {
                break;
            }
        }

        last_height = block.header.height.into();

        let response = recv_data_httpclient(&block, &mut client, cnt, save_header).await;

        header = Some(
            handle_header(
                &transport,
                header,
                response.unwrap(),
                cnt,
                non_adjecent_test,
                gas,
                celo_usd_price,
                celo_gas_price,
            )
            .await
            .unwrap(),
        );
    }

    Ok(())
}

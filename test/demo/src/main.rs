use web3::{
	contract::{Options},
	types::{
		U256,
		H256
	}
};

mod types;
mod eth;
mod proto;
mod consts;
use web3::contract::tokens::Detokenize;

use ethabi::Token;
use std::io::Read;
use std::io::Write;
use std::fs::File;
use std::str::FromStr;
use ibc;

use tendermint_rpc::{WebSocketClient, SubscriptionClient, Client};
use tendermint_rpc::query::EventType;
use futures::try_join;
use std::error::Error;
use futures::StreamExt;

use consts::{TENDERMINT_LIGHT_CLIENT_ADDRESS, IBC_HOST_ADDRESS, IBC_HANDLER_ADDRESS};

async fn recv_data(
	response: Result<tendermint_rpc::event::Event, tendermint_rpc::Error>,
	client: &mut WebSocketClient,
	_cnt: u64,
    save_header: bool,
) -> Result<proto::tendermint::light::LightBlock, Box<dyn Error>> {
	let maybe_result = response;
	if maybe_result.is_err() {
		return Err(types::SimpleError::new("unable to get events from socket").into());
	}
	let result = maybe_result.unwrap();
	match result.data {
		tendermint_rpc::event::EventData::NewBlock {
			block,
			result_begin_block: _,
			result_end_block: _,
		} => {
			if block.is_none() {
				return Err(types::SimpleError::new("e.block".into()).into());
			}
			let block = block.unwrap();
			let commit_future = client.commit(block.header.height);
			let validator_set_future = client.validators(block.header.height);
			let (signed_header_response, validator_set_response) =
				try_join!(commit_future, validator_set_future)?;

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
		_ => Err(types::SimpleError::new("unexpected error").into()),
	}
}

async fn handle_header<'a, T: web3::Transport>(
    client: &mut WebSocketClient,
	transport: &'a T,
	trusted_header: Option<proto::tendermint::light::LightBlock>,
	header: proto::tendermint::light::LightBlock,
	cnt: u64,
    non_adjecent_test: bool
) -> Result<proto::tendermint::light::LightBlock, Box<dyn Error>> {
    let trusted_height = match trusted_header.clone() {
        Some(trusted_header) => trusted_header.signed_header.unwrap().header.unwrap().height,
        None => 0,
    };

	println!("\n[0][header] height = {:?} cnt = {:?} trusted_height = {:?}",
        header.clone().signed_header.unwrap().header.unwrap().height,
        cnt,
        trusted_height
    );

	let sender = types::to_addr("0x47e172F6CfB6c7D01C1574fa3E2Be7CC73269D95".to_string());
	//let sender = to_addr("0xa89f47c6b463f74d87572b058427da0a13ec5425".to_string());
	let mut options = Options::default();
	options.gas_price = Some(U256::from("0"));
	options.gas = Some(U256::from(9000000 as i64));

	// test
	let handler_contract = eth::load_contract(&transport, "../../build/contracts/IBCHandler.json", IBC_HANDLER_ADDRESS);
	let host_contract = eth::load_contract(&transport, "../../build/contracts/IBCHost.json", IBC_HOST_ADDRESS);
	let _tendermint_contract = eth::load_contract(&transport, "../../build/contracts/TendermintClient.json", TENDERMINT_LIGHT_CLIENT_ADDRESS);

	// create client
	if cnt == 0 {
        let register_client_response = handler_contract.call_with_confirmations("registerClient", ("07-tendermint".to_string(), types::to_addr(TENDERMINT_LIGHT_CLIENT_ADDRESS.to_string()) ), sender, options.clone(), 1);
        let register_client_reciept: web3::types::TransactionReceipt = register_client_response.await.unwrap();

        match register_client_reciept.status {
            Some(status) => {
                if status == web3::types::U64([1 as u64]) {
                    println!("[1][register-client] New client: {} registered", "07-tendermint");
                } else {
                    println!("[1][register-client] Warning client: {} already registered", "07-tendermint");
                }
            },
            None => panic!("unkown outcome - cannot determine if client is registered already?")
        };

		let client_state = proto::tendermint::light::ClientState {
			chain_id: "wormhole".to_string(),
			trust_level: Some(proto::tendermint::light::Fraction{
				numerator: 1,
				denominator: 3
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
			latest_height: header.clone().signed_header.unwrap().header.unwrap().height,
			allow_update_after_expiry: true,
			allow_update_after_misbehaviour: true,
		};

		let consensus_state = proto::tendermint::light::ConsensusState {
			root: Some(proto::tendermint::light::MerkleRoot{
				hash: header.clone().signed_header.unwrap().header.unwrap().app_hash,
			}),
			timestamp: header.clone().signed_header.unwrap().header.unwrap().time,
			next_validators_hash: header.clone().signed_header.unwrap().header.unwrap().next_validators_hash
		};

		let consensus_state_bytes = proto::prost_serialize_any(&consensus_state, "/tendermint.types.ConsensusState").unwrap();
		let client_state_bytes = proto::prost_serialize_any(&client_state, "/tendermint.types.ClientState").unwrap();

		// MsgCreateClient
		let tok = ethabi::Token::Tuple(vec![
			Token::String("07-tendermint".to_string()),
			Token::Uint(U256::from(header.clone().signed_header.unwrap().header.unwrap().height)),
			Token::Bytes(client_state_bytes),
			Token::Bytes(consensus_state_bytes),
		]);

		let create_client_result = handler_contract.call_with_confirmations("createClient", tok, sender, options.clone(), 1);
		let create_client_reciept: web3::types::TransactionReceipt = create_client_result.await.unwrap();
		match create_client_reciept.status {
			Some(status) => {
				if status == web3::types::U64([1 as u64]) {
					println!("[2][create-client] new client instance: {} registered", "07-tendermint");
				} else {
					println!("[2][create-client] failed to create new client instance: {}", "07-tendermint");
				}
			},
			None => panic!("unkown outcome - dunno ")
		};


    	Ok(header)
	} else if cnt == 1 && non_adjecent_test {
    	Ok(trusted_header.unwrap())
    } else {
		let client_id = eth::get_client_ids(&transport, &host_contract).await?.last().unwrap().to_string();

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

        //println!("RESP: {:?}", abci_response.value);

		let trusted = trusted_header.unwrap();
		let tm_header = proto::tendermint::light::TmHeader {
			signed_header: header.signed_header.clone(),
			validator_set: header.validator_set.clone(),

			trusted_height: trusted_height,
			trusted_validators: trusted.validator_set.clone(),
		};

		let serialized_header = proto::prost_serialize_any(&tm_header, "/tendermint.types.LightBlock").unwrap();

		// MsgUpdateClient
		let tok = ethabi::Token::Tuple(vec![
			Token::String(client_id.clone()),
			Token::Bytes(serialized_header),
		]);
		let update_client_result = handler_contract.call_with_confirmations("updateClient", tok, sender, options.clone(), 1);
		let update_client_reciept: web3::types::TransactionReceipt = update_client_result.await.unwrap();

		match update_client_reciept.status {
			Some(status) => {
				if status == web3::types::U64([1 as u64]) {
					println!("[3][update-client][{}] updated client tx: {:?}", client_id, update_client_reciept.transaction_hash);
				} else {
					println!("[3][update-client][{}] failed to update client tx: {:?}", client_id, update_client_reciept.transaction_hash);
				}
			},
			None => panic!("unkown outcome - dunno ")
		};

    	Ok(header)
	}
}

#[tokio::main]
async fn main() -> web3::Result<()> {
    let args: Vec<String> = std::env::args().collect();
    let max_headers: u64 = args[1].parse().unwrap();
    let non_adjecent_test: bool = args[2].parse().unwrap();
    let save_header: bool = args[3].parse().unwrap();

	// Setup eth client
	let transport = web3::transports::Http::new("http://localhost:8545").unwrap();

	// Setup tendermint client
	let tm_addr = tendermint::net::Address::Tcp {
		host: "localhost".to_string(),
		port: 26657,
		peer_id: None,
	};
	let (mut client, driver) = WebSocketClient::new(tm_addr.clone())
		.await
		.unwrap();

	let driver_handle = tokio::spawn(async move { driver.run().await });

	println!("[CONN] connected websocket to {:?}", tm_addr);
	let mut subs = client
		.subscribe(EventType::NewBlock.into())
		.await
		.unwrap();

	let mut header: Option<proto::tendermint::light::LightBlock> = None;
	let mut cnt: u64 = 0;
	while let Some(response) = subs.next().await {
		let response = recv_data(response, &mut client, cnt, save_header).await;
		if response.is_err() {
			println!(
				"Error: {} while processing tendermint node response",
				response.err().unwrap()
			);
			continue;
		}

		header = Some(handle_header(&mut client, &transport, header, response.unwrap(), cnt, non_adjecent_test).await.unwrap());
		cnt = cnt +1;

        if cnt == max_headers {
            break;
        }
	}

    client.close().unwrap();
    driver_handle.await.unwrap();

	Ok(())
}

use secp256k1::{key::SecretKey, rand::rngs::OsRng, Secp256k1};
use std::{
    error::Error,
    fs::File,
    io::{Read, Write},
    path::Path,
};

pub fn get_celo_private_key(celo_private_key_path: &str) -> Result<SecretKey, Box<dyn Error>> {
    if Path::new(celo_private_key_path).exists() {
        let mut secret = String::new();
        let mut ifile = File::open(celo_private_key_path)?;
        ifile.read_to_string(&mut secret)?;

        Ok(SecretKey::from_slice(&hex::decode(
            secret.strip_prefix("0x").unwrap(),
        )?)?)
    } else {
        let secp = Secp256k1::new();
        let mut rng = OsRng::new().expect("OsRng");
        let (secret_key, _public_key) = secp.generate_keypair(&mut rng);

        let mut ifile = File::create(celo_private_key_path)?;
        ifile.write_all(format!("0x{}", hex::encode(secret_key.as_ref())).as_bytes())?;

        println!(
            "[0] generated a new celo private key: {}",
            celo_private_key_path
        );

        Ok(secret_key)
    }
}

pub async fn calculate_and_display_fee<'a, T: web3::Transport>(
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

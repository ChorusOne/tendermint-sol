use prost::Message;
use prost_types::Any;

pub mod tendermint {
    pub mod light {
        tonic::include_proto!("tendermint.light");
    }
}

pub fn prost_serialize<T: Message>(msg: &T) -> Result<Vec<u8>, prost::EncodeError> {
	let mut buf = Vec::new();
	msg.encode(&mut buf)?;

	Ok(buf)
}

pub fn prost_serialize_any<T: Message>(msg: &T, type_url: &'static str) -> Result<Vec<u8>, prost::EncodeError> {
	let any = Any {
		type_url: type_url.to_string(),
		value: prost_serialize(msg)?,
	};

	let serialized = prost_serialize(&any)?;

	Ok(serialized)
}

fn main() {
    tonic_build::configure()
        .type_attribute(".", "#[derive(::serde::Serialize, ::serde::Deserialize)]")
        .build_server(false)
        .build_client(true)
        .compile(
            &["../../proto/TendermintLight.proto"],
            &["../../proto", "third_party/proto/"],
        )
        .unwrap();
}

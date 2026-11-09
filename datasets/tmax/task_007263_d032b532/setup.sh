#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip protobuf-compiler g++ cargo rustc
pip3 install pytest

mkdir -p /home/user/rust_client/src

cat << 'EOF' > /home/user/rust_client/Cargo.toml
[package]
name = "rust_client"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

cat << 'EOF' > /home/user/rust_client/src/main.rs
struct MockClient;

impl MockClient {
    fn record(&self, item: String) {
        println!("Recorded: {}", item);
    }
}

fn main() {
    let client = MockClient;
    let logs = vec![
        String::from("error"),
        String::from("warning"),
        String::from("error"),
        String::from("info"),
    ];

    for log in logs {
        let payload = log; // Move occurs here
        client.record(payload);

        // BUG: Using `log` after it was moved into `payload`
        println!("Successfully processed log: {}", log); 
    }
}
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user

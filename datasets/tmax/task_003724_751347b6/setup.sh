#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/graph_etl/src

    cat << 'EOF' > /home/user/transactions.jsonl
{"tx_id": "1", "sender": "U1", "receiver": "U2", "amount": 50}
{"tx_id": "2", "sender": "U1", "receiver": "U3", "amount": 20}
{"tx_id": "3", "sender": "U2", "receiver": "U3", "amount": 10}
{"tx_id": "4", "sender": "U4", "receiver": "U2", "amount": 100}
{"tx_id": "5", "sender": "U5", "receiver": "U2", "amount": 5}
{"tx_id": "6", "sender": "U3", "receiver": "U4", "amount": 60}
{"tx_id": "7", "sender": "U6", "receiver": "U7", "amount": 10}
{"tx_id": "8", "sender": "U7", "receiver": "U3", "amount": 15}
{"tx_id": "9", "sender": "U8", "receiver": "U4", "amount": 100}
{"tx_id": "10", "sender": "U9", "receiver": "U4", "amount": 150}
EOF

    cat << 'EOF' > /home/user/graph_etl/Cargo.toml
[package]
name = "graph_etl"
version = "0.1.0"
edition = "2021"

[dependencies]
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
EOF

    cat << 'EOF' > /home/user/graph_etl/src/main.rs
fn main() {
    println!("Hello, world!");
}
EOF

    chmod -R 777 /home/user

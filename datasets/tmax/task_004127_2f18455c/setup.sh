#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo
    pip3 install pytest

    mkdir -p /home/user/data
    cat << 'EOF' > /home/user/data/transactions.jsonl
{"event_id": "e1", "source_node": "U1", "destinations": ["U2", "U3"], "amount": 100}
{"event_id": "e2", "source_node": "U2", "destinations": ["U4"], "amount": 50}
{"event_id": "e3", "source_node": "U3", "destinations": ["U2"], "amount": 25}
{"event_id": "e4", "source_node": "U4", "destinations": ["U2"], "amount": 10}
{"event_id": "e5", "source_node": "U5", "destinations": ["U2", "U1"], "amount": 500}
{"event_id": "e6", "source_node": "U6", "destinations": ["U1", "U7"], "amount": 50}
{"event_id": "e7", "source_node": "U7", "destinations": ["U6"], "amount": 20}
EOF

    mkdir -p /home/user/graph_etl/src
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

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

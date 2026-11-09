#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential cargo
    pip3 install pytest

    mkdir -p /home/user/etl_project/src

    cat << 'EOF' > /home/user/etl_project/Cargo.toml
[package]
name = "etl_project"
version = "0.1.0"
edition = "2021"

[dependencies]
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
EOF

    cat << 'EOF' > /home/user/etl_project/src/main.rs
fn main() {
    println!("Hello, world!");
}
EOF

    cat << 'EOF' > /home/user/etl_project/transactions.jsonl
{"tx_id": "T1", "waits_for": "T2", "wait_time_ms": 100}
{"tx_id": "T2", "waits_for": "T3", "wait_time_ms": 200}
{"tx_id": "T3", "waits_for": "T1", "wait_time_ms": 50}
{"tx_id": "T4", "waits_for": "T5", "wait_time_ms": 300}
{"tx_id": "T5", "waits_for": "T6", "wait_time_ms": 100}
{"tx_id": "T6", "waits_for": "T4", "wait_time_ms": 400}
{"tx_id": "T7", "waits_for": "T8", "wait_time_ms": 50}
{"tx_id": "T8", "waits_for": "T9", "wait_time_ms": 20}
{"tx_id": "T10", "waits_for": "T11", "wait_time_ms": 600}
{"tx_id": "T11", "waits_for": "T10", "wait_time_ms": 400}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

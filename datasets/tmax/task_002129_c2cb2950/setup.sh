#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/backup_analyzer/src

    cat << 'EOF' > /home/user/backup_analyzer/Cargo.toml
[package]
name = "backup_analyzer"
version = "0.1.0"
edition = "2021"

[dependencies]
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
EOF

    cat << 'EOF' > /home/user/backup_analyzer/src/main.rs
fn main() {
    println!("Hello, world!");
}
EOF

    cat << 'EOF' > /home/user/backups.jsonl
{"id":"A","parent_id":null,"size_bytes":1000,"region":"us-east"}
{"id":"B","parent_id":"A","size_bytes":100,"region":"us-east"}
{"id":"C","parent_id":"A","size_bytes":150,"region":"us-east"}
{"id":"D","parent_id":"C","size_bytes":50,"region":"us-east"}
{"id":"E","parent_id":null,"size_bytes":2000,"region":"eu-west"}
{"id":"F","parent_id":"E","size_bytes":200,"region":"eu-west"}
{"id":"G","parent_id":null,"size_bytes":150,"region":"us-east"}
{"id":"H","parent_id":"G","size_bytes":150,"region":"us-east"}
EOF

    chmod -R 777 /home/user

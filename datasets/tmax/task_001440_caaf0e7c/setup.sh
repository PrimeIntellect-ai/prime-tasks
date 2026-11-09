#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential
    pip3 install pytest

    # Install Rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    export PATH="/root/.cargo/bin:${PATH}"

    # Create directories
    mkdir -p /home/user/config_tracker/src
    cd /home/user/config_tracker

    # Create Cargo.toml
    cat << 'EOF' > Cargo.toml
[package]
name = "config_tracker"
version = "0.1.0"
edition = "2021"

[dependencies]
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
chrono = "0.4"
sha2 = "0.10"
EOF

    # Create input.jsonl
    cat << 'EOF' > input.jsonl
{"server_id": "srv-1", "timestamp": 1698750000, "description": "Mise à jour du réseau", "config_payload": "{\"port\": 8080}"}
{"server_id": "srv-2", "timestamp": "Tue, 31 Oct 2023 11:00:00 +0000", "description": "Mise à jour du réseau", "config_payload": "{\"port\": 8080}"}
{"server_id": "srv-3", "timestamp": 1698740000, "description": "Mise à jour du réseau", "config_payload": "{\"port\": 8080}"}
{"server_id": "srv-4", "timestamp": 1698745000, "description": "更新：システム設定とデータベースの接続パラメータを変更しました。これが長すぎます。", "config_payload": "{\"db\": \"mysql\"}"}
{"server_id": "srv-5", "timestamp": "Wed, 01 Nov 2023 10:00:00 -0400", "description": "Fix DB typo", "config_payload": "{\"db\": mysql\"}"}
{"server_id": "srv-6", "timestamp": 1698850000, "description": "Add new cache node", "config_payload": "{\"cache\": \"redis\"}"}
{"server_id": "srv-7", "timestamp": "Tue, 31 Oct 2023 10:53:20 +0000", "description": "Mise à jour du réseau", "config_payload": "{\"port\": 8080}"}
EOF

    # Create main.rs
    cat << 'EOF' > src/main.rs
fn main() {}
EOF

    # Create user and fix permissions
    useradd -m -s /bin/bash user || true

    # Ensure rustup/cargo is available to user
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | su - user -c "sh -s -- -y"

    chmod -R 777 /home/user

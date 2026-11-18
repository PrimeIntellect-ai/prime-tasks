#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    mkdir -p /home/user/project

    cat << 'EOF' > /home/user/project/Cargo.toml
[package]
name = "my_rust_service"
version = "0.1.0"
edition = "2021"

[dependencies]
serde = "1.0.100"
tokio = "1.15.0"
reqwest = "0.11.0"
EOF

    cat << 'EOF' > /home/user/project/policy.json
{
  "dependencies": {
    "serde": ">=1.0.130",
    "tokio": ">=1.20.0",
    "reqwest": ">=0.11.10"
  }
}
EOF

    cat << 'EOF' > /home/user/project/schema_v1.json
[
  {"id": 1, "first_name": "Alice", "last_name": "Smith"},
  {"id": 2, "first_name": "Bob", "last_name": "Jones"}
]
EOF

    mkdir -p /home/user/project/src
    cat << 'EOF' > /home/user/project/src/main.rs
fn main() {
    println!("Hello, world!");
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

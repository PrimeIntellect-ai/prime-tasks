#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc espeak
    pip3 install pytest

    mkdir -p /app/corpus/evil /app/corpus/clean

    # Generate voice memo
    espeak -w /app/voice_memo.wav "We need to update the grpcio dependency in the Rust project to exactly version 0.13.0 to fix the build error. Also, for the Python WebSocket filter, make sure to reject any payloads where the client_version is strictly less than 1.4.0, as those older versions have a known vulnerability. Accept anything 1.4.0 or higher."

    # Create adversarial corpus
    cat << 'EOF' > /app/corpus/evil/payload1.json
{"client_version": "1.3.9", "data": "test"}
EOF
    cat << 'EOF' > /app/corpus/evil/payload2.json
{"client_version": "0.9.9", "data": "test"}
EOF
    cat << 'EOF' > /app/corpus/evil/payload3.json
{"client_version": "1.4.0-alpha", "data": "test"}
EOF
    cat << 'EOF' > /app/corpus/evil/payload4.json
{"invalid_field": "1.5.0"}
EOF

    cat << 'EOF' > /app/corpus/clean/payload1.json
{"client_version": "1.4.0", "data": "test"}
EOF
    cat << 'EOF' > /app/corpus/clean/payload2.json
{"client_version": "1.5.2", "data": "test"}
EOF
    cat << 'EOF' > /app/corpus/clean/payload3.json
{"client_version": "2.0.0", "data": "test"}
EOF

    # Create Rust project
    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/rust_server/src

    cat << 'EOF' > /home/user/rust_server/Cargo.toml
[package]
name = "rust_server"
version = "0.1.0"
edition = "2021"

[dependencies]
grpcio = "0.12.0"
EOF

    cat << 'EOF' > /home/user/rust_server/src/main.rs
extern crate grpcio;

fn main() {
    println!("Server running");
}
EOF

    chmod -R 777 /home/user
    chmod -R 777 /app

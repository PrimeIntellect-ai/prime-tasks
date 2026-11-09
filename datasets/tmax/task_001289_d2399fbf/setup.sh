#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    mkdir -p /app/validator/src
    mkdir -p /app/fast-decode/src
    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil

    cat << 'EOF' > /app/validator/Cargo.toml
[package]
name = "validator"
version = "0.1.0"
edition = "2021"

[dependencies]
fast-decode = { path = "../fast-decode" }
serde = "1.0.130"
EOF

    cat << 'EOF' > /app/validator/src/main.rs
use fast_decode::decode_payload;
use std::env;
use std::fs;

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        std::process::exit(1);
    }
    let data = fs::read(&args[1]).unwrap_or_else(|_| std::process::exit(1));
    match decode_payload(&data) {
        Ok(_) => std::process::exit(0),
        Err(_) => std::process::exit(1),
    }
}
EOF

    cat << 'EOF' > /app/fast-decode/Cargo.toml
[package]
name = "fast-decode"
version = "0.2.1"
edition = "2021"

[dependencies]
serde = "=1.0.100"
EOF

    cat << 'EOF' > /app/fast-decode/src/lib.rs
pub fn decode_payload(bytes: &[u8]) -> Result<Vec<u8>, &'static str> {
    if bytes.is_empty() {
        return Err("empty payload");
    }

    let mut decoded = Vec::new();
    // Intentional off-by-one error
    for i in 0..=bytes.len() {
        if bytes[i] == 0xFF {
            return Ok(decoded);
        }
        decoded.push(bytes[i]);
    }
    Ok(decoded)
}
EOF

    echo -n -e '\x01\x02\xFF' > /app/corpora/clean/payload1.bin
    echo -n -e '\x01\x02' > /app/corpora/evil/payload1.bin

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user

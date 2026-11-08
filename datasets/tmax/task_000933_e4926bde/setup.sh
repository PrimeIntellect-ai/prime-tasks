#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cd /tmp
    cargo new implant_build
    cd implant_build
    cargo add base64
    cargo add serde_json

    cat << 'EOF' > src/main.rs
use std::io;
use base64::{Engine as _, engine::general_purpose::STANDARD};
use serde_json::Value;

fn main() {
    let mut input = String::new();
    if io::stdin().read_line(&mut input).is_err() {
        return;
    }
    let parts: Vec<&str> = input.trim().split('.').collect();
    if parts.len() < 2 {
        println!("Error: Invalid token format.");
        return;
    }

    let header_b64 = parts[0];
    let payload_b64 = parts[1];

    let header_bytes = STANDARD.decode(header_b64).unwrap_or_default();
    let payload_bytes = STANDARD.decode(payload_b64).unwrap_or_default();

    let header: Value = serde_json::from_slice(&header_bytes).unwrap_or_default();
    let payload: Value = serde_json::from_slice(&payload_bytes).unwrap_or_default();

    if header.get("alg").and_then(|v| v.as_str()) == Some("none") {
        if payload.get("action").and_then(|v| v.as_str()) == Some("extract") {
            println!("{}", "FLAG{JWT_byp4ss_r3c0v3ry}");
            return;
        }
    }
    println!("Error: Unauthorized or invalid action.");
}
EOF

    cargo build --release
    cp target/release/implant_build /home/user/implant
    chmod 755 /home/user/implant
    chown user:user /home/user/implant

    cd /
    rm -rf /tmp/implant_build

    chmod -R 777 /home/user

#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/auth_src/src

    cat << 'EOF' > /home/user/auth_src/Cargo.toml
[package]
name = "auth_checker"
version = "0.1.0"
edition = "2021"

[dependencies]
base64 = "0.21.0"
EOF

    cat << 'EOF' > /home/user/auth_src/src/main.rs
use std::env;
use base64::{engine::general_purpose, Engine as _};

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        println!("Usage: auth_checker <token>");
        return;
    }

    let token = &args[1];
    let parts: Vec<&str> = token.split('.').collect();
    if parts.len() < 2 {
        println!("Access denied: Malformed token.");
        return;
    }

    let header_bytes = general_purpose::URL_SAFE_NO_PAD.decode(parts[0]).unwrap_or_default();
    let header_str = String::from_utf8_lossy(&header_bytes);

    let payload_bytes = general_purpose::URL_SAFE_NO_PAD.decode(parts[1]).unwrap_or_default();
    let payload_str = String::from_utf8_lossy(&payload_bytes);

    // VULNERABILITY: Accepts alg: none without signature verification
    let is_none_alg = header_str.replace(" ", "").contains("\"alg\":\"none\"");

    if is_none_alg {
        let is_admin = payload_str.replace(" ", "").contains("\"role\":\"admin\"");
        if is_admin {
            println!("-----BEGIN OPENSSH PRIVATE KEY-----\nb3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW\nQyNTUxOQAAACBA1/1+xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\n-----END OPENSSH PRIVATE KEY-----");
        } else {
            println!("Access denied: Not admin.");
        }
    } else {
        println!("Access denied: Invalid signature.");
    }
}
EOF

    cd /home/user/auth_src
    cargo build --release
    cp target/release/auth_checker /home/user/auth_checker
    chmod +x /home/user/auth_checker

    chmod -R 777 /home/user

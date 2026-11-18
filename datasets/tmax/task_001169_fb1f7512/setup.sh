#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create the Rust project
    cd /home/user
    cargo new auth_service
    cd auth_service

    # Add base64 dependency
    echo 'base64 = "0.13"' >> Cargo.toml

    # Write the Rust source code
    cat << 'EOF' > src/main.rs
use std::env;
use std::fs;
use std::process;

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() != 2 {
        eprintln!("Usage: auth_verifier <token_file>");
        process::exit(1);
    }

    let token = fs::read_to_string(&args[1]).expect("Failed to read token file");
    let token = token.trim();

    let parts: Vec<&str> = token.split('.').collect();
    if parts.len() != 3 {
        eprintln!("Invalid JWT format");
        process::exit(1);
    }

    // Decode header
    let header_bytes = base64_url_decode(&parts[0]).unwrap_or_default();
    let header_str = String::from_utf8(header_bytes).unwrap_or_default();

    if !header_str.contains("\"alg\":\"none\"") && !header_str.contains("\"alg\": \"none\"") {
        eprintln!("Verification failed: Invalid signature");
        process::exit(1);
    }

    // Decode payload
    let payload_bytes = base64_url_decode(&parts[1]).unwrap_or_default();
    let payload_str = String::from_utf8(payload_bytes).unwrap_or_default();

    if payload_str.contains("\"role\":\"superadmin\"") || payload_str.contains("\"role\": \"superadmin\"") {
        println!("Audit Trail Generated: Authentication Success");
        println!("Granted Access Level: SUPERADMIN");
        println!("Subject: {}", extract_sub(&payload_str));
    } else {
        println!("Audit Trail Generated: Authentication Success");
        println!("Granted Access Level: USER");
    }
}

fn base64_url_decode(input: &str) -> Option<Vec<u8>> {
    let mut b64 = input.replace("-", "+").replace("_", "/");
    match b64.len() % 4 {
        2 => b64.push_str("=="),
        3 => b64.push_str("="),
        _ => {}
    }
    base64::decode(&b64).ok()
}

fn extract_sub(payload: &str) -> String {
    if payload.contains("\"sub\":\"auditor\"") || payload.contains("\"sub\": \"auditor\"") {
        return "auditor".to_string();
    }
    "unknown".to_string()
}
EOF

    # Compile the project
    cargo build --release
    cp target/release/auth_service /home/user/auth_verifier

    # Set permissions
    chmod +x /home/user/auth_verifier
    chmod -R 777 /home/user

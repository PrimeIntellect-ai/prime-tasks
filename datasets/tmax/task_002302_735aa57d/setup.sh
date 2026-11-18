#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/auth_checker.rs
use std::fs;
use std::env;

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        println!("Usage: auth_checker <token_file>");
        return;
    }

    let token_hex = fs::read_to_string(&args[1]).unwrap().trim().to_string();
    let mut decoded = Vec::new();

    for i in (0..token_hex.len()).step_by(2) {
        if let Ok(byte) = u8::from_str_radix(&token_hex[i..i+2], 16) {
            decoded.push(byte);
        }
    }

    // Decrypt payload
    let key = 0x5A; // Hardcoded XOR key
    let mut decrypted = String::new();
    for byte in decoded {
        decrypted.push((byte ^ key) as char);
    }

    if decrypted.contains("role=admin") {
        println!("Access Granted: Admin");
    } else {
        println!("Access Denied: {}", decrypted);
    }
}
EOF

    chmod -R 777 /home/user

#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    mkdir -p /home/user/investigation/src

    cat << 'EOF' > /home/user/investigation/Cargo.toml
[package]
name = "decrypter"
version = "0.1.0"
edition = "2021"

[dependencies]
# Intentional dependency conflict: bincode 1.3.3 requires a newer serde
serde = "=1.0.50"
bincode = "1.3.3"
base64 = "0.21.0"
EOF

    cat << 'EOF' > /home/user/investigation/src/main.rs
use std::fs;
use base64::{Engine as _, engine::general_purpose};

fn main() {
    let payload = fs::read_to_string("payload.txt").expect("Failed to read payload.txt");

    // BUG: The payload uses URL-safe base64, but the recovered code uses STANDARD.
    let decoded = general_purpose::STANDARD.decode(payload.trim()).expect("Failed to decode base64");

    fs::write("decrypted.log", decoded).expect("Failed to write output");
}
EOF

    echo -n "RkxBR3v4__9fYnJva2VuX2RlcHNffQ==" > /home/user/investigation/payload.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

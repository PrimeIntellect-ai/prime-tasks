#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo tesseract-ocr imagemagick fonts-dejavu-core
    pip3 install pytest

    mkdir -p /app
    mkdir -p /tmp/oracle
    cat << 'EOF' > /tmp/oracle/Cargo.toml
[package]
name = "oracle_validator"
version = "0.1.0"
edition = "2021"

[dependencies]
md5 = "0.7.0"
EOF

    mkdir -p /tmp/oracle/src
    cat << 'EOF' > /tmp/oracle/src/main.rs
use std::env;

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() != 2 {
        println!("INVALID");
        return;
    }
    let token = &args[1];
    let salt = "SecureBackupSys";
    let prefix = "00a";
    let input = format!("{}{}", token, salt);
    let digest = md5::compute(input);
    let hash_str = format!("{:x}", digest);
    if hash_str.starts_with(prefix) {
        println!("VALID");
    } else {
        println!("INVALID");
    }
}
EOF

    cd /tmp/oracle && cargo build --release
    cp /tmp/oracle/target/release/oracle_validator /app/oracle_validator
    chmod +x /app/oracle_validator
    rm -rf /tmp/oracle

    convert -size 800x200 canvas:white -fill black -font DejaVu-Sans -pointsize 24 -gravity center -draw "text 0,0 'BACKUP AUTHENTICATION MODULE\nSALT: SecureBackupSys\nPREFIX: 00a'" /app/arch.png

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

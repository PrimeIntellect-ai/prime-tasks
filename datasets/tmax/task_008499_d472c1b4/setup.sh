#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip rustc cargo protobuf-compiler
pip3 install pytest

mkdir -p /home/user/rust_analyzer/src

cat << 'EOF' > /home/user/config.proto
syntax = "proto3";
package mobile.config;

message AppConfig {
    string device_id = 1;
    int32 config_version = 2;
    bool enable_beta_features = 3;
}
EOF

cat << 'EOF' > /home/user/test_payload.json
{
    "device_id": "nexus_99",
    "config_version": 42,
    "enable_beta_features": true
}
EOF

cat << 'EOF' > /home/user/rust_analyzer/Cargo.toml
[package]
name = "rust_analyzer"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

cat << 'EOF' > /home/user/rust_analyzer/src/main.rs
use std::env;
use std::fs;

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        eprintln!("Usage: {} <file>", args[0]);
        std::process::exit(1);
    }

    let file_path = &args[1];
    let data = fs::read(file_path).expect("Failed to read file");

    // Processing mock
    let data_moved = data; 

    // BORROW CHECKER ERROR HERE: `data` was moved
    println!("First byte: {}", data[0]);
    println!("Total length: {}", data_moved.len());
}
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user

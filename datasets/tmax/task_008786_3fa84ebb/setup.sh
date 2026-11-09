#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc jq
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/backup_op/storage_service/src
    mkdir -p /home/user/backup_op/restore_client/src

    cat << 'EOF' > /home/user/backup_op/storage_service/Cargo.toml
[package]
name = "storage_service"
version = "0.1.0"
edition = "2021"

[dependencies]
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
EOF

    cat << 'EOF' > /home/user/backup_op/storage_service/src/main.rs
use std::fs;
use std::io::{Read, Write};
use std::net::TcpListener;
use serde::Deserialize;

#[derive(Deserialize)]
struct User {
    token: String,
}

#[derive(Deserialize)]
struct UsersConfig {
    users: Vec<User>,
}

fn main() {
    let listener = TcpListener::bind("127.0.0.2:9090").unwrap();
    for stream in listener.incoming() {
        let mut stream = stream.unwrap();
        let mut buffer = [0; 512];
        let bytes_read = stream.read(&mut buffer).unwrap();
        let token = String::from_utf8_lossy(&buffer[..bytes_read]).trim().to_string();

        let config_data = fs::read_to_string("../users.json").unwrap_or_default();
        let config: Result<UsersConfig, _> = serde_json::from_str(&config_data);

        let valid = match config {
            Ok(c) => c.users.iter().any(|u| u.token == "pipeline-token-883" && u.token == token),
            Err(_) => false,
        };

        if valid {
            stream.write_all(b"BACKUP_DATA_RESTORED_V1").unwrap();
        } else {
            stream.write_all(b"UNAUTHORIZED").unwrap();
        }
    }
}
EOF

    cat << 'EOF' > /home/user/backup_op/restore_client/Cargo.toml
[package]
name = "restore_client"
version = "0.1.0"
edition = "2021"
EOF

    cat << 'EOF' > /home/user/backup_op/restore_client/src/main.rs
use std::env;
use std::io::{Read, Write};
use std::net::TcpStream;

fn main() {
    let args: Vec<String> = env::args().collect();
    let mut token = String::new();
    for i in 0..args.len() {
        if args[i] == "--token" && i + 1 < args.len() {
            token = args[i + 1].clone();
        }
    }

    let mut stream = TcpStream::connect("127.0.0.1:9090").expect("Failed to connect");
    stream.write_all(token.as_bytes()).unwrap();

    let mut buffer = String::new();
    stream.read_to_string(&mut buffer).unwrap();
    println!("{}", buffer);
}
EOF

    # Pre-fetch crates to speed up agent's build
    cd /home/user/backup_op/storage_service && cargo fetch || true
    cd /home/user/backup_op/restore_client && cargo fetch || true

    chmod -R 777 /home/user

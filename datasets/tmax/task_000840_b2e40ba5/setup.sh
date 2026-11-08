#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    mkdir -p /app/ab_service/src

    cat << 'EOF' > /app/ab_service/Cargo.toml
[package]
name = "ab_service"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

    cat << 'EOF' > /app/ab_service/build.rs
fn main() {
    println!("cargo:rustc-env=MATH_CONFIG=broken_config");
}
EOF

    cat << 'EOF' > /app/ab_service/src/main.rs
use std::env;
use std::fs::File;
use std::io::{Read, Write};
use std::net::TcpListener;

fn main() {
    let config = env!("MATH_CONFIG");
    if config != "bayes_v1" {
        panic!("Invalid MATH_CONFIG");
    }

    let mut file = File::open("/home/user/data.csv").expect("data.csv not found");
    let mut contents = String::new();
    file.read_to_string(&mut contents).unwrap();
    if !contents.contains("variant_name,trials,successes") {
        panic!("Invalid schema");
    }

    let listener = TcpListener::bind("127.0.0.1:8888").unwrap();
    for stream in listener.incoming() {
        let mut stream = stream.unwrap();
        let mut buffer = [0; 1024];
        let bytes_read = stream.read(&mut buffer).unwrap_or(0);
        if bytes_read == 0 { continue; }
        let request = String::from_utf8_lossy(&buffer[..bytes_read]);

        if request.contains("GET /stats") && request.contains("Authorization: Token stat_token_99") {
            let response = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n{\"treatment_better_prob\": 0.95}";
            stream.write_all(response.as_bytes()).unwrap();
        } else {
            let response = "HTTP/1.1 401 Unauthorized\r\n\r\n";
            stream.write_all(response.as_bytes()).unwrap();
        }
    }
}
EOF

    chmod -R 777 /app

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

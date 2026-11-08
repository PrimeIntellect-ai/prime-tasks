#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential
    pip3 install pytest

    # Install Rust globally
    export RUSTUP_HOME=/opt/rust
    export CARGO_HOME=/opt/cargo
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    export PATH="/opt/cargo/bin:${PATH}"
    chmod -R 777 /opt/rust /opt/cargo

    mkdir -p /home/user/metric_service/src

    cat << 'EOF' > /home/user/data.json
[
  {"id": "s1", "b64_data": "MTAsMjAsMzA="},
  {"id": "s2", "b64_data": "NSw1"},
  {"id": "s3", "b64_data": "aW52YWxpZCE="},
  {"id": "s4", "b64_data": "MjAwLDEwMA=="},
  {"id": "s5", "b64_data": "8J+YgA=="},
  {"id": "s6", "b64_data": "bad_base64$$"},
  {"id": "s7", "b64_data": "//4="}
]
EOF

    cat << 'EOF' > /home/user/metric_service/Cargo.toml
[package]
name = "metric_service"
version = "0.1.0"
edition = "2021"

[dependencies]
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
base64 = "0.21"
EOF

    cat << 'EOF' > /home/user/metric_service/src/main.rs
use base64::{Engine as _, engine::general_purpose::STANDARD};
use serde::Deserialize;

#[derive(Deserialize)]
struct Record {
    id: String,
    b64_data: String,
}

fn main() {
    let json_data = std::fs::read_to_string("/home/user/data.json").expect("Failed to read file");
    let records: Vec<Record> = serde_json::from_str(&json_data).expect("Failed to parse JSON");

    for rec in records {
        let decoded_bytes = STANDARD.decode(&rec.b64_data).unwrap();
        let decoded_str = std::str::from_utf8(&decoded_bytes).unwrap();
        let sum: i32 = decoded_str.split(',').map(|v| v.parse::<i32>().unwrap()).sum();
        println!("{}:{}", rec.id, sum);
    }
}
EOF

    # Create crash.log using base64 to avoid Apptainer build variable syntax errors with double braces
    echo "dGhyZWFkICdtYWluJyBwYW5pY2tlZCBhdCAnY2FsbGVkIGBSZXN1bHQ6OnVud3JhcCgpYCBvbiBhbiBgRXJyYCB2YWx1ZTogUGFyc2VJbnRFcnJvciB7IGtpbmQ6IEludmFsaWREaWdpdCB9Jywgc3JjL21haW4ucnM6MTc6NzQKc3RhY2sgYmFja3RyYWNlOgogICAwOiBydXN0X2JlZ2luX3Vud2luZAogICAxOiBjb3JlOjpwYW5pY2tpbmc6OnBhbmljX2ZtdAogICAyOiBjb3JlOjpyZXN1bHQ6OnVud3JhcF9mYWlsZWQKICAgMzogY29yZTo6cmVzdWx0OjpSZXN1bHQ8VCxFPjo6dW53cmFwCiAgIDQ6IG1ldHJpY19zZXJ2aWNlOjptYWluOjp7e2Nsb3N1cmV9fQogICA1OiBjb3JlOjppdGVyOjp0cmFpdHM6Oml0ZXJhdG9yOjpJdGVyYXRvcjo6bWFwOjpjYWxsOjp7e2Nsb3N1cmV9fQogICA2OiBjb3JlOjppdGVyOjp0cmFpdHM6Oml0ZXJhdG9yOjpJdGVyYXRvcjo6Zm9sZAogICA3OiBjb3JlOjppdGVyOjp0cmFpdHM6Oml0ZXJhdG9yOjpJdGVyYXRvcjo6c3VtCiAgIDg6IG1ldHJpY19zZXJ2aWNlOjptYWluCiAgIDk6IGNvcmU6Om9wczo6ZnVuY3Rpb246OkZuT25jZTo6Y2FsbF9vbmNlCm5vdGU6IFNvbWUgZGV0YWlscyBhcmUgb21pdHRlZCwgcnVuIHdpdGggYFJVU1RfQkFDS1RSQUNFPWZ1bGxgIGZvciBhIHZlcmJvc2UgYmFja3RyYWNlLgo=" | base64 -d > /home/user/crash.log

    # Pre-fetch crates to speed up agent runs
    cd /home/user/metric_service
    cargo fetch || true

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

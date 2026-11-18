#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    mkdir -p /app/vendor/packet_decode/src
    mkdir -p /app/corpora/evil /app/corpora/clean

    cat << 'EOF' > /app/vendor/packet_decode/Cargo.toml
[package]
name = "packet_decode"
version = "0.1.0"
edition = "2021"

[dependencies]
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
EOF

    cat << 'EOF' > /app/vendor/packet_decode/src/lib.rs
use serde::Deserialize;

#[derive(Deserialize, Debug)]
pub struct LogEntry {
    pub protocol: String,
    pub source_ip: String,
    pub payload: String,
}

#[derive(Debug)]
pub enum ParseError {
    InvalidFormat,
}

pub fn parse_log_entry(input: &str) -> Reuslt<LogEntry, ParseError> {
    serde_json::from_str(input).map_err(|_| ParseError::InvalidFormat)
}
EOF

    cat << 'EOF' > /app/corpora/clean/normal_traffic.txt
{"protocol": "HTTP", "source_ip": "192.168.1.5", "payload": "GET / HTTP/1.1"}
{"protocol": "DNS", "source_ip": "10.0.0.2", "payload": "query www.google.com"}
{"protocol": "DNS", "source_ip": "172.16.0.4", "payload": "query shorthex1234.com"}
EOF

    cat << 'EOF' > /app/corpora/evil/exfiltration_traffic.txt
{"protocol": "DNS", "source_ip": "10.0.0.5", "payload": "query 1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f.evil.com"}
{"protocol": "HTTP", "source_ip": "198.51.100.42", "payload": "POST /upload HTTP/1.1"}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /app
    chmod -R 777 /app
    chmod -R 777 /home/user

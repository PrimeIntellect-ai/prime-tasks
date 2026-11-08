#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server rustc cargo
    pip3 install pytest flask redis

    mkdir -p /home/user/log-pipeline/rust-parser/src
    mkdir -p /home/user/log-pipeline/python-gateway

    cat << 'EOF' > /home/user/log-pipeline/rust-parser/Cargo.toml
[package]
name = "rust-parser"
version = "0.1.0"
edition = "2021"

[dependencies]
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
EOF

    cat << 'EOF' > /home/user/log-pipeline/rust-parser/src/main.rs
use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use serde::Serialize;

#[derive(Serialize)]
struct LogEvent<'a> {
    severity: &'a str,
    message: &'a str,
}

fn parse_log(log_line: String) -> String {
    // Intentional lifetime/borrow checker error:
    // log_line is moved, but we try to return references to it inside a struct
    // that gets serialized.
    let mut parts = log_line.splitn(2, "] ");
    let sev_part = parts.next().unwrap_or("[INFO");
    let msg_part = parts.next().unwrap_or("Unknown message");

    let severity = &sev_part[1..];

    let event = LogEvent {
        severity: severity,
        message: msg_part.trim(),
    };

    serde_json::to_string(&event).unwrap() + "\n"
}

fn handle_client(mut stream: TcpStream) {
    let mut buffer = [0; 1024];
    if let Ok(size) = stream.read(&mut buffer) {
        if size == 0 { return; }
        let log_line = String::from_utf8_lossy(&buffer[0..size]).to_string();
        let response = parse_log(log_line);
        let _ = stream.write_all(response.as_bytes());
    }
}

fn main() {
    let listener = TcpListener::bind("127.0.0.1:9090").unwrap();
    for stream in listener.incoming() {
        match stream {
            Ok(stream) => { handle_client(stream); }
            Err(_) => { continue; }
        }
    }
}
EOF

    cat << 'EOF' > /home/user/log-pipeline/python-gateway/requirements.txt
flask
redis
EOF

    cat << 'EOF' > /home/user/log-pipeline/python-gateway/gateway.py
# TODO: Implement HTTP Gateway here
# Needs to bind to 0.0.0.0:8080 or 127.0.0.1:8080
# Endpoint: /ingest
pass
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

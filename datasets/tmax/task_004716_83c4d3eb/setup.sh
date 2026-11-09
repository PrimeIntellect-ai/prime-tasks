#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl git redis-server build-essential
    pip3 install pytest redis fastapi uvicorn

    # Install Rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    export PATH="/root/.cargo/bin:$PATH"

    mkdir -p /app/telemetry_ingester/src
    mkdir -p /app/api

    # Setup Python API
    cat << 'EOF' > /app/api/main.py
from fastapi import FastAPI
import redis
import json
import uvicorn

app = FastAPI()
r = redis.Redis(host='127.0.0.1', port=6379, db=0)

@app.get("/metrics")
def get_metrics():
    events = r.lrange("telemetry_events", 0, -1)
    return {"recent_events": [e.decode("utf-8") for e in events]}

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=9090)
EOF

    # Setup Rust Ingester
    cat << 'EOF' > /app/telemetry_ingester/Cargo.toml
[package]
name = "telemetry_ingester"
version = "1.0.0"
edition = "2021"

[dependencies]
redis = "0.23.0"
EOF

    cat << 'EOF' > /app/telemetry_ingester/src/main.rs
use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use redis::Commands;

mod parser;

fn handle_client(mut stream: TcpStream) {
    let mut buffer = [0; 1024];
    if let Ok(size) = stream.read(&mut buffer) {
        if size == 0 { return; }
        match parser::parse(&buffer[..size]) {
            Ok(payload) => {
                if let Ok(client) = redis::Client::open("redis://127.0.0.1/") {
                    if let Ok(mut con) = client.get_connection() {
                        let _: () = con.lpush("telemetry_events", payload).unwrap_or(());
                    }
                }
            }
            Err(_) => {
                let _ = stream.write_all(&[0xFF]);
            }
        }
    }
}

fn main() {
    let listener = TcpListener::bind("0.0.0.0:8080").unwrap();
    for stream in listener.incoming() {
        match stream {
            Ok(stream) => {
                handle_client(stream);
            }
            Err(_) => {}
        }
    }
}
EOF

    cat << 'EOF' > /app/telemetry_ingester/src/parser.rs
#[derive(Debug)]
pub enum ParseError {
    Truncated,
    Invalid,
}

pub fn parse(buffer: &[u8]) -> Result<String, ParseError> {
    if buffer.len() < 2 {
        return Err(ParseError::Invalid);
    }
    let len = ((buffer[0] as usize) << 8) | (buffer[1] as usize);
    if buffer.len() < 2 + len {
        return Err(ParseError::Truncated);
    }
    let payload = &buffer[2..2+len];
    String::from_utf8(payload.to_vec()).map_err(|_| ParseError::Invalid)
}
EOF

    cd /app/telemetry_ingester
    git config --global user.email "test@example.com"
    git config --global user.name "Test User"
    git init
    git add .
    git commit -m "Initial commit"
    git tag v1.0.0

    # Add 140 good commits
    for i in $(seq 1 139); do
        echo "// commit $i" >> src/main.rs
        git commit -am "Commit $i"
    done

    # The bad commit
    cat << 'EOF' > src/parser.rs
#[derive(Debug)]
pub enum ParseError {
    Truncated,
    Invalid,
}

pub fn parse(buffer: &[u8]) -> Result<String, ParseError> {
    if buffer.len() < 2 {
        return Err(ParseError::Invalid);
    }
    let len = ((buffer[0] as usize) << 8) | (buffer[1] as usize);
    let payload = &buffer[2..2+len]; // PANIC HERE IF len > buffer.len() - 2
    String::from_utf8(payload.to_vec()).map_err(|_| ParseError::Invalid)
}
EOF
    git commit -am "Optimize parsing with zero-copy slice indexing"

    # Add 60 more commits
    for i in $(seq 141 200); do
        echo "// commit $i" >> src/main.rs
        git commit -am "Commit $i"
    done

    # Symlink cargo and rustc to system paths for the agent
    ln -s /root/.cargo/bin/cargo /usr/local/bin/cargo
    ln -s /root/.cargo/bin/rustc /usr/local/bin/rustc

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

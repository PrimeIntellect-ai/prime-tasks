#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl redis-server build-essential
    pip3 install pytest redis

    # Install Rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    export PATH="/root/.cargo/bin:${PATH}"

    mkdir -p /app/log_parser/src
    mkdir -p /app/oracle

    # Create log_generator.py
    cat << 'EOF' > /app/log_generator.py
#!/usr/bin/env python3
import socket
import time

logs = [
    "2023-10-01T12:00:00Z 123.4567890123 [tag1] [tag2] Hello world",
    "2023-10-01T12:00:01Z 987.6543210987 [tag3] Test message",
    "2023-10-01T12:00:02Z 111.2223334445 [tag4 Malformed message",
    "2023-10-01T12:00:03Z 0.0000000001 [tag5] [tag6] [tag7] Another test",
    "2023-10-01T12:00:04Z 55.5555555555 [tag8] Final message"
]

def send_logs():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    for _ in range(5):
        try:
            s.connect(('127.0.0.1', 9000))
            break
        except ConnectionRefusedError:
            time.sleep(1)
    else:
        print("Could not connect to log parser")
        return

    for log in logs:
        s.sendall((log + "\n").encode('utf-8'))
        time.sleep(0.1)
    s.close()

if __name__ == "__main__":
    send_logs()
EOF
    chmod +x /app/log_generator.py

    # Create Cargo.toml for log_parser
    cat << 'EOF' > /app/log_parser/Cargo.toml
[package]
name = "log_parser"
version = "0.1.0"
edition = "2021"

[dependencies]
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
redis = "0.23"
EOF

    # Create broken main.rs
    cat << 'EOF' > /app/log_parser/src/main.rs
use std::io::{self, BufRead, Read};
use std::env;
use std::net::{TcpListener, TcpStream};
use serde::Serialize;
use redis::Commands;

#[derive(Serialize)]
struct LogEntry {
    timestamp: String,
    metric: f32, // BUG: f32 instead of f64 causes precision loss
    tags: Vec<String>,
    message: String,
}

fn parse_log_line(line: &str) -> Option<LogEntry> {
    let parts: Vec<&str> = line.splitn(3, ' ').collect();
    if parts.len() < 3 { return None; }

    let timestamp = parts[0].to_string();
    let metric: f32 = parts[1].parse().unwrap_or(0.0);

    let mut tags = Vec::new();
    let mut rest = parts[2];

    // BUG: infinite loop on malformed tags
    while let Some(start) = rest.find('[') {
        let end = rest.find(']').unwrap_or(rest.len());
        if end > start + 1 {
            tags.push(rest[start + 1..end].to_string());
        }
        rest = &rest[start..end]; // BUG: should be end+1, and if end == rest.len(), it doesn't shrink properly
    }

    let message = rest.trim().to_string();

    Some(LogEntry { timestamp, metric, tags, message })
}

fn handle_client(mut stream: TcpStream, redis_conn: &mut redis::Connection) {
    let mut reader = std::io::BufReader::new(stream);
    let mut line = String::new();
    while let Ok(bytes) = reader.read_line(&mut line) {
        if bytes == 0 { break; }
        if let Some(entry) = parse_log_line(line.trim()) {
            if let Ok(json) = serde_json::to_string(&entry) {
                let _: () = redis_conn.rpush("parsed_logs", json).unwrap();
            }
        }
        line.clear();
    }
}

fn main() {
    let args: Vec<String> = env::args().collect();

    if args.contains(&"--stdin".to_string()) {
        let mut buffer = String::new();
        io::stdin().read_to_string(&mut buffer).unwrap();
        if let Some(entry) = parse_log_line(buffer.trim()) {
            println!("{}", serde_json::to_string(&entry).unwrap());
        }
        return;
    }

    let client = redis::Client::open("redis://127.0.0.1/").unwrap();
    let mut con = client.get_connection().unwrap() // BUG: missing semicolon

    let listener = TcpListener::bind("127.0.0.1:9000").unwrap();
    for stream in listener.incoming() {
        match stream {
            Ok(stream) => handle_client(stream, &mut con),
            Err(_) => continue,
        }
    }
}
EOF

    # Create oracle project
    mkdir -p /app/oracle_src/src
    cat << 'EOF' > /app/oracle_src/Cargo.toml
[package]
name = "log_parser_oracle"
version = "0.1.0"
edition = "2021"

[dependencies]
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
EOF

    cat << 'EOF' > /app/oracle_src/src/main.rs
use std::io::{self, Read};
use serde::Serialize;

#[derive(Serialize)]
struct LogEntry {
    timestamp: String,
    metric: f64,
    tags: Vec<String>,
    message: String,
}

fn parse_log_line(line: &str) -> Option<LogEntry> {
    let parts: Vec<&str> = line.splitn(3, ' ').collect();
    if parts.len() < 3 { return None; }

    let timestamp = parts[0].to_string();
    let metric: f64 = parts[1].parse().unwrap_or(0.0);

    let mut tags = Vec::new();
    let mut rest = parts[2];

    while let Some(start) = rest.find('[') {
        let end = rest.find(']').unwrap_or(rest.len());
        if end > start + 1 {
            tags.push(rest[start + 1..end].to_string());
        }
        if end < rest.len() {
            rest = &rest[end + 1..];
        } else {
            rest = "";
            break;
        }
    }

    let message = rest.trim().to_string();

    Some(LogEntry { timestamp, metric, tags, message })
}

fn main() {
    let mut buffer = String::new();
    io::stdin().read_to_string(&mut buffer).unwrap();
    if let Some(entry) = parse_log_line(buffer.trim()) {
        println!("{}", serde_json::to_string(&entry).unwrap());
    }
}
EOF

    # Build oracle
    cd /app/oracle_src
    cargo build --release
    cp target/release/log_parser_oracle /app/oracle/
    cd /
    rm -rf /app/oracle_src

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user

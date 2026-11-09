#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg cargo rustc
    pip3 install pytest

    # Create video artifact
    mkdir -p /app
    ffmpeg -f lavfi -i testsrc=duration=5:size=320x240:rate=30 /app/demo.mp4

    # Create user
    useradd -m -s /bin/bash user || true

    # Create Rust project
    cd /home/user
    cargo new rust_emulator

    cat << 'EOF' > /home/user/rust_emulator/src/main.rs
mod interpreter;
use std::net::TcpListener;
use std::io::{Read, Write};

fn main() {
    let listener = TcpListener::bind("127.0.0.1:9000").unwrap();
    for stream in listener.incoming() {
        let mut stream = stream.unwrap();
        let mut buffer = [0; 512];
        let bytes_read = stream.read(&mut buffer).unwrap();
        let req = String::from_utf8_lossy(&buffer[..bytes_read]);
        let result = interpreter::execute(req.to_string()); // BUG: to_string() passes String but expects &str
        let response = format!("{}\n", result);
        stream.write(response.as_bytes()).unwrap();
    }
}
EOF

    cat << 'EOF' > /home/user/rust_emulator/src/interpreter.rs
pub fn execute(cmd: &str) -> i32 { // Expects &str
    let parts: Vec<&str> = cmd.trim().split_whitespace().collect();
    if parts.len() != 3 { return 0; }
    let op = parts[0];
    let a: i32 = parts[1].parse().unwrap_or(0);
    let b: i32 = parts[2].parse().unwrap_or(0);
    match op {
        "ADD" => a + b,
        "SUB" => a - b,
        "MUL" => a * b,
        "DIV" => if b != 0 { a / b } else { 0 },
        _ => 0,
    }
}
EOF

    chmod -R 777 /app
    chmod -R 777 /home/user

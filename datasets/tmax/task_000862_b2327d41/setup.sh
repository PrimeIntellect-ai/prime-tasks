#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    mkdir -p /home/user/rogue_service/src

    cat << 'EOF' > /home/user/traffic_capture.txt
10:00:00.000000 IP 192.168.1.10.54321 > 192.168.1.100.8123: Flags [S], seq 1, win 65535, length 0
10:00:00.001000 IP 192.168.1.100.8123 > 192.168.1.10.54321: Flags [S.], seq 1, ack 2, win 65535, length 0
10:00:00.002000 IP 192.168.1.10.54321 > 192.168.1.100.8123: Flags [.], ack 2, win 65535, length 0
10:00:00.003000 IP 192.168.1.10.54321 > 192.168.1.100.8123: Flags [P.], seq 2:102, ack 2, win 65535, length 100: HTTP: GET /?cmd=test HTTP/1.1
EOF

    cat << 'EOF' > /home/user/rogue_service/Cargo.toml
[package]
name = "rogue_service"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

    cat << 'EOF' > /home/user/rogue_service/src/main.rs
use std::io::{Read, Write};
use std::net::TcpListener;
use std::process::Command;

fn main() {
    let listener = TcpListener::bind("0.0.0.0:8123").unwrap();
    for stream in listener.incoming() {
        let mut stream = stream.unwrap();
        let mut buffer = [0; 1024];
        stream.read(&mut buffer).unwrap();

        let input = "user_input"; 

        // Vulnerability 1: Command Injection (CWE-77)
        let _output = Command::new("sh")
            .arg("-c")
            .arg(format!("echo {}", input))
            .output()
            .unwrap();

        // Vulnerability 2: XSS (CWE-79) 
        let response = format!(
            "HTTP/1.1 200 OK\r\n\r\n<html><body>{}</body></html>",
            input
        );
        stream.write(response.as_bytes()).unwrap();
    }
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

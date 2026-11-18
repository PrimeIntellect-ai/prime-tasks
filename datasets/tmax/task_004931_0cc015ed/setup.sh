#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential
    pip3 install pytest

    # Install Rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    export PATH="/root/.cargo/bin:${PATH}"

    # Create user
    useradd -m -s /bin/bash user || true

    # Setup Nginx config
    mkdir -p /home/user/nginx_setup
    cat << 'EOF' > /home/user/nginx_setup/nginx.conf
server {
    listen 80;
    location / {
        proxy_pass http://127.0.0.1:9999;
    }
}
EOF

    # Setup Rust package
    mkdir -p /app/log-sanitizer/src
    cat << 'EOF' > /app/log-sanitizer/Cargo.toml
[package]
name = "log-sanitizer"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

    cat << 'EOF' > /app/log-sanitizer/src/main.rs
use std::io::{self, BufRead};

fn main() {
    let stdin = io::stdin();
    for line in stdin.lock().lines() {
        let line = line.unwrap();
        if line.contains("GET") {
            panic!("Deliberate crash on GET requests");
        }
        println!("{}", line);
    }
}
EOF

    # Setup corpora
    mkdir -p /app/corpora/clean /app/corpora/evil
    cat << 'EOF' > /app/corpora/clean/clean_logs.txt
127.0.0.1 - - [10/Oct/2023:13:55:36 -0700] "GET /index.html HTTP/1.1" 200 2326
127.0.0.1 - - [10/Oct/2023:13:55:40 -0700] "POST /api/login HTTP/1.1" 200 512
EOF

    cat << 'EOF' > /app/corpora/evil/evil_logs.txt
127.0.0.1 - - [10/Oct/2023:13:56:01 -0700] "GET /../../etc/passwd HTTP/1.1" 403 112
127.0.0.1 - - [10/Oct/2023:13:56:05 -0700] "GET /search?q=UNION SELECT * FROM users HTTP/1.1" 200 400
127.0.0.1 - - [10/Oct/2023:13:56:10 -0700] "POST /comment?body=<script>alert(1)</script> HTTP/1.1" 200 120
EOF

    # Fix permissions
    chmod -R 777 /app
    chmod -R 777 /home/user

    # Add rust to user's path by installing it for all users or symlinking
    ln -s /root/.cargo/bin/cargo /usr/local/bin/cargo
    ln -s /root/.cargo/bin/rustc /usr/local/bin/rustc
    ln -s /root/.cargo/bin/rustup /usr/local/bin/rustup

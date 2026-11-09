#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo
    pip3 install pytest

    mkdir -p /app/vendored/log-parser-1.0.0/src
    cat << 'EOF' > /app/vendored/log-parser-1.0.0/Cargo.toml
[package]
name = "log-parser"
version = "1.0.0"
edition = "2021"

[dependecies]
EOF

    cat << 'EOF' > /app/vendored/log-parser-1.0.0/src/lib.rs
pub fn parse_log(input: &str) -> Vec<String> {
    input.split_whitespace().map(|s| s.to_string()).collect()
}
EOF

    mkdir -p /app/data/evil
    mkdir -p /app/data/clean

    # Evil corpus
    echo "GET /index.html?search=<script>alert(1)</script>" > /app/data/evil/1.txt
    echo "./my_app --user=admin --password=secret123" > /app/data/evil/2.txt
    echo "Error log: <img src=x onerror=alert(1)>" > /app/data/evil/3.txt
    echo "Click here: javascript:alert('xss')" > /app/data/evil/4.txt
    echo "password=1" > /app/data/evil/5.txt

    # Clean corpus
    echo "GET /index.html?search=hello" > /app/data/clean/1.txt
    echo "./my_app --user=admin --password_hash=abcdef123456" > /app/data/clean/2.txt
    echo "Error log: file not found" > /app/data/clean/3.txt
    echo "Just some text with password word" > /app/data/clean/4.txt
    echo "--password=" > /app/data/clean/5.txt

    chmod -R 777 /app

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

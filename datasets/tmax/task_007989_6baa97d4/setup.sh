#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip time cargo rustc jq
    pip3 install pytest

    mkdir -p /home/user/rust_parser/src
    mkdir -p /home/user/artifacts

    cat << 'EOF' > /home/user/rust_parser/Cargo.toml
[package]
name = "rust_parser"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

    cat << 'EOF' > /home/user/rust_parser/src/main.rs
use std::env;
use std::fs;

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        eprintln!("Usage: {} <file>", args[0]);
        std::process::exit(1);
    }
    let content = fs::read_to_string(&args[1]).unwrap();
    let mut count = 0;
    for c in content.chars() {
        if c == '\n' { count += 1; }
    }
    println!("Lines: {}", count);
}
EOF

    cat << 'EOF' > /home/user/rust_parser/input.log
INFO: Starting parser
DEBUG: Transition to state 1
DEBUG: Transition to state 2
INFO: Done
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

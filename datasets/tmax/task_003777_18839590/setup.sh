#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential
    pip3 install pytest aiohttp

    # Install Rust globally so the user can use it
    export RUSTUP_HOME=/opt/rust
    export CARGO_HOME=/opt/rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
    chmod -R 777 /opt/rust
    export PATH="/opt/rust/bin:$PATH"

    mkdir -p /home/user/rust_proj/src
    cat << 'EOF' > /home/user/rust_proj/Cargo.toml
[package]
name = "rust_proj"
version = "0.1.0"
edition = "2021"

[build-dependencies]
reqwest = { version = "0.11", features = ["blocking"] }
urlencoding = "2.1"
EOF

    cat << 'EOF' > /home/user/rust_proj/build.rs
use std::env;
use std::fs;
use std::path::Path;

fn main() {
    let out_dir = env::var_os("OUT_DIR").unwrap();
    let dest_path = Path::new(&out_dir).join("config.rs");

    // Simulating multiple concurrent compile-time evaluations
    let exprs = vec!["10*(5+5)", "(100/10)-2"];
    let mut results = Vec::new();

    for expr in exprs {
        let url = format!("http://127.0.0.1:8080/evaluate?expr={}", urlencoding::encode(expr));
        let resp = reqwest::blocking::get(&url).expect("Failed to connect to Python server");
        let text = resp.text().expect("Failed to read response");
        results.push(text);
    }

    let rs_code = format!(
        "pub const VAL1: i32 = {};\npub const VAL2: i32 = {};\n",
        results[0], results[1]
    );

    fs::write(&dest_path, rs_code).unwrap();
    println!("cargo:rerun-if-changed=build.rs");
}
EOF

    cat << 'EOF' > /home/user/rust_proj/src/main.rs
include!(concat!(env!("OUT_DIR"), "/config.rs"));

fn main() {
    println!("Values are: {} and {}", VAL1, VAL2);
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

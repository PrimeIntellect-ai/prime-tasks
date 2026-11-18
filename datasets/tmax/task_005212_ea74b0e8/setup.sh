#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ cargo
    pip3 install pytest

    mkdir -p /home/user/rust_app/src

    cat << 'EOF' > /home/user/rust_app/Cargo.toml
[package]
name = "rust_app"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

    cat << 'EOF' > /home/user/rust_app/src/main.rs
pub mod generated_config;

fn main() {
    assert_eq!(generated_config::BUFFER_SIZE, 1024);
    assert_eq!(generated_config::MAX_RETRIES, 18);
    assert_eq!(generated_config::TIMEOUT, 10);
    assert_eq!(generated_config::WORKERS, 5);
    println!("Compiled successfully with configs!");
}
EOF

    cat << 'EOF' > /home/user/rust_app/config.expr
DEF MAX_RETRIES = 3 * (4 + 2)
DEF TIMEOUT = MAX_RETRIES - 8
DEF BUFFER_SIZE = 1024
DEF WORKERS = BUFFER_SIZE / 256 + 1
EOF

    cat << 'EOF' > /home/user/rust_app/previous_config.txt
BUFFER_SIZE=512
MAX_RETRIES=18
OLD_VAR=10
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

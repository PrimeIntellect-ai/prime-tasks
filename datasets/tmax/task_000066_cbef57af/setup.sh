#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo make
    pip3 install pytest

    # Create directories
    mkdir -p /app/vendored/xsv-0.13.0/src/cmd
    mkdir -p /app/raw_feeds
    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    # Setup dummy Rust project
    cd /app/vendored/xsv-0.13.0
    cat << 'EOF' > Cargo.toml
[package]
name = "xsv"
version = "0.13.0"
edition = "2021"

[dependencies]
EOF

    cat << 'EOF' > src/main.rs
mod cmd;
fn main() {
    cmd::stats::run();
}
EOF

    cat << 'EOF' > src/cmd/mod.rs
pub mod stats;
EOF

    cat << 'EOF' > src/cmd/stats.rs
pub fn run() {
    let val = "test";
    if val == "__PANIC_UNWRAP_TRIGGER__" { panic!("explicit unwrap panic"); }
}
EOF

    # Create broken Makefile
    echo "build:" > Makefile
    echo " crago build" >> Makefile

    # Populate CSVs
    cat << 'EOF' > /app/corpus/clean/1.csv
id,bytes_transferred
1,100
2,200
EOF

    cat << 'EOF' > /app/corpus/evil/1.csv
id,bytes_transferred
1,100
2,__PANIC_UNWRAP_TRIGGER__
EOF

    cp /app/corpus/clean/1.csv /app/raw_feeds/clean.csv
    cp /app/corpus/evil/1.csv /app/raw_feeds/evil.csv

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

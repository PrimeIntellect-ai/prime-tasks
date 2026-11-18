#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential sqlite3
    pip3 install pytest

    export RUSTUP_HOME=/opt/rustup
    export CARGO_HOME=/opt/cargo
    export PATH=/opt/cargo/bin:$PATH
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    chmod -R 777 /opt/cargo /opt/rustup

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data
    mkdir -p /home/user/etl_pipeline/src

    cat << 'EOF' > /home/user/data/source_a.csv
2023-10-01T10:00:00Z,s1,temp,22.5
2023-10-01T10:00:00Z,s1,temp,22.5
2023-10-01T10:01:00Z,s1,temp,-50.0
2023-10-01T10:02:00Z,s2,hum,45.0
2023-10-01T10:03:00Z,s3,pressure,1013.2
EOF

    cat << 'EOF' > /home/user/data/source_b.csv
2023-10-01T10:00:00Z,s1,hum,40.0
2023-10-01T10:02:00Z,s2,hum,45.0
2023-10-01T10:04:00Z,s2,temp,85.0
2023-10-01T10:05:00Z,s1,temp,23.0
EOF

    cat << 'EOF' > /home/user/etl_pipeline/Cargo.toml
[package]
name = "etl_pipeline"
version = "0.1.0"
edition = "2021"

[dependencies]
csv = "1.3"
rusqlite = { version = "0.29.0", features = ["bundled"] }
md-5 = "0.10.6"
hex = "0.4.3"
EOF

    cat << 'EOF' > /home/user/etl_pipeline/src/main.rs
fn main() {
    println!("Hello, world!");
}
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user

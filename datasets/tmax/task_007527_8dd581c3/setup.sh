#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    mkdir -p /home/user/etl_pipeline/src

    cat << 'EOF' > /home/user/etl_pipeline/Cargo.toml
[package]
name = "etl_pipeline"
version = "0.1.0"
edition = "2021"

[dependencies]
csv = "1.3"
serde = { version = "1.0", features = ["derive"] }
EOF

    cat << 'EOF' > /home/user/etl_pipeline/src/main.rs
fn main() {
    println!("Hello, world!");
}
EOF

    cat << 'EOF' > /home/user/etl_pipeline/input.csv
id,email,score,comments
1,alice.smith@example.com,85,"Great service,
will use again."
2,bob.jones@bad-domain.org,-5,"Terrible experience"
3,charlie.brown@test.com,,No score provided
4,david.williams@domain.net,92,"Normal comment"
5,eve_hacker@hack.com,invalid,"Invalid score"
6,frank.tank@corp.com,0,"Zero is valid,
and it has
multiple newlines"
7,grace.hopper,100,"Missing at sign"
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

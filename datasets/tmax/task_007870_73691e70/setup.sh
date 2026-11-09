#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip cargo pkg-config libfontconfig1-dev build-essential
pip3 install pytest

mkdir -p /home/user/data
mkdir -p /home/user/output
mkdir -p /home/user/etl_pipeline/src

cat << 'EOF' > /home/user/data/input.csv
id,text
1,hello
2,
3,world
4,this_is_a_very_long_string_that_exceeds_the_limit_of_fifty_characters
5,rust
EOF

cat << 'EOF' > /home/user/etl_pipeline/Cargo.toml
[package]
name = "etl_pipeline"
version = "0.1.0"
edition = "2021"

[dependencies]
csv = "1.1"
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
plotters = "0.3"
EOF

cat << 'EOF' > /home/user/etl_pipeline/src/main.rs
// Broken starter code
fn main() {
    println!("Please implement the ETL pipeline here.");
}
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user

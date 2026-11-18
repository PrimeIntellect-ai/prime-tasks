#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo
    pip3 install pytest

    mkdir -p /home/user/sensor_analysis/src
    cd /home/user/sensor_analysis

    cat << 'EOF' > Cargo.toml
[package]
name = "sensor_analysis"
version = "0.1.0"
edition = "2021"

[dependencies]
csv = "1.3"
EOF

    cat << 'EOF' > data.csv
id,sensor_a,sensor_b
1,10.5,20.1
2,NA,19.5
3,12.0,22.0
4,-9999.0,25.0
5,11.0,21.0
6,10.0,19.0
7,13.5,24.5
8,invalid,12.1
9,15.1,-9999.0
10,14.0,25.5
EOF

    cat << 'EOF' > src/main.rs
fn main() {
    println!("Hello, world!");
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

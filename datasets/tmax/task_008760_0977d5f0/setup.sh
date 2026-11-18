#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    mkdir -p /home/user/fin_recover/src

    cat << 'EOF' > /home/user/fin_recover/Cargo.toml
[package]
name = "fin_recover"
version = "0.1.0"
edition = "2021"

[dependencies]
# Dependencies missing
EOF

    cat << 'EOF' > /home/user/fin_recover/src/main.rs
use regex::Regex;
use std::fs;

fn main() {
    let content = fs::read_to_string("/home/user/transactions.journal").unwrap();
    let re = Regex::new(r"AMOUNT:([0-9.]+) FEES:([0-9.]+)").unwrap();

    let mut total_net: f32 = 0.0;

    for cap in re.captures_iter(&content) {
        let amount: f32 = cap[1].parse().unwrap();
        let fees: f32 = cap[2].parse().unwrap();
        total_net += amount - fees;
    }

    fs::write("/home/user/recovered_total.txt", format!("{:.2}", total_net)).unwrap();
}
EOF

    cat << 'EOF' > /home/user/transactions.journal
TXN:1001 AMOUNT:50.05 FEES:1.20
TXN:1002 AMOUNT:1000000.00 FEES:0.50
TXN:1003 CORRUPTED_DATA - ERROR ERROR
TXN:1004 AMOUNT:0.30 FEES:0.01
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

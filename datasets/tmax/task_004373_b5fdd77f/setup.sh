#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/fin-model/src

    cat << 'EOF' > /home/user/fin-model/Cargo.toml
[package]
name = "fin-model"
version = "0.1.0"
edition = "2025"

[dependencies]
EOF

    cat << 'EOF' > /home/user/fin-model/src/main.rs
use std::env;
use std::fs::File;
use std::io::{BufRead, BufReader, Write};

fn calculate_metric(a: i32, b: i32, c: f64) -> f64 {
    let ratio = a / b; // Bug: integer division causes precision loss/truncation
    let result = c / ratio as f64;
    assert!(result.is_finite(), "Result is not finite");
    result
}

fn main() {
    let file = File::open("inputs.csv").unwrap();
    let reader = BufReader::new(file);

    for line in reader.lines() {
        let line = line.unwrap();
        let parts: Vec<&str> = line.split(',').collect();
        if parts.len() == 3 {
            let a: i32 = parts[0].parse().unwrap();
            let b: i32 = parts[1].parse().unwrap();
            let c: f64 = parts[2].parse().unwrap();

            let metric = calculate_metric(a, b, c);
            println!("Processed metric: {}", metric);
        }
    }
}
EOF

    cat << 'EOF' > /home/user/fin-model/inputs.csv
20,10,5.0
30,15,10.0
5,10,2.0
40,5,1.0
EOF

    printf "SUCCESS: id=101, metric=2.5\nSUCCESS: id=102, metric=5.0\n\x00\x01\x02GARBAGE\xFF\xFF\nSUCCESS: id=103, metric=8.1\n\xFA\xFB\xFC MORE GARBAGE\nSUCCESS: id=104, metric=1.0\n" > /home/user/fin-model/transactions.journal

    chmod -R 777 /home/user

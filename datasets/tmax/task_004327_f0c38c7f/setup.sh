#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential cargo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data /home/user/pipeline/src

    cat << 'EOF' > /home/user/data/input.csv
id,sensor_value
1,100000000.0
2,100000001.0
3,100000002.0
4,100000003.0
5,100000004.0
EOF

    cat << 'EOF' > /home/user/pipeline/Cargo.toml
[package]
name = "pipeline"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

    cat << 'EOF' > /home/user/pipeline/src/main.rs
use std::fs::File;
use std::io::{BufRead, BufReader, Write};

fn main() {
    let file = File::open("/home/user/data/input.csv").unwrap();
    let reader = BufReader::new(file);
    let mut lines = reader.lines().skip(1); // skip header

    let mut ids = Vec::new();
    let mut values = Vec::new();
    let mut sum = 0.0f32;
    let mut sum_sq = 0.0f32;
    let mut count = 0.0f32;

    while let Some(Ok(line)) = lines.next() {
        let parts: Vec<&str> = line.split(',').collect();
        let id = parts[0].to_string();
        let val: f32 = parts[1].parse().unwrap();

        ids.push(id);
        values.push(val);

        sum += val;
        sum_sq += val * val;
        count += 1.0;
    }

    let mean = sum / count;
    let variance = (sum_sq / count) - (mean * mean);
    let std_dev = variance.sqrt();

    let mut out = File::create("/home/user/pipeline/output.csv").unwrap();
    writeln!(out, "id,sensor_value,z_score").unwrap();

    for (i, val) in values.iter().enumerate() {
        let z_score = (val - mean) / std_dev;
        writeln!(out, "{},{},{:.4}", ids[i], val, z_score).unwrap();
    }
}
EOF

    chmod -R 777 /home/user

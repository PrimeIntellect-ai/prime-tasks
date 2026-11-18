#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    mkdir -p /home/user/data
    mkdir -p /home/user/pipeline/src

    # Generate deterministic dataset
    echo "id,category,value" > /home/user/data/input.csv
    for i in $(seq 1 100); do
        echo "$i,cat_$((i%5)),$((i*10))" >> /home/user/data/input.csv
    done

    # Initialize Rust project
    cat << 'EOF' > /home/user/pipeline/Cargo.toml
[package]
name = "pipeline"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

    # Buggy Rust code
    cat << 'EOF' > /home/user/pipeline/src/main.rs
use std::fs::File;
use std::io::{BufRead, BufReader, Write};

fn main() {
    let file = File::open("/home/user/data/input.csv").unwrap();
    let reader = BufReader::new(file);
    let mut lines = reader.lines();

    let header = lines.next().unwrap().unwrap();
    let mut rows: Vec<(String, String, f64)> = Vec::new();

    for line in lines {
        let l = line.unwrap();
        let parts: Vec<&str> = l.split(',').collect();
        let id = parts[0].to_string();
        let cat = parts[1].to_string();
        let val: f64 = parts[2].parse().unwrap();
        rows.push((id, cat, val));
    }

    // BUG: Data leakage! Calculating mean and std on the entire dataset.
    let total_count = rows.len() as f64;
    let sum: f64 = rows.iter().map(|r| r.2).sum();
    let mean = sum / total_count;

    let variance: f64 = rows.iter().map(|r| {
        let diff = r.2 - mean;
        diff * diff
    }).sum::<f64>() / total_count;
    let std_dev = variance.sqrt();

    let split_idx = (total_count * 0.8) as usize;

    let mut train_file = File::create("/home/user/data/train_normalized.csv").unwrap();
    let mut test_file = File::create("/home/user/data/test_normalized.csv").unwrap();

    writeln!(train_file, "id,category,normalized_value").unwrap();
    writeln!(test_file, "id,category,normalized_value").unwrap();

    for (i, row) in rows.iter().enumerate() {
        let norm_val = (row.2 - mean) / std_dev;
        let line = format!("{},{},{:.4}", row.0, row.1, norm_val);
        if i < split_idx {
            writeln!(train_file, "{}", line).unwrap();
        } else {
            writeln!(test_file, "{}", line).unwrap();
        }
    }
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/data
    chown -R user:user /home/user/pipeline
    chmod -R 777 /home/user

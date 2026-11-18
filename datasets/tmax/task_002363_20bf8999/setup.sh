#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    mkdir -p /home/user/data
    mkdir -p /home/user/etl_pipeline/src

    cat << 'EOF' > /home/user/data/dataset.csv
1.0,2.0
1.5,2.5
2.0,1.0
2.5,4.0
3.0,3.5
3.5,2.0
4.0,5.0
4.5,4.5
10.0,1.0
0.0,12.0
EOF

    cat << 'EOF' > /home/user/etl_pipeline/Cargo.toml
[package]
name = "etl_pipeline"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

    cat << 'EOF' > /home/user/etl_pipeline/src/main.rs
use std::fs::File;
use std::io::{BufRead, BufReader};

fn main() {
    let file = File::open("/home/user/data/dataset.csv").unwrap();
    let reader = BufReader::new(file);

    let mut data: Vec<(f64, f64)> = Vec::new();
    for line in reader.lines() {
        let line = line.unwrap();
        let parts: Vec<&str> = line.split(',').collect();
        data.push((parts[0].parse().unwrap(), parts[1].parse().unwrap()));
    }

    // BUG: Data Leakage! Min/Max calculated on the entire dataset.
    let mut min_f1 = f64::MAX;
    let mut max_f1 = f64::MIN;
    let mut min_f2 = f64::MAX;
    let mut max_f2 = f64::MIN;

    for &(f1, f2) in &data {
        if f1 < min_f1 { min_f1 = f1; }
        if f1 > max_f1 { max_f1 = f1; }
        if f2 < min_f2 { min_f2 = f2; }
        if f2 > max_f2 { max_f2 = f2; }
    }

    let mut scaled_data = Vec::new();
    for &(f1, f2) in &data {
        scaled_data.push((
            (f1 - min_f1) / (max_f1 - min_f1),
            (f2 - min_f2) / (max_f2 - min_f2)
        ));
    }

    let train_set = &scaled_data[0..8];
    let test_set = &scaled_data[8..10];

    // TODO: Write nearest neighbor logic here and fix the leakage above
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

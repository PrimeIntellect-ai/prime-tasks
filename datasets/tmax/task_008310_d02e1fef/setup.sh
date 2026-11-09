#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    mkdir -p /home/user/data
    cat << 'EOF' > /home/user/data/measurements.csv
id,f1,f2,f3,f4
1,1.0,5.0,2.0,0.0
2,ERR,1.0,1.0,1.0
3,3.0,3.0,4.0,2.0
4,5.0,1.0,0.0,4.0
5,1.0,N/A,3.0,4.0
6,7.0,7.0,2.0,6.0
EOF

    mkdir -p /home/user/pca_cleaner/src
    cat << 'EOF' > /home/user/pca_cleaner/Cargo.toml
[package]
name = "pca_cleaner"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

    cat << 'EOF' > /home/user/pca_cleaner/src/main.rs
use std::fs::File;
use std::io::{BufRead, BufReader, Write};

fn main() {
    let file = File::open("/home/user/data/measurements.csv").unwrap();
    let reader = BufReader::new(file);

    let mut data: Vec<(String, Vec<f64>)> = Vec::new();

    for line in reader.lines().skip(1) {
        let line = line.unwrap();
        let parts: Vec<&str> = line.split(',').collect();
        let id = parts[0].to_string();

        let mut row = Vec::new();
        for p in &parts[1..] {
            row.push(p.parse::<f64>().unwrap_or(std::f64::NAN));
        }
        data.push((id, row));
    }

    let proj = [
        [0.5, 0.5, -0.5, -0.5],
        [0.5, -0.5, 0.5, -0.5]
    ];

    let mut out = File::create("/home/user/projected.csv").unwrap();
    writeln!(out, "id,p1,p2").unwrap();

    for (id, row) in data.iter() {
        let mut p1 = 0.0;
        let mut p2 = 0.0;
        for j in 0..4 {
            p1 += row[j] * proj[0][j];
            p2 += row[j] * proj[1][j];
        }
        writeln!(out, "{},{:.4},{:.4}", id, p1, p2).unwrap();
    }
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

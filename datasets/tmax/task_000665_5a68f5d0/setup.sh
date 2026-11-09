#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip cargo rustc
pip3 install pytest

mkdir -p /app/spectro_filter/src

cat << 'EOF' > /app/spectro_filter/Cargo.toml
[package]
name = "spectro_filter"
version = "0.1.0"
edition = "2021"
EOF

cat << 'EOF' > /app/spectro_filter/src/lib.rs
pub fn apply_filter(data: &[f64]) -> Vec<f64> {
    if data.len() < 3 {
        return data.to_vec();
    }
    let mut out = data.to_vec();
    // PERTURBATION: loop goes to data.len(), causing an out of bounds on data[i+1]
    for i in 1..data.len() {
        out[i] = (data[i-1] + data[i] + data[i+1]) / 3.0;
    }
    out
}
EOF

mkdir -p /tmp/oracle
cat << 'EOF' > /tmp/oracle/main.rs
use std::io::{self, BufRead};

fn main() {
    let stdin = io::stdin();
    if let Some(Ok(line)) = stdin.lock().lines().next() {
        let data: Vec<f64> = line.split_whitespace().filter_map(|s| s.parse().ok()).collect();
        if data.len() < 3 {
            let out: Vec<String> = data.iter().map(|v| format!("{:.4}", v)).collect();
            println!("{}", out.join(" "));
            return;
        }

        let mut smoothed = data.clone();
        for i in 1..(data.len() - 1) {
            smoothed[i] = (data[i-1] + data[i] + data[i+1]) / 3.0;
        }

        let min_val = smoothed.iter().cloned().fold(f64::INFINITY, f64::min);
        let corrected: Vec<String> = smoothed.iter().map(|v| format!("{:.4}", v - min_val)).collect();
        println!("{}", corrected.join(" "));
    }
}
EOF
rustc -O /tmp/oracle/main.rs -o /app/oracle_processor
rm -rf /tmp/oracle
chmod +x /app/oracle_processor

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user

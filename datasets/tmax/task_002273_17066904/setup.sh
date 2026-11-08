#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick cargo rustc fonts-dejavu-core
    pip3 install pytest

    mkdir -p /app

    # Generate the params image
    convert -size 400x100 xc:white -font DejaVu-Sans -pointsize 24 -fill black -draw "text 10,50 'ETL_SEED=54321'" /app/params.png

    # Create and compile the oracle
    cat << 'EOF' > /app/oracle.rs
use std::io::{self, BufRead};

fn main() {
    let mut x: u64 = 54321;
    let mut p = [[0.0f64; 3]; 8];
    for i in 0..8 {
        for j in 0..3 {
            x = (1103515245 * x + 12345) % 2147483648;
            p[i][j] = (x as f64 / 2147483648.0) * 2.0 - 1.0;
        }
    }

    let stdin = io::stdin();
    for line in stdin.lock().lines() {
        let line = line.unwrap();
        if line.trim().is_empty() { continue; }
        let parts: Vec<f64> = line.split_whitespace().map(|s| s.parse().unwrap()).collect();
        if parts.len() != 8 { continue; }
        let mut w = [0.0f64; 3];
        for j in 0..3 {
            for i in 0..8 {
                w[j] += parts[i] * p[i][j];
            }
        }
        println!("{:.4} {:.4} {:.4}", w[0], w[1], w[2]);
    }
}
EOF
    rustc /app/oracle.rs -o /app/oracle
    rm /app/oracle.rs

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

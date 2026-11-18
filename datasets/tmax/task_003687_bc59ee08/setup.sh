#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/anomaly_detector/src

    cat << 'EOF' > /home/user/anomaly_detector/Cargo.toml
[package]
name = "anomaly_detector"
version = "0.1.0"
edition = "2021"
EOF

    cat << 'EOF' > /home/user/anomaly_detector/src/main.rs
use std::env;
use std::fs::File;
use std::io::{self, BufRead};

fn calculate_variance(data: &[f64]) -> f64 {
    let n = data.len() as f64;
    if n == 0.0 {
        return 0.0;
    }

    // Naive sum of squares algorithm - susceptible to catastrophic cancellation
    let sum: f64 = data.iter().sum();
    let sum_sq: f64 = data.iter().map(|&x| x * x).sum();

    let variance = (sum_sq - (sum * sum / n)) / n;

    assert!(variance >= -1e-10, "Variance cannot be negative! Found {}", variance);
    if variance < 0.0 {
        // Strict assertion for the bug manifestation
        assert!(variance >= 0.0, "Variance cannot be negative! Found {}", variance);
    }

    variance
}

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        eprintln!("Usage: {} <data_file>", args[0]);
        std::process::exit(1);
    }

    let file = File::open(&args[1]).expect("Failed to open file");
    let reader = io::BufReader::new(file);

    for line in reader.lines() {
        let line = line.expect("Failed to read line");
        let parsed: Result<Vec<f64>, _> = line.split(',').map(|s| s.parse::<f64>()).collect();
        match parsed {
            Ok(data) => {
                let var = calculate_variance(&data);
                println!("{}", var);
            }
            Err(_) => eprintln!("Failed to parse line: {}", line),
        }
    }
}
EOF

    cat << 'EOF' > /home/user/sensor_data.csv
1.0,2.0,3.0
100000000.0,100000000.1,100000000.2
5.0,7.0,9.0
EOF

    chmod -R 777 /home/user

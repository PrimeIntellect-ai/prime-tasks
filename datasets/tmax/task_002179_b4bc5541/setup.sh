#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    mkdir -p /home/user/bayes_pipeline/src
    cd /home/user/bayes_pipeline

    cat << 'EOF' > Cargo.toml
[package]
name = "bayes_pipeline"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

    cat << 'EOF' > src/main.rs
use std::fs::File;
use std::io::Write;
use std::time::Instant;

fn main() {
    let data: Vec<f64> = vec![10.0, 20.0, 30.0, 40.0, 50.0, 60.0, 70.0, 80.0, 90.0, 100.0];
    let split_idx = 8;

    // Schema enforcement: All values must be strictly positive
    for &val in &data {
        if val <= 0.0 {
            panic!("Schema violation: Value <= 0.0 found!");
        }
    }

    // BUG: Data leakage! Calculating statistics on the whole dataset.
    let mean = data.iter().sum::<f64>() / data.len() as f64;
    let variance = data.iter().map(|&val| {
        let diff = val - mean;
        diff * diff
    }).sum::<f64>() / data.len() as f64;
    let std_dev = variance.sqrt();

    let start = Instant::now();

    // Normalize test set
    let mut normalized_test = Vec::new();
    for &val in &data[split_idx..] {
        normalized_test.push((val - mean) / std_dev);
    }

    let duration = start.elapsed();

    // Log outputs
    let json = format!(
        "{}\"test_set_normalized\": {:?}, \"benchmark_time_ns\": {}{}",
        "{",
        normalized_test,
        duration.as_nanos(),
        "}"
    );
    let mut file = File::create("/home/user/benchmark_metrics.json").unwrap();
    file.write_all(json.as_bytes()).unwrap();
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/bayes_pipeline
    chmod -R 777 /home/user

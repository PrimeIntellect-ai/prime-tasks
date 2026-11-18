#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc libhdf5-dev
    pip3 install pytest

    mkdir -p /home/user/repro_eval/src

    cat << 'EOF' > /home/user/repro_eval/Cargo.toml
[package]
name = "repro_eval"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

    cat << 'EOF' > /home/user/repro_eval/src/main.rs
use std::collections::HashMap;

fn main() {
    // Simulated data that would normally come from data.h5
    // Using a hardcoded list of key-value pairs to represent the grouped multidimensional array
    let data = vec![
        ("seq1", 0.123456789012345),
        ("seq2", 0.987654321098765),
        ("seq3", 0.555555555555555),
        ("seq4", 0.111111111111111),
        ("seq5", 0.222222222222222),
        ("seq6", 0.333333333333333),
        ("seq7", 0.444444444444444),
        ("seq8", 0.666666666666666),
        ("seq9", 0.777777777777777),
        ("seq10", 0.888888888888888),
    ];

    let mut map = HashMap::new();
    for (k, v) in data {
        map.insert(k.to_string(), v);
    }

    // Non-deterministic reduction order
    let kl_divergence: f64 = map.values().copied().sum();

    // Some complex math to make the rounding error obvious
    let final_val = kl_divergence.powf(2.5).sin();

    println!("{:.15}", final_val);
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

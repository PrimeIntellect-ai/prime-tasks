#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential gawk
    pip3 install pytest

    # Install Rust via rustup to get a recent version
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    export PATH="/root/.cargo/bin:$PATH"

    mkdir -p /home/user/data_gen/src

    # Generate input data
    gawk 'BEGIN { srand(42); for(i=1;i<=100000;i++) print rand()*100 }' > /home/user/input_data.csv

    # Create Cargo.toml
    cat << 'EOF' > /home/user/data_gen/Cargo.toml
[package]
name = "data_gen"
version = "0.1.0"
edition = "2021"

[dependencies]
rayon = "1.8"
EOF

    # Create main.rs with Mutex (non-deterministic)
    cat << 'EOF' > /home/user/data_gen/src/main.rs
use std::fs::File;
use std::io::{BufRead, BufReader, Write};
use std::sync::Mutex;
use rayon::prelude::*;

fn main() {
    let file = File::open("/home/user/input_data.csv").unwrap();
    let reader = BufReader::new(file);
    let mut data: Vec<f64> = Vec::new();

    for line in reader.lines() {
        if let Ok(val) = line.unwrap().parse::<f64>() {
            data.push(val);
        }
    }

    // NON-DETERMINISTIC REDUCTION
    let total = Mutex::new(0.0f64);
    data.par_iter().for_each(|&val| {
        let mut t = total.lock().unwrap();
        *t += val.sin();
    });

    let final_val = *total.lock().unwrap();

    let mut out = File::create("/home/user/output_features.csv").unwrap();
    writeln!(out, "{:.10}", final_val).unwrap();
}
EOF

    # Generate reference features using a temporary sequential Rust script
    mkdir -p /tmp/ref_gen/src
    cat << 'EOF' > /tmp/ref_gen/Cargo.toml
[package]
name = "ref_gen"
version = "0.1.0"
edition = "2021"
EOF
    cat << 'EOF' > /tmp/ref_gen/src/main.rs
use std::fs::File;
use std::io::{BufRead, BufReader, Write};

fn main() {
    let file = File::open("/home/user/input_data.csv").unwrap();
    let reader = BufReader::new(file);
    let mut data: Vec<f64> = Vec::new();

    for line in reader.lines() {
        if let Ok(val) = line.unwrap().parse::<f64>() {
            data.push(val);
        }
    }

    let final_val: f64 = data.iter().map(|&val| val.sin()).sum();

    let mut out = File::create("/home/user/reference_features.csv").unwrap();
    writeln!(out, "{:.10}", final_val).unwrap();
}
EOF
    cd /tmp/ref_gen && cargo run --release
    rm -rf /tmp/ref_gen

    # Ensure rustc and cargo are in system path for the user
    cp -r /root/.cargo /usr/local/cargo
    cp -r /root/.rustup /usr/local/rustup

    # Create wrapper scripts in /usr/local/bin
    for cmd in cargo rustc rustup; do
        ln -s /usr/local/cargo/bin/$cmd /usr/local/bin/$cmd
    done

    export RUSTUP_HOME=/usr/local/rustup
    export CARGO_HOME=/usr/local/cargo

    # Create user
    useradd -m -s /bin/bash user || true

    # Fix permissions
    chmod -R 777 /home/user
    chmod -R 777 /usr/local/cargo
    chmod -R 777 /usr/local/rustup

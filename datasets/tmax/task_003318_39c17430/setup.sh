#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential
    pip3 install pytest

    # Install Rust
    export RUSTUP_HOME=/usr/local/rustup
    export CARGO_HOME=/usr/local/cargo
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    export PATH=/usr/local/cargo/bin:$PATH
    ln -s /usr/local/cargo/bin/* /usr/local/bin/

    # Create user
    useradd -m -s /bin/bash user || true

    # Setup task directory
    mkdir -p /home/user/telemetry_app
    cd /home/user/telemetry_app
    cargo init

    # Remove generated main.rs
    rm src/main.rs

    # Create buggy backup file
    cat << 'EOF' > src/.main.rs.bak
use std::fs::File;
use std::io::{BufRead, BufReader, Write};

fn main() {
    let file = File::open("input_logs.txt").unwrap();
    let reader = BufReader::new(file);
    let mut values: Vec<i32> = Vec::new();

    for line in reader.lines() {
        if let Ok(val) = line.unwrap().parse::<i32>() {
            values.push(val);
        }
    }

    let mut out = File::create("corrected_metrics.txt").unwrap();
    let window = 5;

    // BUG 1: Outer loop misses the last valid window (should be values.len() - window + 1)
    for i in 0..values.len() - window {
        let mut sum_sq: i32 = 0; // BUG 2: Type too small, will overflow
        // BUG 3: Inner loop processes 6 elements instead of 5
        for j in 0..=window {
            let v = values[i + j];
            sum_sq += v * v; 
        }
        writeln!(out, "{}", sum_sq).unwrap();
    }
}
EOF

    # Create input logs
    cat << 'EOF' > input_logs.txt
10000
20000
15000
30000
50000
10000
5000
20000
45000
60000
EOF

    # Create crash log
    cat << 'EOF' > crash.log
thread 'main' panicked at src/main.rs:24:23:
attempt to multiply with overflow
stack backtrace:
   0: rust_begin_unwind
   1: core::panicking::panic_fmt
   2: core::panicking::panic
   3: telemetry_app::main
             at ./src/main.rs:24:23
   4: core::ops::function::FnOnce::call_once
note: run with `RUST_BACKTRACE=1` environment variable to display a backtrace
EOF

    # Fix permissions
    chmod -R 777 /home/user
    chmod -R 777 /usr/local/cargo
    chmod -R 777 /usr/local/rustup

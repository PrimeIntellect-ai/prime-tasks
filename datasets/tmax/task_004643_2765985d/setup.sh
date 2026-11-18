#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        espeak \
        curl \
        build-essential \
        ffmpeg

    pip3 install pytest

    # Install Rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    export PATH="/root/.cargo/bin:${PATH}"

    # Create audio file
    mkdir -p /app/audio
    espeak -w /app/audio/perf_data.wav "Time 0.0, velocity 2.5. Time 1.0, velocity 3.8. Time 2.0, velocity 4.1. Time 3.0, velocity 6.0. Time 4.0, velocity 5.5."

    # Build oracle
    mkdir -p /app/oracle_src
    cd /app/oracle_src
    cargo new oracle
    cd oracle

    cat << 'EOF' > Cargo.toml
[package]
name = "oracle"
version = "0.1.0"
edition = "2021"

[dependencies]
rand = "0.8"
rand_chacha = "0.3"
EOF

    cat << 'EOF' > src/main.rs
use std::io::{self, BufRead};
use rand::Rng;
use rand_chacha::ChaCha8Rng;
use rand::SeedableRng;

fn main() {
    let stdin = io::stdin();
    let mut times = Vec::new();
    let mut vels = Vec::new();
    for line in stdin.lock().lines() {
        let line = line.unwrap();
        if line.trim().is_empty() { continue; }
        let parts: Vec<&str> = line.split(',').collect();
        times.push(parts[0].trim().parse::<f64>().unwrap());
        vels.push(parts[1].trim().parse::<f64>().unwrap());
    }

    let mut dist = 0.0;
    let mut accels = Vec::new();
    for i in 1..times.len() {
        let dt = times[i] - times[i-1];
        let dv = vels[i] - vels[i-1];
        dist += (vels[i] + vels[i-1]) / 2.0 * dt;
        accels.push(dv / dt);
    }

    let mut rng = ChaCha8Rng::seed_from_u64(42);
    let mut means = Vec::with_capacity(1000);
    let n = accels.len();
    for _ in 0..1000 {
        let mut sum = 0.0;
        for _ in 0..n {
            let idx = rng.gen_range(0..n);
            sum += accels[idx];
        }
        means.push(sum / n as f64);
    }
    means.sort_by(|a, b| a.partial_cmp(b).unwrap());

    println!("Distance: {:.4}", dist);
    println!("Accel_CI: [{:.4}, {:.4}]", means[25], means[975]);
}
EOF

    cargo build --release
    mkdir -p /app/oracle
    cp target/release/oracle /app/oracle/kinematics_oracle

    # Clean up build files
    cd /
    rm -rf /app/oracle_src

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

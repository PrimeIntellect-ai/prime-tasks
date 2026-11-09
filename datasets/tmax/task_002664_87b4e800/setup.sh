#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip curl wget ffmpeg nginx build-essential
pip3 install pytest

# Install Rust globally
export RUSTUP_HOME=/opt/rustup
export CARGO_HOME=/opt/cargo
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
export PATH="/opt/cargo/bin:${PATH}"
chmod -R 777 /opt/rustup /opt/cargo
echo 'export RUSTUP_HOME=/opt/rustup' > /etc/profile.d/rust.sh
echo 'export CARGO_HOME=/opt/cargo' >> /etc/profile.d/rust.sh
echo 'export PATH="/opt/cargo/bin:${PATH}"' >> /etc/profile.d/rust.sh

# Generate the dummy video
mkdir -p /app
ffmpeg -f lavfi -i testsrc=duration=10:size=640x480:rate=30 -c:v libx264 /app/pendulum_experiment.mp4

# Create the buggy Rust project
mkdir -p /home/user/project/math_filter/src
mkdir -p /home/user/project/bin
cat << 'EOF' > /home/user/project/math_filter/Cargo.toml
[package]
name = "math_filter"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

cat << 'EOF' > /home/user/project/math_filter/src/main.rs
use std::io::{self, Read};

fn process_signal(data: &mut Vec<f64>) -> f64 {
    let mut acc = 0.0;
    // Bug 1: Borrow checker error. Holding immutable reference while trying to mutate.
    let first_elem = &data[0];
    for i in 1..data.len() {
        data[i] = (data[i] + data[i-1]) * 0.5;
        acc += data[i] * first_elem.sin();
    }
    acc
}

fn main() {
    let mut input = String::new();
    io::stdin().read_to_string(&mut input).unwrap();
    let mut numbers: Vec<f64> = input
        .split_whitespace()
        .filter_map(|s| s.parse().ok())
        .collect();

    if numbers.is_empty() {
        println!("0.0");
        return;
    }

    let result = process_signal(&mut numbers);
    println!("{:.6}", result);
}
EOF

# Compile the oracle (we compile a fixed version of the same code)
mkdir -p /tmp/oracle_build/src
cp /home/user/project/math_filter/Cargo.toml /tmp/oracle_build/
cat << 'EOF' > /tmp/oracle_build/src/main.rs
use std::io::{self, Read};

fn process_signal(data: &mut Vec<f64>) -> f64 {
    let mut acc = 0.0;
    let first_elem = data[0]; // Fix: Copy the f64 instead of borrowing
    for i in 1..data.len() {
        data[i] = (data[i] + data[i-1]) * 0.5;
        acc += data[i] * first_elem.sin();
    }
    acc
}

fn main() {
    let mut input = String::new();
    io::stdin().read_to_string(&mut input).unwrap();
    let mut numbers: Vec<f64> = input
        .split_whitespace()
        .filter_map(|s| s.parse().ok())
        .collect();

    if numbers.is_empty() {
        println!("0.0");
        return;
    }

    let result = process_signal(&mut numbers);
    println!("{:.6}", result);
}
EOF
cd /tmp/oracle_build && cargo build --release
cp /tmp/oracle_build/target/release/math_filter /app/oracle_math_filter
rm -rf /tmp/oracle_build

# Set permissions
useradd -m -s /bin/bash user || true
chown -R user:user /home/user/project
chmod -R 777 /home/user
chmod -R 777 /app

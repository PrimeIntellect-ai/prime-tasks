#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential
    pip3 install pytest

    # Install Rust system-wide
    export RUSTUP_HOME=/usr/local/rustup
    export CARGO_HOME=/usr/local/cargo
    export PATH=/usr/local/cargo/bin:$PATH
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    chmod -R 777 /usr/local/cargo /usr/local/rustup

    # Create vendored package directory
    mkdir -p /app/outlier_detect/src

    # Create Cargo.toml with typo
    cat << 'EOF' > /app/outlier_detect/Cargo.toml
[package]
name = "outlier_detect"
version = "0.1.0"
edition = "2021"

[dependencis]
EOF

    # Create lib.rs with missing semicolon
    cat << 'EOF' > /app/outlier_detect/src/lib.rs
pub fn filter_outliers(data: &[f64]) -> Vec<f64> {
    if data.is_empty() { return vec![]; }
    let mean = data.iter().sum::<f64>() / data.len() as f64;
    let variance = data.iter().map(|value| {
        let diff = mean - *value;
        diff * diff
    }).sum::<f64>() / data.len() as f64
    let std_dev = variance.sqrt();

    data.iter().copied().filter(|&x| (x - mean).abs() <= 2.0 * std_dev).collect()
}
EOF

    # Ensure /app is writable so the agent can fix the files
    chmod -R 777 /app

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential
    pip3 install pytest

    export RUSTUP_HOME=/opt/rust
    export CARGO_HOME=/opt/rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    chmod -R 777 /opt/rust
    ln -s /opt/rust/bin/* /usr/local/bin/

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/incident-1042/src
    cd /home/user/incident-1042

    cat << 'EOF' > Cargo.toml
[package]
name = "deriv_calc"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

    cat << 'EOF' > src/main.rs
use std::fs;

fn compute_derivative(data: &[f64]) -> Vec<f64> {
    let mut deriv = vec![0.0; data.len()];
    // BUG: Panics at i=0 (subtract with overflow) and i=data.len()-1 (index out of bounds)
    for i in 0..data.len() {
        deriv[i] = (data[i+1] - data[i-1]) / 2.0;
    }
    deriv
}

fn main() {
    let data_str = fs::read_to_string("data.csv").expect("Failed to read data.csv");
    let mut data = Vec::new();
    for line in data_str.split(',') {
        if let Ok(val) = line.trim().parse::<f64>() {
            data.push(val);
        }
    }

    let deriv = compute_derivative(&data);
    let sum: f64 = deriv.iter().sum();
    println!("{}", sum);
}
EOF

    python3 -c "print(','.join(str(float(i**2)) for i in range(100)))" > data.csv

    chown -R user:user /home/user/incident-1042
    chmod -R 777 /home/user

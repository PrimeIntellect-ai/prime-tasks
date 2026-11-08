#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip cargo
pip3 install pytest

mkdir -p /home/user/diagnostic/src

cat << 'EOF' > /home/user/diagnostic/Cargo.toml
[package]
name = "diagnostic"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

cat << 'EOF' > /home/user/diagnostic/src/main.rs
use std::env;

fn recursive_diagnostic(x: f32, term: f32, k: f32) -> f32 {
    // BUG 1: Flawed termination condition (exact float match)
    if term == 1e-10 {
        return 0.0;
    }
    // Fallback to prevent stack overflow
    if k > 5000.0 {
        return 0.0;
    }

    // BUG 2: Incorrect formula for the next term
    // (currently using the denominator pattern for sine instead of cosine)
    let next_term = term * (-x * x) / (2.0 * k * (2.0 * k + 1.0));

    term + recursive_diagnostic(x, next_term, k + 1.0)
}

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        println!("Usage: diagnostic <value>");
        return;
    }
    // BUG 3: Catastrophic cancellation due to f32 precision
    let x: f32 = args[1].parse().expect("Invalid float");
    let result = recursive_diagnostic(x, 1.0, 1.0);
    println!("Result: {}", result);
}
EOF

useradd -m -s /bin/bash user || true
chown -R user:user /home/user/diagnostic
chmod -R 777 /home/user

#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    mkdir -p /app/fast_solver/src

    cat << 'EOF' > /app/fast_solver/Cargo.toml
[package]
name = "fast_solver"
version = "0.1.0"
edition = "2021"

[dependencies]
serde = "1.99.0"
EOF

    cat << 'EOF' > /app/fast_solver/src/lib.rs
pub fn solve(data: &[f64]) -> f64 {
    let mean = data.iter().sum::<f64>() / data.len() as f64;
    let variance = data.iter().map(|value| {
        let diff = mean - *value;
        diff * diff
    }).sum::<f64>() / data.len() as f64;

    let result = 1.0 / variance;
    assert!(!result.is_nan() && !result.is_infinite());
    result
}
EOF

    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil

    cat << 'EOF' > /app/corpora/clean/1.txt
1.0
2.0
3.0
EOF

    cat << 'EOF' > /app/corpora/clean/2.txt
4.5
1.2
8.9
EOF

    cat << 'EOF' > /app/corpora/evil/1.txt
2.0
2.0
2.0
EOF

    cat << 'EOF' > /app/corpora/evil/2.txt
5.5
5.5
5.5
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

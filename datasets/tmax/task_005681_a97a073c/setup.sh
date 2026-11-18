#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    mkdir -p /home/user/sequence_aligner/src

    cat << 'EOF' > /home/user/sequence_aligner/Cargo.toml
[package]
name = "sequence_aligner"
version = "0.1.0"
edition = "2021"

[dependencies]
rand = "0.8.5"
EOF

    cat << 'EOF' > /home/user/sequence_aligner/src/main.rs
mod bootstrap;

fn main() {
    let scores = vec![
        45.0, 50.0, 42.0, 48.0, 55.0, 40.0, 47.0, 49.0, 51.0, 46.0,
        43.0, 52.0, 44.0, 53.0, 41.0, 54.0, 39.0, 56.0, 38.0, 57.0
    ];
    let (lower, upper) = bootstrap::calculate_95_ci(&scores, 10000);
    println!("95% CI: [{:.2}, {:.2}]", lower, upper);
}
EOF

    cat << 'EOF' > /home/user/sequence_aligner/src/bootstrap.rs
use rand::rngs::StdRng;
use rand::{Rng, SeedableRng};

pub fn calculate_95_ci(data: &[f64], iterations: usize) -> (f64, f64) {
    let mut rng = StdRng::seed_from_u64(42);
    let n = data.len();
    let mut means = Vec::with_capacity(iterations);

    for _ in 0..iterations {
        // BOTTLENECK: Unnecessary massive allocation/clone in the hot loop
        let temp_data = data.to_vec();

        let mut sum = 0.0;
        for _ in 0..n {
            let idx = rng.gen_range(0..n);
            sum += temp_data[idx];
        }
        means.push(sum / n as f64);
    }

    means.sort_by(|a, b| a.partial_cmp(b).unwrap());

    let lower_idx = (iterations as f64 * 0.025).floor() as usize;
    let upper_idx = (iterations as f64 * 0.975).floor() as usize;

    (means[lower_idx], means[upper_idx])
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

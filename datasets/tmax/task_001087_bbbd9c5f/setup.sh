#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    mkdir -p /home/user/gc_bootstrap/src

    cat << 'EOF' > /home/user/gc_bootstrap/Cargo.toml
[package]
name = "gc_bootstrap"
version = "0.1.0"
edition = "2021"

[dependencies]
rand = "0.8"
rand_chacha = "0.3"
rayon = "1.10.0"
EOF

    cat << 'EOF' > /home/user/gc_bootstrap/src/main.rs
use rand::{SeedableRng, Rng};
use rand_chacha::ChaCha8Rng;
use rayon::prelude::*;
use std::fs;

fn main() {
    let fasta = fs::read_to_string("/home/user/sequences.fasta").expect("Unable to read fasta");
    let mut gc_contents: Vec<f64> = Vec::new();

    for line in fasta.lines() {
        if !line.starts_with('>') && !line.is_empty() {
            let gc = line.chars().filter(|&c| c == 'G' || c == 'C').count() as f64;
            gc_contents.push(gc / line.len() as f64);
        }
    }

    let mut rng = ChaCha8Rng::seed_from_u64(42);
    let mut bootstrap_means = Vec::new();

    let n = gc_contents.len();
    for _ in 0..1000 {
        let sample: Vec<f64> = (0..n).map(|_| {
            let idx = rng.gen_range(0..n);
            gc_contents[idx]
        }).collect();

        // BUG: Non-deterministic parallel float reduction
        let sum: f64 = sample.par_iter().sum();
        bootstrap_means.push(sum / n as f64);
    }

    let overall_mean: f64 = bootstrap_means.iter().sum::<f64>() / bootstrap_means.len() as f64;
    println!("{:.10}", overall_mean);
}
EOF

    cat << 'EOF' > /home/user/generate_fasta.py
import random
random.seed(42)
with open("/home/user/sequences.fasta", "w") as f:
    for i in range(10000):
        f.write(f">seq{i}\n")
        length = random.randint(50, 150)
        seq = "".join(random.choices("ACGT", k=length))
        f.write(seq + "\n")
EOF

    python3 /home/user/generate_fasta.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

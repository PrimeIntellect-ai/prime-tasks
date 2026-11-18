#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential rustc cargo
    pip3 install pytest

    mkdir -p /app/vendored/bio-spectrum-0.1.0/src

    cat << 'EOF' > /app/vendored/bio-spectrum-0.1.0/Cargo.toml
[package]
name = "bio-spectrum"
version = "0.1.0"
edition = "2021"

[dependencies]
# The dependency for FFT is missing here
EOF

    cat << 'EOF' > /app/vendored/bio-spectrum-0.1.0/src/lib.rs
use rustfft::{FftPlanner, num_complex::Complex};

pub fn power_spectrum(seq: &str) -> Vec<f64> {
    let mut planner = FftPlanner::new();
    let fft = planner.plan_fft_forward(seq.len());

    let mut buffer: Vec<Complex<f64>> = seq.chars().map(|c| {
        let val = match c {
            'A' => 1.0,
            'C' => 2.0,
            'G' => 3.0,
            'T' => 4.0,
            _ => 0.0,
        };
        Complex { re: val, im: 0.0 }
    }).collect();

    fft.process(&mut buffer);

    buffer.iter().map(|c| c.norm()).collect()
}
EOF

    mkdir -p /home/user/data/clean
    mkdir -p /home/user/data/evil

    python3 -c "
import os
import random

random.seed(42)
bases = ['A', 'C', 'G', 'T']

for i in range(20):
    with open(f'/home/user/data/clean/clean_{i}.fasta', 'w') as f:
        f.write(f'>clean_{i}\n')
        seq = ''.join(random.choices(bases, k=120))
        f.write(seq + '\n')

for i in range(20):
    with open(f'/home/user/data/evil/evil_{i}.fasta', 'w') as f:
        f.write(f'>evil_{i}\n')
        motif = ''.join(random.choices(bases, k=6))
        seq = motif * 20
        f.write(seq + '\n')
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

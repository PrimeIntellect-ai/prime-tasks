#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip cargo rustc
pip3 install pytest matplotlib pandas

mkdir -p /home/user/langevin_fit/src
mkdir -p /home/user/langevin_fit/tests
mkdir -p /home/user/data

# Create init.pdb
cat << 'EOF' > /home/user/data/init.pdb
ATOM      1  CA  ALA A   1       2.500   1.000   0.000  1.00  0.00           C  
ATOM      2  CB  ALA A   1       3.000   2.000   1.000  1.00  0.00           C  
EOF

# Create target.csv (a simple Gaussian-like distribution discretized into 20 bins)
cat << 'EOF' > /home/user/data/target.csv
0.001
0.003
0.010
0.025
0.050
0.080
0.120
0.150
0.180
0.200
0.180
0.150
0.120
0.080
0.050
0.025
0.010
0.003
0.001
0.000
EOF

# Cargo.toml
cat << 'EOF' > /home/user/langevin_fit/Cargo.toml
[package]
name = "langevin_fit"
version = "0.1.0"
edition = "2021"

[dependencies]
rand = "0.8"
EOF

# src/integrator.rs
cat << 'EOF' > /home/user/langevin_fit/src/integrator.rs
pub fn adaptive_step(dt: f64, err: f64, tolerance: f64) -> f64 {
    // BUG: inverted error and tolerance
    let mut new_dt = dt * (err / tolerance).sqrt();

    // clamp dt
    if new_dt > 0.1 { new_dt = 0.1; }
    if new_dt < 0.0001 { new_dt = 0.0001; }
    new_dt
}

pub fn simulate(initial_x: f64, steps: usize) -> Vec<f64> {
    let mut x = initial_x;
    let mut dt = 0.01;
    let tolerance = 1e-4;

    let mut positions = Vec::new();

    // fixed pseudo-random for reproducibility in test
    let mut seed: u32 = 42;
    let mut next_rand = || -> f64 {
        seed = seed.wrapping_mul(1664525).wrapping_add(1013904223);
        ((seed >> 16) as f64) / 65536.0 - 0.5
    };

    for _ in 0..steps {
        let force = -0.5 * x; // harmonic oscillator
        let noise = next_rand();

        let dx = force * dt + noise * dt.sqrt();
        let err = (dx * 0.1).abs(); // fake local error estimation

        x += dx;
        positions.push(x);

        dt = adaptive_step(dt, err, tolerance);
    }

    // bin into 20 bins between -5 and 5
    let mut bins = vec![0.0; 20];
    for p in positions.iter() {
        let mut bin = ((p + 5.0) / 10.0 * 20.0).floor() as i32;
        if bin < 0 { bin = 0; }
        if bin > 19 { bin = 19; }
        bins[bin as usize] += 1.0;
    }

    // normalize
    let sum: f64 = bins.iter().sum();
    for b in bins.iter_mut() {
        *b /= sum;
    }

    bins
}
EOF

# src/main.rs
cat << 'EOF' > /home/user/langevin_fit/src/main.rs
mod integrator;
use std::fs::File;
use std::io::{BufRead, BufReader, Write};

fn calculate_kl_divergence(p: &[f64], q: &[f64]) -> f64 {
    // TODO: Implement this
    0.0
}

fn main() {
    // TODO: Parse /home/user/data/init.pdb to get initial_x
    let initial_x = 0.0; // Replace this

    let simulated_dist = integrator::simulate(initial_x, 100000);

    // Save simulated.csv
    let mut f = File::create("simulated.csv").unwrap();
    for val in &simulated_dist {
        writeln!(f, "{}", val).unwrap();
    }

    // Read target
    let target_file = File::open("/home/user/data/target.csv").unwrap();
    let reader = BufReader::new(target_file);
    let mut target_dist = Vec::new();
    for line in reader.lines() {
        if let Ok(l) = line {
            if let Ok(v) = l.parse::<f64>() {
                target_dist.push(v);
            }
        }
    }

    let kl = calculate_kl_divergence(&simulated_dist, &target_dist);
    println!("KL Divergence: {}", kl);
}
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user

#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip cargo rustc
pip3 install pytest numpy

mkdir -p /home/user/bio_mcmc/src
cd /home/user/bio_mcmc
cat << 'EOF' > Cargo.toml
[package]
name = "bio_mcmc"
version = "0.1.0"
edition = "2021"

[dependencies]
rayon = "1.7"
EOF

cat << 'EOF' > src/main.rs
use std::fs;
use rayon::prelude::*;

fn calculate_integral(data: &[(f32, f32)]) -> f32 {
    // BUGGY: unordered parallel sum with f32 precision loss
    (0..data.len()-1).into_par_iter().map(|i| {
        let (x1, y1) = data[i];
        let (x2, y2) = data[i+1];
        0.5 * (y1 + y2) * (x2 - x1)
    }).sum()
}

fn main() {
    let content = fs::read_to_string("sequence_likelihoods.txt").unwrap();
    let mut data: Vec<(f32, f32)> = Vec::new();
    for line in content.lines() {
        let parts: Vec<&str> = line.split(',').collect();
        if parts.len() == 2 {
            data.push((parts[0].parse().unwrap(), parts[1].parse().unwrap()));
        }
    }

    // Sort by x
    data.sort_by(|a, b| a.0.partial_cmp(&b.0).unwrap());

    let result = calculate_integral(&data);
    println!("Integral: {:.4}", result);
}
EOF

python3 -c "
import random
random.seed(42)
with open('sequence_likelihoods.txt', 'w') as f:
    for i in range(10000):
        x = i * 0.01 + random.uniform(0, 0.001)
        y = random.uniform(0, 1) * (1.0 / (x + 1.0))
        f.write(f'{x},{y}\n')
"

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user

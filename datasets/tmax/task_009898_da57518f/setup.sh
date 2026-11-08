#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential
    pip3 install pytest

    # Install Rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    export PATH="/root/.cargo/bin:${PATH}"

    mkdir -p /home/user/data /home/user/output /home/user/gc_analyzer/src

    # Generate the fasta file
    cat << 'EOF' > /home/user/setup.py
import random
random.seed(123)
bases = ['A', 'C', 'G', 'T']
# Generate 100,000 bases with a slight drift in GC content
seq = []
for i in range(100000):
    prob_gc = 0.4 + (i / 100000) * 0.2
    if random.random() < prob_gc:
        seq.append(random.choice(['G', 'C']))
    else:
        seq.append(random.choice(['A', 'T']))

with open('/home/user/data/genome.fasta', 'w') as f:
    f.write(">chr1\n")
    # write in lines of 80
    for i in range(0, len(seq), 80):
        f.write("".join(seq[i:i+80]) + "\n")
EOF
    python3 /home/user/setup.py

    # Setup Cargo project
    cat << 'EOF' > /home/user/gc_analyzer/Cargo.toml
[package]
name = "gc_analyzer"
version = "0.1.0"
edition = "2021"

[dependencies]
rayon = "1.7"
EOF

    cat << 'EOF' > /home/user/gc_analyzer/src/main.rs
use rayon::prelude::*;
use std::fs::File;
use std::io::{BufRead, BufReader};

fn main() {
    let file = File::open("/home/user/data/genome.fasta").unwrap();
    let reader = BufReader::new(file);
    let mut seq = String::new();
    for line in reader.lines() {
        let l = line.unwrap();
        if !l.starts_with('>') {
            seq.push_str(&l);
        }
    }

    let seq_bytes = seq.as_bytes();
    let window_size = 100;
    let mut ratios = Vec::new();

    for chunk in seq_bytes.chunks(window_size) {
        if chunk.len() == window_size {
            let gc_count = chunk.iter().filter(|&&b| b == b'G' || b == b'C').count();
            ratios.push(gc_count as f64 / window_size as f64);
        }
    }

    // Buggy parallel reduction
    let total_gc_integral: f64 = ratios.par_iter().sum();
    println!("Total GC integral: {}", total_gc_integral);
}
EOF

    useradd -m -s /bin/bash user || true
    # Symlink cargo to user's home so it works without PATH adjustments if needed
    cp -r /root/.cargo /home/user/.cargo
    cp -r /root/.rustup /home/user/.rustup
    chown -R user:user /home/user/.cargo /home/user/.rustup

    chmod -R 777 /home/user
